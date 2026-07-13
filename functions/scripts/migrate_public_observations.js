"use strict";

const admin = require("firebase-admin");

const apply = process.argv.includes("--apply");
const limitArg = process.argv.find((arg) => arg.startsWith("--limit="));
const limit = limitArg ? Number(limitArg.split("=")[1]) : 500;

if (!Number.isFinite(limit) || limit <= 0) {
  throw new Error("Use --limit=<positive number>.");
}

admin.initializeApp();

const db = admin.firestore();

function hasValidCoordinates(data) {
  const lat = Number(data.latitude ?? data.lat ?? data.publicLat);
  const lng = Number(data.longitude ?? data.lon ?? data.lng ?? data.publicLng);
  return Number.isFinite(lat) &&
    Number.isFinite(lng) &&
    lat >= -90 &&
    lat <= 90 &&
    lng >= -180 &&
    lng <= 180;
}

async function main() {
  const snapshot = await db.collection("observations").limit(limit).get();
  let withCoordinates = 0;
  let alreadyPublic = 0;
  let candidates = 0;
  let updated = 0;

  const batch = db.batch();
  for (const doc of snapshot.docs) {
    const data = doc.data();
    const mapped = hasValidCoordinates(data);
    if (mapped) {
      withCoordinates += 1;
    }
    if (data.isPublic === true) {
      alreadyPublic += 1;
      continue;
    }
    if (!mapped) {
      continue;
    }

    candidates += 1;
    if (apply) {
      batch.update(doc.ref, {
        isPublic: true,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      updated += 1;
    }
  }

  if (apply && updated > 0) {
    await batch.commit();
  }

  console.log(JSON.stringify({
    apply,
    scanned: snapshot.docs.length,
    withCoordinates,
    alreadyPublic,
    candidates,
    updated,
  }, null, 2));
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
