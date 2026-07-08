import '../models/project.dart';
import '../models/project_evaluation.dart';

class CsvHandler {
  /// Bir veri listesini CSV formatında stringe dönüştürür.
  static String convertToCsv(List<List<dynamic>> rows) {
    return rows.map((row) {
      return row.map((field) {
        if (field == null) return '';
        final str = field.toString();
        if (str.contains(',') || str.contains('\n') || str.contains('"')) {
          final escaped = str.replaceAll('"', '""');
          return '"$escaped"';
        }
        return str;
      }).join(',');
    }).join('\n');
  }

  /// CSV stringini listelere geri dönüştürür.
  static List<List<String>> parseCsv(String csvText) {
    final List<List<String>> result = [];
    final lines = csvText.split('\n');
    for (var line in lines) {
      if (line.trim().isEmpty) continue;
      final List<String> row = [];
      final RegExp regExp = RegExp(r'(?:"([^"]*(?:""[^"]*)*)"|([^,\n]+))|^,');
      final matches = regExp.allMatches(line);
      for (var match in matches) {
        if (match.group(1) != null) {
          row.add(match.group(1)!.replaceAll('""', '"'));
        } else if (match.group(2) != null) {
          row.add(match.group(2)!);
        } else {
          row.add('');
        }
      }
      result.add(row);
    }
    return result;
  }

  /// Projeleri ve Değerlendirmeleri CSV formatına dönüştürür.
  static String exportToCsv(List<Project> projects, List<ProjectEvaluation> evaluations) {
    final List<List<dynamic>> rows = [];
    // Header
    rows.add(['Tarih', 'Proje ID', 'Proje Başlığı', 'Puan', 'Çalışılan Saat', 'Not', 'Pas Geçildi']);
    
    for (var eval in evaluations) {
      final project = projects.firstWhere(
        (p) => p.id == eval.projectId,
        orElse: () => const Project(id: '', title: 'Bilinmeyen Proje', colorValue: 0, evaluationType: 'PERCENTAGE', targetValue: 100.0),
      );
      final dateStr = '${eval.sessionDate.year}-${eval.sessionDate.month.toString().padLeft(2, '0')}-${eval.sessionDate.day.toString().padLeft(2, '0')}';
      rows.add([
        dateStr,
        eval.projectId,
        project.title,
        eval.score,
        eval.durationHours,
        eval.note,
        eval.isSkipped ? 'Evet' : 'Hayır'
      ]);
    }
    
    return convertToCsv(rows);
  }

  /// CSV verisini Değerlendirme listesine dönüştürür.
  static List<ProjectEvaluation> importFromCsv(String csvText, List<Project> projects) {
    final List<ProjectEvaluation> evaluations = [];
    final rows = parseCsv(csvText);
    if (rows.isEmpty || rows.length < 2) return [];

    // Header skip
    for (int i = 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.length < 6) continue;
      
      try {
        final date = DateTime.parse(row[0]);
        final projectId = row[1];
        final score = double.tryParse(row[3]) ?? 0.0;
        final durationHours = double.tryParse(row[4]) ?? 0.0;
        final note = row[5];
        final isSkipped = row.length > 6 && row[6] == 'Evet';

        evaluations.add(ProjectEvaluation(
          id: '${projectId}_${date.millisecondsSinceEpoch}',
          projectId: projectId,
          sessionDate: date,
          score: score,
          durationHours: durationHours,
          note: note,
          isSkipped: isSkipped,
          performancePercent: score,
        ));
      } catch (_) {
        // Skip malformed rows
      }
    }
    return evaluations;
  }
}
