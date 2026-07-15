import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/field_note.dart';
import '../models/observation.dart';
import '../repositories/firebase_observation_repository.dart';
import 'app_toast_service.dart';
import 'auth_service.dart';

enum SyncMutationType {
  observationUpsert,
  observationsClear,
  fieldNoteUpsert,
  fieldNoteDelete,
}

class SyncMutation {
  final String id;
  final SyncMutationType type;
  final String? entityId;
  final Map<String, dynamic>? payload;
  final DateTime createdAt;
  final int retryCount;

  const SyncMutation({
    required this.id,
    required this.type,
    required this.entityId,
    required this.payload,
    required this.createdAt,
    required this.retryCount,
  });

  SyncMutation copyWith({
    String? id,
    SyncMutationType? type,
    String? entityId,
    Map<String, dynamic>? payload,
    DateTime? createdAt,
    int? retryCount,
  }) {
    return SyncMutation(
      id: id ?? this.id,
      type: type ?? this.type,
      entityId: entityId ?? this.entityId,
      payload: payload ?? this.payload,
      createdAt: createdAt ?? this.createdAt,
      retryCount: retryCount ?? this.retryCount,
    );
  }

  factory SyncMutation.fromJson(Map<String, dynamic> json) {
    final rawType = json['type']?.toString() ?? '';
    final type = SyncMutationType.values.firstWhere(
      (candidate) => candidate.name == rawType,
      orElse: () => SyncMutationType.observationUpsert,
    );
    final createdAt = DateTime.tryParse(json['createdAt']?.toString() ?? '');
    return SyncMutation(
      id: json['id']?.toString() ?? '',
      type: type,
      entityId: json['entityId']?.toString(),
      payload: (json['payload'] as Map<String, dynamic>?),
      createdAt: createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
      retryCount: (json['retryCount'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'entityId': entityId,
      'payload': payload,
      'createdAt': createdAt.toIso8601String(),
      'retryCount': retryCount,
    };
  }
}

class SyncStatus {
  final bool isSyncing;
  final bool isOnline;
  final int pendingMutations;
  final DateTime? lastSyncedAt;
  final String? message;

  const SyncStatus({
    required this.isSyncing,
    required this.isOnline,
    required this.pendingMutations,
    required this.lastSyncedAt,
    required this.message,
  });

  const SyncStatus.initial()
    : this(
        isSyncing: false,
        isOnline: true,
        pendingMutations: 0,
        lastSyncedAt: null,
        message: null,
      );

  SyncStatus copyWith({
    bool? isSyncing,
    bool? isOnline,
    int? pendingMutations,
    DateTime? lastSyncedAt,
    String? message,
  }) {
    return SyncStatus(
      isSyncing: isSyncing ?? this.isSyncing,
      isOnline: isOnline ?? this.isOnline,
      pendingMutations: pendingMutations ?? this.pendingMutations,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      message: message ?? this.message,
    );
  }
}

class _SyncQueueStore {
  _SyncQueueStore._();

  static final _SyncQueueStore instance = _SyncQueueStore._();
  final Random _random = Random();
  Completer<void>? _activeOperation;

  Future<File> _getFile() async {
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}/sync_queue.json');
  }

  Future<List<SyncMutation>> load() async {
    return _synchronized(_loadUnlocked);
  }

  Future<List<SyncMutation>> _loadUnlocked() async {
    final file = await _getFile();
    if (!await file.exists()) {
      return [];
    }
    try {
      final raw = await file.readAsString();
      final data = jsonDecode(raw) as List<dynamic>;
      return data
          .whereType<Map<String, dynamic>>()
          .map(SyncMutation.fromJson)
          .toList();
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('SYNC_QUEUE: read failed: $e');
        debugPrintStack(stackTrace: st, label: 'SYNC_QUEUE');
      }
      rethrow;
    }
  }

  Future<int> enqueue({
    required SyncMutationType type,
    String? entityId,
    Map<String, dynamic>? payload,
  }) async {
    return _synchronized(() async {
      final queue = await _loadUnlocked();
      final mutation = SyncMutation(
        id: _newMutationId(),
        type: type,
        entityId: entityId,
        payload: payload,
        createdAt: DateTime.now(),
        retryCount: 0,
      );
      final merged = _merge(queue, mutation);
      if (kDebugMode) {
        debugPrint(
          'SYNC_QUEUE: write started mutation=${mutation.id} '
          'type=${type.name} observationId=${entityId ?? "-"}',
        );
      }
      await _replaceUnlocked(merged);
      if (kDebugMode) {
        debugPrint(
          'SYNC_QUEUE: write succeeded mutation=${mutation.id} '
          'queueLength=${merged.length}',
        );
      }
      return merged.length;
    });
  }

  Future<void> _replaceUnlocked(List<SyncMutation> queue) async {
    final file = await _getFile();
    final data = queue.map((mutation) => mutation.toJson()).toList();
    await file.writeAsString(jsonEncode(data));
  }

  Future<List<SyncMutation>> completeAttempt({
    required Set<String> attemptedIds,
    required Map<String, SyncMutation> failedById,
  }) {
    return _synchronized(() async {
      final current = await _loadUnlocked();
      final reconciled = <SyncMutation>[];
      for (final mutation in current) {
        if (!attemptedIds.contains(mutation.id)) {
          reconciled.add(mutation);
          continue;
        }
        final failed = failedById[mutation.id];
        if (failed != null) reconciled.add(failed);
      }
      await _replaceUnlocked(reconciled);
      return reconciled;
    });
  }

  Future<T> _synchronized<T>(Future<T> Function() operation) async {
    while (_activeOperation != null) {
      await _activeOperation!.future;
    }
    final completer = Completer<void>();
    _activeOperation = completer;
    try {
      return await operation();
    } finally {
      _activeOperation = null;
      completer.complete();
    }
  }

  List<SyncMutation> _merge(List<SyncMutation> queue, SyncMutation incoming) {
    final result = List<SyncMutation>.from(queue);
    switch (incoming.type) {
      case SyncMutationType.observationUpsert:
        result.removeWhere(
          (item) =>
              item.type == SyncMutationType.observationUpsert &&
              item.entityId == incoming.entityId,
        );
        result.add(incoming);
      case SyncMutationType.observationsClear:
        result.removeWhere(
          (item) =>
              item.type == SyncMutationType.observationsClear ||
              item.type == SyncMutationType.observationUpsert,
        );
        result.add(incoming);
      case SyncMutationType.fieldNoteUpsert:
        result.removeWhere(
          (item) =>
              (item.type == SyncMutationType.fieldNoteUpsert ||
                  item.type == SyncMutationType.fieldNoteDelete) &&
              item.entityId == incoming.entityId,
        );
        result.add(incoming);
      case SyncMutationType.fieldNoteDelete:
        result.removeWhere(
          (item) =>
              (item.type == SyncMutationType.fieldNoteUpsert ||
                  item.type == SyncMutationType.fieldNoteDelete) &&
              item.entityId == incoming.entityId,
        );
        result.add(incoming);
    }
    return result;
  }

  String _newMutationId() {
    final now = DateTime.now().microsecondsSinceEpoch;
    final suffix = _random.nextInt(1 << 32);
    return '$now-$suffix';
  }
}

class SyncManager {
  SyncManager._();

  static final SyncManager instance = SyncManager._();

  final AuthService _authService = AuthService.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;
  final FirebaseObservationRepository _firebaseObservationRepository =
      FirebaseObservationRepository.instance;
  final _SyncQueueStore _queueStore = _SyncQueueStore.instance;
  final ValueNotifier<SyncStatus> syncStatusNotifier =
      ValueNotifier<SyncStatus>(const SyncStatus.initial());

  StreamSubscription<AppAuthState>? _authStateSubscription;
  bool _isInitialized = false;
  bool _isSyncing = false;
  bool _lastKnownOnline = true;

  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;

    _debugLog('initialized after Firebase startup');

    await _authService.initialize();
    _lastKnownOnline = _authService.currentState.isOnline;

    _authStateSubscription = _authService.authStateChanges().listen((state) {
      syncStatusNotifier.value = syncStatusNotifier.value.copyWith(
        isOnline: state.isOnline,
      );

      final regainedConnectivity = state.isOnline && !_lastKnownOnline;
      _lastKnownOnline = state.isOnline;

      if (regainedConnectivity && state.isAuthenticated) {
        unawaited(triggerSync(reason: 'connectivity_restored'));
      } else if (state.isOnline && state.isAuthenticated) {
        unawaited(triggerSync(reason: 'auth_available_online'));
      }
    });

    unawaited(triggerSync(reason: 'startup'));
  }

  Future<int> enqueueObservationUpsert(Observation observation) async {
    final queueLength = await _queueStore.enqueue(
      type: SyncMutationType.observationUpsert,
      entityId: observation.id,
      payload: observation.toJson(),
    );
    _debugLog(
      'queued observation=${observation.id} '
      'detectionSource=${observation.detectionSource ?? "-"} '
      'identificationSource=${observation.identificationSource ?? "-"} '
      'queueLength=$queueLength',
    );
    unawaited(_triggerIfReady());
    return queueLength;
  }

  Future<void> enqueueObservationsClear() async {
    await _queueStore.enqueue(
      type: SyncMutationType.observationsClear,
    );
    unawaited(_triggerIfReady());
  }

  Future<void> enqueueFieldNoteUpsert(FieldNote note) async {
    await _queueStore.enqueue(
      type: SyncMutationType.fieldNoteUpsert,
      entityId: note.id,
      payload: note.toJson(),
    );
    unawaited(_triggerIfReady());
  }

  Future<void> enqueueFieldNoteDelete(String noteId) async {
    await _queueStore.enqueue(
      type: SyncMutationType.fieldNoteDelete,
      entityId: noteId,
    );
    unawaited(_triggerIfReady());
  }

  Future<void> triggerSync({String reason = 'manual'}) async {
    if (_isSyncing) {
      _debugLog('trigger=$reason deferred because sync is already running');
      return;
    }
    await initialize();

    final authState = _authService.currentState;
    _debugLog(
      'trigger=$reason authStateSignedIn=${authState.isAuthenticated} '
      'firebaseAuthPresent=${_firebaseAuth.currentUser != null} '
      'uidPresent=${authState.uid?.isNotEmpty == true} '
      'online=${authState.isOnline}',
    );
    if (!authState.isOnline || !authState.isAuthenticated) {
      final pending = (await _queueStore.load()).length;
      syncStatusNotifier.value = syncStatusNotifier.value.copyWith(
        isSyncing: false,
        pendingMutations: pending,
        message: authState.isOnline
            ? 'Sync waiting for authenticated session.'
            : 'Sync paused while offline.',
      );
      return;
    }

    final uid = authState.uid;
    if (uid == null || uid.isEmpty) {
      return;
    }

    final queue = await _queueStore.load();
    _debugLog('processing started trigger=$reason queueLength=${queue.length}');
    if (queue.isEmpty) {
      syncStatusNotifier.value = syncStatusNotifier.value.copyWith(
        isSyncing: false,
        pendingMutations: 0,
        message: 'No pending offline changes.',
      );
      return;
    }

    _isSyncing = true;
    syncStatusNotifier.value = syncStatusNotifier.value.copyWith(
      isSyncing: true,
      pendingMutations: queue.length,
      message: 'Syncing offline changes...',
    );

    int successCount = 0;
    final failedById = <String, SyncMutation>{};
    final attemptedIds = queue.map((item) => item.id).toSet();
    for (final mutation in queue) {
      _debugLog(
        'processing mutation=${mutation.id} type=${mutation.type.name} '
        'observationId=${mutation.entityId ?? "-"} '
        'detectionSource=${mutation.payload?["detectionSource"] ?? "-"}',
      );
      try {
        await _applyMutation(uid: uid, mutation: mutation);
        successCount += 1;
        _debugLog('mutation success id=${mutation.id}');
      } catch (e, st) {
        _debugLog(
          'mutation failed id=${mutation.id} ${_safeError(e)}',
          stackTrace: st,
        );
        failedById[mutation.id] =
            mutation.copyWith(retryCount: mutation.retryCount + 1);
      }
    }

    final queueAfter = await _queueStore.completeAttempt(
      attemptedIds: attemptedIds,
      failedById: failedById,
    );

    _isSyncing = false;
    final pendingAfter = queueAfter.length;
    final message = pendingAfter == 0
        ? 'Sync complete.'
        : 'Synced $successCount change(s), $pendingAfter pending.';
    syncStatusNotifier.value = syncStatusNotifier.value.copyWith(
      isSyncing: false,
      pendingMutations: pendingAfter,
      lastSyncedAt: DateTime.now(),
      message: message,
    );

    if (successCount > 0) {
      await AppToastService.show(
        'Sync complete: $successCount changes uploaded.',
      );
    }
    final observationSyncFailed = queue.any(
      (item) =>
          item.type == SyncMutationType.observationUpsert &&
          failedById.containsKey(item.id),
    );
    if (observationSyncFailed) {
      await AppToastService.show(
        'Saved locally. Cloud sync failed and will retry.',
      );
    }
    final hasNewUnattempted =
        queueAfter.any((item) => !attemptedIds.contains(item.id));
    if (hasNewUnattempted) {
      _debugLog('new mutations arrived during sync; processing next batch');
      unawaited(triggerSync(reason: 'queued_during_sync'));
    }
  }

  Future<void> _applyMutation({
    required String uid,
    required SyncMutation mutation,
  }) async {
    final userDoc = _firestore.collection('users').doc(uid);

    switch (mutation.type) {
      case SyncMutationType.observationUpsert:
        final entityId = mutation.entityId;
        final payload = mutation.payload;
        if (entityId == null || entityId.isEmpty || payload == null) {
          throw StateError('Observation sync mutation is incomplete.');
        }
        _debugLog(
          'Firestore upload called observation=$entityId '
          'detectionSource=${payload["detectionSource"] ?? "-"} '
          'authPresent=${_firebaseAuth.currentUser != null} online=true',
        );
        final result = await _firebaseObservationRepository.saveObservation(
          Observation.fromJson(payload),
          userId: uid,
        );
        if (result.status == FirebaseObservationSaveStatus.failed) {
          throw result.error ?? StateError('Observation cloud save failed.');
        }
        if (!result.saved) {
          throw StateError('Observation cloud save requires Firebase auth.');
        }
      case SyncMutationType.observationsClear:
        await _deleteUserObservations(uid);
      case SyncMutationType.fieldNoteUpsert:
        final entityId = mutation.entityId;
        final payload = mutation.payload;
        if (entityId == null || entityId.isEmpty || payload == null) {
          return;
        }
        await userDoc.collection('field_notes').doc(entityId).set({
          ...payload,
          '_syncedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      case SyncMutationType.fieldNoteDelete:
        final entityId = mutation.entityId;
        if (entityId == null || entityId.isEmpty) {
          return;
        }
        await userDoc.collection('field_notes').doc(entityId).delete();
    }
  }

  Future<void> _deleteUserObservations(String uid) async {
    const int chunkSize = 400;
    while (true) {
      final snapshot = await _firestore
          .collection('observations')
          .where('userId', isEqualTo: uid)
          .limit(chunkSize)
          .get();
      if (snapshot.docs.isEmpty) {
        return;
      }
      final batch = _firestore.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      if (snapshot.docs.length < chunkSize) {
        return;
      }
    }
  }

  Future<void> _triggerIfReady() async {
    await initialize();
    final state = _authService.currentState;
    if (state.isAuthenticated && state.isOnline) {
      await triggerSync(reason: 'mutation_enqueued');
    }
  }

  String _safeError(Object error) {
    if (error is FirebaseException) {
      return 'FirebaseException code=${error.code} '
          'message=${error.message ?? "-"}';
    }
    final value = error.toString();
    return value.length <= 300 ? value : value.substring(0, 300);
  }

  void _debugLog(String message, {StackTrace? stackTrace}) {
    if (!kDebugMode) return;
    debugPrint('SYNC: $message');
    if (stackTrace != null) {
      debugPrintStack(stackTrace: stackTrace, label: 'SYNC');
    }
  }

  Future<void> dispose() async {
    await _authStateSubscription?.cancel();
    _authStateSubscription = null;
    syncStatusNotifier.dispose();
    _isInitialized = false;
  }
}
