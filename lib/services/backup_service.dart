import '../models/project.dart';
import '../models/project_evaluation.dart';
import '../models/event.dart';
import '../models/task_item.dart';

import 'backup_service_stub.dart'
    if (dart.library.html) 'backup_service_web.dart';

class BackupService {
  /// Verileri JSON formatında dışa aktarır ve Web ortamında tarayıcıya indirir.
  static Future<void> exportAndShareBackup({
    required List<Project> projects,
    required List<ProjectEvaluation> evaluations,
    required List<Event> events,
    required List<TaskItem> tasks,
  }) async {
    await exportAndShareBackupImpl(
      projects: projects,
      evaluations: evaluations,
      events: events,
      tasks: tasks,
    );
  }

  /// JSON dosyasını içe aktarmak için web dosya seçicisini kullanır.
  static Future<Map<String, List<dynamic>>?> importBackup() async {
    return await importBackupImpl();
  }
}
