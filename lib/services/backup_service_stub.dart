import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import '../models/project.dart';
import '../models/project_evaluation.dart';
import '../models/event.dart';
import '../models/task_item.dart';
import '../models/day_note.dart';

Future<void> downloadFileImpl({
  required String fileName,
  required String content,
  required String mimeType,
}) async {
  try {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsString(content, encoding: utf8);
    await Share.shareXFiles([XFile(file.path, mimeType: mimeType)], text: fileName);
  } catch (e) {
    // Fallback if needed
  }
}

Future<void> exportAndShareBackupImpl({
  required List<Project> projects,
  required List<ProjectEvaluation> evaluations,
  required List<Event> events,
  required List<TaskItem> tasks,
  List<DayNote> dayNotes = const [],
}) async {
  final Map<String, dynamic> backupData = {
    'projects': projects.map((p) => p.toJson()).toList(),
    'evaluations': evaluations.map((e) => e.toJson()).toList(),
    'events': events.map((e) => e.toJson()).toList(),
    'tasks': tasks.map((t) => t.toJson()).toList(),
    'day_notes': dayNotes.map((d) => d.toJson()).toList(),
  };

  final jsonStr = json.encode(backupData);
  await downloadFileImpl(
    fileName: 'my_plan_backup_${DateTime.now().millisecondsSinceEpoch}.json',
    content: jsonStr,
    mimeType: 'application/json',
  );
}

Future<Map<String, List<dynamic>>?> importBackupImpl() async {
  try {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (result == null || result.files.isEmpty) return null;

    final bytes = result.files.first.bytes;
    String content = '';
    if (bytes != null) {
      content = utf8.decode(bytes);
    } else if (result.files.first.path != null) {
      content = await File(result.files.first.path!).readAsString();
    }

    if (content.isEmpty) return null;
    final Map<String, dynamic> decoded = json.decode(content);

    final List<Project> projects = (decoded['projects'] as List? ?? [])
        .map((p) => Project.fromJson(p as Map<String, dynamic>))
        .toList();

    final List<ProjectEvaluation> evaluations = (decoded['evaluations'] as List? ?? [])
        .map((e) => ProjectEvaluation.fromJson(e as Map<String, dynamic>))
        .toList();

    final List<Event> events = (decoded['events'] as List? ?? [])
        .map((e) => Event.fromJson(e as Map<String, dynamic>))
        .toList();

    final List<TaskItem> tasks = (decoded['tasks'] as List? ?? [])
        .map((t) => TaskItem.fromJson(t as Map<String, dynamic>))
        .toList();

    final List<DayNote> dayNotes = (decoded['day_notes'] as List? ?? [])
        .map((d) => DayNote.fromJson(d as Map<String, dynamic>))
        .toList();

    return {
      'projects': projects,
      'evaluations': evaluations,
      'events': events,
      'tasks': tasks,
      'day_notes': dayNotes,
    };
  } catch (_) {
    return null;
  }
}
