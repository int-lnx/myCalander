import 'dart:convert';
import 'dart:io' show File; // Keep for mobile/desktop references if any
import 'package:flutter/foundation.dart';
import '../models/project.dart';
import '../models/project_evaluation.dart';
import '../models/event.dart';
import '../models/task_item.dart';

// HTML import only on Web to prevent compilation errors on mobile/desktop
import 'dart:html' as html;

class BackupService {
  /// Verileri JSON formatında dışa aktarır ve Web ortamında tarayıcıya indirir.
  static Future<void> exportAndShareBackup({
    required List<Project> projects,
    required List<ProjectEvaluation> evaluations,
    required List<Event> events,
    required List<TaskItem> tasks,
  }) async {
    final Map<String, dynamic> backupData = {
      'projects': projects.map((p) => p.toJson()).toList(),
      'evaluations': evaluations.map((e) => e.toJson()).toList(),
      'events': events.map((e) => e.toJson()).toList(),
      'tasks': tasks.map((t) => t.toJson()).toList(),
    };

    final jsonStr = json.encode(backupData);

    if (kIsWeb) {
      // Web download implementation
      final bytes = utf8.encode(jsonStr);
      final blob = html.Blob([bytes], 'application/json');
      final url = html.Url.createObjectUrlFromBlob(blob);
      final anchor = html.document.createElement('a') as html.AnchorElement
        ..href = url
        ..style.display = 'none'
        ..download = 'my_plan_backup_${DateTime.now().millisecondsSinceEpoch}.json';
      html.document.body?.children.add(anchor);
      anchor.click();
      html.document.body?.children.remove(anchor);
      html.Url.revokeObjectUrl(url);
    } else {
      // Desktop/Mobile placeholder or print
      debugPrint('Backup payload (non-web): $jsonStr');
    }
  }

  /// JSON dosyasını içe aktarmak için web dosya seçicisini kullanır.
  static Future<Map<String, List<dynamic>>?> importBackup() async {
    if (!kIsWeb) {
      return null;
    }

    final uploadInput = html.FileUploadInputElement()..accept = '.json';
    uploadInput.click();

    await uploadInput.onChange.first;
    if (uploadInput.files == null || uploadInput.files!.isEmpty) {
      return null;
    }

    final file = uploadInput.files!.first;
    final reader = html.FileReader();
    reader.readAsText(file);

    await reader.onLoad.first;
    final String? result = reader.result as String?;
    if (result == null || result.isEmpty) {
      return null;
    }

    final Map<String, dynamic> decoded = json.decode(result);
    
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

    return {
      'projects': projects,
      'evaluations': evaluations,
      'events': events,
      'tasks': tasks,
    };
  }
}
