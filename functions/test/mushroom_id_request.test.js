"use strict";

const assert = require("node:assert/strict");
const {test} = require("node:test");
const {
  createMushroomIdRequest,
  mushroomIdUrl,
  normalizeImageBase64,
} = require("../mushroom_id_request");

test("normalizes pure base64 image input", () => {
  const imageBase64 = Buffer.from("fixture image bytes").toString("base64");

  assert.equal(normalizeImageBase64(imageBase64), imageBase64);
});

test("normalizes data URL image input", () => {
  const imageBase64 = Buffer.from("fixture image bytes").toString("base64");

  assert.equal(
    normalizeImageBase64(`data:image/jpeg;base64,${imageBase64}`),
    imageBase64,
  );
});

test("builds mushroom.id request with expected URL, headers, and body", () => {
  const imageBase64 = Buffer.from("fixture image bytes").toString("base64");
  const request = createMushroomIdRequest("server-side-secret", imageBase64);

  assert.equal(request.url, mushroomIdUrl);
  assert.equal(request.options.method, "POST");
  assert.equal(request.options.headers["Content-Type"], "application/json");
  assert.equal(request.options.headers["Api-Key"], "server-side-secret");
  assert.deepEqual(JSON.parse(request.options.body), {
    images: [imageBase64],
    similar_images: true,
  });
});

test("rejects invalid base64 image input", () => {
  assert.throws(
    () => normalizeImageBase64("not valid base64"),
    /Image data is not valid base64/,
  );
});
