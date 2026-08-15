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
  final _contentController = FormattedTextEditingController();
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

  void _applyFormatting(TextEditingController controller, String prefix, String suffix) {
    final text = controller.text;
    final selection = controller.selection;
    if (!selection.isValid) return;

    final start = selection.start;
    final end = selection.end;

    if (start != end) {
      final selectedText = text.substring(start, end);
      final newText = text.replaceRange(start, end, '$prefix$selectedText$suffix');
      controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection(
          baseOffset: start,
          extentOffset: end + prefix.length + suffix.length,
        ),
      );
    } else {
      final newText = text.replaceRange(start, end, '$prefix$suffix');
      controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: start + prefix.length),
      );
    }
  }

  static Widget buildFormattedText(String text, TextStyle baseStyle) {
    final RegExp exp = RegExp(r'(\*\*\*.*?\*\*\*|\*\*.*?\*\*|\*.*?\*|~~.*?~~)');
    final List<TextSpan> spans = [];
    int start = 0;

    for (final Match match in exp.allMatches(text)) {
      if (match.start > start) {
        spans.add(TextSpan(text: text.substring(start, match.start), style: baseStyle));
      }
      final String matchText = match.group(0)!;
      if (matchText.startsWith('***') && matchText.endsWith('***') && matchText.length >= 6) {
        spans.add(TextSpan(
          text: matchText.substring(3, matchText.length - 3),
          style: baseStyle.copyWith(fontWeight: FontWeight.bold, fontStyle: FontStyle.italic),
        ));
      } else if (matchText.startsWith('**') && matchText.endsWith('**') && matchText.length >= 4) {
        spans.add(TextSpan(
          text: matchText.substring(2, matchText.length - 2),
          style: baseStyle.copyWith(fontWeight: FontWeight.bold),
        ));
      } else if (matchText.startsWith('*') && matchText.endsWith('*') && matchText.length >= 2) {
        spans.add(TextSpan(
          text: matchText.substring(1, matchText.length - 1),
          style: baseStyle.copyWith(fontStyle: FontStyle.italic),
        ));
      } else if (matchText.startsWith('~~') && matchText.endsWith('~~') && matchText.length >= 4) {
        spans.add(TextSpan(
          text: matchText.substring(2, matchText.length - 2),
          style: baseStyle.copyWith(decoration: TextDecoration.lineThrough),
        ));
      }
      start = match.end;
    }

    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start), style: baseStyle));
    }

    return RichText(text: TextSpan(children: spans));
  }

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
    showDialog(
      context: context,
      builder: (ctx) {
        return EditNoteDialog(
          appState: appState,
          note: note,
          noteColors: _noteColors,
          onTagsDialogRequested: (currentTags, onTagsUpdated) {
            _showTagsDialog(context, currentTags, onTagsUpdated);
          },
          onColorPickerRequested: (onColorSelected) {
            _showColorPickerBottomSheet(context, onColorSelected);
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final isDark = appState.isDarkMode;
    final allNotes = appState.notes;

    if (appState.lastFirebaseError != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Firebase Hatası: ${appState.lastFirebaseError}'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: 'Kapat',
              textColor: Colors.white,
              onPressed: () => appState.clearFirebaseError(),
            ),
          ),
        );
        appState.clearFirebaseError();
      });
    }

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
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                child: Center(
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 800),
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
                            child: _isExpanded
                                ? ConstrainedBox(
                                    constraints: const BoxConstraints(maxHeight: 250),
                                    child: Scrollbar(
                                      child: SingleChildScrollView(
                                        child: TextField(
                                          controller: _contentController,
                                          maxLines: null,
                                          decoration: const InputDecoration(
                                            hintText: 'Not alın...',
                                            border: InputBorder.none,
                                          ),
                                          style: const TextStyle(fontSize: 14),
                                        ),
                                      ),
                                    ),
                                  )
                                : TextField(
                                    controller: _contentController,
                                    maxLines: 1,
                                    enabled: false,
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
                                      icon: const Icon(Icons.format_bold, size: 20),
                                      onPressed: () => _applyFormatting(_contentController, '**', '**'),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.format_italic, size: 20),
                                      onPressed: () => _applyFormatting(_contentController, '*', '*'),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.format_strikethrough, size: 20),
                                      onPressed: () => _applyFormatting(_contentController, '~~', '~~'),
                                    ),
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
                                      return NoteCard(
                                        appState: appState,
                                        note: pinnedNotes[index],
                                        isDarkTheme: isDark,
                                        onTap: () => _editNoteDialog(context, appState, pinnedNotes[index]),
                                      );
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
                                      return NoteCard(
                                        appState: appState,
                                        note: otherNotes[index],
                                        isDarkTheme: isDark,
                                        onTap: () => _editNoteDialog(context, appState, otherNotes[index]),
                                      );
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

class NoteCard extends StatefulWidget {
  final AppState appState;
  final Note note;
  final bool isDarkTheme;
  final VoidCallback onTap;

  const NoteCard({
    super.key,
    required this.appState,
    required this.note,
    required this.isDarkTheme,
    required this.onTap,
  });

  @override
  State<NoteCard> createState() => _NoteCardState();
}

class _NoteCardState extends State<NoteCard> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final note = widget.note;
    final isNoteDark = Color(note.colorValue).computeLuminance() < 0.5;
    final cardColor = Color(note.colorValue);

    return Card(
      elevation: 1.5,
      color: cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: widget.isDarkTheme ? Colors.grey.shade800 : Colors.grey.shade300,
          width: note.colorValue == 0xFFFFFFFF ? 1.0 : 0.0,
        ),
      ),
      child: InkWell(
        onTap: widget.onTap,
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
                      widget.appState.updateNote(note.copyWith(isPinned: !note.isPinned));
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
                Expanded(
                  child: Scrollbar(
                    controller: _scrollController,
                    thumbVisibility: true,
                    trackVisibility: true,
                    thickness: 4,
                    radius: const Radius.circular(2),
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.only(right: 6.0),
                        child: _NotesScreenState.buildFormattedText(
                          note.content,
                          TextStyle(
                            fontSize: 12,
                            color: isNoteDark ? Colors.white70 : Colors.black87,
                          ),
                        ),
                      ),
                    ),
                  ),
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
}

class EditNoteDialog extends StatefulWidget {
  final AppState appState;
  final Note note;
  final List<int> noteColors;
  final void Function(List<String> currentTags, ValueChanged<List<String>> onTagsUpdated) onTagsDialogRequested;
  final void Function(ValueChanged<int> onColorSelected) onColorPickerRequested;

  const EditNoteDialog({
    super.key,
    required this.appState,
    required this.note,
    required this.noteColors,
    required this.onTagsDialogRequested,
    required this.onColorPickerRequested,
  });

  @override
  State<EditNoteDialog> createState() => _EditNoteDialogState();
}

class _EditNoteDialogState extends State<EditNoteDialog> {
  late TextEditingController _titleController;
  late FormattedTextEditingController _contentController;
  late int _colorValue;
  late bool _isPinned;
  late List<String> _tags;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.note.title);
    _contentController = FormattedTextEditingController(text: widget.note.content);
    _colorValue = widget.note.colorValue;
    _isPinned = widget.note.isPinned;
    _tags = List.from(widget.note.tags);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isNoteDark = Color(_colorValue).computeLuminance() < 0.5;
    return AlertDialog(
      backgroundColor: Color(_colorValue),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _titleController,
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
              _isPinned ? Icons.push_pin : Icons.push_pin_outlined,
              color: isNoteDark ? Colors.white : Colors.black87,
            ),
            onPressed: () {
              setState(() {
                _isPinned = !_isPinned;
              });
            },
          ),
        ],
      ),
      content: Container(
        width: double.maxFinite,
        constraints: BoxConstraints(
          maxWidth: 750,
          maxHeight: MediaQuery.of(context).size.height * 0.45,
        ),
        child: Scrollbar(
          controller: _scrollController,
          thumbVisibility: true,
          trackVisibility: true,
          thickness: 6,
          radius: const Radius.circular(3),
          child: SingleChildScrollView(
            controller: _scrollController,
            child: Padding(
              padding: const EdgeInsets.only(right: 12.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _contentController,
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
                  if (_tags.isNotEmpty)
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: _tags.map((tag) {
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
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      actions: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    padding: const EdgeInsets.all(8),
                    constraints: const BoxConstraints(),
                    icon: Icon(
                      Icons.format_bold,
                      color: isNoteDark ? Colors.white70 : Colors.black87,
                      size: 20,
                    ),
                    onPressed: () {
                      final text = _contentController.text;
                      final selection = _contentController.selection;
                      if (!selection.isValid) return;
                      final start = selection.start;
                      final end = selection.end;
                      if (start != end) {
                        final selectedText = text.substring(start, end);
                        final newText = text.replaceRange(start, end, '**$selectedText**');
                        _contentController.value = TextEditingValue(
                          text: newText,
                          selection: TextSelection(baseOffset: start, extentOffset: end + 4),
                        );
                      } else {
                        final newText = text.replaceRange(start, end, '****');
                        _contentController.value = TextEditingValue(
                          text: newText,
                          selection: TextSelection.collapsed(offset: start + 2),
                        );
                      }
                    },
                  ),
                  IconButton(
                    padding: const EdgeInsets.all(8),
                    constraints: const BoxConstraints(),
                    icon: Icon(
                      Icons.format_italic,
                      color: isNoteDark ? Colors.white70 : Colors.black87,
                      size: 20,
                    ),
                    onPressed: () {
                      final text = _contentController.text;
                      final selection = _contentController.selection;
                      if (!selection.isValid) return;
                      final start = selection.start;
                      final end = selection.end;
                      if (start != end) {
                        final selectedText = text.substring(start, end);
                        final newText = text.replaceRange(start, end, '*$selectedText*');
                        _contentController.value = TextEditingValue(
                          text: newText,
                          selection: TextSelection(baseOffset: start, extentOffset: end + 2),
                        );
                      } else {
                        final newText = text.replaceRange(start, end, '**');
                        _contentController.value = TextEditingValue(
                          text: newText,
                          selection: TextSelection.collapsed(offset: start + 1),
                        );
                      }
                    },
                  ),
                  IconButton(
                    padding: const EdgeInsets.all(8),
                    constraints: const BoxConstraints(),
                    icon: Icon(
                      Icons.format_strikethrough,
                      color: isNoteDark ? Colors.white70 : Colors.black87,
                      size: 20,
                    ),
                    onPressed: () {
                      final text = _contentController.text;
                      final selection = _contentController.selection;
                      if (!selection.isValid) return;
                      final start = selection.start;
                      final end = selection.end;
                      if (start != end) {
                        final selectedText = text.substring(start, end);
                        final newText = text.replaceRange(start, end, '~~$selectedText~~');
                        _contentController.value = TextEditingValue(
                          text: newText,
                          selection: TextSelection(baseOffset: start, extentOffset: end + 4),
                        );
                      } else {
                        final newText = text.replaceRange(start, end, '~~~~');
                        _contentController.value = TextEditingValue(
                          text: newText,
                          selection: TextSelection.collapsed(offset: start + 2),
                        );
                      }
                    },
                  ),
                  IconButton(
                    padding: const EdgeInsets.all(8),
                    constraints: const BoxConstraints(),
                    icon: Icon(
                      Icons.palette_outlined,
                      color: isNoteDark ? Colors.white70 : Colors.black87,
                      size: 20,
                    ),
                    onPressed: () {
                      widget.onColorPickerRequested((color) {
                        setState(() {
                          _colorValue = color;
                        });
                      });
                    },
                  ),
                  IconButton(
                    padding: const EdgeInsets.all(8),
                    constraints: const BoxConstraints(),
                    icon: Icon(
                      Icons.label_outline,
                      color: isNoteDark ? Colors.white70 : Colors.black87,
                      size: 20,
                    ),
                    onPressed: () {
                      widget.onTagsDialogRequested(_tags, (updatedTags) {
                        setState(() {
                          _tags = updatedTags;
                        });
                      });
                    },
                  ),
                  IconButton(
                    padding: const EdgeInsets.all(8),
                    constraints: const BoxConstraints(),
                    icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                    onPressed: () {
                      widget.appState.deleteNote(widget.note.id);
                      Navigator.pop(context);
                    },
                  ),
                ],
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'İptal',
                    style: TextStyle(
                      color: isNoteDark ? Colors.white70 : Colors.black87,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () {
                    final updatedNote = widget.note.copyWith(
                      title: _titleController.text.trim(),
                      content: _contentController.text.trim(),
                      colorValue: _colorValue,
                      isPinned: _isPinned,
                      tags: _tags,
                    );
                    widget.appState.updateNote(updatedNote);
                    Navigator.pop(context);
                  },
                  child: const Text('Kaydet', style: TextStyle(fontSize: 13)),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

class FormattedTextEditingController extends TextEditingController {
  FormattedTextEditingController({super.text});

  @override
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}) {
    final baseStyle = style ?? const TextStyle();
    final RegExp exp = RegExp(r'(\*\*\*.*?\*\*\*|\*\*.*?\*\*|\*.*?\*|~~.*?~~)');
    final List<TextSpan> spans = [];
    int start = 0;

    for (final Match match in exp.allMatches(text)) {
      if (match.start > start) {
        spans.add(TextSpan(text: text.substring(start, match.start), style: baseStyle));
      }
      final String matchText = match.group(0)!;
      if (matchText.startsWith('***') && matchText.endsWith('***') && matchText.length >= 6) {
        final innerText = matchText.substring(3, matchText.length - 3);
        spans.add(TextSpan(text: '***', style: baseStyle.copyWith(color: Colors.transparent, fontSize: 0.1)));
        spans.add(TextSpan(
          text: innerText,
          style: baseStyle.copyWith(fontWeight: FontWeight.bold, fontStyle: FontStyle.italic),
        ));
        spans.add(TextSpan(text: '***', style: baseStyle.copyWith(color: Colors.transparent, fontSize: 0.1)));
      } else if (matchText.startsWith('**') && matchText.endsWith('**') && matchText.length >= 4) {
        final innerText = matchText.substring(2, matchText.length - 2);
        spans.add(TextSpan(text: '**', style: baseStyle.copyWith(color: Colors.transparent, fontSize: 0.1)));
        spans.add(TextSpan(
          text: innerText,
          style: baseStyle.copyWith(fontWeight: FontWeight.bold),
        ));
        spans.add(TextSpan(text: '**', style: baseStyle.copyWith(color: Colors.transparent, fontSize: 0.1)));
      } else if (matchText.startsWith('*') && matchText.endsWith('*') && matchText.length >= 2) {
        final innerText = matchText.substring(1, matchText.length - 1);
        spans.add(TextSpan(text: '*', style: baseStyle.copyWith(color: Colors.transparent, fontSize: 0.1)));
        spans.add(TextSpan(
          text: innerText,
          style: baseStyle.copyWith(fontStyle: FontStyle.italic),
        ));
        spans.add(TextSpan(text: '*', style: baseStyle.copyWith(color: Colors.transparent, fontSize: 0.1)));
      } else if (matchText.startsWith('~~') && matchText.endsWith('~~') && matchText.length >= 4) {
        final innerText = matchText.substring(2, matchText.length - 2);
        spans.add(TextSpan(text: '~~', style: baseStyle.copyWith(color: Colors.transparent, fontSize: 0.1)));
        spans.add(TextSpan(
          text: innerText,
          style: baseStyle.copyWith(decoration: TextDecoration.lineThrough),
        ));
        spans.add(TextSpan(text: '~~', style: baseStyle.copyWith(color: Colors.transparent, fontSize: 0.1)));
      }
      start = match.end;
    }

    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start), style: baseStyle));
    }

    return TextSpan(children: spans);
  }
}

