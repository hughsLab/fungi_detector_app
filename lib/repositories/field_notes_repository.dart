import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';

import '../models/field_note.dart';
import '../services/attachment_storage_service.dart';

enum FieldNotesSearchFilter {
  all,
  linkedObservation,
  linkedSpecies,
  linkedLocation,
  pinned,
  archived,
}

class FieldNotesRepository {
  FieldNotesRepository._();

  static final FieldNotesRepository instance = FieldNotesRepository._();

  final StreamController<List<FieldNote>> _notesStreamController =
      StreamController<List<FieldNote>>.broadcast();

  Future<File> _getFile() async {
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}/field_notes.json');
  }

  Future<List<FieldNote>> loadNotes() async {
    final file = await _getFile();
    if (!await file.exists()) {
      return [];
    }
    try {
      final raw = await file.readAsString();
      final data = jsonDecode(raw) as List<dynamic>;
      return data
          .whereType<Map<String, dynamic>>()
          .map(FieldNote.fromJson)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<FieldNote?> getNoteById(String id) async {
    final notes = await loadNotes();
    try {
      return notes.firstWhere((note) => note.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveNotes(List<FieldNote> notes) async {
    final file = await _getFile();
    final data = notes.map((note) => note.toJson()).toList();
    await file.writeAsString(jsonEncode(data));
    await _emitUpdate(notes);
  }

  Future<void> upsertNote(FieldNote note) async {
    final notes = await loadNotes();
    final index = notes.indexWhere((item) => item.id == note.id);
    if (index >= 0) {
      notes[index] = note;
    } else {
      notes.add(note);
    }
    await saveNotes(notes);
  }

  Future<void> deleteNote(
    String noteId, {
    bool deleteAttachments = true,
  }) async {
    final notes = await loadNotes();
    notes.removeWhere((note) => note.id == noteId);
    await saveNotes(notes);
    if (deleteAttachments) {
      await AttachmentStorageService.instance.deleteNoteFolder(noteId);
    }
  }

  Stream<List<FieldNote>> watchAllNotes() async* {
    yield await loadNotes();
    yield* _notesStreamController.stream;
  }

  Future<List<FieldNote>> searchNotes(
    String query, {
    FieldNotesSearchFilter filter = FieldNotesSearchFilter.all,
  }) async {
    final notes = await loadNotes();
    final normalized = query.trim().toLowerCase();
    return notes.where((note) {
      switch (filter) {
        case FieldNotesSearchFilter.linkedObservation:
          if (note.links.observationIds.isEmpty) return false;
          break;
        case FieldNotesSearchFilter.linkedSpecies:
          if (note.links.speciesIds.isEmpty) return false;
          break;
        case FieldNotesSearchFilter.linkedLocation:
          if (note.links.locations.isEmpty) return false;
          break;
        case FieldNotesSearchFilter.pinned:
          if (!note.isPinned) return false;
          break;
        case FieldNotesSearchFilter.archived:
          if (!note.isArchived) return false;
          break;
        case FieldNotesSearchFilter.all:
          break;
      }
      if (normalized.isEmpty) {
        return true;
      }
      final haystack = [
        note.title,
        note.body,
        note.tags.join(' '),
      ].join(' ').toLowerCase();
      return haystack.contains(normalized);
    }).toList();
  }

  Future<List<FieldNote>> getNotesForObservation(String observationId) async {
    final notes = await loadNotes();
    return notes
        .where(
          (note) => note.links.observationIds.contains(observationId),
        )
        .toList();
  }

  Future<List<FieldNote>> getNotesForSpecies(String speciesId) async {
    final notes = await loadNotes();
    return notes
        .where((note) => note.links.speciesIds.contains(speciesId))
        .toList();
  }

  Future<List<FieldNote>> getNotesNearLocation(
    double lat,
    double lon,
    double radiusMeters,
  ) async {
    final notes = await loadNotes();
    final target = LatLng(lat, lon);
    const distance = Distance();
    return notes.where((note) {
      for (final location in note.links.locations) {
        final meters = distance(
          target,
          LatLng(location.lat, location.lon),
        );
        if (meters <= radiusMeters) {
          return true;
        }
      }
      return false;
    }).toList();
  }

  Future<int> getStorageBytes() async {
    int total = 0;
    final file = await _getFile();
    if (await file.exists()) {
      total += await file.length();
    }
    total += await AttachmentStorageService.instance.getStorageBytes();
    return total;
  }

  Future<void> _emitUpdate([List<FieldNote>? notes]) async {
    if (_notesStreamController.isClosed) {
      return;
    }
    final data = notes ?? await loadNotes();
    _notesStreamController.add(data);
  }
}
