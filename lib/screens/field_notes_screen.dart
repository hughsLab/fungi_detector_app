import 'package:flutter/material.dart';

import '../models/field_note.dart';
import '../models/navigation_args.dart';
import '../repositories/field_notes_repository.dart';
import '../utils/formatting.dart';
import '../widgets/forest_background.dart';

enum FieldNotesFilter {
  all,
  observation,
  species,
  location,
  pinned,
  archived,
}

enum FieldNotesSort { updatedDesc, createdDesc, titleAsc }

class FieldNotesScreen extends StatefulWidget {
  const FieldNotesScreen({super.key});

  @override
  State<FieldNotesScreen> createState() => _FieldNotesScreenState();
}

class _FieldNotesScreenState extends State<FieldNotesScreen> {
  final FieldNotesRepository _repository = FieldNotesRepository.instance;
  final TextEditingController _searchController = TextEditingController();

  FieldNotesFilter _filter = FieldNotesFilter.all;
  FieldNotesSort _sort = FieldNotesSort.updatedDesc;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_handleSearch);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _handleSearch() {
    final text = _searchController.text.trim();
    if (text == _query) return;
    setState(() => _query = text);
  }

  List<FieldNote> _applyFilters(List<FieldNote> notes) {
    final normalized = _query.trim().toLowerCase();
    final bool showArchived = _filter == FieldNotesFilter.archived;
    final filtered = notes.where((note) {
      if (!showArchived && note.isArchived) {
        return false;
      }
      if (showArchived && !note.isArchived) {
        return false;
      }
      switch (_filter) {
        case FieldNotesFilter.all:
        case FieldNotesFilter.archived:
          break;
        case FieldNotesFilter.observation:
          if (note.links.observationIds.isEmpty) return false;
          break;
        case FieldNotesFilter.species:
          if (note.links.speciesIds.isEmpty) return false;
          break;
        case FieldNotesFilter.location:
          if (note.links.locations.isEmpty) return false;
          break;
        case FieldNotesFilter.pinned:
          if (!note.isPinned) return false;
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

    filtered.sort((a, b) {
      if (a.isPinned != b.isPinned) {
        return a.isPinned ? -1 : 1;
      }
      switch (_sort) {
        case FieldNotesSort.updatedDesc:
          return b.updatedAt.compareTo(a.updatedAt);
        case FieldNotesSort.createdDesc:
          return b.createdAt.compareTo(a.createdAt);
        case FieldNotesSort.titleAsc:
          return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      }
    });
    return filtered;
  }

  void _openEditor({String? noteId}) {
    Navigator.of(context).pushNamed(
      '/field-note-editor',
      arguments: FieldNoteEditorArgs(noteId: noteId),
    );
  }

  Future<void> _togglePinned(FieldNote note) async {
    final updated = note.copyWith(
      isPinned: !note.isPinned,
      updatedAt: DateTime.now(),
    );
    await _repository.upsertNote(updated);
  }

  Future<void> _toggleArchived(FieldNote note) async {
    final updated = note.copyWith(
      isArchived: !note.isArchived,
      updatedAt: DateTime.now(),
    );
    await _repository.upsertNote(updated);
  }

  Future<void> _deleteNote(FieldNote note) async {
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
    await _repository.deleteNote(note.id, deleteAttachments: deleteFiles);
  }

  String _snippetFor(FieldNote note) {
    final raw = note.body.trim();
    if (raw.isEmpty) {
      return 'No note body yet.';
    }
    if (raw.length <= 120) {
      return raw;
    }
    return '${raw.substring(0, 120)}...';
  }

  Widget _linkChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const accentTextColor = Color(0xCCFFFFFF);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Field Notes'),
        backgroundColor: const Color(0xFF1F4E3D),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          DropdownButtonHideUnderline(
            child: DropdownButton<FieldNotesSort>(
              value: _sort,
              dropdownColor: const Color(0xFF1F4E3D),
              iconEnabledColor: Colors.white,
              items: const [
                DropdownMenuItem(
                  value: FieldNotesSort.updatedDesc,
                  child: Text(
                    'Updated',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
                DropdownMenuItem(
                  value: FieldNotesSort.createdDesc,
                  child: Text(
                    'Created',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
                DropdownMenuItem(
                  value: FieldNotesSort.titleAsc,
                  child: Text(
                    'Title A-Z',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => _sort = value);
              },
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openEditor(),
        backgroundColor: const Color(0xFF8FBFA1),
        foregroundColor: Colors.white,
        child: const Icon(Icons.note_add),
      ),
      body: ForestBackground(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        includeTopSafeArea: false,
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search notes, tags, or body text',
                hintStyle: const TextStyle(color: accentTextColor),
                prefixIcon: const Icon(Icons.search, color: accentTextColor),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.08),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: FieldNotesFilter.values.map((value) {
                  final bool selected = _filter == value;
                  final String label = switch (value) {
                    FieldNotesFilter.all => 'All',
                    FieldNotesFilter.observation => 'Observation',
                    FieldNotesFilter.species => 'Species',
                    FieldNotesFilter.location => 'Location',
                    FieldNotesFilter.pinned => 'Pinned',
                    FieldNotesFilter.archived => 'Archived',
                  };
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(label),
                      selected: selected,
                      onSelected: (_) {
                        setState(() => _filter = value);
                      },
                      selectedColor: const Color(0xFF8FBFA1),
                      labelStyle: TextStyle(
                        color: selected ? Colors.white : accentTextColor,
                      ),
                      backgroundColor: Colors.white.withValues(alpha: 0.1),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: StreamBuilder<List<FieldNote>>(
                stream: _repository.watchAllNotes(),
                builder: (context, snapshot) {
                  final notes = _applyFilters(snapshot.data ?? const []);
                  if (notes.isEmpty) {
                    return const Center(
                      child: Text(
                        'No field notes yet.',
                        style: TextStyle(color: accentTextColor),
                      ),
                    );
                  }
                  return ListView.separated(
                    itemCount: notes.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final note = notes[index];
                      final title =
                          note.title.trim().isEmpty ? 'Untitled note' : note.title;
                      final chips = <Widget>[];
                      if (note.links.observationIds.isNotEmpty) {
                        chips.add(
                          _linkChip('Obs ${note.links.observationIds.length}'),
                        );
                      }
                      if (note.links.speciesIds.isNotEmpty) {
                        chips.add(
                          _linkChip('Species ${note.links.speciesIds.length}'),
                        );
                      }
                      if (note.links.locations.isNotEmpty) {
                        chips.add(
                          _linkChip('Loc ${note.links.locations.length}'),
                        );
                      }
                      return Material(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(16),
                        child: InkWell(
                          onTap: () => _openEditor(noteId: note.id),
                          borderRadius: BorderRadius.circular(16),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        title,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 15.5,
                                        ),
                                      ),
                                    ),
                                    if (note.isPinned)
                                      const Icon(
                                        Icons.push_pin,
                                        color: Color(0xFF7CD39A),
                                        size: 18,
                                      ),
                                    if (note.isArchived)
                                      const Padding(
                                        padding: EdgeInsets.only(left: 6),
                                        child: Icon(
                                          Icons.archive,
                                          color: Colors.white54,
                                          size: 18,
                                        ),
                                      ),
                                    PopupMenuButton<String>(
                                      icon: const Icon(
                                        Icons.more_vert,
                                        color: Colors.white70,
                                      ),
                                      onSelected: (value) {
                                        switch (value) {
                                          case 'pin':
                                            _togglePinned(note);
                                            break;
                                          case 'archive':
                                            _toggleArchived(note);
                                            break;
                                          case 'delete':
                                            _deleteNote(note);
                                            break;
                                        }
                                      },
                                      itemBuilder: (context) => [
                                        PopupMenuItem(
                                          value: 'pin',
                                          child: Text(
                                            note.isPinned
                                                ? 'Unpin'
                                                : 'Pin',
                                          ),
                                        ),
                                        PopupMenuItem(
                                          value: 'archive',
                                          child: Text(
                                            note.isArchived
                                                ? 'Unarchive'
                                                : 'Archive',
                                          ),
                                        ),
                                        const PopupMenuItem(
                                          value: 'delete',
                                          child: Text('Delete'),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  _snippetFor(note),
                                  style: const TextStyle(
                                    color: accentTextColor,
                                    fontSize: 12.5,
                                    height: 1.4,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Updated ${formatDateTime(note.updatedAt)}',
                                  style: const TextStyle(
                                    color: Color(0x99FFFFFF),
                                    fontSize: 11.5,
                                  ),
                                ),
                                if (chips.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: chips,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
