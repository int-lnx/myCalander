import 'package:intl/intl.dart';
import '../models/project.dart';
import '../models/project_evaluation.dart';
import '../models/event.dart';
import '../models/task_item.dart';
import '../models/day_note.dart';

import 'backup_service_stub.dart'
    if (dart.library.html) 'backup_service_web.dart';

class BackupService {
  /// Genel dosya indirme/paylaşma fonksiyonu
  static Future<void> downloadFile({
    required String fileName,
    required String content,
    required String mimeType,
  }) async {
    await downloadFileImpl(
      fileName: fileName,
      content: content,
      mimeType: mimeType,
    );
  }

  /// Tüm verileri JSON formatında dışa aktarır ve tarayıcıya indirir.
  static Future<void> exportAndShareBackup({
    required List<Project> projects,
    required List<ProjectEvaluation> evaluations,
    required List<Event> events,
    required List<TaskItem> tasks,
    List<DayNote> dayNotes = const [],
  }) async {
    await exportAndShareBackupImpl(
      projects: projects,
      evaluations: evaluations,
      events: events,
      tasks: tasks,
      dayNotes: dayNotes,
    );
  }

  /// JSON dosyasını içe aktarmak için dosya seçicisini kullanır.
  static Future<Map<String, List<dynamic>>?> importBackup() async {
    return await importBackupImpl();
  }

  /// Günlük verilerini Microsoft Word ve Google Docs uyumlu zengin metin (.doc) formatında dışa aktarır.
  static Future<void> exportDailyNotesDoc({
    required List<DayNote> notes,
    required List<Project> projects,
    required List<ProjectEvaluation> evaluations,
  }) async {
    final sortedNotes = List<DayNote>.from(notes)
      ..sort((a, b) => b.date.compareTo(a.date)); // En yeniden en eskiye

    final turkishDateFormatter = DateFormat('d MMMM yyyy, EEEE', 'tr_TR');
    final nowStr = DateFormat('d MMMM yyyy HH:mm', 'tr_TR').format(DateTime.now());

    final sb = StringBuffer();
    sb.writeln('''<!DOCTYPE html>
<html xmlns:o='urn:schemas-microsoft-com:office:office' xmlns:w='urn:schemas-microsoft-com:office:word' xmlns='http://www.w3.org/TR/REC-html40'>
<head>
<meta charset="utf-8">
<title>My Plan - Kişisel Günlük</title>
<!--[if gte mso 9]>
<xml>
<w:WordDocument>
<w:View>Print</w:View>
<w:Zoom>100</w:Zoom>
<w:DoNotOptimizeForBrowser/>
</w:WordDocument>
</xml>
<![endif]-->
<style>
  body {
    font-family: 'Calibri', 'Segoe UI', Arial, sans-serif;
    color: #2D3748;
    line-height: 1.6;
    margin: 30px;
    background-color: #FFFFFF;
  }
  .doc-title {
    font-size: 26pt;
    font-weight: bold;
    color: #1A365D;
    text-align: center;
    border-bottom: 3px solid #3182CE;
    padding-bottom: 10px;
    margin-bottom: 8px;
  }
  .doc-subtitle {
    font-size: 11pt;
    color: #718096;
    text-align: center;
    margin-bottom: 35px;
  }
  .day-card {
    border: 1px solid #E2E8F0;
    border-left: 6px solid #3182CE;
    background-color: #F8FAFC;
    border-radius: 8px;
    padding: 18px 22px;
    margin-bottom: 25px;
    page-break-inside: avoid;
  }
  .day-header {
    border-bottom: 1px solid #E2E8F0;
    padding-bottom: 10px;
    margin-bottom: 14px;
  }
  .day-date {
    font-size: 15pt;
    font-weight: bold;
    color: #2B6CB0;
  }
  .day-badges {
    margin-top: 6px;
    font-size: 11pt;
  }
  .star-badge {
    color: #D69E2E;
    font-weight: bold;
    margin-right: 15px;
  }
  .emoji-badge {
    font-size: 14pt;
    vertical-align: middle;
    margin-right: 8px;
  }
  .entry-box {
    margin-top: 10px;
    padding: 12px 16px;
    background-color: #FFFFFF;
    border: 1px solid #EDF2F7;
    border-radius: 6px;
  }
  .entry-text {
    font-size: 11pt;
    color: #1A202C;
    white-space: pre-wrap;
    line-height: 1.6;
  }
  .tag-container {
    margin-top: 8px;
  }
  .tag-pill {
    display: inline-block;
    background-color: #EBF8FF;
    color: #2B6CB0;
    border-radius: 12px;
    padding: 2px 10px;
    font-size: 9pt;
    font-weight: bold;
    margin-right: 6px;
    margin-top: 4px;
  }
  .project-section {
    margin-top: 14px;
    padding: 10px 14px;
    background-color: #FAF5FF;
    border-left: 4px solid #805AD5;
    border-radius: 4px;
    font-size: 10.5pt;
  }
  .project-item {
    margin-bottom: 6px;
  }
  .footer {
    text-align: center;
    color: #A0AEC0;
    font-size: 9pt;
    margin-top: 50px;
    border-top: 1px solid #E2E8F0;
    padding-top: 15px;
  }
</style>
</head>
<body>
  <div class="doc-title">📖 Kişisel Günlük Defteri</div>
  <div class="doc-subtitle">My Plan • Oluşturulma Tarihi: $nowStr • Toplam Kayıt: ${sortedNotes.length} Gün</div>
''');

    for (final dayNote in sortedNotes) {
      final dateStr = turkishDateFormatter.format(dayNote.date);

      // İlgili günün proje değerlendirmeleri
      final dayEvals = evaluations.where((e) =>
          e.sessionDate.year == dayNote.date.year &&
          e.sessionDate.month == dayNote.date.month &&
          e.sessionDate.day == dayNote.date.day).toList();

      sb.writeln('  <div class="day-card">');
      sb.writeln('    <div class="day-header">');
      sb.writeln('      <div class="day-date">$dateStr</div>');
      sb.writeln('      <div class="day-badges">');

      if (dayNote.emoji != null && dayNote.emoji!.isNotEmpty) {
        sb.writeln('        <span class="emoji-badge">${dayNote.emoji}</span>');
      }

      if (dayNote.rating != null && dayNote.rating! > 0) {
        final stars = '★' * dayNote.rating! + '☆' * (5 - dayNote.rating!);
        sb.writeln('        <span class="star-badge">Günün Puanı: $stars (${dayNote.rating}/5)</span>');
      } else {
        sb.writeln('        <span style="color: #A0AEC0; font-size: 10pt;">(Puan girilmedi)</span>');
      }

      sb.writeln('      </div>');
      sb.writeln('    </div>');

      // Not Girdileri
      if (dayNote.entries.isNotEmpty) {
        for (final entry in dayNote.entries) {
          if (entry.text.trim().isEmpty && entry.tags.isEmpty) continue;
          sb.writeln('    <div class="entry-box">');
          if (entry.text.trim().isNotEmpty) {
            sb.writeln('      <div class="entry-text">${_escapeHtml(entry.text)}</div>');
          }
          if (entry.tags.isNotEmpty) {
            sb.writeln('      <div class="tag-container">');
            for (final tag in entry.tags) {
              sb.writeln('        <span class="tag-pill">#${_escapeHtml(tag)}</span>');
            }
            sb.writeln('      </div>');
          }
          sb.writeln('    </div>');
        }
      } else if (dayNote.note.trim().isNotEmpty) {
        sb.writeln('    <div class="entry-box">');
        sb.writeln('      <div class="entry-text">${_escapeHtml(dayNote.note)}</div>');
        sb.writeln('    </div>');
      }

      // Projeler
      if (dayEvals.isNotEmpty) {
        sb.writeln('    <div class="project-section">');
        sb.writeln('      <div style="font-weight: bold; color: #553C9A; margin-bottom: 6px;">🎯 Günün Proje İlerlemeleri:</div>');
        for (final ev in dayEvals) {
          final p = projects.cast<Project?>().firstWhere(
                (proj) => proj?.id == ev.projectId,
                orElse: () => null,
              );
          final pTitle = p?.title ?? 'Proje';
          final scoreStr = ev.isSkipped
              ? 'Pas Geçildi'
              : (p?.evaluationType == 'PERCENTAGE'
                  ? '%${ev.score.toStringAsFixed(0)}'
                  : '${ev.score.toStringAsFixed(0)} Puan');
          final durationStr = ev.durationHours > 0
              ? ' • ${ev.durationHours.toStringAsFixed(1)} saat'
              : '';
          final noteStr = (ev.note != null && ev.note!.trim().isNotEmpty)
              ? ' (Not: ${_escapeHtml(ev.note!)})'
              : '';

          sb.writeln('      <div class="project-item">• <b>$pTitle:</b> $scoreStr$durationStr$noteStr</div>');
        }
        sb.writeln('    </div>');
      }

      sb.writeln('  </div>');
    }

    sb.writeln('''
  <div class="footer">
    My Plan Kişisel Ajanda ve Planlama Sistemi tarafından üretilmiştir.
  </div>
</body>
</html>
''');

    final dateTag = DateFormat('yyyy-MM-dd').format(DateTime.now());
    await downloadFileImpl(
      fileName: 'MyPlan_Gunluk_Notlari_$dateTag.doc',
      content: sb.toString(),
      mimeType: 'application/msword;charset=utf-8',
    );
  }

  /// Görevler (Yapılacaklar) verilerini Excel uyumlu CSV formatında dışa aktarır.
  static Future<void> exportTasksCsv({
    required List<TaskItem> tasks,
    required List<Project> projects,
  }) async {
    final sb = StringBuffer();
    // Excel için UTF-8 BOM ekliyoruz
    sb.write('\uFEFF');

    // Başlık Satırı (Noktalı virgül delimiter ile Türkçe Excel için tam uyumlu)
    sb.writeln(
      'Görev Adı;Durum;Öncelik;Kategori / Etiket;Son Tarih;Saat;Hatırlatıcı;İlişkili Proje;Alt Görevler;Notlar;Oluşturulma Tarihi;Tamamlanma Tarihi',
    );

    for (final task in tasks) {
      final status = task.isCompleted
          ? 'Tamamlandı'
          : (task.isInProgress ? 'Devam Ediyor' : 'Bekliyor');
      final priority = _formatPriority(task.importance);
      final tag = task.tag;
      final dateStr = task.from != null
          ? DateFormat('dd.MM.yyyy').format(task.from!)
          : '-';
      final timeStr = task.from != null
          ? (task.isAllDay ? 'Tüm Gün' : DateFormat('HH:mm').format(task.from!))
          : '-';
      final reminder = task.hasNotification
          ? '${task.notificationMinutesBefore ?? 0} dk önce'
          : '-';

      final p = projects.cast<Project?>().firstWhere(
            (proj) => proj?.id == task.projectId,
            orElse: () => null,
          );
      final projectTitle = p?.title ?? (task.projectId != null ? 'Proje' : '-');

      // Alt görevler (bu göreve bağlı olan alt görevler)
      final subtasks = tasks
          .where((t) => t.parentTaskId == task.id)
          .map((st) => '${st.isCompleted ? "[X]" : "[ ]"} ${st.title}')
          .join(' | ');

      final notes = task.details;
      final createdAt = DateFormat('dd.MM.yyyy HH:mm').format(task.createdAt);
      final completedAt = task.completedDate != null
          ? DateFormat('dd.MM.yyyy HH:mm').format(task.completedDate!)
          : '-';

      sb.writeln([
        _escapeCsv(task.title),
        _escapeCsv(status),
        _escapeCsv(priority),
        _escapeCsv(tag),
        _escapeCsv(dateStr),
        _escapeCsv(timeStr),
        _escapeCsv(reminder),
        _escapeCsv(projectTitle),
        _escapeCsv(subtasks),
        _escapeCsv(notes),
        _escapeCsv(createdAt),
        _escapeCsv(completedAt),
      ].join(';'));
    }

    final dateTag = DateFormat('yyyy-MM-dd').format(DateTime.now());
    await downloadFileImpl(
      fileName: 'MyPlan_Gorevler_Excel_$dateTag.csv',
      content: sb.toString(),
      mimeType: 'text/csv;charset=utf-8',
    );
  }

  /// Projeler ve Değerlendirmeleri Excel uyumlu CSV formatında dışa aktarır.
  static Future<void> exportProjectsCsv({
    required List<Project> projects,
    required List<ProjectEvaluation> evaluations,
  }) async {
    final sb = StringBuffer();
    sb.write('\uFEFF');

    // BÖLÜM 1: PROJE LİSTESİ
    sb.writeln('--- PROJE LİSTESİ VE DETAYLARI ---');
    sb.writeln('Proje Adı;Kategori;Alt Kategori;Değerlendirme Tipi;Hedef Değer;Durum;Kontrol Adımları;Kayıtlı Oturum Sayısı;Toplam Süre (Saat);Ortalama Puan');

    for (final proj in projects) {
      final evals = evaluations.where((e) => e.projectId == proj.id).toList();
      final evalCount = evals.length;
      final totalHours = evals.fold<double>(0.0, (acc, e) => acc + e.durationHours);
      final avgScore = evalCount > 0
          ? (evals.fold<double>(0.0, (acc, e) => acc + e.score) / evalCount)
          : 0.0;

      final typeStr = proj.evaluationType == 'PERCENTAGE' ? '% Yüzdelik' : 'Sayısal Puan';
      final targetStr = proj.targetValue!.toStringAsFixed(0);
      final statusStr = proj.isArchived ? 'Arşivlenmiş' : 'Aktif';
      final stepsStr = proj.checkSteps.map((s) => s.title + (s.weight != null ? ' (%${s.weight!.toStringAsFixed(0)})' : '')).join(' | ');

      sb.writeln([
        _escapeCsv(proj.title),
        _escapeCsv(proj.tag),
        _escapeCsv(proj.subTag ?? '-'),
        _escapeCsv(typeStr),
        _escapeCsv(targetStr),
        _escapeCsv(statusStr),
        _escapeCsv(stepsStr),
        _escapeCsv(evalCount.toString()),
        _escapeCsv(totalHours.toStringAsFixed(2)),
        _escapeCsv(avgScore.toStringAsFixed(1)),
      ].join(';'));
    }

    sb.writeln();
    sb.writeln('--- GÜNLÜK PROJE DEĞERLENDİRME GEÇMİŞİ ---');
    sb.writeln('Tarih;Proje Adı;Durum;Puan / Yüzde;Harcanan Süre (Saat);Tamamlanan Adımlar;Oturum Notu');

    final sortedEvals = List<ProjectEvaluation>.from(evaluations)
      ..sort((a, b) => b.sessionDate.compareTo(a.sessionDate));

    for (final ev in sortedEvals) {
      final proj = projects.cast<Project?>().firstWhere(
            (p) => p?.id == ev.projectId,
            orElse: () => null,
          );
      final pTitle = proj?.title ?? 'Bilinmeyen Proje';
      final dateStr = DateFormat('dd.MM.yyyy').format(ev.sessionDate);
      final statusStr = ev.isSkipped ? 'Pas Geçildi' : 'Yapıldı';
      final scoreStr = ev.isSkipped
          ? '-'
          : (proj?.evaluationType == 'PERCENTAGE'
              ? '%${ev.score.toStringAsFixed(0)}'
              : ev.score.toStringAsFixed(1));
      final durStr = ev.durationHours > 0 ? ev.durationHours.toStringAsFixed(2) : '-';
      final checkedStepsStr = ev.checkedSteps.join(', ');
      final noteStr = ev.note ?? '-';

      sb.writeln([
        _escapeCsv(dateStr),
        _escapeCsv(pTitle),
        _escapeCsv(statusStr),
        _escapeCsv(scoreStr),
        _escapeCsv(durStr),
        _escapeCsv(checkedStepsStr),
        _escapeCsv(noteStr),
      ].join(';'));
    }

    final dateTag = DateFormat('yyyy-MM-dd').format(DateTime.now());
    await downloadFileImpl(
      fileName: 'MyPlan_Projeler_Excel_$dateTag.csv',
      content: sb.toString(),
      mimeType: 'text/csv;charset=utf-8',
    );
  }

  // --- Yardımcı Güvenlik Formatlayıcıları ---
  static String _escapeHtml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
  }

  static String _escapeCsv(String field) {
    if (field.contains(';') || field.contains('"') || field.contains('\n') || field.contains('\r')) {
      return '"${field.replaceAll('"', '""')}"';
    }
    return field;
  }

  static String _formatPriority(int priority) {
    switch (priority) {
      case 3:
        return 'Acil (Yüksek)';
      case 2:
        return 'Yüksek';
      case 1:
        return 'Orta';
      case 0:
      default:
        return 'Düşük';
    }
  }
}
