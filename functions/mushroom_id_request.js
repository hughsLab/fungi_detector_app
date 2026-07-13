"use strict";

const mushroomIdUrl =
  "https://mushroom.kindwise.com/api/v1/identification" +
  "?details=common_names,url,description,edibility,toxicity,look_alikes," +
  "taxonomy,rank";

const maxImageBytes = 5 * 1024 * 1024;
const maxImageBase64Chars = 7 * 1024 * 1024;

function normalizeImageBase64(input) {
  if (typeof input !== "string") {
    throw invalidImage("invalid_image", "imageBase64 is required.");
  }

  const trimmed = input.trim();
  if (!trimmed) {
    throw invalidImage("invalid_image", "imageBase64 is required.");
  }

  const base64 = stripDataUrlPrefix(trimmed).replace(/\s/g, "");
  if (!base64) {
    throw invalidImage("invalid_image", "Image data is invalid.");
  }
  if (base64.length > maxImageBase64Chars) {
    throw invalidImage(
      "invalid_image",
      "Image is too large for online identification.",
      413,
    );
  }
  if (base64.length % 4 !== 0 || !/^[A-Za-z0-9+/]+={0,2}$/.test(base64)) {
    throw invalidImage("invalid_image", "Image data is not valid base64.");
  }

  const bytes = Buffer.from(base64, "base64");
  if (bytes.length <= 0) {
    throw invalidImage("invalid_image", "Image data is invalid.");
  }
  if (bytes.length > maxImageBytes) {
    throw invalidImage(
      "invalid_image",
      "Image is too large for online identification.",
      413,
    );
  }

  return base64;
}

function createMushroomIdRequest(apiKey, imageBase64) {
  return {
    url: mushroomIdUrl,
    options: {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Api-Key": apiKey,
      },
      body: JSON.stringify({
        images: [imageBase64],
        similar_images: true,
      }),
    },
  };
}

function stripDataUrlPrefix(value) {
  const match = value.match(/^data:[^,]*;base64,(.*)$/is);
  return match ? match[1] : value;
}

function invalidImage(code, message, status = 400) {
  const error = new Error(message);
  error.code = code;
  error.status = status;
  return error;
}

module.exports = {
  createMushroomIdRequest,
  maxImageBase64Chars,
  maxImageBytes,
  mushroomIdUrl,
  normalizeImageBase64,
};
