import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import 'settings_screen.dart';
import '../models/note.dart';
import '../utils/id_generator.dart';

class AppDrawer extends StatefulWidget {
  final bool isSidebar;
  final int currentIndex;
  final ValueChanged<int> onIndexChanged;

  const AppDrawer({
    super.key,
    required this.isSidebar,
    required this.currentIndex,
    required this.onIndexChanged,
  });

  @override
  State<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer> {
  bool _projectsExpanded = true;
  final Map<String, bool> _expandedCategories = {};

  Widget _buildCategoryEditor(
    BuildContext context,
    AppState appState,
    bool isEvent,
  ) {
    final title = isEvent ? 'Etkinlik Kategorileri' : 'Görev Kategorileri';
    String? selectedCategory;
    final categoryCtrl = TextEditingController();
    final subCategoryCtrl = TextEditingController();

    final List<int> colorsList = [
      0xFF2196F3, // Blue
      0xFFF44336, // Red
      0xFF4CAF50, // Green
      0xFFFF9800, // Orange
      0xFF9C27B0, // Purple
      0xFF009688, // Teal
      0xFFE91E63, // Pink
      0xFFFFC107, // Amber
      0xFF00BCD4, // Cyan
      0xFF8BC34A, // Light Green
      0xFFE040FB, // Orchid
      0xFFFF5722, // Deep Orange
      0xFF607D8B, // Blue Grey
      0xFF795548, // Brown
    ];

    return StatefulBuilder(
      builder: (context, setDialogState) {
        final categories = isEvent ? appState.eventTags : appState.taskTags;

        if (selectedCategory == null) {
          // List View of Categories
          return AlertDialog(
            title: Text('$title Düzenle'),
            content: SizedBox(
              width: 350,
              height: 450,
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: categoryCtrl,
                          decoration: const InputDecoration(
                            hintText: 'Yeni Kategori Adı',
                            isDense: true,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add, color: Colors.blue),
                        onPressed: () {
                          final name = categoryCtrl.text.trim();
                          if (name.isNotEmpty) {
                            if (isEvent) {
                              appState.addEventCategory(name);
                            } else {
                              appState.addTaskCategory(name);
                            }
                            categoryCtrl.clear();
                            setDialogState(() {});
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ReorderableListView.builder(
                      itemCount: categories.length,
                      onReorder: (oldIndex, newIndex) {
                        if (isEvent) {
                          appState.reorderEventCategories(oldIndex, newIndex);
                        } else {
                          appState.reorderTaskCategories(oldIndex, newIndex);
                        }
                        setDialogState(() {});
                      },
                      itemBuilder: (context, idx) {
                        final cat = categories[idx];
                        final catColor = isEvent
                            ? (appState.getEventTagColor(cat) ?? 0xFF2196F3)
                            : (appState.getTaskTagColor(cat) ?? 0xFF2196F3);

                        return ListTile(
                          key: ValueKey(cat),
                          leading: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.drag_handle, size: 20, color: Colors.grey),
                              const SizedBox(width: 8),
                              CircleAvatar(
                                radius: 8,
                                backgroundColor: Color(catColor),
                              ),
                            ],
                          ),
                          title: Text(cat),
                          dense: true,
                          onTap: () {
                            setDialogState(() {
                              selectedCategory = cat;
                            });
                          },
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit, size: 18, color: Colors.blue),
                                onPressed: () {
                                  final editCtrl = TextEditingController(text: cat);
                                  showDialog(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      title: Text(isEvent ? 'Etkinlik Kategorisini Yeniden Adlandır' : 'Görev Kategorisini Yeniden Adlandır'),
                                      content: TextField(
                                        controller: editCtrl,
                                        decoration: const InputDecoration(
                                          hintText: 'Yeni Kategori Adı',
                                        ),
                                        autofocus: true,
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(ctx),
                                          child: const Text('İptal'),
                                        ),
                                        TextButton(
                                          onPressed: () {
                                            final newName = editCtrl.text.trim();
                                            if (newName.isNotEmpty) {
                                              if (isEvent) {
                                                appState.renameEventCategory(cat, newName);
                                              } else {
                                                appState.renameTaskCategory(cat, newName);
                                              }
                                            }
                                            Navigator.pop(ctx);
                                            setDialogState(() {});
                                          },
                                          child: const Text('Kaydet'),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                              if (cat != 'Genel' && cat != 'Yapılacaklar') ...[
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: const Icon(Icons.delete, color: Colors.red, size: 18),
                                  onPressed: () {
                                    if (isEvent) {
                                      appState.deleteEventCategory(cat);
                                    } else {
                                      appState.deleteTaskCategory(cat);
                                    }
                                    setDialogState(() {});
                                  },
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Kapat'),
              ),
            ],
          );
        } else {
          // Details & Subcategories & Color Picker view
          final currentCat = selectedCategory!;
          final catColor = isEvent
              ? (appState.getEventTagColor(currentCat) ?? 0xFF2196F3)
              : (appState.getTaskTagColor(currentCat) ?? 0xFF2196F3);

          final subTags = isEvent
              ? (appState.eventSubTags[currentCat] ?? [])
              : (appState.taskSubTags[currentCat] ?? []);

          return AlertDialog(
            title: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () {
                    setDialogState(() {
                      selectedCategory = null;
                    });
                  },
                ),
                Expanded(
                  child: Text(
                    currentCat,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit, size: 20, color: Colors.blue),
                  onPressed: () {
                    final editCtrl = TextEditingController(text: currentCat);
                    showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: Text(isEvent ? 'Kategoriyi Yeniden Adlandır' : 'Görev Kategorisini Yeniden Adlandır'),
                        content: TextField(
                          controller: editCtrl,
                          decoration: const InputDecoration(
                            hintText: 'Yeni Kategori Adı',
                          ),
                          autofocus: true,
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('İptal'),
                          ),
                          TextButton(
                            onPressed: () {
                              final newName = editCtrl.text.trim();
                              if (newName.isNotEmpty) {
                                if (isEvent) {
                                  appState.renameEventCategory(currentCat, newName);
                                } else {
                                  appState.renameTaskCategory(currentCat, newName);
                                }
                                setDialogState(() {
                                  selectedCategory = newName;
                                });
                              }
                              Navigator.pop(ctx);
                            },
                            child: const Text('Kaydet'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
            content: SizedBox(
              width: 350,
              height: 450,
              child: ListView(
                children: [
                  const Text(
                    'Kategori Rengi',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: colorsList.map((colVal) {
                      final isSelected = colVal == catColor;
                      return GestureDetector(
                        onTap: () {
                          if (isEvent) {
                            appState.setEventTagColor(currentCat, colVal);
                          } else {
                            appState.setTaskTagColor(currentCat, colVal);
                          }
                          setDialogState(() {});
                        },
                        child: CircleAvatar(
                          radius: 14,
                          backgroundColor: Color(colVal),
                          child: isSelected
                              ? const Icon(Icons.check, size: 14, color: Colors.white)
                              : null,
                        ),
                      );
                    }).toList(),
                  ),
                  const Divider(height: 24),
                  const Text(
                    'Alt Kategoriler (Subcategories)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: subCategoryCtrl,
                          decoration: const InputDecoration(
                            hintText: 'Yeni Alt Kategori',
                            isDense: true,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add, color: Colors.blue),
                        onPressed: () {
                          final subName = subCategoryCtrl.text.trim();
                          if (subName.isNotEmpty) {
                            if (isEvent) {
                              appState.addEventSubTag(currentCat, subName);
                            } else {
                              appState.addTaskSubTag(currentCat, subName);
                            }
                            subCategoryCtrl.clear();
                            setDialogState(() {});
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ...subTags.map((sub) {
                    return ListTile(
                      title: Text(sub, style: const TextStyle(fontSize: 12)),
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit, color: Colors.blue, size: 16),
                            onPressed: () {
                              final editCtrl = TextEditingController(text: sub);
                              showDialog(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('Alt Kategoriyi Yeniden Adlandır'),
                                  content: TextField(
                                    controller: editCtrl,
                                    decoration: const InputDecoration(
                                      hintText: 'Yeni ad',
                                    ),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx),
                                      child: const Text('İptal'),
                                    ),
                                    TextButton(
                                      onPressed: () {
                                        final newName = editCtrl.text.trim();
                                        if (newName.isNotEmpty) {
                                          if (isEvent) {
                                            appState.renameEventSubTag(currentCat, sub, newName);
                                          } else {
                                            appState.renameTaskSubTag(currentCat, sub, newName);
                                          }
                                        }
                                        Navigator.pop(ctx);
                                        setDialogState(() {});
                                      },
                                      child: const Text('Kaydet'),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red, size: 16),
                            onPressed: () {
                              if (isEvent) {
                                appState.deleteEventSubTag(currentCat, sub);
                              } else {
                                appState.deleteTaskSubTag(currentCat, sub);
                              }
                              setDialogState(() {});
                            },
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  setDialogState(() {
                    selectedCategory = null;
                  });
                },
                child: const Text('Geri Dön'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Kapat'),
              ),
            ],
          );
        }
      },
    );
  }


  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final isDark = appState.isDarkMode;

    return Drawer(
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      backgroundColor: isDark ? Colors.grey.shade900 : Colors.grey.shade50,
      child: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.asset(
                      'assets/images/app_logo.png',
                      width: 40,
                      height: 40,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Plan-A v${AppState.appVersion}',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade700,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.note_alt_outlined, color: Colors.orange),
                    tooltip: 'Hızlı Not (Sticky Note)',
                    onPressed: () {
                      _showQuickStickyNote(context, appState);
                    },
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Drawer content (scrollable)
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                children: [
                  // Nav Items
                  if (widget.isSidebar) ...[
                    _buildNavItem(0, 'Takvim', Icons.calendar_today),
                    _buildNavItem(1, 'Görevler', Icons.check_circle_outline),
                    _buildNavItem(2, 'Projeler', Icons.rocket_launch),
                    _buildNavItem(3, 'Analiz', Icons.bar_chart),
                    _buildNavItem(4, 'Notlar', Icons.note_alt),
                    const Divider(),
                  ],

                  // Etkinlik Kategorileri
                  _buildHeaderRow(
                    title: 'Etkinlik Kategorileri',
                    isChecked: appState.selectedEventTags.length == appState.eventTags.length,
                    onCheckChanged: (val) {
                      if (val == true) {
                        appState.selectAllEventTags();
                      } else {
                        appState.deselectAllEventTags();
                      }
                    },
                    onEditTap: () {
                      showDialog(
                        context: context,
                        builder: (ctx) => _buildCategoryEditor(context, appState, true),
                      );
                    },
                  ),
                  ...appState.eventTags.map((tag) {
                    final isChecked = appState.selectedEventTags.contains(tag);
                    final subTags = appState.eventSubTags[tag] ?? [];
                    final isExpanded = _expandedCategories[tag] ?? false;
                    final tagColorVal = appState.getEventTagColor(tag) ?? 0xFF2196F3;
                    final baseColor = Color(tagColorVal);
                    final borderColor = isDark ? Colors.white70 : Colors.black87;
                    final bgColor = isChecked 
                        ? baseColor.withOpacity(0.25) 
                        : baseColor.withOpacity(0.08);

                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        InkWell(
                          onTap: () {
                            appState.toggleEventTag(tag);
                          },
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                            decoration: BoxDecoration(
                              color: bgColor,
                              borderRadius: BorderRadius.circular(8.0),
                              border: Border.all(color: isChecked ? baseColor : borderColor, width: 1.2),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: baseColor,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    tag,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: isChecked ? FontWeight.bold : FontWeight.normal,
                                    ),
                                  ),
                                ),
                                if (subTags.isNotEmpty)
                                  GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () {
                                      setState(() {
                                        _expandedCategories[tag] = !isExpanded;
                                      });
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0),
                                      child: Icon(
                                        isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                                        size: 18,
                                      ),
                                    ),
                                  )
                              ],
                            ),
                          ),
                        ),
                        if (isExpanded && subTags.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(left: 32.0),
                            child: Column(
                              children: subTags.map((sub) {
                                final isSubChecked = appState.selectedEventSubTags.contains('$tag:$sub');
                                final subBgColor = isSubChecked 
                                    ? baseColor.withOpacity(0.2) 
                                    : baseColor.withOpacity(0.06);

                                return InkWell(
                                  onTap: () {
                                    appState.toggleEventSubTag(tag, sub);
                                  },
                                  child: Container(
                                    margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                                    padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 6.0),
                                    decoration: BoxDecoration(
                                      color: subBgColor,
                                      borderRadius: BorderRadius.circular(6.0),
                                      border: Border.all(color: isSubChecked ? baseColor : borderColor, width: 1.0),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 6,
                                          height: 6,
                                          decoration: BoxDecoration(
                                            color: baseColor,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            sub,
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: isSubChecked ? FontWeight.bold : FontWeight.normal,
                                              color: isSubChecked ? baseColor : Colors.grey.shade700,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                      ],
                    );
                  }),
                  const Divider(),

                  // Görev Kategorileri
                  _buildHeaderRow(
                    title: 'Görev Kategorileri',
                    isChecked: appState.selectedTaskTags.length == appState.taskTags.length,
                    onCheckChanged: (val) {
                      if (val == true) {
                        appState.selectAllTaskTags();
                      } else {
                        appState.deselectAllTaskTags();
                      }
                    },
                    onEditTap: () {
                      showDialog(
                        context: context,
                        builder: (ctx) => _buildCategoryEditor(context, appState, false),
                      );
                    },
                  ),
                  CheckboxListTile(
                    value: appState.selectedTaskTags.length == appState.taskTags.length,
                    title: const Text('<Tüm>', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    controlAffinity: ListTileControlAffinity.leading,
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16.0),
                    onChanged: (val) {
                      if (val == true) {
                        appState.selectAllTaskTags();
                      } else {
                        appState.deselectAllTaskTags();
                      }
                    },
                  ),
                  ...appState.taskTags.map((tag) {
                    final isChecked = appState.selectedTaskTags.contains(tag);
                    final subTags = appState.taskSubTags[tag] ?? [];
                    final isExpanded = _expandedCategories['task_$tag'] ?? false;
                    final tagColorVal = appState.getTaskTagColor(tag) ?? 0xFF2196F3;
                    final baseColor = Color(tagColorVal);
                    final borderColor = isDark ? Colors.white70 : Colors.black87;
                    final bgColor = isChecked 
                        ? baseColor.withOpacity(0.25) 
                        : baseColor.withOpacity(0.08);

                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        InkWell(
                          onTap: () {
                            appState.toggleTaskTag(tag);
                          },
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                            decoration: BoxDecoration(
                              color: bgColor,
                              borderRadius: BorderRadius.circular(8.0),
                              border: Border.all(color: isChecked ? baseColor : borderColor, width: 1.2),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: baseColor,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    tag,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: isChecked ? FontWeight.bold : FontWeight.normal,
                                    ),
                                  ),
                                ),
                                if (subTags.isNotEmpty)
                                  GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () {
                                      setState(() {
                                        _expandedCategories['task_$tag'] = !isExpanded;
                                      });
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0),
                                      child: Icon(
                                        isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                                        size: 18,
                                      ),
                                    ),
                                  )
                              ],
                            ),
                          ),
                        ),
                        if (isExpanded && subTags.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(left: 32.0),
                            child: Column(
                              children: subTags.map((sub) {
                                final isSubChecked = appState.selectedTaskSubTags.contains('$tag:$sub');
                                final subBgColor = isSubChecked 
                                    ? baseColor.withOpacity(0.2) 
                                    : baseColor.withOpacity(0.06);

                                return InkWell(
                                  onTap: () {
                                    appState.toggleTaskSubTag(tag, sub);
                                  },
                                  child: Container(
                                    margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                                    padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 6.0),
                                    decoration: BoxDecoration(
                                      color: subBgColor,
                                      borderRadius: BorderRadius.circular(6.0),
                                      border: Border.all(color: isSubChecked ? baseColor : borderColor, width: 1.0),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 6,
                                          height: 6,
                                          decoration: BoxDecoration(
                                            color: baseColor,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            sub,
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: isSubChecked ? FontWeight.bold : FontWeight.normal,
                                              color: isSubChecked ? baseColor : Colors.grey.shade700,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                      ],
                    );
                  }),
                  const Divider(),

                  // Önem Seviyeleri
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                    child: Text(
                      'Önem Seviyeleri',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.blueGrey,
                      ),
                    ),
                  ),
                  _buildImportanceItem(appState, 2, 'Yüksek', Colors.red),
                  _buildImportanceItem(appState, 1, 'Orta', Colors.orange),
                  _buildImportanceItem(appState, 0, 'Düşük', Colors.green),
                  const Divider(),

                  // Projeler
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Projeler',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.blueGrey,
                            ),
                          ),
                        ),
                        Checkbox(
                          value: appState.selectedProjectIds.length == appState.projects.length + 1,
                          tristate: true,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          onChanged: (val) {
                            if (val == true) {
                              appState.selectAllProjects();
                            } else {
                              appState.deselectAllProjects();
                            }
                          },
                        ),
                        IconButton(
                          icon: Icon(
                            _projectsExpanded ? Icons.remove_circle : Icons.add_circle,
                            color: Colors.blue,
                            size: 20,
                          ),
                          onPressed: () {
                            setState(() {
                              _projectsExpanded = !_projectsExpanded;
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                  if (_projectsExpanded) ...[
                    // Projesiz Ögeler
                    InkWell(
                      onTap: () {
                        appState.toggleProjectSelection('no_project');
                      },
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                        decoration: BoxDecoration(
                          color: appState.selectedProjectIds.contains('no_project')
                              ? Colors.grey.withOpacity(0.25)
                              : Colors.grey.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(8.0),
                          border: Border.all(
                            color: appState.selectedProjectIds.contains('no_project')
                                ? Colors.grey
                                : (isDark ? Colors.white70 : Colors.black87),
                            width: 1.2,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.grid_on_outlined, size: 16, color: Colors.grey.shade600),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'Projesiz Ögeler',
                                style: TextStyle(fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Proje listesi
                    ...appState.projects.map((proj) {
                      final isSelected = appState.selectedProjectIds.contains(proj.id);
                      final categoryColorVal = appState.getEventTagColor(proj.tag) ?? appState.getTaskTagColor(proj.tag) ?? 0xFF9E9E9E;
                      final baseColor = Color(categoryColorVal);
                      final bgColor = isSelected 
                          ? baseColor.withOpacity(0.25) 
                          : baseColor.withOpacity(0.08);

                      return InkWell(
                        onTap: () {
                          appState.toggleProjectSelection(proj.id);
                        },
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                          decoration: BoxDecoration(
                            color: bgColor,
                            borderRadius: BorderRadius.circular(8.0),
                            border: Border.all(
                              color: isSelected ? baseColor : (isDark ? Colors.white70 : Colors.black87),
                              width: 1.2,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.rocket_launch, size: 16, color: baseColor),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  proj.title,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                  const Divider(),

                  ListTile(
                    leading: Icon(
                      Icons.settings,
                      color: Colors.grey.shade600,
                      size: 20,
                    ),
                    title: const Text(
                      'Ayarlar',
                      style: TextStyle(fontSize: 13),
                    ),
                    dense: true,
                    onTap: () {
                      if (!widget.isSidebar) {
                        Navigator.pop(context); // Mobile drawer close
                      }
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const SettingsScreen(),
                        ),
                      );
                    },
                  ),
                  const Divider(),

                  // Gizlenenleri Göster
                  SwitchListTile(
                    value: appState.showHiddenEvents,
                    title: const Row(
                      children: [
                        Icon(Icons.visibility_off_outlined, size: 18),
                        SizedBox(width: 8),
                        Text('Gizlenenleri Göster', style: TextStyle(fontSize: 13)),
                      ],
                    ),
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16.0),
                    onChanged: (val) {
                      appState.toggleShowHiddenEvents();
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, String title, IconData icon) {
    final isSelected = widget.currentIndex == index;
    return ListTile(
      leading: Icon(
        icon,
        color: isSelected ? Colors.blue : Colors.grey.shade600,
        size: 20,
      ),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected ? Colors.blue : null,
        ),
      ),
      selected: isSelected,
      dense: true,
      onTap: () {
        widget.onIndexChanged(index);
        if (!widget.isSidebar) {
          Navigator.pop(context); // Mobile drawer close
        }
      },
    );
  }

  Widget _buildHeaderRow({
    required String title,
    required bool isChecked,
    required ValueChanged<bool?> onCheckChanged,
    required VoidCallback onEditTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.blueGrey,
              ),
            ),
          ),
          Checkbox(
            value: isChecked,
            tristate: true,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onChanged: onCheckChanged,
          ),
          IconButton(
            icon: const Icon(Icons.edit, size: 16, color: Colors.blue),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: onEditTap,
          ),
        ],
      ),
    );
  }

  Widget _buildImportanceItem(
    AppState appState,
    int importance,
    String label,
    Color color,
  ) {
    final isChecked = appState.selectedImportances.contains(importance);
    final isDark = appState.isDarkMode;
    final borderColor = isDark ? Colors.white70 : Colors.black87;
    final bgColor = isChecked 
        ? color.withOpacity(0.25) 
        : color.withOpacity(0.08);

    return InkWell(
      onTap: () {
        appState.toggleImportance(importance);
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(8.0),
          border: Border.all(
            color: isChecked ? color : borderColor,
            width: 1.2,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isChecked ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showQuickStickyNote(BuildContext context, AppState appState) {
    final textCtrl = TextEditingController(text: appState.quickNote);

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 8,
          child: Container(
            width: 480,
            height: 480,
            decoration: BoxDecoration(
              color: const Color(0xFFFFFDE7), // Light yellow sticky note color
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amber.shade300, width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 8,
                  offset: const Offset(4, 4),
                )
              ]
            ),
            child: Column(
              children: [
                // Header bar of the sticky note
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade200,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(10),
                      topRight: Radius.circular(10),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.push_pin, size: 16, color: Colors.orange),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Hızlı Yapışkan Not',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.brown,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.archive, size: 16, color: Colors.brown),
                        tooltip: 'Notlarıma Kaydet',
                        onPressed: () {
                          if (textCtrl.text.trim().isNotEmpty) {
                            appState.addNote(Note(
                              id: IdGenerator.generate('quick_note'),
                              title: 'Hızlı Not',
                              content: textCtrl.text,
                              colorValue: 0xFFFFF475, // Light Yellow
                            ));
                            textCtrl.clear();
                            appState.updateQuickNote('');
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Not kaydedildi!')),
                            );
                          }
                        },
                      ),
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: const Icon(Icons.close, size: 16, color: Colors.brown),
                      ),
                    ],
                  ),
                ),
                // Text Area
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: TextField(
                      controller: textCtrl,
                      maxLines: null,
                      keyboardType: TextInputType.multiline,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 14,
                        color: Colors.black87,
                      ),
                      decoration: const InputDecoration(
                        hintText: 'Bir şeyler yazın... (Otomatik kaydedilir)',
                        border: InputBorder.none,
                      ),
                      onChanged: (val) {
                        appState.updateQuickNote(val);
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
