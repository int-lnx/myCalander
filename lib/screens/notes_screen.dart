import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/note.dart';
import '../utils/id_generator.dart';

class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key});

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  bool _isExpanded = false;
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  final _tagController = TextEditingController();
  
  int _selectedColorValue = 0xFFFFFFFF; // Default White
  bool _isPinned = false;
  List<String> _tags = [];

  final List<int> _noteColors = const [
    0xFFFFFFFF, // White
    0xFFF28B82, // Red
    0xFFFBBC04, // Orange
    0xFFFFF475, // Yellow
    0xFFCCFF90, // Green
    0xFFA7FFEB, // Teal
    0xFFCBF0F8, // Blue
    0xFFAECBFA, // Dark Blue
    0xFFD7AEFB, // Purple
    0xFFFDCFE8, // Pink
    0xFFE6C9A8, // Brown
    0xFFE8EAED, // Grey
  ];

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _tagController.dispose();
    super.dispose();
  }

  void _resetInputArea() {
    _titleController.clear();
    _contentController.clear();
    _tagController.clear();
    setState(() {
      _selectedColorValue = 0xFFFFFFFF;
      _isPinned = false;
      _tags = [];
      _isExpanded = false;
    });
  }

  void _saveNote(AppState appState) {
    final title = _titleController.text.trim();
    final content = _contentController.text.trim();
    if (title.isEmpty && content.isEmpty) {
      _resetInputArea();
      return;
    }

    final newNote = Note(
      id: IdGenerator.generate(title.isNotEmpty ? title : 'note'),
      title: title,
      content: content,
      colorValue: _selectedColorValue,
      isPinned: _isPinned,
      tags: List.from(_tags),
    );

    appState.addNote(newNote);
    _resetInputArea();
  }

  void _showColorPickerBottomSheet(BuildContext context, ValueChanged<int> onColorSelected) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Arka Plan Rengi Seç',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 50,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _noteColors.length,
                  itemBuilder: (context, index) {
                    final colorVal = _noteColors[index];
                    return GestureDetector(
                      onTap: () {
                        onColorSelected(colorVal);
                        Navigator.pop(context);
                      },
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 6),
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(colorVal),
                          border: Border.all(
                            color: Colors.grey.shade400,
                            width: colorVal == 0xFFFFFFFF ? 1.5 : 0.5,
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
  }

  void _showTagsDialog(BuildContext context, List<String> currentTags, ValueChanged<List<String>> onTagsUpdated) {
    final tagsList = List<String>.from(currentTags);
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Etiketleri Düzenle'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _tagController,
                            decoration: const InputDecoration(
                              hintText: 'Yeni etiket ekle...',
                              isDense: true,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add, color: Colors.blue),
                          onPressed: () {
                            final text = _tagController.text.trim();
                            if (text.isNotEmpty && !tagsList.contains(text)) {
                              setDialogState(() {
                                tagsList.add(text);
                              });
                              _tagController.clear();
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      children: tagsList.map((tag) {
                        return Chip(
                          label: Text(tag, style: const TextStyle(fontSize: 12)),
                          onDeleted: () {
                            setDialogState(() {
                              tagsList.remove(tag);
                            });
                          },
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('İptal'),
                ),
                ElevatedButton(
                  onPressed: () {
                    onTagsUpdated(tagsList);
                    Navigator.pop(ctx);
                  },
                  child: const Text('Kaydet'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _editNoteDialog(BuildContext context, AppState appState, Note note) {
    final editTitleController = TextEditingController(text: note.title);
    final editContentController = TextEditingController(text: note.content);
    int editColorValue = note.colorValue;
    bool editIsPinned = note.isPinned;
    List<String> editTags = List.from(note.tags);

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final isNoteDark = Color(editColorValue).computeLuminance() < 0.5;
            return AlertDialog(
              backgroundColor: Color(editColorValue),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              title: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: editTitleController,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: isNoteDark ? Colors.white : Colors.black87,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Başlık',
                        border: InputBorder.none,
                        hintStyle: TextStyle(
                          color: isNoteDark ? Colors.white70 : Colors.black45,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      editIsPinned ? Icons.push_pin : Icons.push_pin_outlined,
                      color: isNoteDark ? Colors.white : Colors.black87,
                    ),
                    onPressed: () {
                      setDialogState(() {
                        editIsPinned = !editIsPinned;
                      });
                    },
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: editContentController,
                      maxLines: null,
                      style: TextStyle(
                        fontSize: 14,
                        color: isNoteDark ? Colors.white70 : Colors.black87,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Not alın...',
                        border: InputBorder.none,
                        hintStyle: TextStyle(
                          color: isNoteDark ? Colors.white60 : Colors.black45,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (editTags.isNotEmpty)
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: editTags.map((tag) {
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: isNoteDark ? Colors.white10 : Colors.black12,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              tag,
                              style: TextStyle(
                                fontSize: 10,
                                color: isNoteDark ? Colors.white70 : Colors.black87,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                  ],
                ),
              ),
              actions: [
                // Color Picker Button
                IconButton(
                  icon: Icon(
                    Icons.palette_outlined,
                    color: isNoteDark ? Colors.white70 : Colors.black87,
                  ),
                  onPressed: () {
                    _showColorPickerBottomSheet(context, (color) {
                      setDialogState(() {
                        editColorValue = color;
                      });
                    });
                  },
                ),
                // Tags Button
                IconButton(
                  icon: Icon(
                    Icons.label_outline,
                    color: isNoteDark ? Colors.white70 : Colors.black87,
                  ),
                  onPressed: () {
                    _showTagsDialog(context, editTags, (updatedTags) {
                      setDialogState(() {
                        editTags = updatedTags;
                      });
                    });
                  },
                ),
                // Delete Button
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: () {
                    appState.deleteNote(note.id);
                    Navigator.pop(ctx);
                  },
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(
                    'İptal',
                    style: TextStyle(
                      color: isNoteDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    final updatedNote = note.copyWith(
                      title: editTitleController.text.trim(),
                      content: editContentController.text.trim(),
                      colorValue: editColorValue,
                      isPinned: editIsPinned,
                      tags: editTags,
                    );
                    appState.updateNote(updatedNote);
                    Navigator.pop(ctx);
                  },
                  child: const Text('Kaydet'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildNoteCard(AppState appState, Note note, bool isDarkTheme) {
    final isNoteDark = Color(note.colorValue).computeLuminance() < 0.5;
    final cardColor = Color(note.colorValue);

    return Card(
      elevation: 1.5,
      color: cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: isDarkTheme ? Colors.grey.shade800 : Colors.grey.shade300,
          width: note.colorValue == 0xFFFFFFFF ? 1.0 : 0.0,
        ),
      ),
      child: InkWell(
        onTap: () => _editNoteDialog(context, appState, note),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      note.title,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: isNoteDark ? Colors.white : Colors.black87,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: () {
                      appState.updateNote(note.copyWith(isPinned: !note.isPinned));
                    },
                    child: Icon(
                      note.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                      size: 16,
                      color: isNoteDark ? Colors.white60 : Colors.black54,
                    ),
                  ),
                ],
              ),
              if (note.title.isNotEmpty && note.content.isNotEmpty)
                const SizedBox(height: 8),
              if (note.content.isNotEmpty)
                Text(
                  note.content,
                  style: TextStyle(
                    fontSize: 12,
                    color: isNoteDark ? Colors.white70 : Colors.black87,
                  ),
                  maxLines: 12,
                  overflow: TextOverflow.ellipsis,
                ),
              if (note.tags.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: note.tags.map((tag) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: isNoteDark ? Colors.white10 : Colors.black12,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        tag,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: isNoteDark ? Colors.white70 : Colors.black87,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final isDark = appState.isDarkMode;
    final allNotes = appState.notes;

    final pinnedNotes = allNotes.where((n) => n.isPinned).toList();
    final otherNotes = allNotes.where((n) => !n.isPinned).toList();

    return Scaffold(
      backgroundColor: isDark ? Colors.grey.shade900 : Colors.grey.shade50,
      body: SafeArea(
        child: GestureDetector(
          onTap: () {
            if (_isExpanded) {
              _saveNote(appState);
            }
          },
          child: Column(
            children: [
              // Top Write Area
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                child: Center(
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 600),
                    decoration: BoxDecoration(
                      color: Color(_selectedColorValue),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: 4,
                          offset: Offset(0, 2),
                        )
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_isExpanded)
                          Row(
                            children: [
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                                  child: TextField(
                                    controller: _titleController,
                                    decoration: const InputDecoration(
                                      hintText: 'Başlık',
                                      border: InputBorder.none,
                                    ),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: Icon(_isPinned ? Icons.push_pin : Icons.push_pin_outlined),
                                onPressed: () {
                                  setState(() {
                                    _isPinned = !_isPinned;
                                  });
                                },
                              ),
                            ],
                          ),
                        GestureDetector(
                          onTap: () {
                            if (!_isExpanded) {
                              setState(() {
                                _isExpanded = true;
                              });
                            }
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16.0),
                            child: TextField(
                              controller: _contentController,
                              maxLines: _isExpanded ? null : 1,
                              enabled: _isExpanded,
                              decoration: const InputDecoration(
                                hintText: 'Not alın...',
                                border: InputBorder.none,
                              ),
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                        ),
                        if (_isExpanded) ...[
                          if (_tags.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Wrap(
                                  spacing: 6,
                                  children: _tags.map((tag) => Chip(
                                    label: Text(tag, style: const TextStyle(fontSize: 10)),
                                    padding: EdgeInsets.zero,
                                    onDeleted: () {
                                      setState(() {
                                        _tags.remove(tag);
                                      });
                                    },
                                  )).toList(),
                                ),
                              ),
                            ),
                          const Divider(height: 1),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.palette_outlined, size: 20),
                                      onPressed: () {
                                        _showColorPickerBottomSheet(context, (color) {
                                          setState(() {
                                            _selectedColorValue = color;
                                          });
                                        });
                                      },
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.label_outline, size: 20),
                                      onPressed: () {
                                        _showTagsDialog(context, _tags, (updatedTags) {
                                          setState(() {
                                            _tags = updatedTags;
                                          });
                                        });
                                      },
                                    ),
                                  ],
                                ),
                                TextButton(
                                  onPressed: () => _saveNote(appState),
                                  child: const Text('Kapat', style: TextStyle(fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),

              // Grid List of Notes
              Expanded(
                child: allNotes.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.lightbulb_outline, size: 80, color: isDark ? Colors.grey.shade700 : Colors.grey.shade300),
                            const SizedBox(height: 16),
                            const Text(
                              'Burada eklediğiniz notlar görünecektir',
                              style: TextStyle(color: Colors.grey, fontSize: 14),
                            ),
                          ],
                        ),
                      )
                    : SingleChildScrollView(
                        padding: const EdgeInsets.all(16.0),
                        child: Center(
                          child: Container(
                            constraints: const BoxConstraints(maxWidth: 1000),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (pinnedNotes.isNotEmpty) ...[
                                  const Padding(
                                    padding: EdgeInsets.only(left: 8.0, bottom: 8.0),
                                    child: Text(
                                      'SABİTLENDİ',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.grey,
                                        letterSpacing: 1.2,
                                      ),
                                    ),
                                  ),
                                  GridView.builder(
                                    shrinkWrap: true,
                                    physics: const NeverScrollableScrollPhysics(),
                                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                                      maxCrossAxisExtent: 220,
                                      crossAxisSpacing: 12,
                                      mainAxisSpacing: 12,
                                      childAspectRatio: 0.85,
                                    ),
                                    itemCount: pinnedNotes.length,
                                    itemBuilder: (context, index) {
                                      return _buildNoteCard(appState, pinnedNotes[index], isDark);
                                    },
                                  ),
                                  const SizedBox(height: 24),
                                ],
                                if (otherNotes.isNotEmpty) ...[
                                  if (pinnedNotes.isNotEmpty)
                                    const Padding(
                                      padding: EdgeInsets.only(left: 8.0, bottom: 8.0),
                                      child: Text(
                                        'DİĞER',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.grey,
                                          letterSpacing: 1.2,
                                        ),
                                      ),
                                    ),
                                  GridView.builder(
                                    shrinkWrap: true,
                                    physics: const NeverScrollableScrollPhysics(),
                                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                                      maxCrossAxisExtent: 220,
                                      crossAxisSpacing: 12,
                                      mainAxisSpacing: 12,
                                      childAspectRatio: 0.85,
                                    ),
                                    itemCount: otherNotes.length,
                                    itemBuilder: (context, index) {
                                      return _buildNoteCard(appState, otherNotes[index], isDark);
                                    },
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
