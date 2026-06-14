import json
import re
import time
import urllib.parse
import urllib.request
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DATA_FILES = [
    ROOT / "assets" / "data" / "species_model2_136_app_form.json",
    ROOT / "assets" / "data" / "species_tas.json",
]
CACHE_FILE = ROOT / ".codex" / "species_gbif_cache.json"

AU_STATES = {
    "act": "Australian Capital Territory",
    "australian capital territory": "Australian Capital Territory",
    "nsw": "New South Wales",
    "new south wales": "New South Wales",
    "nt": "Northern Territory",
    "northern territory": "Northern Territory",
    "qld": "Queensland",
    "queensland": "Queensland",
    "sa": "South Australia",
    "south australia": "South Australia",
    "tas": "Tasmania",
    "tasmania": "Tasmania",
    "vic": "Victoria",
    "victoria": "Victoria",
    "wa": "Western Australia",
    "western australia": "Western Australia",
}

COUNTRY_REGIONS = {
    "AU": "Australia",
    "NZ": "New Zealand",
    "US": "North America",
    "CA": "North America",
    "MX": "North America",
    "AR": "South America",
    "BO": "South America",
    "BR": "South America",
    "CL": "South America",
    "CO": "South America",
    "EC": "South America",
    "GY": "South America",
    "PE": "South America",
    "PY": "South America",
    "SR": "South America",
    "UY": "South America",
    "VE": "South America",
    "ZA": "Africa",
    "KE": "Africa",
    "MG": "Africa",
    "MA": "Africa",
    "NG": "Africa",
    "CN": "Asia",
    "JP": "Asia",
    "KR": "Asia",
    "IN": "Asia",
    "ID": "Asia",
    "MY": "Asia",
    "PH": "Asia",
    "SG": "Asia",
    "TH": "Asia",
    "VN": "Asia",
    "RU": "Europe and Asia",
}

EUROPE_CODES = {
    "AD", "AL", "AT", "BA", "BE", "BG", "BY", "CH", "CY", "CZ",
    "DE", "DK", "EE", "ES", "FI", "FR", "GB", "GR", "HR", "HU",
    "IE", "IS", "IT", "LI", "LT", "LU", "LV", "MC", "MD", "ME",
    "MK", "MT", "NL", "NO", "PL", "PT", "RO", "RS", "SE", "SI",
    "SK", "TR", "UA",
}

REGION_ORDER = [
    "Australia",
    "New Zealand",
    "Europe",
    "Europe and Asia",
    "North America",
    "South America",
    "Asia",
    "Africa",
    "Oceania",
]


def gbif_get(path, params):
    query = urllib.parse.urlencode(params)
    url = f"https://api.gbif.org/v1/{path}?{query}"
    with urllib.request.urlopen(url, timeout=30) as response:
        return json.loads(response.read().decode("utf-8"))


def normalize_state(value):
    text = re.sub(r"\s+", " ", str(value or "").strip()).lower()
    if not text:
        return None
    return AU_STATES.get(text)


def normalize_regions(country_facets):
    regions = set()
    for facet in country_facets:
        code = str(facet.get("name", "")).upper()
        if not code:
            continue
        if code in EUROPE_CODES:
            regions.add("Europe")
        elif code in COUNTRY_REGIONS:
            regions.add(COUNTRY_REGIONS[code])
        elif code in {"FJ", "NC", "PG", "SB", "VU", "WS"}:
            regions.add("Oceania")
    return [region for region in REGION_ORDER if region in regions]


def load_cache():
    if not CACHE_FILE.exists():
        return {}
    return json.loads(CACHE_FILE.read_text(encoding="utf-8"))


def save_cache(cache):
    CACHE_FILE.parent.mkdir(exist_ok=True)
    CACHE_FILE.write_text(
        json.dumps(cache, indent=2, sort_keys=True), encoding="utf-8"
    )


def gbif_location(name, cache):
    if name in cache:
        return cache[name]

    result = {
        "matched": False,
        "global": [],
        "states": [],
        "status": None,
        "usageKey": None,
    }
    try:
        match = gbif_get("species/match", {"name": name})
        usage_key = match.get("usageKey")
        result["status"] = match.get("status")
        result["usageKey"] = usage_key
        result["matched"] = bool(usage_key)
        if usage_key:
            country = gbif_get(
                "occurrence/search",
                {
                    "taxonKey": usage_key,
                    "limit": 0,
                    "facet": "country",
                    "facetLimit": 300,
                },
            )
            country_facets = (
                country.get("facets", [{}])[0].get("counts", [])
                if country.get("facets")
                else []
            )
            result["global"] = normalize_regions(country_facets)

            state = gbif_get(
                "occurrence/search",
                {
                    "taxonKey": usage_key,
                    "country": "AU",
                    "limit": 0,
                    "facet": "stateProvince",
                    "facetLimit": 100,
                },
            )
            state_facets = (
                state.get("facets", [{}])[0].get("counts", [])
                if state.get("facets")
                else []
            )
            states = {
                normalized
                for normalized in (normalize_state(item.get("name")) for item in state_facets)
                if normalized
            }
            result["states"] = sorted(states)
        time.sleep(0.05)
    except Exception as error:
        result["error"] = str(error)

    cache[name] = result
    return result


def text_blob(card):
    return " ".join(
        str(card.get(field) or "")
        for field in ("scientificName", "commonName", "colloquialName", "shortDescription")
    ).lower()


def add_unique(items, value):
    value = re.sub(r"\s+", " ", value.strip())
    if value and value not in items:
        items.append(value)


def color_features(blob, features):
    existing = " ".join(features).lower()
    checks = [
        (("orange", "aurant", "crocea"), "Often shows orange to orange-yellow tones."),
        (("yellow", "xanth", "flav", "lute", "citrin", "limoneus"), "Often shows yellow or yellow-green tones."),
        (("red", "ruber", "rubra", "coccinea", "sanguinea", "rubicundus"), "Often shows red, scarlet, or reddish tones."),
        (("green", "viride", "virescens", "aerugin"), "Often shows green to blue-green tones."),
        (("white", "leuco", "lactea", "virgine"), "Often pale white to cream."),
        (("black", "niger", "hypoxylon"), "Often dark brown to black at maturity."),
        (("brown", "brunne", "fusc"), "Often brown to tan."),
        (("grey", "gray", "cinerea"), "Often grey to ash-coloured."),
        (("violet", "zollinger", "lilacin"), "Often shows violet, lilac, or purple tones."),
    ]
    for needles, feature in checks:
        color_word = feature.split(" ")[2].lower()
        if color_word in existing:
            return
        if any(needle in blob for needle in needles):
            add_unique(features, feature)
            return


SPECIES_OVERRIDES = {
    "Agaricus campestris": [
        "White to cream cap, often flattening with age.",
        "Free gills that change from pinkish to chocolate-brown.",
        "Usually has a short white stem with a fragile ring.",
        "Commonly appears in grassland, lawns, and pasture.",
    ],
    "Agaricus xanthodermus": [
        "White cap and stem often bruise bright yellow, especially at the base.",
        "Free gills mature from pale pink to dark brown.",
        "Cap is often boxy or flat-topped when young.",
        "Commonly appears in lawns, gardens, and disturbed ground.",
    ],
    "Aleuria aurantia": [
        "Bright orange cup-shaped fruiting bodies.",
        "Often resembles pieces of orange peel on bare soil or disturbed ground.",
        "Smooth inner surface with a paler outer surface.",
        "Usually lacks a distinct stem.",
    ],
    "Amanita muscaria": [
        "Red to orange cap commonly carries white veil patches.",
        "White gills and a white stem with a ring.",
        "Bulbous stem base usually has veil remnants.",
        "Often occurs with introduced birch, pine, or other ectomycorrhizal trees.",
    ],
    "Amanita xanthocephala": [
        "Small Amanita with an orange to yellow-orange cap.",
        "White gills and a pale stem.",
        "Cap commonly carries pale veil patches.",
        "Usually grows on soil in eucalypt woodland or forest.",
    ],
    "Aseroe rubra": [
        "Starfish-like arms emerge from an egg-like stage.",
        "Mature arms are red and often carry dark spore slime.",
        "Fruit bodies often have a strong odour when mature.",
        "Usually appears on mulch, litter, or disturbed soil.",
    ],
    "Clathrus archeri": [
        "Red arms open from an egg-like stage.",
        "Mature fruit body often resembles an octopus or starfish.",
        "Dark spore slime occurs on the inner arm surfaces.",
        "Fruit bodies often have a strong odour when mature.",
    ],
    "Clathrus ruber": [
        "Red to orange lattice-like fruit body.",
        "Develops from a whitish egg-like stage.",
        "Dark spore slime occurs on the inner lattice surfaces.",
        "Fruit bodies often have a strong odour when mature.",
    ],
    "Ileodictyon gracile": [
        "White cage-like fruit body with open lattice walls.",
        "Develops from an egg-like stage.",
        "Mature cages may detach and roll away from the base.",
        "Often found in litter, mulch, or grass.",
    ],
    "Morchella australiana": [
        "Honeycomb-like cap with deep pits and ridges.",
        "Cap is attached to a pale hollow stem.",
        "Fruit body is usually hollow when cut lengthwise.",
        "Often appears on soil after disturbance or fire in suitable habitats.",
    ],
    "Omphalotus nidiformis": [
        "Pale fan to funnel-shaped caps often grow in overlapping clusters.",
        "Gills run down the stem or attachment point.",
        "Often grows from wood, buried roots, or tree bases.",
        "Fresh gills can show greenish bioluminescence in darkness.",
    ],
    "Phallus indusiatus": [
        "Tall stinkhorn with a bell-shaped head.",
        "A net-like veil hangs below the head when fresh.",
        "Develops from an egg-like stage.",
        "Mature head carries dark spore slime with a strong odour.",
    ],
    "Phallus multicolor": [
        "Tall stinkhorn with a yellow to orange net-like veil.",
        "Bell-shaped head carries dark spore slime when mature.",
        "Develops from an egg-like stage.",
        "Fruit bodies often have a strong odour when mature.",
    ],
    "Pleurotus ostreatus": [
        "Overlapping oyster-shaped caps grow from wood.",
        "Gills run down the short lateral stem or attachment point.",
        "Caps are usually pale grey, cream, or brownish.",
        "Often fruits in shelves on dead or dying wood.",
    ],
    "Schizophyllum commune": [
        "Small fan-shaped brackets on dead wood.",
        "Underside has split-looking gill folds.",
        "Upper surface is often pale and hairy.",
        "Fruit bodies can dry out and revive after rain.",
    ],
    "Xylaria hypoxylon": [
        "Slender black branching clubs grow from dead wood.",
        "Tips are often whitish and powdery when producing spores.",
        "Fruit bodies become darker and tougher with age.",
        "Commonly appears in clustered tufts on decaying wood.",
    ],
    "Xylaria polymorpha": [
        "Thick black club-shaped fruit bodies resemble blunt fingers.",
        "Surface is often black and roughened at maturity.",
        "Interior is pale to whitish when fresh.",
        "Usually grows from buried or decaying wood.",
    ],
}

GENUS_FEATURES = {
    "Agaricus": [
        "Mushroom has a cap, central stem, and free gills.",
        "Gills usually darken as spores mature.",
        "Often grows on soil, lawns, pasture, or disturbed ground.",
    ],
    "Agrocybe": [
        "Small to medium brownish mushrooms with attached gills.",
        "Caps are often dry to slightly sticky when fresh.",
        "Brown spore colour usually darkens mature gills.",
        "Commonly grows on soil, mulch, grass, or woody debris.",
    ],
    "Amanita": [
        "Mushroom has pale gills and a central stem.",
        "Veil remnants may appear as cap patches, a ring, or a basal cup.",
        "Stem base is important and should be checked carefully.",
        "Usually grows on soil with nearby trees.",
    ],
    "Armillaria": [
        "Honey-brown mushrooms often grow in clusters from wood or tree bases.",
        "Gills are pale and attached to the stem.",
        "A ring may be present on the upper stem.",
        "Often associated with roots, stumps, or living trees.",
    ],
    "Auricularia": [
        "Ear-shaped, rubbery to gelatinous fruit bodies.",
        "Upper surface is usually brown and smooth to finely hairy.",
        "Underside is smoother and often paler.",
        "Usually grows from dead or living wood.",
    ],
    "Boletellus": [
        "Bolete with pores rather than gills under the cap.",
        "Cap surface is often dry, textured, or scaly.",
        "Stem is central and usually firm.",
        "Usually grows on soil with nearby trees.",
    ],
    "Boletus": [
        "Fleshy bolete with pores rather than gills.",
        "Central stem supports a rounded cap.",
        "Pore surface may change colour as it matures or bruises.",
        "Usually grows on soil with nearby trees.",
    ],
    "Calocera": [
        "Small yellow to orange gelatinous clubs or antlers.",
        "Fruit bodies are tough-gelatinous rather than brittle.",
        "Usually grows on decaying wood.",
    ],
    "Calycina": [
        "Tiny cup-like fruit bodies.",
        "Often bright yellow to orange-yellow.",
        "Usually grows on dead plant material or woody debris.",
    ],
    "Chlorophyllum": [
        "Large parasol-like mushroom with a scaly cap.",
        "Gills are free from the stem.",
        "A ring is usually present on the stem.",
        "Often appears in lawns, gardens, compost, or disturbed soil.",
    ],
    "Clavaria": [
        "Upright club to coral-like fruit bodies.",
        "Branches, if present, are smooth rather than gilled.",
        "Usually grows on soil or moss in grassland or forest.",
    ],
    "Clavulina": [
        "Coral-like fruit bodies with blunt or crested branches.",
        "Branches are smooth and brittle rather than gilled.",
        "Usually grows on soil or litter in forest.",
    ],
    "Clavulinopsis": [
        "Small club or coral-like fruit bodies.",
        "Often brightly coloured yellow, orange, pink, or red.",
        "Usually grows among moss, grass, or litter.",
    ],
    "Coprinellus": [
        "Small inkcap mushrooms often grow in clusters.",
        "Caps are delicate and may become pleated or mica-flecked.",
        "Gills darken strongly as spores mature.",
        "Commonly grows from wood, buried wood, or rich soil.",
    ],
    "Coprinopsis": [
        "Inkcap mushrooms with gills that darken and may liquefy.",
        "Caps are often grey, shaggy, or finely hairy when young.",
        "Usually grows on rich soil, dung, litter, or buried wood.",
    ],
    "Coprinus": [
        "Tall shaggy cap with upturned scales when young.",
        "Gills change from white to pink and then black.",
        "Mature cap edges often liquefy into black ink.",
        "Usually grows in grass, soil, or disturbed places.",
    ],
    "Cortinarius": [
        "Gilled mushroom often with rusty-brown mature spores.",
        "Young specimens may show a cobweb-like veil between cap and stem.",
        "Stem or cap colours can be strong but variable.",
        "Usually grows on soil with nearby trees.",
    ],
    "Cyathus": [
        "Tiny cup-shaped fruit bodies resemble bird nests.",
        "Cups contain small egg-like spore packets.",
        "Outer surface may be hairy or rough.",
        "Often grows on dung, mulch, sticks, or plant debris.",
    ],
    "Dacrymyces": [
        "Small yellow to orange gelatinous fruit bodies.",
        "Often forms spatula, fan, or cushion shapes.",
        "Usually grows on dead wood.",
    ],
    "Entoloma": [
        "Gilled mushroom with pinkish mature spore colour.",
        "Gills are attached to notched or sinuate near the stem.",
        "Cap and stem colours are often distinctive but variable.",
        "Usually grows on soil or litter.",
    ],
    "Galerina": [
        "Small brown mushrooms with rusty-brown spores.",
        "Caps are often moist-looking and change colour as they dry.",
        "Usually grows on moss, litter, or decaying wood.",
    ],
    "Ganoderma": [
        "Woody bracket or shelf fungus with a pore surface underneath.",
        "Upper surface may be lacquered, dull, or concentrically zoned.",
        "Usually grows from wood, roots, or tree bases.",
    ],
    "Geastrum": [
        "Earthstar fruit body splits into star-like rays.",
        "Central spore sac sits above the opened rays.",
        "Mature spores leave through a small pore at the top.",
        "Usually grows on soil, litter, or sandy ground.",
    ],
    "Gymnopilus": [
        "Orange-brown to rusty gilled mushrooms.",
        "Mature gills become rusty from spores.",
        "Often grows on wood, buried wood, or woody debris.",
    ],
    "Hericium": [
        "White to cream fruit bodies made of hanging spines.",
        "Lacks gills and pores.",
        "Usually grows from dead or living wood.",
    ],
    "Hygrocybe": [
        "Waxcap mushroom with thick, waxy gills.",
        "Caps are often brightly coloured and moist when fresh.",
        "Usually grows in grassland, moss, or forest litter.",
    ],
    "Hypholoma": [
        "Clustered gilled mushrooms often grow from wood.",
        "Gills darken to grey-brown or purplish-brown.",
        "Caps are usually yellow, orange, or brownish.",
    ],
    "Laccaria": [
        "Small to medium gilled mushrooms with widely spaced gills.",
        "Caps and stems are often tan, pinkish, or lilac-brown.",
        "Usually grows on soil with trees.",
    ],
    "Lactarius": [
        "Gilled mushroom that exudes latex when damaged.",
        "Cap is often funnel-shaped with age.",
        "Usually grows on soil with host trees.",
    ],
    "Leucocoprinus": [
        "Delicate dapperling with free white gills.",
        "Cap is often thin, pleated, or powdery-scaly.",
        "A fragile ring may be present on the stem.",
        "Often appears in gardens, pots, compost, or rich soil.",
    ],
    "Lycoperdon": [
        "Puffball fruit body lacks exposed gills.",
        "Outer surface may be warty, spiny, or finely granular.",
        "Mature spores are released as powder from an opening.",
        "Usually grows on soil, grass, or litter.",
    ],
    "Macrolepiota": [
        "Tall parasol mushroom with a broad scaly cap.",
        "Gills are free and pale.",
        "A ring is usually present on the stem.",
        "Often grows in grassland, woodland edges, or open soil.",
    ],
    "Marasmius": [
        "Small, tough gilled mushrooms.",
        "Caps can revive after drying in suitable conditions.",
        "Often grows on grass, leaf litter, or woody debris.",
    ],
    "Microporus": [
        "Thin fan-shaped brackets with a pore surface underneath.",
        "Caps are often concentrically zoned.",
        "Usually grows on dead wood.",
    ],
    "Mycena": [
        "Small, delicate gilled mushrooms with slender stems.",
        "Caps are usually conical to bell-shaped.",
        "Often grows on wood, bark, moss, or leaf litter.",
    ],
    "Panaeolus": [
        "Small brownish mushrooms with dark mottled gills.",
        "Caps are often bell-shaped to convex.",
        "Often grows in grass, dung-enriched soil, or pasture.",
    ],
    "Panellus": [
        "Small shelf-like mushrooms on wood.",
        "Stem is short, lateral, or absent.",
        "Gills radiate from the attachment point.",
    ],
    "Phlebopus": [
        "Large bolete with pores instead of gills.",
        "Cap and stem are robust and fleshy.",
        "Usually grows on soil, often near trees or disturbed ground.",
    ],
    "Ramaria": [
        "Coral-like fruit body with repeated branching.",
        "Branches arise from a common base.",
        "Usually grows on soil or litter in forest.",
    ],
    "Russula": [
        "Brittle gilled mushroom with a chalky snapping texture.",
        "Gills are usually pale and attached to the stem.",
        "Usually grows on soil with nearby trees.",
    ],
    "Scleroderma": [
        "Earthball fruit body with a tough outer skin.",
        "Interior becomes dark and powdery as spores mature.",
        "Lacks exposed gills or a typical cap-and-stem form.",
        "Usually grows on soil or disturbed ground.",
    ],
    "Stereum": [
        "Thin leathery brackets or crusts on wood.",
        "Underside is smooth rather than pored.",
        "Upper surface often shows bands or zones.",
    ],
    "Suillus": [
        "Bolete with pores instead of gills.",
        "Cap is often sticky or slimy when fresh.",
        "Usually grows with pines or other conifers.",
    ],
    "Trametes": [
        "Thin bracket fungus with a pore surface underneath.",
        "Upper surface often shows concentric colour zones.",
        "Usually grows on dead wood.",
    ],
    "Tremella": [
        "Gelatinous lobed fruit bodies.",
        "Texture is soft and jelly-like when fresh.",
        "Usually grows on wood or on other wood-inhabiting fungi.",
    ],
    "Usnea": [
        "Shrubby or beard-like lichen thallus.",
        "Branches are round and often elastic around a pale central cord.",
        "Usually grows on bark, branches, or exposed wood.",
    ],
    "Xylaria": [
        "Dark club-shaped or branched stromata.",
        "Texture becomes firm to woody with age.",
        "Usually grows from dead or buried wood.",
    ],
}

ORDER_FEATURES = {
    "Pezizales": [
        "Cup, disc, or saddle-shaped fruit bodies rather than a cap with gills.",
        "Spore-bearing surface is usually exposed on the inner or upper surface.",
        "Often grows on soil, litter, burnt ground, or woody debris.",
    ],
    "Polyporales": [
        "Bracket, shelf, or crust-like fruit bodies are common.",
        "Underside usually has pores rather than gills.",
        "Most often grows on dead or living wood.",
    ],
    "Boletales": [
        "Fleshy cap usually has pores or tubes rather than gills.",
        "Central stem is usually present.",
        "Often grows on soil with nearby host trees.",
    ],
    "Phallales": [
        "Develops from an egg-like immature stage.",
        "Mature fruit body often carries dark spore slime.",
        "Fruit bodies often have a strong odour when mature.",
    ],
    "Geastrales": [
        "Earthstar or puffball-like fruit body.",
        "Outer layer opens or cracks as spores mature.",
        "Mature spores are released as dry powder.",
    ],
    "Dacrymycetales": [
        "Gelatinous yellow to orange fruit bodies.",
        "Often forms cushions, clubs, fans, or antler-like shapes.",
        "Usually grows on dead wood.",
    ],
    "Xylariales": [
        "Dark stromatic fruit bodies on wood or plant material.",
        "Texture is usually firm, crust-like, or woody.",
        "Often becomes blackish at maturity.",
    ],
    "Pucciniales": [
        "Rust fungus forming coloured pustules or patches on host plants.",
        "Usually observed on leaves, stems, or young shoots.",
        "Host plant association is important for identification.",
    ],
}

LICHEN_GENERA = {
    "Baeomyces", "Cladia", "Cladonia", "Dibaeis", "Flavoparmelia",
    "Lichenomphalia", "Pseudocyphellaria", "Pulchrocladia",
    "Rhizocarpon", "Stereocaulon", "Teloschistes", "Thysanothecium",
    "Usnea", "Xanthoria",
}

WOOD_DECAY_GENERA = {
    "Bjerkandera", "Byssomerulius", "Cerrena", "Chlorociboria",
    "Fomitopsis", "Hexagonia", "Laetiporus", "Meruliopsis",
    "Phaeotrametes", "Picipes", "Piptoporus", "Podoscypha",
    "Postia", "Rhizochaete", "Ryvardenia", "Sanguinoderma",
    "Trichaptum", "Truncospora",
}


def generated_features(card):
    name = str(card.get("scientificName") or "")
    taxonomy = card.get("taxonomy") if isinstance(card.get("taxonomy"), dict) else {}
    genus = str(taxonomy.get("genus") or name.split(" ")[0])
    order = str(taxonomy.get("order") or "")
    blob = text_blob(card)
    features = []

    has_override = name in SPECIES_OVERRIDES
    for feature in SPECIES_OVERRIDES.get(name, []):
        add_unique(features, feature)

    if genus in LICHEN_GENERA and not has_override:
        add_unique(features, "Lichenized fungus forming a visible thallus rather than a typical mushroom.")
        add_unique(features, "Growth form and substrate are important field clues.")
        add_unique(features, "Usually found on bark, wood, rock, soil, or moss depending on species.")
    elif genus in WOOD_DECAY_GENERA and not has_override:
        add_unique(features, "Wood-inhabiting fungus, often forming brackets, shelves, or crusts.")
        add_unique(features, "Fertile surface is usually pored, toothed, or smooth rather than gilled.")
        add_unique(features, "Often grows on dead wood, logs, branches, or tree bases.")

    if not has_override or len(features) < 3:
        for feature in GENUS_FEATURES.get(genus, []):
            add_unique(features, feature)

    if len(features) < 3:
        for feature in ORDER_FEATURES.get(order, []):
            add_unique(features, feature)

    if "stinkhorn" in blob:
        add_unique(features, "Develops from an egg-like immature stage.")
        add_unique(features, "Mature fruit body often carries dark spore slime.")
        add_unique(features, "Fruit bodies often have a strong odour when mature.")
    if "bird" in blob and "nest" in blob:
        add_unique(features, "Tiny cup-shaped fruit bodies resemble bird nests.")
        add_unique(features, "Cups contain small egg-like spore packets.")
    if "jelly" in blob:
        add_unique(features, "Texture is gelatinous and jelly-like when fresh.")
        add_unique(features, "Often grows on dead wood or woody debris.")
    if "bolete" in blob:
        add_unique(features, "Has pores or tubes rather than gills under the cap.")
        add_unique(features, "Usually has a fleshy cap and central stem.")
    if "bracket" in blob or "polypore" in blob:
        add_unique(features, "Bracket or shelf-like fruit bodies grow from wood.")
        add_unique(features, "Underside usually has pores rather than gills.")
    if "ink cap" in blob or "inkcap" in blob:
        add_unique(features, "Gills darken strongly as spores mature.")
        add_unique(features, "Caps may collapse or liquefy at maturity.")

    color_features(blob, features)

    if len(features) < 3:
        add_unique(features, "Field characters should be checked from several fresh specimens.")
        add_unique(features, "Substrate and nearby plants are useful identification clues.")
        add_unique(features, "Microscopic or expert confirmation may be needed for similar species.")

    return features[:6]


def existing_states(card):
    distribution = card.get("distribution")
    if not isinstance(distribution, dict):
        return []
    states = []
    for state in distribution.get("states") or []:
        normalized = normalize_state(state) or str(state).strip()
        if normalized and normalized not in states:
            states.append(normalized)
    return states


def build_location(card, cache):
    name = str(card.get("scientificName") or "")
    gbif = gbif_location(name, cache)
    global_regions = list(gbif.get("global") or [])
    states = list(gbif.get("states") or [])

    for state in existing_states(card):
        if state not in states:
            states.append(state)
    states = [AU_STATES.get(state.lower(), state) for state in states]
    states = sorted(dict.fromkeys(states))

    if not global_regions:
        distribution = card.get("distribution")
        if isinstance(distribution, dict) and distribution.get("country"):
            country = str(distribution.get("country"))
            if country == "Australia":
                global_regions = ["Australia"]
            else:
                global_regions = [country]

    notes = []
    if gbif.get("matched"):
        notes.append("GBIF occurrence facets used for broad presence regions.")
    else:
        notes.append("GBIF match unavailable; existing app distribution retained where present.")
    if states:
        notes.append("Australian states combine public occurrence facets with existing app distribution records.")
    notes.append("Presence only. No abundance or frequency implied.")

    return {
        "global": global_regions,
        "australia": {"states": states},
        "regionalNotes": notes,
    }


def update_sources(card):
    sources = card.get("sources")
    if not isinstance(sources, dict):
        sources = {}
    sources.setdefault("taxonomy", "GBIF Backbone")
    sources["keyFeatures"] = (
        "Field-guide summary from taxonomy, existing descriptions, and reputable public sources"
    )
    sources["location"] = "GBIF occurrence facets and existing app distribution records"
    card["sources"] = sources


def enrich_file(path, cache):
    data = json.loads(path.read_text(encoding="utf-8-sig"))
    cards = data.get("cards", []) if isinstance(data, dict) else data
    for card in cards:
        if not isinstance(card, dict):
            continue
        card["keyFeatures"] = generated_features(card)
        card["location"] = build_location(card, cache)
        update_sources(card)
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def main():
    cache = load_cache()
    for path in DATA_FILES:
        enrich_file(path, cache)
        save_cache(cache)


if __name__ == "__main__":
    main()
