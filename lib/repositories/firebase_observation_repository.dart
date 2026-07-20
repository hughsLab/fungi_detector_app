import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import '../models/observation.dart';
import '../models/user_profile.dart';
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
  final Object? error;

  const _PhotoUploadResult({
    required this.imageStoragePath,
    required this.downloadUrl,
    required this.status,
    this.error,
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

  const _PhotoUploadResult.failed([Object? error])
      : this(
          imageStoragePath: null,
          downloadUrl: null,
          status: 'cloud_photo_failed',
          error: error,
        );

  bool get failed => status == 'cloud_photo_failed';
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
    if (kDebugMode) {
      debugPrint(
        'FIREBASE_OBSERVATION_WRITE: called id=${observation.id} '
        'signedIn=${_firebaseAuth.currentUser != null} '
        'uidPresent=${uid?.trim().isNotEmpty == true} '
        'hasLocalPhoto=${_hasLocalPhoto(observation.photoPath)} '
        'hasValidCoordinates=${observation.location != null} '
        'isPublic=${observation.isPublic} path=observations/${observation.id}',
      );
    }
    if (uid == null || uid.trim().isEmpty) {
      _debugLog('cloud save skipped: no signed-in Firebase user');
      return FirebaseObservationSaveResult(
        status: FirebaseObservationSaveStatus.skippedNoUser,
        observation: observation,
      );
    }
    if (observation.id.trim().isEmpty) {
      return FirebaseObservationSaveResult(
        status: FirebaseObservationSaveStatus.failed,
        observation: observation.copyWith(syncStatus: 'cloud_failed'),
        error: StateError('Observation id is empty.'),
      );
    }

    try {
      UserProfile? profile;
      try {
        profile = await _userProfileRepository.ensureUserProfile(
          user: _firebaseAuth.currentUser,
        );
      } catch (e) {
        // Profile metadata is optional and must not block an observation write.
        _debugLog('optional user profile lookup failed: ${_safeError(e)}');
      }
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
      if (photoUpload.failed && downloadUrl == null) {
        return FirebaseObservationSaveResult(
          status: FirebaseObservationSaveStatus.failed,
          observation: observation.copyWith(syncStatus: 'cloud_photo_failed'),
          error: photoUpload.error ??
              StateError('The observation photo could not be uploaded.'),
        );
      }
      if (downloadUrl == null) {
        return FirebaseObservationSaveResult(
          status: FirebaseObservationSaveStatus.failed,
          observation: observation.copyWith(syncStatus: 'cloud_photo_failed'),
          error: StateError('Every cloud observation requires a photo.'),
        );
      }
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
        _debugLog(
          'public save without username id=${observation.id}',
        );
      }

      final data = _toFirestoreDocument(
        observation: cloudObservation,
        userId: uid,
        downloadUrl: downloadUrl,
        imageStoragePath: imageStoragePath,
        syncStatus: syncStatus,
        syncedAt: now,
      );
      _debugLog(
        'Firestore write attempted=true collection=observations '
        'document=${observation.id} ownerUidPresent=${uid.isNotEmpty} '
        'userIdPresent=${uid.isNotEmpty} isPublic=${observation.isPublic} '
        'detectionSource=${observation.detectionSource ?? "-"} '
        'hasValidLocation=${observation.location != null} '
        'hasPhoto=true keys=${data.keys.toList()..sort()}',
      );
      await _observations.doc(observation.id).set(
            data,
            SetOptions(merge: true),
          );
      _debugLog('write succeeded id=${observation.id}');
      return FirebaseObservationSaveResult(
        status: FirebaseObservationSaveStatus.saved,
        observation: cloudObservation,
      );
    } catch (e, st) {
      final detail = e is FirebaseException
          ? 'code=${e.code} message=${e.message ?? "-"}'
          : _safeError(e);
      _debugLog('write failed id=${observation.id} $detail', stackTrace: st);
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

    _debugLog(
      'read query path=observations filter=userId==currentUser limit=$limit',
    );
    final snapshot = await _observations
        .where('userId', isEqualTo: uid)
        .limit(limit)
        .get();
    final observations = _fromDocuments(snapshot.docs);
    observations.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _debugLog(
      'read snapshot=${snapshot.docs.length} parsed=${observations.length}',
    );
    return observations;
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
      _debugLog(
        'no local photo id=${observation.id}; checking existing cloud image',
      );
      return _httpUrlOrNull(observation.imageUrl) != null ||
              _httpUrlOrNull(observation.photoPath) != null
          ? const _PhotoUploadResult.noPhoto()
          : _PhotoUploadResult.failed(
              StateError('No observation photo was provided.'),
            );
    }

    final photoFile = File(photoPath);
    if (!await photoFile.exists()) {
      _debugLog(
        'local photo missing id=${observation.id}; sync will retry',
      );
      return _PhotoUploadResult.failed(
        StateError('The local observation photo is missing.'),
      );
    }

    try {
      final storagePath = _photoStoragePath(userId, observation.id);
      final ref = _storage.ref(storagePath);
      await ref.putFile(
        photoFile,
        SettableMetadata(
          contentType: _photoContentType(photoPath),
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
      _debugLog(
        'photo upload failed id=${observation.id}; metadata write continues: '
        '${_safeError(e)}',
        stackTrace: st,
      );
      return _PhotoUploadResult.failed(e);
    }
  }

  Stream<List<Observation>> _streamObservationQuery(
    Query<Map<String, dynamic>> baseQuery, {
    required int limit,
  }) async* {
    yield* baseQuery.limit(limit).snapshots().map((snapshot) {
      final observations = _fromSnapshot(snapshot);
      observations.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return observations;
    });
  }

  List<Observation> _fromSnapshot(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    final observations = _fromDocuments(snapshot.docs);
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
      final snapshot = await _observations
          .where('isPublic', isEqualTo: true)
          .limit(limit)
          .get();
      var skippedMissingCoordinates = 0;
      var markerCount = 0;
      for (final doc in snapshot.docs) {
        final observation = _tryFromDocument(doc);
        if (observation == null) continue;
        if (observation.location == null) {
          skippedMissingCoordinates += 1;
        } else {
          markerCount += 1;
        }
      }
      debugPrint(
        'FIREBASE_OBSERVATION: public map diagnostics fetched '
        '${snapshot.docs.length}; skipped because missing coordinates '
        '$skippedMissingCoordinates; marker count $markerCount.',
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

  String _photoContentType(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.heic') || lower.endsWith('.heif')) {
      return 'image/heic';
    }
    return 'image/jpeg';
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
    data['userId'] ??= data['ownerUid'];
    data['ownerUsername'] ??=
        data['username'] ?? data['authorUsername'] ?? data['userName'];
    data['ownerDisplayName'] ??=
        data['displayName'] ??
        data['authorDisplayName'] ??
        data['userDisplayName'];
    data['photoPath'] ??= data['imageUrl'] ?? data['downloadUrl'];
    return Observation.fromJson(data);
  }

  List<Observation> _fromDocuments(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final observations = <Observation>[];
    var parseFailures = 0;
    for (final doc in docs) {
      final observation = _tryFromDocument(doc);
      if (observation == null) {
        parseFailures += 1;
      } else {
        observations.add(observation);
      }
    }
    if (parseFailures > 0) {
      _debugLog('document parse failures=$parseFailures');
    }
    return observations;
  }

  Observation? _tryFromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    try {
      return _fromDocument(doc);
    } catch (e) {
      _debugLog('parse failed doc=${doc.id} reason=${_safeError(e)}');
      return null;
    }
  }

  bool _hasLocalPhoto(String? value) {
    final path = value?.trim();
    return path != null &&
        path.isNotEmpty &&
        !path.startsWith('http://') &&
        !path.startsWith('https://');
  }

  String _safeError(Object error) {
    final value = error.toString();
    return value.length <= 300 ? value : value.substring(0, 300);
  }

  void _debugLog(String message, {StackTrace? stackTrace}) {
    if (!kDebugMode) return;
    debugPrint('FIREBASE_OBSERVATION: $message');
    if (stackTrace != null) {
      debugPrintStack(stackTrace: stackTrace, label: 'FIREBASE_OBSERVATION');
    }
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
