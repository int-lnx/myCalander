import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';

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
    final categories = isEvent ? appState.eventTags : appState.taskTags;
    final ctrl = TextEditingController();

    return AlertDialog(
      title: Text('$title Düzenle'),
      content: SizedBox(
        width: 300,
        height: 400,
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: ctrl,
                    decoration: const InputDecoration(
                      hintText: 'Yeni Kategori Adı',
                      isDense: true,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add, color: Colors.blue),
                  onPressed: () {
                    final name = ctrl.text.trim();
                    if (name.isNotEmpty) {
                      if (isEvent) {
                        appState.addEventCategory(name);
                      } else {
                        appState.addTaskCategory(name);
                      }
                      ctrl.clear();
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                itemCount: categories.length,
                itemBuilder: (context, idx) {
                  final cat = categories[idx];
                  if (cat == 'Genel' || cat == 'Yapılacaklar') {
                    // Varsayılan kategoriler silinemez
                    return ListTile(
                      title: Text(cat, style: const TextStyle(fontWeight: FontWeight.bold)),
                      dense: true,
                    );
                  }
                  return ListTile(
                    title: Text(cat),
                    dense: true,
                    trailing: IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red, size: 18),
                      onPressed: () {
                        if (isEvent) {
                          appState.deleteEventCategory(cat);
                        } else {
                          appState.deleteTaskCategory(cat);
                        }
                      },
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
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.blue.shade600,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Center(
                      child: Text(
                        'A',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
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
                  _buildNavItem(0, 'Takvim', Icons.calendar_today),
                  _buildNavItem(1, 'Görevler', Icons.check_circle_outline),
                  _buildNavItem(2, 'Projeler', Icons.rocket_launch),
                  _buildNavItem(3, 'Analiz', Icons.bar_chart),
                  _buildNavItem(4, 'Ayarlar', Icons.settings),
                  const Divider(),

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

                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CheckboxListTile(
                          value: isChecked,
                          title: Text(tag, style: const TextStyle(fontSize: 13)),
                          controlAffinity: ListTileControlAffinity.leading,
                          dense: true,
                          visualDensity: VisualDensity.compact,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16.0),
                          onChanged: (val) {
                            appState.toggleEventTag(tag);
                          },
                          secondary: subTags.isNotEmpty
                              ? IconButton(
                                  icon: Icon(
                                    isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                                    size: 18,
                                  ),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  onPressed: () {
                                    setState(() {
                                      _expandedCategories[tag] = !isExpanded;
                                    });
                                  },
                                )
                              : null,
                        ),
                        if (isExpanded && subTags.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(left: 32.0),
                            child: Column(
                              children: subTags.map((sub) {
                                final isSubChecked = appState.selectedEventSubTags.contains('$tag:$sub');
                                return CheckboxListTile(
                                  value: isSubChecked,
                                  title: Text(sub, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                  controlAffinity: ListTileControlAffinity.leading,
                                  dense: true,
                                  visualDensity: VisualDensity.compact,
                                  onChanged: (val) {
                                    appState.toggleEventSubTag(tag, sub);
                                  },
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

                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CheckboxListTile(
                          value: isChecked,
                          title: Text(tag, style: const TextStyle(fontSize: 13)),
                          controlAffinity: ListTileControlAffinity.leading,
                          dense: true,
                          visualDensity: VisualDensity.compact,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16.0),
                          onChanged: (val) {
                            appState.toggleTaskTag(tag);
                          },
                          secondary: subTags.isNotEmpty
                              ? IconButton(
                                  icon: Icon(
                                    isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                                    size: 18,
                                  ),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  onPressed: () {
                                    setState(() {
                                      _expandedCategories['task_$tag'] = !isExpanded;
                                    });
                                  },
                                )
                              : null,
                        ),
                        if (isExpanded && subTags.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(left: 32.0),
                            child: Column(
                              children: subTags.map((sub) {
                                final isSubChecked = appState.selectedTaskSubTags.contains('$tag:$sub');
                                return CheckboxListTile(
                                  value: isSubChecked,
                                  title: Text(sub, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                  controlAffinity: ListTileControlAffinity.leading,
                                  dense: true,
                                  visualDensity: VisualDensity.compact,
                                  onChanged: (val) {
                                    appState.toggleTaskSubTag(tag, sub);
                                  },
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
                    CheckboxListTile(
                      value: appState.selectedProjectIds.contains('no_project'),
                      title: Row(
                        children: [
                          Icon(Icons.grid_on_outlined, size: 16, color: Colors.grey.shade600),
                          const SizedBox(width: 8),
                          const Text('Projesiz Ögeler', style: TextStyle(fontSize: 13)),
                        ],
                      ),
                      controlAffinity: ListTileControlAffinity.trailing,
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16.0),
                      onChanged: (val) {
                        appState.toggleProjectSelection('no_project');
                      },
                    ),
                    // Proje listesi
                    ...appState.projects.map((proj) {
                      final isSelected = appState.selectedProjectIds.contains(proj.id);
                      return CheckboxListTile(
                        value: isSelected,
                        title: Row(
                          children: [
                            Icon(Icons.rocket_launch, size: 16, color: Color(proj.colorValue)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                proj.title,
                                style: const TextStyle(fontSize: 13),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        controlAffinity: ListTileControlAffinity.trailing,
                        dense: true,
                        visualDensity: VisualDensity.compact,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16.0),
                        onChanged: (val) {
                          appState.toggleProjectSelection(proj.id);
                        },
                      );
                    }),
                  ],
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
    return CheckboxListTile(
      value: isChecked,
      title: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontSize: 13)),
        ],
      ),
      controlAffinity: ListTileControlAffinity.leading,
      dense: true,
      visualDensity: VisualDensity.compact,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16.0),
      onChanged: (val) {
        appState.toggleImportance(importance);
      },
    );
  }
}
