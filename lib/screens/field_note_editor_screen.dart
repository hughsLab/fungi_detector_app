import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../models/field_note.dart';
import '../models/navigation_args.dart';
import '../repositories/field_notes_repository.dart';
import '../services/attachment_storage_service.dart';
import '../widgets/forest_background.dart';
import '../widgets/local_image_preview.dart';

class FieldNoteEditorScreen extends StatefulWidget {
  const FieldNoteEditorScreen({super.key});

  @override
  State<FieldNoteEditorScreen> createState() => _FieldNoteEditorScreenState();
}

class _FieldNoteEditorScreenState extends State<FieldNoteEditorScreen> {
  final FieldNotesRepository _repository = FieldNotesRepository.instance;
  final AttachmentStorageService _attachmentStorage =
      AttachmentStorageService.instance;
  final ImagePicker _imagePicker = ImagePicker();
  final Uuid _uuid = const Uuid();

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _bodyController = TextEditingController();

  final Map<String, NoteAttachment> _attachmentById = {};
  final Set<String> _newAttachmentIds = {};
  final Set<String> _attachmentsToDelete = {};

  List<NoteAttachment> _attachments = [];
  NoteLinks _links = NoteLinks.empty();

  bool _loading = true;
  bool _saving = false;
  bool _saved = false;
  bool _initialized = false;
  bool _isNew = true;
  bool _isPinned = false;
  bool _isArchived = false;
  String _noteId = '';
  FieldNote? _originalNote;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final args =
        ModalRoute.of(context)?.settings.arguments as FieldNoteEditorArgs?;
    _loadInitialData(args);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    _cleanupUnsavedAttachments();
    super.dispose();
  }

  Future<void> _cleanupUnsavedAttachments() async {
    if (_saved) return;
    if (_isNew && _noteId.isNotEmpty) {
      await _attachmentStorage.deleteNoteFolder(_noteId);
      return;
    }
    if (_newAttachmentIds.isEmpty) return;
    for (final id in _newAttachmentIds) {
      final attachment = _attachmentById[id];
      if (attachment != null) {
        await _attachmentStorage.deleteAttachment(attachment);
      }
    }
  }

  Future<void> _loadInitialData(FieldNoteEditorArgs? args) async {
    FieldNote? note;
    if (args?.noteId != null) {
      note = await _repository.getNoteById(args!.noteId!);
    }

    if (note != null) {
      _isNew = false;
      _noteId = note.id;
      _originalNote = note;
      _titleController.text = note.title;
      _bodyController.text = note.body;
      _attachments = [...note.attachments];
      for (final attachment in note.attachments) {
        _attachmentById[attachment.id] = attachment;
      }
      _links = note.links;
      _isPinned = note.isPinned;
      _isArchived = note.isArchived;
    } else {
      _isNew = true;
      _noteId = args?.noteId ?? _uuid.v4();
      _links = NoteLinks.empty();
    }

    final String? preObservation = args?.prelinkedObservationId;
    if (preObservation != null &&
        !_links.observationIds.contains(preObservation)) {
      _links = _links.copyWith(
        observationIds: [..._links.observationIds, preObservation],
      );
    }
    final String? preSpecies = args?.prelinkedSpeciesId;
    if (preSpecies != null && !_links.speciesIds.contains(preSpecies)) {
      _links = _links.copyWith(speciesIds: [..._links.speciesIds, preSpecies]);
    }
    final LocationRef? preLocation = args?.prelinkedLocation;
    if (preLocation != null &&
        !_links.locations.any((item) => item.id == preLocation.id)) {
      _links = _links.copyWith(locations: [..._links.locations, preLocation]);
    }

    if (!mounted) return;
    setState(() {
      _loading = false;
    });
  }

  Future<void> _saveNote() async {
    if (_saving) return;
    setState(() => _saving = true);

    try {
      final now = DateTime.now();
      final title = _titleController.text.trim();
      final body = _bodyController.text.trim();

      final note = FieldNote(
        id: _noteId,
        title: title.isEmpty ? 'Untitled note' : title,
        body: body,
        createdAt: _originalNote?.createdAt ?? now,
        updatedAt: now,
        tags: _originalNote?.tags ?? const <String>[],
        attachments: _attachments,
        links: _links,
        isPinned: _isPinned,
        isArchived: _isArchived,
      );
      await _repository.upsertNote(note);

      for (final id in _attachmentsToDelete) {
        final attachment = _attachmentById[id];
        if (attachment != null) {
          await _attachmentStorage.deleteAttachment(attachment);
        }
      }
      _saved = true;
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save note: $e')));
    } finally {
      if (!mounted) return;
      setState(() => _saving = false);
    }
  }

  Future<void> _deleteNote() async {
    if (_noteId.isEmpty) return;
    bool deleteFiles = true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Delete note?'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('This note will be removed from your device.'),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    value: deleteFiles,
                    onChanged: (value) {
                      setDialogState(() {
                        deleteFiles = value ?? true;
                      });
                    },
                    title: const Text('Delete attachments from disk'),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Delete'),
                ),
              ],
            );
          },
        );
      },
    );
    if (confirmed != true) return;
    await _repository.deleteNote(_noteId, deleteAttachments: deleteFiles);
    _saved = true;
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _addImage(ImageSource source) async {
    final XFile? file = await _imagePicker.pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 1920,
    );
    if (file == null) return;
    final attachment = await _attachmentStorage.saveImageToNoteFolder(
      _noteId,
      File(file.path),
    );
    _attachmentById[attachment.id] = attachment;
    _newAttachmentIds.add(attachment.id);
    setState(() {
      _attachments = [..._attachments, attachment];
    });
  }

  void _removeAttachment(NoteAttachment attachment) {
    setState(() {
      _attachments = _attachments
          .where((item) => item.id != attachment.id)
          .toList();
      _attachmentsToDelete.add(attachment.id);
    });
  }

  void _showPhotoSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1F4E3D),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera, color: Colors.white),
                title: const Text(
                  'Take photo',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  _addImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo, color: Colors.white),
                title: const Text(
                  'Pick image',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  _addImage(ImageSource.gallery);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _attachmentTile(NoteAttachment attachment) {
    final bool isImage = attachment.type == NoteAttachmentType.image;
    final String path = attachment.thumbnailPath ?? attachment.filePath;
    return Stack(
      children: [
        Container(
          width: 92,
          height: 92,
          decoration: BoxDecoration(
            color: const Color(0xFFEAE4D7),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFCAD4C2)),
          ),
          child: isImage
              ? LocalImagePreview(
                  path: path,
                  borderRadius: BorderRadius.circular(12),
                  cacheWidth: 220,
                  placeholder: const Icon(
                    Icons.image_not_supported_outlined,
                    color: Color(0xFF4A5D54),
                  ),
                )
              : const Icon(Icons.insert_drive_file, color: Color(0xFF4A5D54)),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: InkWell(
            onTap: () => _removeAttachment(attachment),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, size: 14, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  InputDecoration _paperFieldDecoration({
    required String hintText,
    bool isTitle = false,
  }) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: TextStyle(
        color: const Color(0xFF3D5349).withValues(alpha: 0.6),
        fontSize: isTitle ? 20 : 16,
      ),
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      contentPadding: EdgeInsets.zero,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Color(0xFF1F4E3D),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'New Field Note' : 'Edit Field Note'),
        backgroundColor: const Color(0xFF1F4E3D),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: _isPinned ? 'Unpin' : 'Pin',
            icon: Icon(_isPinned ? Icons.push_pin : Icons.push_pin_outlined),
            onPressed: () {
              setState(() => _isPinned = !_isPinned);
            },
          ),
          IconButton(
            tooltip: _isArchived ? 'Unarchive' : 'Archive',
            icon: Icon(_isArchived ? Icons.archive : Icons.archive_outlined),
            onPressed: () {
              setState(() => _isArchived = !_isArchived);
            },
          ),
          if (!_isNew)
            IconButton(
              tooltip: 'Delete note',
              icon: const Icon(Icons.delete_outline),
              onPressed: _deleteNote,
            ),
        ],
      ),
      body: ForestBackground(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        includeTopSafeArea: false,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4F0E4),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFE0DBC8)),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x3322302A),
                        blurRadius: 12,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: _titleController,
                        style: const TextStyle(
                          color: Color(0xFF2A3A33),
                          fontSize: 23,
                          fontWeight: FontWeight.w600,
                        ),
                        textCapitalization: TextCapitalization.sentences,
                        decoration: _paperFieldDecoration(
                          hintText: 'Title',
                          isTitle: true,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Divider(
                        color: Color(0xFFDBD2BF),
                        thickness: 1,
                        height: 1,
                      ),
                      const SizedBox(height: 14),
                      ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 320),
                        child: TextField(
                          controller: _bodyController,
                          minLines: 12,
                          maxLines: null,
                          keyboardType: TextInputType.multiline,
                          textCapitalization: TextCapitalization.sentences,
                          style: const TextStyle(
                            color: Color(0xFF2F443B),
                            fontSize: 17,
                            height: 1.45,
                          ),
                          decoration: _paperFieldDecoration(
                            hintText: 'Write your field note...',
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          const Text(
                            'Photos',
                            style: TextStyle(
                              color: Color(0xFF2A3A33),
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: _showPhotoSheet,
                            icon: const Icon(Icons.add_a_photo_outlined),
                            label: const Text('Add photo'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _attachments.isEmpty
                          ? const Text(
                              'No photos yet.',
                              style: TextStyle(color: Color(0xFF5A6D62)),
                            )
                          : Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: _attachments
                                  .map(_attachmentTile)
                                  .toList(),
                            ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _saving ? null : _saveNote,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF8FBFA1),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: const Icon(Icons.save_outlined),
                label: Text(_saving ? 'Saving...' : 'Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
