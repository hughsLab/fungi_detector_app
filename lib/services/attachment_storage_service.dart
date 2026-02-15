import 'dart:io';
import 'dart:ui' as ui;

import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/field_note.dart';

class AttachmentStorageService {
  AttachmentStorageService._();

  static final AttachmentStorageService instance =
      AttachmentStorageService._();
  static const String _baseFolderName = 'field_notes';
  static const String _thumbnailPrefix = 'thumb_';
  final Uuid _uuid = const Uuid();

  Future<Directory> _getBaseDir() async {
    final directory = await getApplicationSupportDirectory();
    final baseDir = Directory('${directory.path}/$_baseFolderName');
    if (!await baseDir.exists()) {
      await baseDir.create(recursive: true);
    }
    return baseDir;
  }

  Future<Directory> _getNoteDir(String noteId) async {
    final baseDir = await _getBaseDir();
    final noteDir = Directory(
      '${baseDir.path}${Platform.pathSeparator}$noteId',
    );
    if (!await noteDir.exists()) {
      await noteDir.create(recursive: true);
    }
    return noteDir;
  }

  Future<NoteAttachment> saveImageToNoteFolder(
    String noteId,
    File imageFile,
  ) async {
    final noteDir = await _getNoteDir(noteId);
    final attachmentId = _uuid.v4();
    final extension = _extensionForPath(imageFile.path);
    final safeExtension = extension.isEmpty ? 'jpg' : extension;
    final filePath =
        '${noteDir.path}${Platform.pathSeparator}$attachmentId.$safeExtension';
    final savedFile = await imageFile.copy(filePath);
    String? thumbnailPath;
    try {
      thumbnailPath = await _generateThumbnail(savedFile, noteDir, attachmentId);
    } catch (_) {
      thumbnailPath = null;
    }
    return NoteAttachment(
      id: attachmentId,
      type: NoteAttachmentType.image,
      filePath: savedFile.path,
      thumbnailPath: thumbnailPath,
      createdAt: DateTime.now(),
    );
  }

  Future<NoteAttachment> saveFileToNoteFolder(
    String noteId,
    File file,
  ) async {
    final noteDir = await _getNoteDir(noteId);
    final attachmentId = _uuid.v4();
    final extension = _extensionForPath(file.path);
    final safeExtension = extension.isEmpty ? 'bin' : extension;
    final filePath =
        '${noteDir.path}${Platform.pathSeparator}$attachmentId.$safeExtension';
    final savedFile = await file.copy(filePath);
    return NoteAttachment(
      id: attachmentId,
      type: NoteAttachmentType.file,
      filePath: savedFile.path,
      thumbnailPath: null,
      createdAt: DateTime.now(),
    );
  }

  Future<void> deleteAttachment(NoteAttachment attachment) async {
    final file = File(attachment.filePath);
    if (await file.exists()) {
      try {
        await file.delete();
      } catch (_) {}
    }
    final thumbPath = attachment.thumbnailPath;
    if (thumbPath != null) {
      final thumb = File(thumbPath);
      if (await thumb.exists()) {
        try {
          await thumb.delete();
        } catch (_) {}
      }
    }
  }

  Future<void> deleteNoteFolder(String noteId) async {
    final baseDir = await _getBaseDir();
    final noteDir = Directory(
      '${baseDir.path}${Platform.pathSeparator}$noteId',
    );
    if (await noteDir.exists()) {
      try {
        await noteDir.delete(recursive: true);
      } catch (_) {}
    }
  }

  Future<int> getStorageBytes() async {
    final baseDir = await _getBaseDir();
    return _directorySize(baseDir);
  }

  Future<int> getThumbnailCacheBytes() async {
    final baseDir = await _getBaseDir();
    return _directorySize(baseDir, onlyThumbnails: true);
  }

  Future<void> clearThumbnails() async {
    final baseDir = await _getBaseDir();
    if (!await baseDir.exists()) {
      return;
    }
    await for (final entity in baseDir.list(recursive: true, followLinks: false)) {
      if (entity is File && _isThumbnailFile(entity.path)) {
        try {
          await entity.delete();
        } catch (_) {}
      }
    }
  }

  Future<int> _directorySize(
    Directory directory, {
    bool onlyThumbnails = false,
  }) async {
    if (!await directory.exists()) {
      return 0;
    }
    int total = 0;
    await for (final entity in directory.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        if (onlyThumbnails && !_isThumbnailFile(entity.path)) {
          continue;
        }
        try {
          total += await entity.length();
        } catch (_) {}
      }
    }
    return total;
  }

  Future<String?> _generateThumbnail(
    File imageFile,
    Directory noteDir,
    String attachmentId,
  ) async {
    final bytes = await imageFile.readAsBytes();
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: 360,
    );
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData(
      format: ui.ImageByteFormat.png,
    );
    frame.image.dispose();
    if (data == null) {
      return null;
    }
    final thumbPath =
        '${noteDir.path}${Platform.pathSeparator}$_thumbnailPrefix$attachmentId.png';
    final file = File(thumbPath);
    await file.writeAsBytes(data.buffer.asUint8List());
    return thumbPath;
  }

  String _extensionForPath(String path) {
    final int dot = path.lastIndexOf('.');
    if (dot == -1 || dot == path.length - 1) {
      return '';
    }
    return path.substring(dot + 1).toLowerCase();
  }

  bool _isThumbnailFile(String path) {
    final fileName = path.split(Platform.pathSeparator).last;
    return fileName.startsWith(_thumbnailPrefix);
  }
}
