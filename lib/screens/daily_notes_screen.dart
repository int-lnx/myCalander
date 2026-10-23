import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import 'day_note_dialog.dart';

class DailyNotesScreen extends StatefulWidget {
  const DailyNotesScreen({super.key});

  @override
  State<DailyNotesScreen> createState() => _DailyNotesScreenState();
}

class _DailyNotesScreenState extends State<DailyNotesScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String? _selectedTag;
  int? _selectedRating;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _getTurkishDateFormat(DateTime date) {
    final months = [
      'Ocak',
      'Şubat',
      'Mart',
      'Nisan',
      'Mayıs',
      'Haziran',
      'Temmuz',
      'Ağustos',
      'Eylül',
      'Ekim',
      'Kasım',
      'Aralık'
    ];
    final days = [
      'Pazartesi',
      'Salı',
      'Çarşamba',
      'Perşembe',
      'Cuma',
      'Cumartesi',
      'Pazar'
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}, ${days[date.weekday - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final isDark = appState.isDarkMode;

    // Filter to only get notes that have actual content (text, rating, or emoji)
    final allDailyNotes = appState.dayNotes.where((note) {
      return note.note.trim().isNotEmpty ||
          note.entries.any((e) => e.text.trim().isNotEmpty || e.tags.isNotEmpty) ||
          (note.rating != null && note.rating! > 0) ||
          (note.emoji != null && note.emoji!.trim().isNotEmpty);
    }).toList();

    // Collect all unique tags across notes
    final allTags = <String>{};
    for (final note in appState.dayNotes) {
      for (final entry in note.entries) {
        for (final tag in entry.tags) {
          if (tag.trim().isNotEmpty) {
            allTags.add(tag.trim());
          }
        }
      }
    }
    final sortedTags = allTags.toList()..sort();

    // Apply active filters
    final filteredNotes = allDailyNotes.where((note) {
      // 1. Search filter
      if (_searchQuery.trim().isNotEmpty) {
        final q = _searchQuery.trim().toLowerCase();
        final dateStr = _getTurkishDateFormat(note.date).toLowerCase();
        final noteMatch = note.note.toLowerCase().contains(q);
        final entryMatch = note.entries.any((e) =>
            e.text.toLowerCase().contains(q) ||
            e.tags.any((t) => t.toLowerCase().contains(q)));
        final emojiMatch = note.emoji != null && note.emoji!.contains(q);
        if (!noteMatch && !entryMatch && !emojiMatch && !dateStr.contains(q)) {
          return false;
        }
      }

      // 2. Tag filter
      if (_selectedTag != null) {
        final hasTag = note.entries.any((e) => e.tags.contains(_selectedTag));
        if (!hasTag) return false;
      }

      // 3. Rating filter
      if (_selectedRating != null) {
        if (note.rating != _selectedRating) return false;
      }

      return true;
    }).toList();

    // Sort newest first
    filteredNotes.sort((a, b) => b.date.compareTo(a.date));

    final hasActiveFilter =
        _searchQuery.isNotEmpty || _selectedTag != null || _selectedRating != null;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : Colors.grey.shade50,
      body: Column(
        children: [
          // ─── Filtre Başlık Alanı ──────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              border: Border(
                bottom: BorderSide(
                  color: isDark ? Colors.white12 : Colors.grey.shade200,
                  width: 1,
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Arama Kutusu
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 38,
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF282828)
                              : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isDark
                                ? Colors.white12
                                : Colors.grey.shade300,
                          ),
                        ),
                        child: TextField(
                          controller: _searchController,
                          style: const TextStyle(fontSize: 13),
                          decoration: InputDecoration(
                            hintText: 'Notlarda, etiketlerde veya tarihte ara...',
                            hintStyle: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white38 : Colors.grey.shade500,
                            ),
                            prefixIcon: const Icon(
                              Icons.search,
                              size: 18,
                              color: Colors.amber,
                            ),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, size: 16),
                                    onPressed: () {
                                      setState(() {
                                        _searchController.clear();
                                        _searchQuery = '';
                                      });
                                    },
                                  )
                                : null,
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                          ),
                          onChanged: (val) {
                            setState(() {
                              _searchQuery = val;
                            });
                          },
                        ),
                      ),
                    ),
                    if (hasActiveFilter) ...[
                      const SizedBox(width: 8),
                      Tooltip(
                        message: 'Filtreleri Temizle',
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () {
                            setState(() {
                              _searchController.clear();
                              _searchQuery = '';
                              _selectedTag = null;
                              _selectedRating = null;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.red.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.filter_alt_off,
                              size: 18,
                              color: Colors.red,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 10),

                // Filtre Çipleri (Puan & Etiketler)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      // Puan Başlığı
                      Icon(Icons.star, size: 14, color: Colors.amber.shade700),
                      const SizedBox(width: 4),
                      Text(
                        'Puan:',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white70 : Colors.grey.shade700,
                        ),
                      ),
                      const SizedBox(width: 6),

                      // Yıldız Seçenekleri (5..1)
                      ...List.generate(5, (idx) {
                        final starVal = 5 - idx;
                        final isSelected = _selectedRating == starVal;
                        return Padding(
                          padding: const EdgeInsets.only(right: 6.0),
                          child: FilterChip(
                            label: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '$starVal',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: isSelected
                                        ? Colors.amber.shade900
                                        : (isDark ? Colors.white70 : Colors.black87),
                                  ),
                                ),
                                const SizedBox(width: 2),
                                const Icon(Icons.star, size: 12, color: Colors.amber),
                              ],
                            ),
                            selected: isSelected,
                            selectedColor: Colors.amber.shade200,
                            checkmarkColor: Colors.amber.shade900,
                            showCheckmark: false,
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            onSelected: (selected) {
                              setState(() {
                                _selectedRating = selected ? starVal : null;
                              });
                            },
                          ),
                        );
                      }),

                      // Etiket Seçenekleri
                      if (sortedTags.isNotEmpty) ...[
                        Container(
                          height: 18,
                          width: 1,
                          color: isDark ? Colors.white24 : Colors.grey.shade300,
                          margin: const EdgeInsets.symmetric(horizontal: 6),
                        ),
                        Icon(Icons.label_outline, size: 14, color: Colors.amber.shade700),
                        const SizedBox(width: 4),
                        Text(
                          'Etiket:',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white70 : Colors.grey.shade700,
                          ),
                        ),
                        const SizedBox(width: 6),
                        ...sortedTags.map((tag) {
                          final isSelected = _selectedTag == tag;
                          return Padding(
                            padding: const EdgeInsets.only(right: 6.0),
                            child: FilterChip(
                              label: Text(
                                '#$tag',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                  color: isSelected
                                      ? Colors.amber.shade900
                                      : (isDark ? Colors.white70 : Colors.black87),
                                ),
                              ),
                              selected: isSelected,
                              selectedColor: Colors.amber.shade200,
                              showCheckmark: false,
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              onSelected: (selected) {
                                setState(() {
                                  _selectedTag = selected ? tag : null;
                                });
                              },
                            ),
                          );
                        }),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ─── Not Listesi ──────────────────────────────────────────────────
          Expanded(
            child: allDailyNotes.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.note_alt_outlined,
                          size: 64,
                          color: isDark ? Colors.white30 : Colors.grey.shade300,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Henüz günlük not eklenmemiş.',
                          style: TextStyle(
                            fontSize: 16,
                            color: isDark ? Colors.white54 : Colors.grey.shade600,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Takvimden bir güne tıklayarak not ekleyebilirsiniz.',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white30 : Colors.grey.shade400,
                          ),
                        ),
                      ],
                    ),
                  )
                : filteredNotes.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.search_off_rounded,
                              size: 56,
                              color: isDark ? Colors.white30 : Colors.grey.shade300,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Seçilen filtrelere uygun not bulunamadı.',
                              style: TextStyle(
                                fontSize: 15,
                                color: isDark ? Colors.white54 : Colors.grey.shade600,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextButton.icon(
                              onPressed: () {
                                setState(() {
                                  _searchController.clear();
                                  _searchQuery = '';
                                  _selectedTag = null;
                                  _selectedRating = null;
                                });
                              },
                              icon: const Icon(Icons.refresh, size: 16),
                              label: const Text('Filtreleri Temizle'),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        itemCount: filteredNotes.length,
                        itemBuilder: (context, index) {
                          final note = filteredNotes[index];
                          final hasEmoji =
                              note.emoji != null && note.emoji!.trim().isNotEmpty;
                          final hasRating =
                              note.rating != null && note.rating! > 0;

                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            elevation: 1,
                            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color: isDark ? Colors.white10 : Colors.grey.shade200,
                                width: 1,
                              ),
                            ),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () {
                                DayNoteDialog.show(context, appState, note.date);
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        // Date display
                                        Expanded(
                                          child: Text(
                                            _getTurkishDateFormat(note.date),
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                              color: isDark
                                                  ? Colors.white70
                                                  : Colors.black87,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (hasEmoji || hasRating) ...[
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          if (hasEmoji) ...[
                                            Text(
                                              note.emoji!,
                                              style: const TextStyle(fontSize: 18),
                                            ),
                                            const SizedBox(width: 8),
                                          ],
                                          if (hasRating) ...[
                                            Row(
                                              children: List.generate(5, (starIdx) {
                                                return Icon(
                                                  starIdx < note.rating!
                                                      ? Icons.star
                                                      : Icons.star_border,
                                                  color: Colors.amber,
                                                  size: 16,
                                                );
                                              }),
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              '(${note.rating}/5)',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: isDark
                                                    ? Colors.white54
                                                    : Colors.grey.shade600,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ],
                                    // Note content
                                    if (note.entries.isNotEmpty) ...[
                                      const Divider(height: 16),
                                      ...note.entries.asMap().entries.map((mapEntry) {
                                        final idx = mapEntry.key;
                                        final entry = mapEntry.value;
                                        return Padding(
                                          padding: EdgeInsets.only(
                                            bottom: idx < note.entries.length - 1
                                                ? 10.0
                                                : 0.0,
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              if (note.entries.length > 1)
                                                Padding(
                                                  padding: const EdgeInsets.only(
                                                      bottom: 2),
                                                  child: Text(
                                                    'Not ${idx + 1}',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.bold,
                                                      color: isDark
                                                          ? Colors.amber.shade300
                                                          : Colors.amber.shade800,
                                                    ),
                                                  ),
                                                ),
                                              if (entry.text.trim().isNotEmpty)
                                                Text(
                                                  entry.text,
                                                  style: TextStyle(
                                                    fontSize: 14,
                                                    height: 1.5,
                                                    color: isDark
                                                        ? Colors.white70
                                                        : Colors.black87,
                                                  ),
                                                  maxLines: 4,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              if (entry.tags.isNotEmpty) ...[
                                                const SizedBox(height: 4),
                                                Wrap(
                                                  spacing: 6,
                                                  runSpacing: 4,
                                                  children: entry.tags.map((tag) => Container(
                                                    padding: const EdgeInsets.symmetric(
                                                      horizontal: 7,
                                                      vertical: 2,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: isDark
                                                          ? Colors.amber.shade900.withValues(alpha: 0.3)
                                                          : Colors.amber.shade100,
                                                      borderRadius: BorderRadius.circular(10),
                                                      border: Border.all(
                                                        color: isDark
                                                            ? Colors.amber.shade700
                                                            : Colors.amber.shade300,
                                                        width: 0.5,
                                                      ),
                                                    ),
                                                    child: Text(
                                                      '#$tag',
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        fontWeight: FontWeight.w600,
                                                        color: isDark
                                                            ? Colors.amber.shade200
                                                            : Colors.amber.shade900,
                                                      ),
                                                    ),
                                                  )).toList(),
                                                ),
                                              ],
                                            ],
                                          ),
                                        );
                                      }),
                                    ] else if (note.note.trim().isNotEmpty) ...[
                                      const Divider(height: 16),
                                      Text(
                                        note.note,
                                        style: TextStyle(
                                          fontSize: 14,
                                          height: 1.5,
                                          color: isDark
                                              ? Colors.white70
                                              : Colors.black87,
                                        ),
                                        maxLines: 5,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
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
  }
}

