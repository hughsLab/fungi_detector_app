"use strict";

const admin = require("firebase-admin");
const {defineSecret} = require("firebase-functions/params");
const {onRequest} = require("firebase-functions/v2/https");
const {
  normalizeMushroomIdResponse,
} = require("./mushroom_id_normalizer");
const {
  createMushroomIdRequest,
  mushroomIdUrl,
  normalizeImageBase64,
} = require("./mushroom_id_request");

admin.initializeApp();

// Configure with:
// firebase functions:secrets:set MUSHROOM_ID_API_KEY
// The mushroom.id API key must never be placed in Flutter, Remote Config,
// Firestore, assets, or any client-visible code.
const mushroomIdApiKey = defineSecret("MUSHROOM_ID_API_KEY");

exports.identifyMushroomOnline = onRequest(
  {
    region: "australia-southeast1",
    secrets: [mushroomIdApiKey],
    timeoutSeconds: 60,
    memory: "512MiB",
    cors: true,
  },
  async (req, res) => {
    console.info("identifyMushroomOnline invoked");
    console.info("method", req.method);
    console.info("auth present", Boolean(req.get("Authorization")));
    console.info("content-type", req.headers["content-type"] || "unknown");
    try {
      if (req.method === "GET") {
        const apiKey = mushroomIdApiKey.value();
        console.info("MUSHROOM_ID_API_KEY present:", Boolean(apiKey));
        return res.status(200).json({
          ok: true,
          service: "identifyMushroomOnline",
          apiKeyConfigured: Boolean(apiKey),
          method: req.method,
        });
      }

      if (req.method !== "POST") {
        return sendError(res, 405, "method-not-allowed", "Use POST.");
      }

      const uid = await verifyAuth(req);
      console.info("authenticated user present:", Boolean(uid));
      if (!uid) {
        return sendError(
          res,
          401,
          "unauthenticated",
          "Sign in before using online identification.",
        );
      }

      let imageBase64;
      try {
        imageBase64 = normalizeImageBase64(req.body && req.body.imageBase64);
      } catch (error) {
        return sendError(
          res,
          error.status || 400,
          error.code || "invalid_image",
          error.message || "Image data is invalid.",
        );
      }
      console.info("imageBase64 length:", imageBase64.length);

      const apiKey = mushroomIdApiKey.value();
      console.info("MUSHROOM_ID_API_KEY present:", Boolean(apiKey));
      if (!apiKey) {
        return sendError(
          res,
          500,
          "backend_config_missing",
          "Online identification backend is not configured.",
        );
      }

      console.info("outgoing mushroom.id URL:", mushroomIdUrl);
      const request = createMushroomIdRequest(apiKey, imageBase64);
      const upstream = await fetch(request.url, request.options);
      console.info("mushroom.id HTTP status:", upstream.status);

      if (!upstream.ok) {
        return sendUpstreamError(res, upstream.status);
      }

      const raw = await upstream.json();
      const dto = normalizeMushroomIdResponse(raw);
      const suggestionsCount = dto.topSuggestion ? dto.alternatives.length + 1 : 0;
      console.info("suggestions count > 0:", suggestionsCount > 0);
      if (dto.topSuggestion) {
        console.info("top suggestion:", {
          name: dto.topSuggestion.scientificName,
          probability: dto.topSuggestion.probability,
        });
      }
      if (!dto.topSuggestion) {
        return sendError(
          res,
          422,
          "no_suggestions",
          "No online identification suggestions were returned for this image.",
        );
      }
      return res.status(200).json(dto);
    } catch (error) {
      console.error("identifyMushroomOnline failed", {
        message: error && error.message,
        code: error && error.code,
      });
      return sendError(
        res,
        500,
        "backend_unavailable",
        "Online identification is unavailable right now.",
      );
    }
  },
);

async function verifyAuth(req) {
  const authHeader = req.get("Authorization") || "";
  const match = authHeader.match(/^Bearer\s+(.+)$/i);
  if (!match) {
    return null;
  }
  try {
    const decoded = await admin.auth().verifyIdToken(match[1]);
    return decoded.uid || null;
  } catch (_) {
    return null;
  }
}

function sendUpstreamError(res, status) {
  if (status === 401 || status === 403) {
    return sendError(
      res,
      500,
      "backend_config_missing",
      "Online identification backend is not configured.",
    );
  }
  if (status === 402 || status === 429) {
    return sendError(
      res,
      429,
      "quota_or_credits_unavailable",
      "Online identification credits are unavailable.",
    );
  }
  if (status >= 500) {
    return sendError(
      res,
      502,
      "backend_unavailable",
      "Online identification provider is unavailable right now.",
    );
  }
  return sendError(
    res,
    400,
    "mushroom_id_rejected",
    "Online identification provider rejected the image.",
  );
}

function sendError(res, status, code, message) {
  return res.status(status).json({error: code, code, message});
}
