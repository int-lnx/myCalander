import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/project.dart';
import '../models/task_item.dart';
import 'task_form_screen.dart';

class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  String _selectedTab = 'Tüm Tarihliler';
  String _sortMode = 'CUSTOM'; // 'CUSTOM' (Benim sıralamam), 'DATE', 'IMPORTANCE', 'CREATED_DATE'
  final Set<String> _animatingTaskIds = {};

  String _getRelativeDateString(DateTime? date) {
    if (date == null) return '';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final taskDay = DateTime(date.year, date.month, date.day);
    final diff = today.difference(taskDay).inDays;
    if (diff == 0) {
      return 'Bugün';
    } else if (diff == 1) {
      return 'Dün';
    } else if (diff == -1) {
      return 'Yarın';
    } else if (diff > 1) {
      return '$diff gün önce';
    } else {
      return '${diff.abs()} gün sonra';
    }
  }

  String _getRecurrenceText(String rule) {
    if (rule.contains('FREQ=DAILY')) return 'Günlük';
    if (rule.contains('FREQ=WEEKLY')) {
      final daysMap = {
        'MO': 'Pzt', 'TU': 'Sal', 'WE': 'Çar',
        'TH': 'Per', 'FR': 'Cum', 'SA': 'Cmt', 'SU': 'Paz',
      };
      String days = '';
      daysMap.forEach((key, val) {
        if (rule.contains(key)) {
          if (days.isNotEmpty) days += ', ';
          days += val;
        }
      });
      return 'Haftalık${days.isNotEmpty ? ' ($days)' : ''}';
    }
    if (rule.contains('FREQ=MONTHLY')) return 'Aylık';
    if (rule.contains('FREQ=YEARLY')) return 'Yıllık';
    return 'Tekrarlayan';
  }

  Widget _buildTaskCard(
    BuildContext context,
    dynamic task,
    bool isDark,
    AppState appState,
  ) {
    final isCompleted = _animatingTaskIds.contains(task.id)
        ? !task.isCompleted
        : task.isCompleted;
    final dateLabel = task.from != null
        ? '${task.from!.day}/${task.from!.month}/${task.from!.year}'
        : 'Tarihsiz';
    final relativeStr = _getRelativeDateString(task.from);
    final isOverdue = task.from != null &&
        task.from!.isBefore(DateTime.now()) &&
        !isCompleted &&
        relativeStr.contains('önce');

    final project = appState.projects.firstWhere(
      (p) => p.id == task.projectId,
      orElse: () => const Project(
        id: '', title: '', colorValue: 0xFF2196F3,
        evaluationType: 'PERCENTAGE', targetValue: 100.0,
      ),
    );
    final circleColor = task.projectId != null
        ? Color(project.colorValue)
        : (task.importance == 2
            ? Colors.red
            : (task.importance == 1 ? Colors.orange : Colors.blue));

    final isSelectedResult = appState.searchQuery.isNotEmpty &&
        appState.searchResults.isNotEmpty &&
        appState.searchResultIndex < appState.searchResults.length &&
        appState.searchResults[appState.searchResultIndex] is TaskItem &&
        appState.searchResults[appState.searchResultIndex].id == task.id;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey.shade900 : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: task.isInProgress
            ? Border.all(color: Colors.amber.shade700, width: 2.0)
            : (isSelectedResult
                ? Border.all(color: Colors.blue.shade500, width: 2.5)
                : Border.all(color: isDark ? Colors.grey.shade800 : Colors.grey.shade200, width: 1.0)),
        boxShadow: [
          BoxShadow(
            color: task.isInProgress
                ? Colors.amber.withOpacity(0.15)
                : (isSelectedResult
                    ? Colors.blue.withOpacity(0.2)
                    : Colors.black.withOpacity(0.03)),
            blurRadius: (task.isInProgress || isSelectedResult) ? 8 : 4,
            spreadRadius: (task.isInProgress || isSelectedResult) ? 2 : 0,
            offset: (task.isInProgress || isSelectedResult) ? const Offset(0, 0) : const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        leading: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            GestureDetector(
              onTap: () async {
                if (_animatingTaskIds.contains(task.id)) return;
                setState(() {
                  _animatingTaskIds.add(task.id);
                });
                await Future.delayed(const Duration(milliseconds: 400));
                final hasRecurrence = task.recurrenceRule != null &&
                    task.recurrenceRule!.isNotEmpty;
                if (hasRecurrence && !task.isCompleted && task.from != null) {
                  final toggleId =
                      'occ_${task.id}_${task.from!.millisecondsSinceEpoch}';
                  appState.toggleTaskCompletion(toggleId);
                  setState(() {
                    _animatingTaskIds.remove(task.id);
                  });
                } else {
                  appState.toggleTaskCompletion(task.id);
                  setState(() {
                    _animatingTaskIds.remove(task.id);
                  });
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: circleColor, width: 2),
                  color: isCompleted ? circleColor : Colors.transparent,
                ),
                child: AnimatedScale(
                  scale: isCompleted ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutBack,
                  child: const Icon(Icons.check, size: 14, color: Colors.white),
                ),
              ),
            ),
            const SizedBox(height: 6),
            InkWell(
              onTap: () {
                final hasRecurrence = task.recurrenceRule != null &&
                    task.recurrenceRule!.isNotEmpty;
                if (hasRecurrence && !task.isInProgress && task.from != null) {
                  final toggleId =
                      'occ_${task.id}_${task.from!.millisecondsSinceEpoch}';
                  appState.toggleTaskInProgress(toggleId);
                } else {
                  appState.toggleTaskInProgress(task.id);
                }
              },
              child: Icon(
                task.isInProgress ? Icons.hourglass_full : Icons.hourglass_empty,
                size: 16,
                color: task.isInProgress ? Colors.amber.shade700 : Colors.blueGrey,
              ),
            ),
          ],
        ),
        title: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 250),
          style: TextStyle(
            decoration: isCompleted ? TextDecoration.lineThrough : TextDecoration.none,
            color: isCompleted ? Colors.grey : (isDark ? Colors.white : Colors.black87),
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
          child: Text(task.title),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (task.description.isNotEmpty)
              Text(task.description, style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      Text(
                        dateLabel,
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                      ),
                      if (relativeStr.isNotEmpty) ...[
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isOverdue
                                  ? Icons.warning_amber_rounded
                                  : Icons.calendar_today_outlined,
                              size: 11,
                              color: isOverdue
                                  ? Colors.red.shade700
                                  : Colors.blue.shade700,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              relativeStr,
                              style: TextStyle(
                                fontSize: 11,
                                color: isOverdue
                                    ? Colors.red.shade700
                                    : Colors.blue.shade700,
                                fontWeight:
                                    isOverdue ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (task.recurrenceRule != null &&
                          task.recurrenceRule!.isNotEmpty) ...[
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.autorenew, size: 11, color: Colors.green.shade700),
                            const SizedBox(width: 2),
                            Text(
                              _getRecurrenceText(task.recurrenceRule!),
                              style:
                                  TextStyle(fontSize: 11, color: Colors.green.shade700),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InkWell(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => TaskFormScreen(existingTask: task),
                          ),
                        );
                      },
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0),
                        child: Icon(Icons.edit_note, size: 18, color: Colors.blueGrey),
                      ),
                    ),
                    const SizedBox(width: 4),
                    InkWell(
                      onTap: () {
                        final hasRecurrence = task.recurrenceRule != null &&
                            task.recurrenceRule!.isNotEmpty;
                        if (hasRecurrence) {
                          _showRecurringTaskDeleteDialog(context, appState, task);
                        } else {
                          showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Görevi Sil'),
                              content: const Text(
                                  'Bu görevi silmek istediğinize emin misiniz?'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('Vazgeç'),
                                ),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.red),
                                  onPressed: () {
                                    final deleted = task;
                                    appState.deleteTask(task.id);
                                    Navigator.pop(context);
                                    _showUndoSnackBar(context, '"${deleted.title}" silindi', () {
                                      appState.addTask(deleted);
                                    });
                                  },
                                  child: const Text('Sil',
                                      style: TextStyle(color: Colors.white)),
                                ),
                              ],
                            ),
                          );
                        }
                      },
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0),
                        child: Icon(Icons.delete_outline, size: 16, color: Colors.red),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Gruplandırılmış görev listesi: her subTag kendi başlığı altında
  Widget _buildGroupedTaskList(
    BuildContext context,
    List tasks,
    bool isDark,
    AppState appState,
    String selectedTag,
  ) {
    // subTag'a göre grupla: null/empty subTag → "" bucket
    final Map<String, List> groups = {};

    for (final task in tasks) {
      final sub = (task.subTag != null && task.subTag!.trim().isNotEmpty)
          ? task.subTag!.trim()
          : '';
      groups.putIfAbsent(sub, () => []).add(task);
    }

    // Her grupta tamamlananları en alta taşı
    groups.forEach((key, list) {
      list.sort((a, b) {
        if (a.isCompleted == b.isCompleted) return 0;
        return a.isCompleted ? 1 : -1;
      });
    });

    // Sıralama: subTag'ı olmayanlar (boş) en üste, geri kalanlar alfabetik
    final sortedKeys = groups.keys.toList()
      ..sort((a, b) {
        if (a.isEmpty && b.isEmpty) return 0;
        if (a.isEmpty) return -1;
        if (b.isEmpty) return 1;
        return a.compareTo(b);
      });

    // Sadece tek bir grup ve adı "" ise (hiç subTag yok) → düz liste göster
    final hasSubGroups = sortedKeys.length > 1 ||
        (sortedKeys.length == 1 && sortedKeys.first.isNotEmpty);

    // Mevcut tab'ın tag değeri
    final currentTag = (selectedTag == 'Tüm Tarihliler' || selectedTag == 'Tüm Tarihsizler') ? null : selectedTag;

    if (!hasSubGroups) {
      if (_sortMode == 'CUSTOM') {
        return ReorderableListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: tasks.length,
          itemBuilder: (ctx, i) {
            final task = tasks[i];
            return Container(
              key: ValueKey(task.id),
              child: _buildTaskCard(ctx, task, isDark, appState),
            );
          },
          onReorder: (oldIndex, newIndex) {
            setState(() {
              if (newIndex > oldIndex) {
                newIndex -= 1;
              }
              final item = tasks.removeAt(oldIndex);
              tasks.insert(newIndex, item);
              final newOrderIds = tasks.map((t) => t.id as String).toList();
              final currentOrder = List<String>.from(appState.customTaskOrder);
              currentOrder.removeWhere((id) => newOrderIds.contains(id));
              currentOrder.addAll(newOrderIds);
              appState.updateTaskOrder(currentOrder);
            });
          },
        );
      }
      return ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: tasks.length,
        itemBuilder: (ctx, i) =>
            _buildTaskCard(ctx, tasks[i], isDark, appState),
      );
    }

    // Gruplandırılmış liste
    final List<Widget> items = [];
    for (final key in sortedKeys) {
      final groupTasks = groups[key]!;
      if (key.isNotEmpty) {
        // subTag başlık satırı — tıklanınca görev oluşturma formu açılır
        items.add(
          GestureDetector(
            onTap: () {
              final resolvedTag = currentTag ?? (groupTasks.isNotEmpty ? groupTasks.first.tag : null);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => TaskFormScreen(
                    initialTag: resolvedTag,
                    initialSubTag: key,
                  ),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 16,
                    decoration: BoxDecoration(
                      color: Colors.blue.shade400,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    key,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: isDark
                          ? Colors.blue.shade200
                          : Colors.blue.shade700,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${groupTasks.length}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.blue.shade700,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue.shade200, width: 0.8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.add,
                          size: 12,
                          color: Colors.blue.shade700,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Görev Ekle',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade700,
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
      }
      if (_sortMode == 'CUSTOM') {
        items.add(
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: groupTasks.length,
            itemBuilder: (ctx, i) {
              final task = groupTasks[i];
              return Container(
                key: ValueKey(task.id),
                child: _buildTaskCard(ctx, task, isDark, appState),
              );
            },
            onReorder: (oldIndex, newIndex) {
              setState(() {
                if (newIndex > oldIndex) {
                  newIndex -= 1;
                }
                final item = groupTasks.removeAt(oldIndex);
                groupTasks.insert(newIndex, item);
                
                final List<String> newOrderIds = [];
                for (final k in sortedKeys) {
                  final gTasks = (k == key) ? groupTasks : (groups[k] ?? []);
                  newOrderIds.addAll(gTasks.map((t) => t.id as String));
                }
                
                final currentOrder = List<String>.from(appState.customTaskOrder);
                currentOrder.removeWhere((id) => newOrderIds.contains(id));
                currentOrder.addAll(newOrderIds);
                appState.updateTaskOrder(currentOrder);
              });
            },
          ),
        );
      } else {
        for (final task in groupTasks) {
          items.add(_buildTaskCard(context, task, isDark, appState));
        }
      }
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: items,
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final tasks = appState.filteredTasks;
    final isDark = appState.isDarkMode;

    // Filter tasks based on selected horizontal tab
    final displayedTasks = tasks.where((t) {
      if (_selectedTab == 'Tüm Tarihliler') return t.from != null;
      if (_selectedTab == 'Tüm Tarihsizler') return t.from == null;
      return t.tag == _selectedTab;
    }).toList();

    // Sort tasks based on selected sortMode
    if (_sortMode == 'DATE') {
      displayedTasks.sort((a, b) {
        if (a.isCompleted != b.isCompleted) return a.isCompleted ? 1 : -1;
        if (a.from == null && b.from == null) return 0;
        if (a.from == null) return 1;
        if (b.from == null) return -1;
        return a.from!.compareTo(b.from!);
      });
    } else if (_sortMode == 'IMPORTANCE') {
      displayedTasks.sort((a, b) {
        if (a.isCompleted != b.isCompleted) return a.isCompleted ? 1 : -1;
        return b.importance.compareTo(a.importance);
      });
    } else if (_sortMode == 'CREATED_DATE') {
      displayedTasks.sort((a, b) {
        if (a.isCompleted != b.isCompleted) return a.isCompleted ? 1 : -1;
        return b.createdAt.compareTo(a.createdAt);
      });
    } else {
      // CUSTOM order: Benim sıralamam
      final orderMap = {
        for (var i = 0; i < appState.customTaskOrder.length; i++)
          appState.customTaskOrder[i]: i
      };
      displayedTasks.sort((a, b) {
        if (a.isCompleted != b.isCompleted) return a.isCompleted ? 1 : -1;
        final indexA = orderMap[a.id] ?? 999999;
        final indexB = orderMap[b.id] ?? 999999;
        return indexA.compareTo(indexB);
      });
    }

    // Group tags
    final tabs = ['Tüm Tarihliler', 'Tüm Tarihsizler', ...appState.taskTags];

    final now = DateTime.now();

    return Scaffold(
      appBar: null,
      body: Column(
        children: [
          // Actions row (refresh, sort, add)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: isDark ? Colors.grey.shade900 : Colors.grey.shade100,
            child: Row(
              children: [
                // Date chip
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Text(
                    '${now.day}/${now.month}/${now.year}',
                    style: TextStyle(
                      color: Colors.blue.shade700,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Spacer(),
                // Refresh
                IconButton(
                  icon: const Icon(Icons.refresh, size: 20),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () async {
                    if (appState.firebaseUser != null) {
                      await appState.syncDataWithFirebase();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Veriler senkronize edildi.')),
                        );
                      }
                    }
                  },
                ),
                const SizedBox(width: 8),
                // Add task
                IconButton(
                  icon: const Icon(Icons.add, size: 20),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const TaskFormScreen()),
                    );
                  },
                ),
                const SizedBox(width: 8),
                // Sort & more
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, size: 20),
                  padding: EdgeInsets.zero,
                  onSelected: (val) {
                    if (val == 'SORT_CUSTOM') {
                      setState(() => _sortMode = 'CUSTOM');
                    } else if (val == 'SORT_DATE') {
                      setState(() => _sortMode = 'DATE');
                    } else if (val == 'SORT_IMPORTANCE') {
                      setState(() => _sortMode = 'IMPORTANCE');
                    } else if (val == 'SORT_CREATED_DATE') {
                      setState(() => _sortMode = 'CREATED_DATE');
                    } else if (val == 'RENAME_LIST') {
                      _showRenameListDialog(context, appState, _selectedTab);
                    } else if (val == 'DELETE_LIST') {
                      _showDeleteListDialog(context, appState, _selectedTab);
                    } else if (val == 'DELETE_COMPLETED') {
                      _deleteCompletedTasks(context, appState, displayedTasks);
                    }
                  },
                  itemBuilder: (context) {
                    final isAllTab = _selectedTab == 'Tüm Tarihliler' || _selectedTab == 'Tüm Tarihsizler';
                    return [
                      PopupMenuItem(
                        enabled: false,
                        child: Text(
                          'Sıralama ölçütü',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).primaryColor,
                          ),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'SORT_CUSTOM',
                        child: Row(children: [
                          Icon(Icons.check, color: _sortMode == 'CUSTOM' ? Colors.blue : Colors.transparent, size: 18),
                          const SizedBox(width: 8),
                          const Text('Benim sıralamam'),
                        ]),
                      ),
                      PopupMenuItem(
                        value: 'SORT_DATE',
                        child: Row(children: [
                          Icon(Icons.check, color: _sortMode == 'DATE' ? Colors.blue : Colors.transparent, size: 18),
                          const SizedBox(width: 8),
                          const Text('Tarih'),
                        ]),
                      ),
                      PopupMenuItem(
                        value: 'SORT_IMPORTANCE',
                        child: Row(children: [
                          Icon(Icons.check, color: _sortMode == 'IMPORTANCE' ? Colors.blue : Colors.transparent, size: 18),
                          const SizedBox(width: 8),
                          const Text('Önem seviyesi'),
                        ]),
                      ),
                      PopupMenuItem(
                        value: 'SORT_CREATED_DATE',
                        child: Row(children: [
                          Icon(Icons.check, color: _sortMode == 'CREATED_DATE' ? Colors.blue : Colors.transparent, size: 18),
                          const SizedBox(width: 8),
                          const Text('Eklenme tarihi'),
                        ]),
                      ),
                      const PopupMenuDivider(),
                      if (!isAllTab) ...[
                        const PopupMenuItem(value: 'RENAME_LIST', child: Text('Listeyi yeniden adlandır')),
                        const PopupMenuItem(value: 'DELETE_LIST', child: Text('Listeyi sil')),
                        const PopupMenuDivider(),
                      ],
                      const PopupMenuItem(value: 'DELETE_COMPLETED', child: Text('Tamamlanan tüm görevleri sil')),
                    ];
                  },
                ),
              ],
            ),
          ),
          // Horizontal scrolling tab bar
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(vertical: 6.0),
            color: isDark ? Colors.grey.shade900 : Colors.grey.shade100,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: tabs.length,
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              itemBuilder: (context, index) {
                final tab = tabs[index];
                final isSelected = tab == _selectedTab;
                final count = tasks.where((t) {
                  if (t.isCompleted) return false;
                  if (tab == 'Tüm Tarihliler') return t.from != null;
                  if (tab == 'Tüm Tarihsizler') return t.from == null;
                  return t.tag == tab;
                }).length;
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedTab = tab;
                    });
                  },
                  onLongPress: (tab == 'Tüm Tarihliler' || tab == 'Tüm Tarihsizler')
                      ? null
                      : () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => TaskFormScreen(
                                initialTag: tab,
                              ),
                            ),
                          );
                        },
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4.0),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16.0, vertical: 6.0),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Colors.blue
                          : (isDark
                              ? Colors.grey.shade800
                              : Colors.white),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color:
                            isSelected ? Colors.blue : Colors.grey.shade300,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        '$tab ($count)',
                        style: TextStyle(
                          color: isSelected
                              ? Colors.white
                              : (isDark ? Colors.white70 : Colors.black87),
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // Grouped task list
          Expanded(
            child: displayedTasks.isEmpty
                ? Center(
                    child: Text(
                      'Seçili kategoride görev bulunmamaktadır.',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  )
                : _buildGroupedTaskList(
                    context,
                    displayedTasks,
                    isDark,
                    appState,
                    _selectedTab,
                  ),
          ),
        ],
      ),
    );
  }

  void _showRenameListDialog(BuildContext context, AppState appState, String oldName) {
    final textCtrl = TextEditingController(text: oldName);
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Listeyi Yeniden Adlandır'),
          content: TextField(
            controller: textCtrl,
            decoration: const InputDecoration(labelText: 'Yeni Liste Adı'),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('İptal'),
            ),
            ElevatedButton(
              onPressed: () {
                final newName = textCtrl.text.trim();
                if (newName.isNotEmpty && newName != oldName) {
                  appState.renameTaskCategory(oldName, newName);
                  setState(() {
                    _selectedTab = newName;
                  });
                }
                Navigator.pop(context);
              },
              child: const Text('Kaydet'),
            ),
          ],
        );
      },
    );
  }

  void _showDeleteListDialog(BuildContext context, AppState appState, String categoryName) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Listeyi Sil'),
          content: Text('"$categoryName" listesini ve bu listedeki tüm görevleri silmek istediğinize emin misiniz?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('İptal'),
            ),
            ElevatedButton(
              onPressed: () {
                appState.deleteTaskCategory(categoryName);
                setState(() {
                  _selectedTab = 'Tüm Tarihliler';
                });
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Sil', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  void _deleteCompletedTasks(BuildContext context, AppState appState, List displayedTasks) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Tamamlanan Görevleri Sil'),
          content: const Text('Bu listedeki tamamlanmış tüm görevleri kalıcı olarak silmek istiyor musunuz?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('İptal'),
            ),
            ElevatedButton(
              onPressed: () {
                final deletedTasks = displayedTasks.where((t) => t.isCompleted).toList();
                for (var t in deletedTasks) {
                  appState.deleteTask(t.id);
                }
                Navigator.pop(context);
                if (deletedTasks.isNotEmpty) {
                  _showUndoSnackBar(context, 'Tamamlanan tüm görevler silindi', () {
                    for (var t in deletedTasks) {
                      appState.addTask(t);
                    }
                  });
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Sil', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  void _showRecurringTaskDeleteDialog(
      BuildContext context, AppState appState, TaskItem task) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Tekrarlayan Görevi Sil'),
          content: const Text(
              'Bu tekrarlayan bir görev. Nasıl silmek istersiniz?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Vazgeç'),
            ),
            TextButton(
              onPressed: () {
                final originalParent = task;
                final deleteId = 'occ_${task.id}_${task.from != null ? task.from!.millisecondsSinceEpoch : DateTime.now().millisecondsSinceEpoch}';
                appState.deleteTask(deleteId);
                Navigator.pop(context);
                _showUndoSnackBar(context, '"${task.title}" bugünkü tekrarı silindi', () {
                  appState.updateTask(originalParent);
                });
              },
              child: const Text('Sadece Bugün'),
            ),
            TextButton(
              onPressed: () {
                final originalParent = task;
                final dateRef = task.from ?? DateTime.now();
                DateTime untilDate = dateRef.subtract(const Duration(days: 1));
                String untilStr =
                    "${untilDate.year}${untilDate.month.toString().padLeft(2, '0')}${untilDate.day.toString().padLeft(2, '0')}T235959Z";
                
                List<String> parts = task.recurrenceRule!.split(';');
                parts.removeWhere((p) => p.startsWith('UNTIL='));
                parts.add('UNTIL=$untilStr');
                String limitedRule = parts.join(';');
                
                final updatedOriginal = task.copyWith(
                  recurrenceRule: limitedRule,
                );
                appState.updateTask(updatedOriginal);
                Navigator.pop(context);
                _showUndoSnackBar(context, '"${task.title}" sonraki tekrarlar silindi', () {
                  appState.updateTask(originalParent);
                });
              },
              child: const Text('Bugün ve Sonrası'),
            ),
            TextButton(
              onPressed: () {
                final deletedClones = appState.tasks
                    .where((t) => t.seriesId == task.seriesId && t.isCompleted)
                    .toList();
                appState.deleteCompletedTasksInSeries(task.seriesId);
                Navigator.pop(context);
                _showUndoSnackBar(context, '"${task.title}" serideki tamamlanmış görevler silindi', () {
                  for (var tc in deletedClones) {
                    appState.addTask(tc);
                  }
                });
              },
              child: const Text('Tamamlananları Sil'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () {
                final deletedTasks = appState.tasks
                    .where((t) => t.seriesId == task.seriesId)
                    .toList();
                appState.deleteTaskSeries(task.seriesId);
                Navigator.pop(context);
                _showUndoSnackBar(context, '"${task.title}" tüm serisi silindi', () {
                  for (var t in deletedTasks) {
                    appState.addTask(t);
                  }
                });
              },
              child: const Text('Tüm Seri', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  void _showUndoSnackBar(BuildContext context, String message, VoidCallback onUndo) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 10),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        showCloseIcon: true,
        closeIconColor: Colors.white70,
        action: SnackBarAction(
          label: 'Geri Al',
          textColor: Colors.amber,
          onPressed: onUndo,
        ),
      ),
    );
  }
}
