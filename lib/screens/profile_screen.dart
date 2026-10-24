import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../services/auth_service.dart';
import '../services/backup_service.dart';
import '../models/project.dart';
import '../models/project_evaluation.dart';
import '../models/event.dart';
import '../models/task_item.dart';
import '../models/day_note.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final user = appState.firebaseUser;
    final authService = AuthService();
    final isDark = appState.isDarkMode;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profilim ve Veriler'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // KULLANICI KARTI
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: isDark ? Colors.white12 : Colors.grey.shade300,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    if (user != null) ...[
                      CircleAvatar(
                        radius: 36,
                        backgroundImage: user.photoURL != null
                            ? NetworkImage(user.photoURL!)
                            : null,
                        child: user.photoURL == null
                            ? const Icon(Icons.person, size: 36)
                            : null,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        user.displayName ?? 'Kullanıcı',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        user.email ?? '',
                        style: const TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.logout, size: 18, color: Colors.red),
                        label: const Text('Çıkış Yap', style: TextStyle(color: Colors.red)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.red),
                        ),
                        onPressed: () async {
                          await authService.signOut();
                          if (context.mounted) Navigator.pop(context);
                        },
                      ),
                    ] else ...[
                      const Icon(Icons.cloud_off, size: 52, color: Colors.orange),
                      const SizedBox(height: 12),
                      const Text(
                        'Giriş Yapılmadı',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Bulut senkronizasyonunu etkinleştirmek ve cihazlar arasında verileri eşitlemek için Google ile giriş yapabilirsiniz.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.login),
                          label: const Text('Google ile Giriş Yap'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onPressed: () async {
                            try {
                              await appState.loginWithGoogle();
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Google Girişi Başarılı!')),
                                );
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Giriş Hatası: $e')),
                                );
                              }
                            }
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // VERİ YÖNETİMİ (DIŞA / İÇE AKTAR) KARTI
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: isDark ? Colors.white12 : Colors.grey.shade300,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.indigo.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.sync_alt, color: Colors.indigo, size: 22),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Veri Yönetimi (Dışa / İçe Aktar)',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                'Günlük, görev ve projelerinizi dışa aktarın veya yedekten yükleyin',
                                style: TextStyle(fontSize: 11.5, color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Divider(height: 1),
                    const SizedBox(height: 16),

                    // DIŞA AKTAR BUTONU
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.file_download, size: 20),
                        label: const Text(
                          'Verileri Dışa Aktar (Export)',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.indigo,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: () => _showExportDialog(context, appState),
                      ),
                    ),

                    const SizedBox(height: 10),

                    // İÇE AKTAR BUTONU
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.file_upload, size: 20, color: Colors.teal),
                        label: const Text(
                          'Yedekten İçe Aktar (Import)',
                          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.teal),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.teal),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: () => _handleImport(context, appState),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showExportDialog(BuildContext context, AppState appState) {
    final isDark = appState.isDarkMode;

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.file_download, color: Colors.indigo),
            SizedBox(width: 8),
            Text('Verileri Dışa Aktar (Export)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Hangi verileri dışa aktarmak istediğinizi seçin:',
                  style: TextStyle(fontSize: 12.5, color: Colors.grey),
                ),
                const SizedBox(height: 14),

                // 1. GÜNLÜK VERİLERİ (WORD .DOC)
                _buildExportItem(
                  context: dialogCtx,
                  isDark: isDark,
                  icon: Icons.menu_book,
                  iconColor: Colors.deepPurple,
                  title: 'Günlük Verileri (Kişisel Günlük)',
                  subtitle: 'Günün puanı (★), emoji, etiketler ve notlarınızı Word & Google Docs içinde gerçek bir kitap/günlük gibi okuyabileceğiniz formatta (.doc) indirir.',
                  badge: '${appState.dayNotes.length} Gün Kayıtlı',
                  badgeColor: Colors.deepPurple,
                  buttonLabel: 'Word (.doc) İndir',
                  onPressed: () async {
                    Navigator.pop(dialogCtx);
                    await BackupService.exportDailyNotesDoc(
                      notes: appState.dayNotes,
                      projects: appState.projects,
                      evaluations: appState.evaluations,
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Günlük notları Word belgesi (.doc) olarak indirildi!')),
                      );
                    }
                  },
                ),

                const SizedBox(height: 10),

                // 2. YAPILACAKLAR & GÖREVLER (EXCEL .CSV)
                _buildExportItem(
                  context: dialogCtx,
                  isDark: isDark,
                  icon: Icons.table_chart,
                  iconColor: Colors.green.shade700,
                  title: 'Yapılacaklar & Görevler',
                  subtitle: 'Tüm görevler, öncelikler, kategoriler, alt görevler, hatırlatıcılar ve durumları Excel tablosu (.csv) olarak indirir.',
                  badge: '${appState.tasks.length} Görev',
                  badgeColor: Colors.green.shade700,
                  buttonLabel: 'Excel (.csv) İndir',
                  onPressed: () async {
                    Navigator.pop(dialogCtx);
                    await BackupService.exportTasksCsv(
                      tasks: appState.tasks,
                      projects: appState.projects,
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Görevler Excel tablosu (.csv) olarak indirildi!')),
                      );
                    }
                  },
                ),

                const SizedBox(height: 10),

                // 3. PROJE VERİLERİ & DEĞERLENDİRMELER (EXCEL .CSV)
                _buildExportItem(
                  context: dialogCtx,
                  isDark: isDark,
                  icon: Icons.assignment_turned_in,
                  iconColor: Colors.blue.shade700,
                  title: 'Proje Verileri & Değerlendirmeler',
                  subtitle: 'Projelerinizi, kontrol adımlarını, hedeflerini ve tüm geçmiş oturum değerlendirmelerini Excel tablosu (.csv) olarak indirir.',
                  badge: '${appState.projects.length} Proje',
                  badgeColor: Colors.blue.shade700,
                  buttonLabel: 'Excel (.csv) İndir',
                  onPressed: () async {
                    Navigator.pop(dialogCtx);
                    await BackupService.exportProjectsCsv(
                      projects: appState.projects,
                      evaluations: appState.evaluations,
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Projeler Excel tablosu (.csv) olarak indirildi!')),
                      );
                    }
                  },
                ),

                const SizedBox(height: 10),

                // 4. TÜM VERİLER (TAM YEDEK JSON)
                _buildExportItem(
                  context: dialogCtx,
                  isDark: isDark,
                  icon: Icons.inventory_2,
                  iconColor: Colors.orange.shade800,
                  title: 'Tüm Sistem Verileri (Tam Yedek)',
                  subtitle: 'Tüm günlükler, projeler, etkinlikler ve görevleri içeren eksiksiz geri yüklenebilir JSON yedek dosyası.',
                  badge: 'Tam Yedek',
                  badgeColor: Colors.orange.shade800,
                  buttonLabel: 'JSON Olarak İndir',
                  onPressed: () async {
                    Navigator.pop(dialogCtx);
                    await BackupService.exportAndShareBackup(
                      projects: appState.projects,
                      evaluations: appState.evaluations,
                      events: appState.events,
                      tasks: appState.tasks,
                      dayNotes: appState.dayNotes,
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Tam sistem yedeği (.json) olarak indirildi!')),
                      );
                    }
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Kapat'),
          ),
        ],
      ),
    );
  }

  Widget _buildExportItem({
    required BuildContext context,
    required bool isDark,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required String badge,
    required Color badgeColor,
    required String buttonLabel,
    required VoidCallback onPressed,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF222222) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  badge,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    color: badgeColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 11.5, color: Colors.grey, height: 1.4),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.download, size: 16),
              label: Text(buttonLabel, style: const TextStyle(fontSize: 12)),
              style: ElevatedButton.styleFrom(
                backgroundColor: iconColor,
                foregroundColor: Colors.white,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              ),
              onPressed: onPressed,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleImport(BuildContext context, AppState appState) async {
    try {
      final data = await BackupService.importBackup();
      if (data == null) return;

      if (!context.mounted) return;
      final confirm = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange),
              SizedBox(width: 8),
              Text('Yedeği Geri Yükle'),
            ],
          ),
          content: Text(
            'Seçilen yedek dosyasından şu veriler yüklenecek:\n\n'
            '• ${data['projects']?.length ?? 0} Proje\n'
            '• ${data['evaluations']?.length ?? 0} Değerlendirme\n'
            '• ${data['events']?.length ?? 0} Etkinlik\n'
            '• ${data['tasks']?.length ?? 0} Görev\n'
            '• ${data['day_notes']?.length ?? 0} Günlük Notu\n\n'
            'Mevcut verileriniz bu yedekteki verilerle güncellenecektir. Onaylıyor musunuz?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Vazgeç'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Evet, Geri Yükle'),
            ),
          ],
        ),
      );

      if (confirm == true) {
        await appState.restoreBackup(
          projects: (data['projects'] as List<dynamic>?)?.cast<Project>() ?? [],
          evaluations: (data['evaluations'] as List<dynamic>?)?.cast<ProjectEvaluation>() ?? [],
          events: (data['events'] as List<dynamic>?)?.cast<Event>() ?? [],
          tasks: (data['tasks'] as List<dynamic>?)?.cast<TaskItem>() ?? [],
          dayNotes: (data['day_notes'] as List<dynamic>?)?.cast<DayNote>() ?? [],
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Yedek başarıyla geri yüklendi!')),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('İçe aktarma hatası: $e')),
        );
      }
    }
  }
}
