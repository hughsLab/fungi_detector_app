
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../models/field_note.dart';
import '../models/navigation_args.dart';
import '../models/observation.dart';
import '../models/species.dart';
import '../repositories/field_notes_repository.dart';
import '../repositories/observation_repository.dart';
import '../repositories/species_repository.dart';
import '../services/attachment_storage_service.dart';
import '../services/location_capture_service.dart';
import '../services/location_label_service.dart';
import '../services/settings_service.dart';
import '../utils/formatting.dart';
import '../widgets/forest_background.dart';

class FieldNoteEditorScreen extends StatefulWidget {
  const FieldNoteEditorScreen({super.key});

  @override
  State<FieldNoteEditorScreen> createState() => _FieldNoteEditorScreenState();
}

class _FieldNoteEditorScreenState extends State<FieldNoteEditorScreen> {
  final FieldNotesRepository _repository = FieldNotesRepository.instance;
  final ObservationRepository _observationRepository =
      ObservationRepository.instance;
  final SpeciesRepository _speciesRepository = SpeciesRepository.instance;
  final AttachmentStorageService _attachmentStorage =
      AttachmentStorageService.instance;
  final SettingsService _settingsService = SettingsService.instance;
  final LocationCaptureService _locationCaptureService =
      LocationCaptureService.instance;
  final LocationLabelService _locationLabelService =
      LocationLabelService.instance;
  final ImagePicker _imagePicker = ImagePicker();
  final Uuid _uuid = const Uuid();

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _bodyController = TextEditingController();
  final TextEditingController _tagsController = TextEditingController();

  final Map<String, NoteAttachment> _attachmentById = {};
  final Set<String> _newAttachmentIds = {};
  final Set<String> _attachmentsToDelete = {};

  List<NoteAttachment> _attachments = [];
  List<Observation> _observations = [];
  List<Species> _species = [];
  Map<String, String> _speciesNames = {};
  AppSettings? _settings;
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
    _tagsController.dispose();
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
    final settings = await _settingsService.loadSettings();
    final observations = await _observationRepository.loadObservations();
    final species = await _speciesRepository.loadSpecies();
    FieldNote? note;
    if (args?.noteId != null) {
      note = await _repository.getNoteById(args!.noteId!);
    }

    final Map<String, String> speciesNames = {
      for (final item in species) item.id: item.displayName,
    };

    if (note != null) {
      _isNew = false;
      _noteId = note.id;
      _originalNote = note;
      _titleController.text = note.title;
      _bodyController.text = note.body;
      _tagsController.text = note.tags.join(', ');
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
      _links = _links.copyWith(
        speciesIds: [..._links.speciesIds, preSpecies],
      );
    }
    final LocationRef? preLocation = args?.prelinkedLocation;
    if (preLocation != null) {
      final allow = await _confirmLocationOverride(settings: settings);
      if (allow) {
        _links = _links.copyWith(
          locations: [..._links.locations, preLocation],
        );
      }
    }

    if (!mounted) return;
    setState(() {
      _settings = settings;
      _observations = observations;
      _species = species;
      _speciesNames = speciesNames;
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
      final tags = _tagsController.text
          .split(',')
          .map((tag) => tag.trim())
          .where((tag) => tag.isNotEmpty)
          .toSet()
          .toList();

      final note = FieldNote(
        id: _noteId,
        title: title.isEmpty ? 'Untitled note' : title,
        body: body,
        createdAt: _originalNote?.createdAt ?? now,
        updatedAt: now,
        tags: tags,
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save note: $e')),
      );
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

  Future<void> _addFile() async {
    final result = await FilePicker.platform.pickFiles();
    if (result == null || result.files.isEmpty) return;
    final String? path = result.files.single.path;
    if (path == null) return;
    final attachment = await _attachmentStorage.saveFileToNoteFolder(
      _noteId,
      File(path),
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

  void _showAttachmentSheet() {
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
                title: const Text('Take photo',
                    style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.of(context).pop();
                  _addImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo, color: Colors.white),
                title: const Text('Pick image',
                    style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.of(context).pop();
                  _addImage(ImageSource.gallery);
                },
              ),
              ListTile(
                leading: const Icon(Icons.attach_file, color: Colors.white),
                title: const Text('Pick file',
                    style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.of(context).pop();
                  _addFile();
                },
              ),
            ],
          ),
        );
      },
    );
  }
  Future<void> _linkObservation() async {
    if (_observations.isEmpty) return;
    final selected = await showModalBottomSheet<Observation>(
      context: context,
      backgroundColor: const Color(0xFF1F4E3D),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: _observations.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final observation = _observations[index];
              final name = _speciesNames[observation.speciesId] ??
                  observation.label.trim();
              final photoPath = observation.photoPath;
              final hasImage =
                  photoPath != null && File(photoPath).existsSync();
              return Material(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: () => Navigator.of(context).pop(observation),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Row(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: hasImage
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Image.file(
                                    File(photoPath!),
                                    fit: BoxFit.cover,
                                    cacheWidth: 120,
                                  ),
                                )
                              : const Icon(
                                  Icons.local_florist,
                                  color: Colors.white70,
                                ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name.isEmpty ? 'Unknown' : name,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                formatDateTime(observation.timestamp),
                                style: const TextStyle(
                                  color: Color(0xCCFFFFFF),
                                  fontSize: 12.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
    if (selected == null) return;
    if (_links.observationIds.contains(selected.id)) return;
    setState(() {
      _links = _links.copyWith(
        observationIds: [..._links.observationIds, selected.id],
      );
    });
  }

  Future<void> _linkSpecies() async {
    if (_species.isEmpty) return;
    final selected = await showModalBottomSheet<Species>(
      context: context,
      backgroundColor: const Color(0xFF1F4E3D),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (context) {
        String query = '';
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final filtered = _species.where((item) {
              if (query.isEmpty) return true;
              final normalized = query.trim().toLowerCase();
              final common = item.commonName?.toLowerCase() ?? '';
              return item.scientificName.toLowerCase().contains(normalized) ||
                  common.contains(normalized);
            }).toList();
            return SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: TextField(
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Search species',
                        hintStyle: const TextStyle(color: Color(0xCCFFFFFF)),
                        prefixIcon: const Icon(Icons.search,
                            color: Color(0xCCFFFFFF)),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.08),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onChanged: (value) {
                        setSheetState(() {
                          query = value;
                        });
                      },
                    ),
                  ),
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final item = filtered[index];
                        return Material(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            onTap: () => Navigator.of(context).pop(item),
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.scientificName,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (item.commonName != null &&
                                      item.commonName!.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        item.commonName!,
                                        style: const TextStyle(
                                          color: Color(0xCCFFFFFF),
                                          fontSize: 12.5,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    if (selected == null) return;
    if (_links.speciesIds.contains(selected.id)) return;
    setState(() {
      _links = _links.copyWith(
        speciesIds: [..._links.speciesIds, selected.id],
      );
    });
  }

  Future<bool> _confirmLocationOverride({AppSettings? settings}) async {
    final resolved = settings ?? _settings;
    if (resolved == null || resolved.locationTaggingEnabled) {
      return true;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Location tagging is off'),
          content: const Text(
            'Location tagging is disabled in Settings. Add a location anyway?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Add location'),
            ),
          ],
        );
      },
    );
    return confirmed ?? false;
  }

  Future<void> _addCurrentLocation() async {
    final ok = await _confirmLocationOverride();
    if (!ok) return;
    final captured = await _locationCaptureService.captureForObservation();
    if (captured == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _locationCaptureService.lastErrorMessage ??
                'Unable to capture location.',
          ),
        ),
      );
      return;
    }
    final settings = _settings ?? await _settingsService.loadSettings();
    final label = await _locationLabelService.labelFor(
      latitude: captured.latitude,
      longitude: captured.longitude,
      mode: settings.locationLabelMode,
    );
    final location = LocationRef(
      id: _uuid.v4(),
      lat: captured.latitude,
      lon: captured.longitude,
      label: label,
      accuracyMeters: captured.accuracyMeters,
      capturedAt: captured.capturedAt,
    );
    setState(() {
      _links = _links.copyWith(
        locations: [..._links.locations, location],
      );
    });
  }

  Future<void> _pickLocationOnMap() async {
    final ok = await _confirmLocationOverride();
    if (!ok) return;
    final result = await Navigator.of(context).pushNamed(
      '/map',
      arguments: const MapPickLocationArgs(
        title: 'Pick note location',
      ),
    );
    if (result is! MapPickResult) return;
    final settings = _settings ?? await _settingsService.loadSettings();
    final label = result.label ??
        await _locationLabelService.labelFor(
          latitude: result.lat,
          longitude: result.lon,
          mode: settings.locationLabelMode,
        );
    final location = LocationRef(
      id: _uuid.v4(),
      lat: result.lat,
      lon: result.lon,
      label: label,
      accuracyMeters: null,
      capturedAt: DateTime.now(),
    );
    setState(() {
      _links = _links.copyWith(
        locations: [..._links.locations, location],
      );
    });
  }

  void _openLocation(LocationRef location) {
    Navigator.of(context).pushNamed(
      '/map',
      arguments: MapFocusRequest(
        observationId: null,
        lat: location.lat,
        lon: location.lon,
        zoom: 15,
        label: location.label,
      ),
    );
  }

  void _removeLocation(LocationRef location) {
    setState(() {
      _links = _links.copyWith(
        locations:
            _links.locations.where((item) => item.id != location.id).toList(),
      );
    });
  }
  Widget _attachmentTile(NoteAttachment attachment) {
    final bool isImage = attachment.type == NoteAttachmentType.image;
    final String path = attachment.thumbnailPath ?? attachment.filePath;
    final bool exists = File(path).existsSync();
    return Stack(
      children: [
        Container(
          width: 92,
          height: 92,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
          ),
          child: isImage && exists
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(
                    File(path),
                    fit: BoxFit.cover,
                    cacheWidth: 220,
                  ),
                )
              : const Icon(Icons.insert_drive_file, color: Colors.white70),
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
              child: const Icon(
                Icons.close,
                size: 14,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _linkChip(String label, VoidCallback onRemove) {
    return Chip(
      label: Text(
        label,
        style: const TextStyle(color: Colors.white, fontSize: 12.5),
      ),
      deleteIcon: const Icon(Icons.close, size: 18),
      onDeleted: onRemove,
      backgroundColor: Colors.white.withValues(alpha: 0.12),
      side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    const accentTextColor = Color(0xCCFFFFFF);

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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _saving ? null : _saveNote,
        backgroundColor: const Color(0xFF8FBFA1),
        foregroundColor: Colors.white,
        label: Text(_saving ? 'Saving...' : 'Save'),
        icon: const Icon(Icons.save),
      ),
      body: ForestBackground(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        includeTopSafeArea: false,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _titleController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Title',
                  labelStyle: const TextStyle(color: accentTextColor),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.08),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _bodyController,
                maxLines: 6,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Note body',
                  labelStyle: const TextStyle(color: accentTextColor),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.08),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _tagsController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Tags (comma separated)',
                  labelStyle: const TextStyle(color: accentTextColor),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.08),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  const Text(
                    'Attachments',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _showAttachmentSheet,
                    icon: const Icon(Icons.add, color: Colors.white),
                    label: const Text(
                      'Add',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _attachments.isEmpty
                  ? const Text(
                      'No attachments yet.',
                      style: TextStyle(color: accentTextColor),
                    )
                  : Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children:
                          _attachments.map(_attachmentTile).toList(),
                    ),
              const SizedBox(height: 20),
              const Text(
                'Links',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 8),
              _SectionCard(
                title: 'Observations',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_links.observationIds.isEmpty)
                      const Text(
                        'No linked observations.',
                        style: TextStyle(color: accentTextColor),
                      )
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _links.observationIds.map((id) {
                          final observation = _observations
                              .where((item) => item.id == id)
                              .firstOrNull;
                          final label = observation == null
                              ? 'Observation $id'
                              : (_speciesNames[observation.speciesId] ??
                                  observation.label.trim());
                          return _linkChip(label, () {
                            setState(() {
                              _links = _links.copyWith(
                                observationIds: _links.observationIds
                                    .where((item) => item != id)
                                    .toList(),
                              );
                            });
                          });
                        }).toList(),
                      ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _linkObservation,
                      icon: const Icon(Icons.add, color: Colors.white),
                      label: const Text(
                        'Link observation',
                        style: TextStyle(color: Colors.white),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white54),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _SectionCard(
                title: 'Species',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_links.speciesIds.isEmpty)
                      const Text(
                        'No linked species.',
                        style: TextStyle(color: accentTextColor),
                      )
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _links.speciesIds.map((id) {
                          final label = _speciesNames[id] ?? 'Species $id';
                          return _linkChip(label, () {
                            setState(() {
                              _links = _links.copyWith(
                                speciesIds: _links.speciesIds
                                    .where((item) => item != id)
                                    .toList(),
                              );
                            });
                          });
                        }).toList(),
                      ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _linkSpecies,
                      icon: const Icon(Icons.add, color: Colors.white),
                      label: const Text(
                        'Link species',
                        style: TextStyle(color: Colors.white),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white54),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _SectionCard(
                title: 'Locations',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_links.locations.isEmpty)
                      const Text(
                        'No linked locations.',
                        style: TextStyle(color: accentTextColor),
                      )
                    else
                      Column(
                        children: _links.locations.map((location) {
                          final label = (location.label ?? '').trim().isEmpty
                              ? '${location.lat.toStringAsFixed(3)}, ${location.lon.toStringAsFixed(3)}'
                              : location.label!;
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              label,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13.5,
                              ),
                            ),
                            subtitle: Text(
                              'Captured ${formatDateTime(location.capturedAt)}',
                              style: const TextStyle(
                                color: Color(0xCCFFFFFF),
                                fontSize: 11.5,
                              ),
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.close, color: Colors.white70),
                              onPressed: () => _removeLocation(location),
                            ),
                            onTap: () => _openLocation(location),
                          );
                        }).toList(),
                      ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _addCurrentLocation,
                            icon: const Icon(Icons.gps_fixed,
                                color: Colors.white),
                            label: const Text(
                              'Use current GPS',
                              style: TextStyle(color: Colors.white),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: const BorderSide(color: Colors.white54),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _pickLocationOnMap,
                            icon: const Icon(Icons.map, color: Colors.white),
                            label: const Text(
                              'Pick on Map',
                              style: TextStyle(color: Colors.white),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: const BorderSide(color: Colors.white54),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 90),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
