import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/field_note.dart';
import '../models/observation.dart';
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

  Future<File> _getFile() async {
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}/sync_queue.json');
  }

  Future<List<SyncMutation>> load() async {
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
    } catch (_) {
      return [];
    }
  }

  Future<void> enqueue({
    required SyncMutationType type,
    String? entityId,
    Map<String, dynamic>? payload,
  }) async {
    final queue = await load();
    final mutation = SyncMutation(
      id: _newMutationId(),
      type: type,
      entityId: entityId,
      payload: payload,
      createdAt: DateTime.now(),
      retryCount: 0,
    );
    final merged = _merge(queue, mutation);
    await replace(merged);
  }

  Future<void> replace(List<SyncMutation> queue) async {
    final file = await _getFile();
    final data = queue.map((mutation) => mutation.toJson()).toList();
    await file.writeAsString(jsonEncode(data));
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

  Future<void> enqueueObservationUpsert(Observation observation) {
    final future = _queueStore.enqueue(
      type: SyncMutationType.observationUpsert,
      entityId: observation.id,
      payload: observation.toJson(),
    );
    unawaited(_triggerIfReady());
    return future;
  }

  Future<void> enqueueObservationsClear() {
    final future = _queueStore.enqueue(
      type: SyncMutationType.observationsClear,
    );
    unawaited(_triggerIfReady());
    return future;
  }

  Future<void> enqueueFieldNoteUpsert(FieldNote note) {
    final future = _queueStore.enqueue(
      type: SyncMutationType.fieldNoteUpsert,
      entityId: note.id,
      payload: note.toJson(),
    );
    unawaited(_triggerIfReady());
    return future;
  }

  Future<void> enqueueFieldNoteDelete(String noteId) {
    final future = _queueStore.enqueue(
      type: SyncMutationType.fieldNoteDelete,
      entityId: noteId,
    );
    unawaited(_triggerIfReady());
    return future;
  }

  Future<void> triggerSync({String reason = 'manual'}) async {
    if (_isSyncing) return;
    await initialize();

    final authState = _authService.currentState;
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
    final remaining = <SyncMutation>[];
    for (final mutation in queue) {
      try {
        await _applyMutation(uid: uid, mutation: mutation);
        successCount += 1;
      } catch (e, st) {
        debugPrint('SYNC[$reason]: failed mutation ${mutation.id}: $e');
        debugPrintStack(stackTrace: st, label: 'SYNC');
        remaining.add(mutation.copyWith(retryCount: mutation.retryCount + 1));
      }
    }

    await _queueStore.replace(remaining);

    _isSyncing = false;
    final pendingAfter = remaining.length;
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
          return;
        }
        await userDoc.collection('observations').doc(entityId).set({
          ...payload,
          '_syncedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      case SyncMutationType.observationsClear:
        await _deleteCollection(userDoc.collection('observations'));
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

  Future<void> _deleteCollection(
    CollectionReference<Map<String, dynamic>> collection,
  ) async {
    const int chunkSize = 400;
    while (true) {
      final snapshot = await collection.limit(chunkSize).get();
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

  Future<void> dispose() async {
    await _authStateSubscription?.cancel();
    _authStateSubscription = null;
    syncStatusNotifier.dispose();
    _isInitialized = false;
  }
}
