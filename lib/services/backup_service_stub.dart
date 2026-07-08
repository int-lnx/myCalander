import '../models/project.dart';
import '../models/project_evaluation.dart';
import '../models/event.dart';
import '../models/task_item.dart';

Future<void> exportAndShareBackupImpl({
  required List<Project> projects,
  required List<ProjectEvaluation> evaluations,
  required List<Event> events,
  required List<TaskItem> tasks,
}) async {
  // Non-web placeholder: sharing/saving is not implemented via Web Blobs
}

Future<Map<String, List<dynamic>>?> importBackupImpl() async {
  // Non-web placeholder: file input stream not supported
  return null;
}
