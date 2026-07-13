"use strict";

const warnings = [
  "Do not consume fungi based on app identification.",
  "Online identification is probabilistic and should be verified by an expert.",
];

function normalizeMushroomIdResponse(raw) {
  const suggestions = readSuggestions(raw);
  const normalized = suggestions.map(normalizeSuggestion);
  const topSuggestion = normalized[0] || null;
  return {
    source: "mushroom.id",
    onlineIdentification: true,
    topSuggestion,
    alternatives: normalized.slice(1, 4).map(compactAlternative),
    warnings,
    regionSupported: null,
    locationFilterApplied: false,
  };
}

function readSuggestions(raw) {
  const candidates = [
    raw && raw.result && raw.result.classification &&
      raw.result.classification.suggestions,
    raw && raw.classification && raw.classification.suggestions,
    raw && raw.suggestions,
  ];
  for (const value of candidates) {
    if (Array.isArray(value)) {
      return value;
    }
  }
  return [];
}

function normalizeSuggestion(suggestion) {
  const details = objectOrEmpty(suggestion && suggestion.details);
  const probability = numberOrZero(suggestion && suggestion.probability);
  const commonNames = arrayOfStrings(
    details.common_names || details.commonNames,
  );
  return {
    scientificName: stringOrEmpty(
      (suggestion && suggestion.name) ||
        details.scientific_name ||
        details.scientificName,
    ),
    probability,
    confidencePercent: round(probability * 100, 2),
    commonNames,
    edibility: optionalString(details.edibility),
    toxicity: optionalString(details.toxicity),
    rank: optionalString(details.rank),
    description: normalizeDescription(details.description),
    url: optionalString(details.url),
    taxonomy: normalizeTaxonomy(details.taxonomy),
    similarImages: normalizeSimilarImages(suggestion && suggestion.similar_images),
  };
}

function compactAlternative(suggestion) {
  return {
    scientificName: suggestion.scientificName,
    probability: suggestion.probability,
    confidencePercent: suggestion.confidencePercent,
    commonNames: suggestion.commonNames,
    edibility: suggestion.edibility,
    url: suggestion.url,
  };
}

function normalizeDescription(value) {
  if (typeof value === "string") {
    return optionalString(value);
  }
  if (value && typeof value === "object") {
    return optionalString(value.value || value.text);
  }
  return undefined;
}

function normalizeTaxonomy(value) {
  const source = objectOrEmpty(value);
  const keys = ["kingdom", "phylum", "class", "order", "family", "genus"];
  const output = {};
  for (const key of keys) {
    const text = optionalString(source[key]);
    if (text) {
      output[key] = text;
    }
  }
  return output;
}

function normalizeSimilarImages(value) {
  if (!Array.isArray(value)) {
    return [];
  }
  return value.slice(0, 5).map((image) => ({
    urlSmall: optionalString(image && (image.url_small || image.urlSmall)),
    url: optionalString(image && image.url),
    similarity: optionalNumber(image && image.similarity),
    citation: optionalString(image && image.citation),
    licenseName: optionalString(
      image && (image.license_name || image.licenseName),
    ),
  }));
}

function objectOrEmpty(value) {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value
    : {};
}

function stringOrEmpty(value) {
  return optionalString(value) || "";
}

function optionalString(value) {
  if (value === null || value === undefined) {
    return undefined;
  }
  const text = String(value).trim();
  return text === "" ? undefined : text;
}

function arrayOfStrings(value) {
  if (!Array.isArray(value)) {
    return [];
  }
  return value
    .map((item) => optionalString(item))
    .filter((item) => item);
}

function numberOrZero(value) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

function optionalNumber(value) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : undefined;
}

function round(value, digits) {
  const factor = 10 ** digits;
  return Math.round(value * factor) / factor;
}

module.exports = {
  normalizeMushroomIdResponse,
};
