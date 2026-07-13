import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import '../models/observation.dart';
import '../services/settings_service.dart';
import 'user_profile_repository.dart';

enum FirebaseObservationSaveStatus {
  saved,
  skippedNoUser,
  failed,
}

class FirebaseObservationSaveResult {
  final FirebaseObservationSaveStatus status;
  final Observation observation;
  final Object? error;

  const FirebaseObservationSaveResult({
    required this.status,
    required this.observation,
    this.error,
  });

  bool get saved => status == FirebaseObservationSaveStatus.saved;
}

class _PhotoUploadResult {
  final String? imageStoragePath;
  final String? downloadUrl;
  final String status;

  const _PhotoUploadResult({
    required this.imageStoragePath,
    required this.downloadUrl,
    required this.status,
  });

  const _PhotoUploadResult.synced({
    required String imageStoragePath,
    required String downloadUrl,
  }) : this(
          imageStoragePath: imageStoragePath,
          downloadUrl: downloadUrl,
          status: 'cloud_synced',
        );

  const _PhotoUploadResult.noPhoto()
      : this(
          imageStoragePath: null,
          downloadUrl: null,
          status: 'cloud_synced_no_photo',
        );

  const _PhotoUploadResult.failed()
      : this(
          imageStoragePath: null,
          downloadUrl: null,
          status: 'cloud_photo_failed',
        );
}

class FirebaseObservationRepository {
  FirebaseObservationRepository({
    FirebaseAuth? firebaseAuth,
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
    UserProfileRepository? userProfileRepository,
  })  : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance,
        _storage = storage ?? FirebaseStorage.instance,
        _userProfileRepository =
            userProfileRepository ?? UserProfileRepository.instance;

  static final FirebaseObservationRepository instance =
      FirebaseObservationRepository();

  final FirebaseAuth _firebaseAuth;
  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;
  final UserProfileRepository _userProfileRepository;
  final SettingsService _settingsService = SettingsService.instance;

  CollectionReference<Map<String, dynamic>> get _observations =>
      _firestore.collection('observations');

  Future<FirebaseObservationSaveResult> saveObservation(
    Observation observation, {
    String? userId,
  }) async {
    final uid = userId ?? _firebaseAuth.currentUser?.uid;
    if (uid == null || uid.trim().isEmpty) {
      debugPrint(
        'FIREBASE_OBSERVATION: no signed-in Firebase user; '
        'cloud save skipped for ${observation.id}.',
      );
      return FirebaseObservationSaveResult(
        status: FirebaseObservationSaveStatus.skippedNoUser,
        observation: observation,
      );
    }

    try {
      final profile = await _userProfileRepository.ensureUserProfile(
        user: _firebaseAuth.currentUser,
      );
      final settings = await _settingsService.loadSettings();
      final hasUsername = profile?.hasUsername ?? false;
      final showUsername =
          settings.showUsernameOnPublicObservations && hasUsername;
      final photoUpload = await _tryUploadPhoto(
        observation: observation,
        userId: uid,
      );
      final now = DateTime.now();
      final syncStatus = photoUpload.status;
      final imageStoragePath = photoUpload.imageStoragePath ??
          _nonEmptyOrNull(observation.imageStoragePath);
      final downloadUrl = photoUpload.downloadUrl ??
          _httpUrlOrNull(observation.imageUrl) ??
          _httpUrlOrNull(observation.photoPath);
      final cloudObservation = observation.copyWith(
        userId: uid,
        ownerUsername: showUsername ? profile?.username : null,
        ownerDisplayName: showUsername ? profile?.displayName : null,
        imageStoragePath: imageStoragePath,
        imageUrl: downloadUrl,
        isPublic: observation.isPublic,
        syncStatus: syncStatus,
        updatedAt: now,
      );
      if (observation.isPublic && !showUsername) {
        debugPrint(
          'FIREBASE_OBSERVATION: public save without username for '
          '${observation.id}.',
        );
      }

      await _observations.doc(observation.id).set(
            _toFirestoreDocument(
              observation: cloudObservation,
              userId: uid,
              downloadUrl: downloadUrl,
              imageStoragePath: imageStoragePath,
              syncStatus: syncStatus,
              syncedAt: now,
            ),
            SetOptions(merge: true),
          );
      debugPrint(
        'FIREBASE_OBSERVATION: saved observation ${observation.id} '
        'for user $uid.',
      );
      return FirebaseObservationSaveResult(
        status: FirebaseObservationSaveStatus.saved,
        observation: cloudObservation,
      );
    } catch (e, st) {
      debugPrint(
        'FIREBASE_OBSERVATION: cloud save failed for ${observation.id}: $e',
      );
      debugPrintStack(stackTrace: st, label: 'FIREBASE_OBSERVATION');
      return FirebaseObservationSaveResult(
        status: FirebaseObservationSaveStatus.failed,
        observation: observation.copyWith(syncStatus: 'cloud_failed'),
        error: e,
      );
    }
  }

  Stream<List<Observation>> streamPublicObservations({
    int limit = 300,
  }) async* {
    if (kDebugMode) {
      await _logPublicMapDiagnostics(limit: limit);
    }
    yield* _streamObservationQuery(
      _observations.where('isPublic', isEqualTo: true),
      limit: limit,
    );
  }

  Stream<List<Observation>> streamMyObservations({
    int limit = 300,
  }) async* {
    final uid = _firebaseAuth.currentUser?.uid;
    if (uid == null || uid.trim().isEmpty) {
      yield const <Observation>[];
      return;
    }
    yield* _streamObservationQuery(
      _observations.where('userId', isEqualTo: uid),
      limit: limit,
    );
  }

  Future<List<Observation>> loadCurrentUserObservations({
    int limit = 100,
  }) async {
    final uid = _firebaseAuth.currentUser?.uid;
    if (uid == null || uid.trim().isEmpty) {
      debugPrint(
        'FIREBASE_OBSERVATION: no signed-in Firebase user; cloud load skipped.',
      );
      return const <Observation>[];
    }

    final snapshot = await _observations
        .where('userId', isEqualTo: uid)
        .orderBy('observedAt', descending: true)
        .limit(limit)
        .get();
    debugPrint(
      'FIREBASE_OBSERVATION: loaded ${snapshot.docs.length} observation(s) '
      'for user $uid.',
    );
    return snapshot.docs.map(_fromDocument).toList(growable: false);
  }

  Future<void> updateObservationDetails(
    String observationId, {
    String? notes,
    String? locationLabel,
    bool? isPublic,
    double? publicLat,
    double? publicLng,
  }) async {
    final uid = _firebaseAuth.currentUser?.uid;
    if (uid == null || uid.trim().isEmpty) {
      debugPrint(
        'FIREBASE_OBSERVATION: no signed-in Firebase user; '
        'cloud update skipped for $observationId.',
      );
      return;
    }
    final updates = <String, dynamic>{
      'updatedAt': Timestamp.fromDate(DateTime.now()),
      'syncStatus': 'cloud_synced',
    };
    if (notes != null) updates['notes'] = notes;
    if (locationLabel != null) updates['locationLabel'] = locationLabel;
    if (isPublic != null) {
      if (isPublic) {
        final settings = await _settingsService.loadSettings();
        final profile = await _userProfileRepository.ensureUserProfile();
        final showUsername =
            settings.showUsernameOnPublicObservations &&
            (profile?.hasUsername ?? false);
        updates['ownerUsername'] = showUsername ? profile?.username : null;
        updates['ownerDisplayName'] =
            showUsername ? profile?.displayName : null;
      }
      updates['isPublic'] = isPublic;
    }
    if (publicLat != null) updates['publicLat'] = publicLat;
    if (publicLng != null) updates['publicLng'] = publicLng;

    final doc = await _observations.doc(observationId).get();
    if (!doc.exists || doc.data()?['userId'] != uid) {
      debugPrint(
        'FIREBASE_OBSERVATION: update denied locally for $observationId; '
        'document is missing or owned by another user.',
      );
      return;
    }
    await doc.reference.update(updates);
    debugPrint('FIREBASE_OBSERVATION: updated observation $observationId.');
  }

  Future<void> deleteObservation(
    String observationId, {
    bool deletePhoto = true,
  }) async {
    final uid = _firebaseAuth.currentUser?.uid;
    if (uid == null || uid.trim().isEmpty) {
      debugPrint(
        'FIREBASE_OBSERVATION: no signed-in Firebase user; '
        'cloud delete skipped for $observationId.',
      );
      return;
    }

    final doc = await _observations.doc(observationId).get();
    if (!doc.exists || doc.data()?['userId'] != uid) {
      debugPrint(
        'FIREBASE_OBSERVATION: delete denied locally for $observationId; '
        'document is missing or owned by another user.',
      );
      return;
    }

    final data = doc.data();
    await doc.reference.delete();
    if (deletePhoto) {
      final path = data?['imageStoragePath']?.toString();
      if (path != null && path.trim().isNotEmpty) {
        try {
          await _storage.ref(path).delete();
        } on FirebaseException catch (e) {
          if (e.code != 'object-not-found') {
            rethrow;
          }
        }
      }
    }
    debugPrint('FIREBASE_OBSERVATION: deleted observation $observationId.');
  }

  String _photoStoragePath(String userId, String observationId) {
    return 'users/$userId/observations/$observationId/photo.jpg';
  }

  Future<_PhotoUploadResult> _tryUploadPhoto({
    required Observation observation,
    required String userId,
  }) async {
    final photoPath = observation.photoPath?.trim();
    if (photoPath == null ||
        photoPath.isEmpty ||
        photoPath.startsWith('http://') ||
        photoPath.startsWith('https://')) {
      debugPrint(
        'FIREBASE_OBSERVATION: no local photo to upload for '
        '${observation.id}; writing metadata only.',
      );
      return _PhotoUploadResult.noPhoto();
    }

    final photoFile = File(photoPath);
    if (!await photoFile.exists()) {
      debugPrint(
        'FIREBASE_OBSERVATION: photo file missing at $photoPath for '
        '${observation.id}; writing metadata only.',
      );
      return _PhotoUploadResult.noPhoto();
    }

    try {
      final storagePath = _photoStoragePath(userId, observation.id);
      final ref = _storage.ref(storagePath);
      await ref.putFile(
        photoFile,
        SettableMetadata(
          contentType: 'image/jpeg',
          customMetadata: <String, String>{
            'observationId': observation.id,
            'userId': userId,
          },
        ),
      );
      final downloadUrl = await ref.getDownloadURL();
      return _PhotoUploadResult.synced(
        imageStoragePath: storagePath,
        downloadUrl: downloadUrl,
      );
    } catch (e, st) {
      debugPrint(
        'FIREBASE_OBSERVATION: photo upload failed for '
        '${observation.id}; writing observation metadata: $e',
      );
      debugPrintStack(stackTrace: st, label: 'FIREBASE_OBSERVATION');
      return _PhotoUploadResult.failed();
    }
  }

  Stream<List<Observation>> _streamObservationQuery(
    Query<Map<String, dynamic>> baseQuery, {
    required int limit,
  }) async* {
    Stream<List<Observation>> unorderedFallback() {
      return baseQuery.limit(limit).snapshots().map((snapshot) {
        final observations = _fromSnapshot(snapshot);
        observations.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return observations;
      });
    }

    try {
      yield* baseQuery
          .orderBy('observedAt', descending: true)
          .limit(limit)
          .snapshots()
          .map(_fromSnapshot);
    } on FirebaseException catch (e) {
      if (e.code != 'failed-precondition') {
        rethrow;
      }
      debugPrint(
        'FIREBASE_OBSERVATION: observedAt index missing; falling back to '
        'createdAt ordering. Create a composite index for production.',
      );
      try {
        yield* baseQuery
            .orderBy('createdAt', descending: true)
            .limit(limit)
            .snapshots()
            .map(_fromSnapshot);
      } on FirebaseException catch (fallbackError) {
        if (fallbackError.code != 'failed-precondition') {
          rethrow;
        }
        debugPrint(
          'FIREBASE_OBSERVATION: createdAt index also missing; falling back '
          'to unordered Firebase snapshots sorted locally.',
        );
        yield* unorderedFallback();
      }
    }
  }

  List<Observation> _fromSnapshot(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    final observations = snapshot.docs.map(_fromDocument).toList(
          growable: false,
        );
    if (kDebugMode) {
      final skipped = <String>[];
      var validCoordinates = 0;
      for (final observation in observations) {
        if (observation.location == null) {
          if (skipped.length < 5) {
            skipped.add(
              '${observation.id}: ${_coordinateSkipReason(observation)}',
            );
          }
        } else {
          validCoordinates += 1;
        }
      }
      debugPrint(
        'FIREBASE_OBSERVATION: fetched ${observations.length} observation(s); '
        '${observations.where((item) => item.isPublic).length} public; '
        '$validCoordinates with valid coordinates; '
        '${observations.length - validCoordinates} skipped because missing '
        'coordinates; marker count $validCoordinates.',
      );
      if (skipped.isNotEmpty) {
        debugPrint(
          'FIREBASE_OBSERVATION: skipped map document samples: '
          '${skipped.join(', ')}',
        );
      }
    }
    return observations;
  }

  Future<void> _logPublicMapDiagnostics({required int limit}) async {
    try {
      final snapshot = await _observations.limit(limit).get();
      var publicCount = 0;
      var skippedPrivate = 0;
      var skippedMissingCoordinates = 0;
      var markerCount = 0;
      for (final doc in snapshot.docs) {
        final observation = _fromDocument(doc);
        final isPublic = doc.data()['isPublic'] == true;
        if (isPublic) {
          publicCount += 1;
        } else {
          skippedPrivate += 1;
        }
        if (observation.location == null) {
          skippedMissingCoordinates += 1;
        } else if (isPublic) {
          markerCount += 1;
        }
      }
      debugPrint(
        'FIREBASE_OBSERVATION: public map diagnostics fetched '
        '${snapshot.docs.length}; public $publicCount; skipped because '
        'isPublic false/missing $skippedPrivate; skipped because missing '
        'coordinates $skippedMissingCoordinates; marker count $markerCount.',
      );
    } catch (e) {
      debugPrint('FIREBASE_OBSERVATION: public map diagnostics failed: $e');
    }
  }

  Map<String, dynamic> _toFirestoreDocument({
    required Observation observation,
    required String userId,
    required String? downloadUrl,
    required String? imageStoragePath,
    required String syncStatus,
    required DateTime syncedAt,
  }) {
    final json = observation.toJson();
    final imageUrl = downloadUrl ?? _httpUrlOrNull(observation.imageUrl);
    final cloudPhotoPath =
        imageUrl ?? _httpUrlOrNull(observation.photoPath);
    return <String, dynamic>{
      ...json,
      'id': observation.id,
      'ownerUid': userId,
      'userId': userId,
      'ownerUsername': observation.ownerUsername,
      'ownerDisplayName': observation.ownerDisplayName,
      'speciesId': observation.speciesId,
      'speciesName': observation.speciesName,
      'scientificName': observation.scientificName,
      'commonName': observation.commonName ?? observation.colloquialName,
      'confidence': observation.confidence,
      'modelId': observation.modelId,
      'sourceClassId': observation.sourceClassId,
      'detectionSource':
          observation.detectionSource ?? _defaultDetectionSource(observation),
      'latitude': observation.latitude,
      'longitude': observation.longitude,
      'locationLabel': observation.locationLabel,
      'country': observation.country,
      'region': observation.region,
      'notes': observation.notes,
      'fieldNoteIds': observation.fieldNoteIds,
      'observedAt': Timestamp.fromDate(observation.createdAt),
      'createdAt': Timestamp.fromDate(observation.createdAt),
      'updatedAt': Timestamp.fromDate(observation.updatedAt ?? syncedAt),
      'photoPath': cloudPhotoPath,
      'imageStoragePath': imageStoragePath,
      'imageUrl': imageUrl,
      'downloadUrl': imageUrl,
      'thumbnailStoragePath': observation.thumbnailStoragePath,
      'isPublic': observation.isPublic,
      'publicLat': observation.publicLat,
      'publicLng': observation.publicLng,
      'syncStatus': syncStatus,
      '_syncedAt': FieldValue.serverTimestamp(),
    };
  }

  String? _httpUrlOrNull(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    return null;
  }

  String? _nonEmptyOrNull(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }

  String _defaultDetectionSource(Observation observation) {
    if (observation.modelId != null || observation.sourceClassId != null) {
      return 'offline_model';
    }
    return 'manual';
  }

  Observation _fromDocument(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = Map<String, dynamic>.from(doc.data());
    data['id'] ??= doc.id;
    for (final key in <String>[
      'observedAt',
      'createdAt',
      'updatedAt',
      'timestamp',
      'capturedAt',
    ]) {
      final value = data[key];
      if (value is Timestamp) {
        data[key] = value.toDate().toIso8601String();
      }
    }
    data['createdAt'] ??= data['observedAt'] ?? data['timestamp'];
    data['timestamp'] ??= data['observedAt'] ?? data['createdAt'];
    data['ownerUsername'] ??=
        data['username'] ?? data['authorUsername'] ?? data['userName'];
    data['ownerDisplayName'] ??=
        data['displayName'] ??
        data['authorDisplayName'] ??
        data['userDisplayName'];
    data['photoPath'] ??= data['imageUrl'] ?? data['downloadUrl'];
    return Observation.fromJson(data);
  }

  String _coordinateSkipReason(Observation observation) {
    final latitude = observation.latitude;
    final longitude = observation.longitude;
    if (latitude == null && longitude == null) {
      return 'missing latitude and longitude';
    }
    if (latitude == null) {
      return 'missing latitude';
    }
    if (longitude == null) {
      return 'missing longitude';
    }
    return 'invalid latitude or longitude';
  }
}
