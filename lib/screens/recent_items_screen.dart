import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/event.dart';
import '../models/task_item.dart';
import 'event_form_screen.dart';
import 'task_form_screen.dart';
import '../models/project.dart';

class RecentItemsScreen extends StatefulWidget {
  const RecentItemsScreen({super.key});

  @override
  State<RecentItemsScreen> createState() => _RecentItemsScreenState();
}

class _RecentItemsScreenState extends State<RecentItemsScreen> {
  final Set<String> _animatingTaskIds = {};

  String _formatDateTime(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildSectionHeader(String title, IconData icon, Color color, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEventCard(BuildContext context, Event event, bool isDark, AppState appState) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      elevation: 1,
      color: isDark ? Colors.grey.shade800 : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        leading: Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Color(event.colorValue),
          ),
        ),
        title: Text(
          event.title,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (event.description.isNotEmpty)
              Text(
                event.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.calendar_today, size: 12, color: Colors.grey.shade600),
                const SizedBox(width: 4),
                Text(
                  '${event.from.day}/${event.from.month}/${event.from.year}',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
                const Spacer(),
                Icon(Icons.access_time, size: 12, color: Colors.blue.shade700),
                const SizedBox(width: 4),
                Text(
                  'Eklenme: ${_formatDateTime(event.createdAt)}',
                  style: TextStyle(fontSize: 11, color: Colors.blue.shade700, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit_note, color: Colors.blueGrey),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => EventFormScreen(existingEvent: event),
                  ),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Etkinliği Sil'),
                    content: const Text('Bu etkinliği silmek istediğinize emin misiniz?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Vazgeç'),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                        onPressed: () {
                          appState.deleteEvent(event.id);
                          Navigator.pop(context);
                        },
                        child: const Text('Sil', style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTaskCard(BuildContext context, TaskItem task, bool isDark, AppState appState) {
    final isCompleted = _animatingTaskIds.contains(task.id)
        ? !task.isCompleted
        : task.isCompleted;

    final circleColor = task.projectId != null
        ? Color(appState.projects.firstWhere((p) => p.id == task.projectId, orElse: () => const Project(id: '', title: '', colorValue: 0xFF2196F3, evaluationType: 'PERCENTAGE', targetValue: 100.0)).colorValue)
        : (task.importance == 2
            ? Colors.red
            : (task.importance == 1 ? Colors.orange : Colors.blue));

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      elevation: 1,
      color: isDark ? Colors.grey.shade800 : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        leading: GestureDetector(
          onTap: () async {
            if (_animatingTaskIds.contains(task.id)) return;
            setState(() {
              _animatingTaskIds.add(task.id);
            });
            await Future.delayed(const Duration(milliseconds: 400));
            if (mounted) {
              appState.toggleTaskCompletion(task.id);
              setState(() {
                _animatingTaskIds.remove(task.id);
              });
            }
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: circleColor, width: 2),
              color: isCompleted ? circleColor : Colors.transparent,
            ),
            child: AnimatedScale(
              scale: isCompleted ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutBack,
              child: const Icon(Icons.check, size: 16, color: Colors.white),
            ),
          ),
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
                Icon(Icons.label_outline, size: 12, color: Colors.grey.shade600),
                const SizedBox(width: 4),
                Text(
                  task.tag,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
                const Spacer(),
                Icon(Icons.access_time, size: 12, color: Colors.green.shade700),
                const SizedBox(width: 4),
                Text(
                  'Eklenme: ${_formatDateTime(task.createdAt)}',
                  style: TextStyle(fontSize: 11, color: Colors.green.shade700, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit_note, color: Colors.blueGrey),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => TaskFormScreen(existingTask: task),
                  ),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Görevi Sil'),
                    content: const Text('Bu görevi silmek istediğinize emin misiniz?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Vazgeç'),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                        onPressed: () {
                          appState.deleteTask(task.id);
                          Navigator.pop(context);
                        },
                        child: const Text('Sil', style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final isDark = appState.isDarkMode;
    final isWide = MediaQuery.of(context).size.width > 900;

    // Filter and sort events by creation date descending
    final List<Event> recentEvents = List<Event>.from(appState.events)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    
    // Filter and sort tasks by creation date descending
    final List<TaskItem> recentTasks = List<TaskItem>.from(appState.tasks)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final eventsWidget = Column(
      children: [
        _buildSectionHeader('Son Eklenen Etkinlikler', Icons.event, Colors.blue, isDark),
        Expanded(
          child: recentEvents.isEmpty
              ? const Center(child: Text('Henüz etkinlik bulunmuyor.'))
              : ListView.builder(
                  itemCount: recentEvents.length,
                  itemBuilder: (context, index) => _buildEventCard(context, recentEvents[index], isDark, appState),
                ),
        ),
      ],
    );

    final tasksWidget = Column(
      children: [
        _buildSectionHeader('Son Eklenen Görevler', Icons.task_alt, Colors.green, isDark),
        Expanded(
          child: recentTasks.isEmpty
              ? const Center(child: Text('Henüz görev bulunmuyor.'))
              : ListView.builder(
                  itemCount: recentTasks.length,
                  itemBuilder: (context, index) => _buildTaskCard(context, recentTasks[index], isDark, appState),
                ),
        ),
      ],
    );

    return Scaffold(
      backgroundColor: isDark ? Colors.grey.shade900 : Colors.grey.shade50,
      body: isWide
          ? Row(
              children: [
                Expanded(child: eventsWidget),
                const VerticalDivider(width: 1),
                Expanded(child: tasksWidget),
              ],
            )
          : Column(
              children: [
                Expanded(child: eventsWidget),
                const Divider(height: 1),
                Expanded(child: tasksWidget),
              ],
            ),
    );
  }
}
