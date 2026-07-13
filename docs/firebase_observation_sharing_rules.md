# Firebase Observation Sharing Rules

## Firestore Structure

Observations are stored as full documents in:

```text
/observations/{observationId}
```

User profiles are stored in:

```text
/users/{uid}
/usernames/{usernameLower}
```

Public observation documents may include `ownerUsername` and
`ownerDisplayName`. They must not include owner email addresses.

Public map reads query:

```text
/observations where isPublic == true orderBy observedAt desc limit 300
```

The in-app map combines that public stream with the signed-in user's own
observation stream so owners can still see private observations and mark them
public later.

My-observations reads query:

```text
/observations where userId == request.auth.uid orderBy observedAt desc
```

Missing `isPublic` is treated as private by the app and by these rules.

## Firestore Rules

```text
rules_version = '2';

service cloud.firestore {
  match /databases/{database}/documents {
    function signedIn() {
      return request.auth != null;
    }

    function ownsUserProfile(uid) {
      return signedIn() && request.auth.uid == uid;
    }

    match /users/{uid} {
      allow read: if signedIn();

      allow create: if ownsUserProfile(uid)
        && request.resource.data.uid == request.auth.uid;

      allow update: if ownsUserProfile(uid)
        && request.resource.data.uid == resource.data.uid;

      allow delete: if false;
    }

    match /usernames/{usernameLower} {
      allow read: if signedIn();

      allow create: if signedIn()
        && request.resource.data.uid == request.auth.uid
        && !exists(/databases/$(database)/documents/usernames/$(usernameLower));

      allow update: if signedIn()
        && resource.data.uid == request.auth.uid
        && request.resource.data.uid == resource.data.uid;

      allow delete: if signedIn()
        && resource.data.uid == request.auth.uid;
    }

    match /observations/{observationId} {
      allow read: if signedIn()
        && (
          resource.data.userId == request.auth.uid ||
          resource.data.isPublic == true
        );

      allow create: if signedIn()
        && request.resource.data.userId == request.auth.uid
        && !('ownerEmail' in request.resource.data);

      allow update: if signedIn()
        && resource.data.userId == request.auth.uid
        && request.resource.data.userId == resource.data.userId
        && !('ownerEmail' in request.resource.data);

      allow delete: if signedIn()
        && resource.data.userId == request.auth.uid;
    }
  }
}
```

## Storage Structure

Observation photos are stored in:

```text
users/{uid}/observations/{observationId}/photo.jpg
```

## Storage Rules

Firestore lookups from Storage rules can enforce public/private read access
against the linked observation document:

```text
rules_version = '2';

service firebase.storage {
  match /b/{bucket}/o {
    match /users/{uid}/observations/{observationId}/{fileName} {
      allow write: if request.auth != null
        && request.auth.uid == uid;

      allow read: if request.auth != null
        && (
          request.auth.uid == uid ||
          firestore.get(
            /databases/(default)/documents/observations/$(observationId)
          ).data.isPublic == true
        );
    }
  }
}
```

If your Firebase project cannot use Firestore document reads from Storage rules,
use the MVP fallback of allowing signed-in users to read observation images under
this path, while keeping writes owner-only:

```text
allow read: if request.auth != null;
allow write: if request.auth != null && request.auth.uid == uid;
```

Do not allow anonymous public writes.

## Required Indexes

Create these composite Firestore indexes for production:

```text
Collection: observations
Fields: isPublic Ascending, observedAt Descending
Query scope: Collection

Collection: observations
Fields: userId Ascending, observedAt Descending
Query scope: Collection
```

The app falls back from `observedAt` ordering to `createdAt` ordering if
Firestore reports a missing index, but `observedAt` should be indexed for the
intended query shape.
