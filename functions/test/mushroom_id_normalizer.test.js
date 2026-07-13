"use strict";

const assert = require("node:assert/strict");
const {test} = require("node:test");
const {
  normalizeMushroomIdResponse,
} = require("../mushroom_id_normalizer");

test("normalizes mushroom.id suggestions into app DTO", () => {
  const dto = normalizeMushroomIdResponse({
    result: {
      classification: {
        suggestions: [
          {
            name: "Amanita muscaria",
            probability: 0.6433,
            details: {
              common_names: ["Fly agaric"],
              edibility: "poisonous",
              toxicity: "toxic if eaten",
              rank: "species",
              url: "https://example.com/amanita",
              description: {value: "Red cap with white warts."},
              taxonomy: {
                kingdom: "Fungi",
                phylum: "Basidiomycota",
                class: "Agaricomycetes",
                order: "Agaricales",
                family: "Amanitaceae",
                genus: "Amanita",
              },
            },
            similar_images: [
              {
                url_small: "https://example.com/small.jpg",
                url: "https://example.com/full.jpg",
                similarity: 0.694,
                citation: "Example",
                license_name: "CC BY",
              },
            ],
          },
          {
            name: "Amanita parcivolvata",
            probability: 0.1589,
            details: {
              common_names: ["False fly agaric"],
              url: "https://example.com/alt",
            },
          },
        ],
      },
    },
  });

  assert.equal(dto.source, "mushroom.id");
  assert.equal(dto.topSuggestion.scientificName, "Amanita muscaria");
  assert.equal(dto.topSuggestion.confidencePercent, 64.33);
  assert.deepEqual(dto.topSuggestion.commonNames, ["Fly agaric"]);
  assert.equal(dto.topSuggestion.edibility, "poisonous");
  assert.equal(dto.topSuggestion.taxonomy.genus, "Amanita");
  assert.equal(dto.topSuggestion.similarImages[0].licenseName, "CC BY");
  assert.equal(dto.alternatives.length, 1);
  assert.equal(dto.alternatives[0].scientificName, "Amanita parcivolvata");
  assert.equal(dto.locationFilterApplied, false);
});

test("handles empty suggestions", () => {
  const dto = normalizeMushroomIdResponse({
    result: {classification: {suggestions: []}},
  });

  assert.equal(dto.topSuggestion, null);
  assert.deepEqual(dto.alternatives, []);
  assert.equal(dto.onlineIdentification, true);
});
