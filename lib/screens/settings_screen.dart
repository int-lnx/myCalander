import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../utils/csv_handler.dart';
import '../services/backup_service.dart';
import '../models/project.dart';
import '../models/project_evaluation.dart';
import '../models/event.dart';
import '../models/task_item.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  void _exportEvaluations(BuildContext context, AppState appState) {
    final csv = CsvHandler.exportToCsv(appState.projects, appState.evaluations);
    
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Excel/CSV Dışa Aktar'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Aşağıdaki CSV formatındaki verileri kopyalayarak bir Excel veya metin dosyasına (.csv olarak) kaydedebilirsiniz.',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 12),
              Container(
                constraints: const BoxConstraints(maxHeight: 200),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    csv,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Kapat'),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.copy),
              label: const Text('Panoya Kopyala'),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: csv));
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Veriler başarıyla panoya kopyalandı!')),
                );
              },
            ),
          ],
        );
      },
    );
  }

  void _importEvaluations(BuildContext context, AppState appState) {
    final textController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Excel/CSV İçe Aktar'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Daha önce kopyaladığınız CSV formatındaki veriyi aşağıdaki alana yapıştırın:',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: textController,
                maxLines: 6,
                decoration: const InputDecoration(
                  hintText: 'Tarih,Proje 1 (ID:x),...\n2026-06-09,80 / 2s / Not...',
                  border: OutlineInputBorder(),
                ),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Vazgeç'),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.upload_file),
              label: const Text('Verileri Yükle'),
              onPressed: () {
                final input = textController.text.trim();
                if (input.isEmpty) return;

                try {
                  final imported = CsvHandler.importFromCsv(input, appState.projects);
                  if (imported.isNotEmpty) {
                    appState.importEvaluations(imported);
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('${imported.length} değerlendirme kaydı başarıyla geri yüklendi!')),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Hata: Geçerli veri bulunamadı veya format hatalı.')),
                    );
                  }
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Ayrıştırma hatası: $e')),
                  );
                }
              },
            ),
          ],
        );
      },
    );
  }

  void _confirmClearAllData(BuildContext context, AppState appState) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Tüm Verileri Kalıcı Olarak Sil?'),
          content: const Text(
            'Bu işlem yerel cihazınızdaki ve buluttaki (Firebase) tüm etkinlikleri, görevleri, projeleri, değerlendirmeleri ve ayarları kalıcı olarak silecektir. Bu işlem geri alınamaz!\n\nDevam etmek istiyor musunuz?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Vazgeç'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                Navigator.pop(context); // dialogu kapat
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (context) => const Center(
                    child: CircularProgressIndicator(),
                  ),
                );
                try {
                  await appState.clearAllUserData();
                  if (context.mounted) {
                    Navigator.pop(context); // yükleniyor ekranını kapat
                    appState.setCurrentTabIndex(0); // Takvim ekranına yönlendir
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Tüm verileriniz başarıyla sıfırlandı.'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    Navigator.pop(context); // yükleniyor ekranını kapat
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Hata oluştu: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              child: const Text('Tümünü Sil'),
            ),
          ],
        );
      },
    );
  }

  void _confirmDeleteAccount(BuildContext context, AppState appState) {
    final confirmationController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Hesabınızı Kalıcı Olarak Silmek İstiyor musunuz?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Bu işlem tüm verilerinizi kalıcı olarak silecek, kullanıcı eşleştirmenizi sıfırlayacak ve Google hesabınızla olan bu uygulama kaydını veritabanından tamamen silecektir. Bu işlem geri alınamaz!\n\nOnaylamak için lütfen aşağıdaki kutuya büyük harflerle "HESABIMI SİL" yazın:',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirmationController,
                decoration: const InputDecoration(
                  hintText: 'HESABIMI SİL',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Vazgeç'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade900,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                if (confirmationController.text.trim() != 'HESABIMI SİL') {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Lütfen doğrulamayı doğru şekilde girin.')),
                  );
                  return;
                }
                Navigator.pop(context); // dialogu kapat
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (context) => const Center(
                    child: CircularProgressIndicator(),
                  ),
                );
                try {
                  await appState.deleteUserAccount();
                  if (context.mounted) {
                    Navigator.pop(context); // yükleniyor ekranını kapat
                    appState.setCurrentTabIndex(0); // Takvim ekranına yönlendir
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Hesabınız ve tüm verileriniz kalıcı olarak silindi.'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    Navigator.pop(context); // yükleniyor ekranını kapat
                    String errMsg = e.toString();
                    if (errMsg.contains('requires-recent-login')) {
                      errMsg = 'Güvenlik nedeniyle hesabınızı silebilmemiz için yakın zamanda giriş yapmış olmanız gerekmektedir. Lütfen uygulamadan çıkıp tekrar giriş yapın, ardından tekrar deneyin.';
                    }
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Hata oluştu: $errMsg'),
                        backgroundColor: Colors.red,
                        duration: const Duration(seconds: 7),
                      ),
                    );
                  }
                }
              },
              child: const Text('Hesabı Kalıcı Olarak Sil'),
            ),
          ],
        );
      },
    );
  }


  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ayarlar'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          const Text(
            'Genel Ayarlar',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue),
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            title: const Text('Gece Modu (Karanlık Tema)'),
            subtitle: const Text('Uygulama genelinde koyu renk temasını etkinleştirin.'),
            value: appState.isDarkMode,
            onChanged: (bool value) {
              appState.toggleDarkMode();
            },
            secondary: Icon(
              appState.isDarkMode ? Icons.dark_mode : Icons.light_mode,
              color: appState.isDarkMode ? Colors.amber : Colors.blueGrey,
            ),
          ),
          ListTile(
            title: const Text('Haftanın İlk Günü'),
            subtitle: const Text('Takvim görünümünde haftanın hangi günle başlayacağını belirleyin.'),
            trailing: DropdownButton<int>(
              value: appState.firstDayOfWeek,
              items: const [
                DropdownMenuItem(value: 1, child: Text('Pazartesi')),
                DropdownMenuItem(value: 6, child: Text('Cumartesi')),
                DropdownMenuItem(value: 7, child: Text('Pazar')),
              ],
              onChanged: (value) {
                if (value != null) {
                  appState.updateFirstDayOfWeek(value);
                }
              },
            ),
          ),
          ListTile(
            title: const Text('Takvim Log Yazı Boyutu'),
            subtitle: const Text('Takvim hücrelerindeki log yazılarının boyutunu ölçeklendirin (Cihaza özeldir).'),
            trailing: DropdownButton<double>(
              value: appState.fontSizeMultiplier,
              items: const [
                DropdownMenuItem(value: 0.85, child: Text('Küçük (%85)')),
                DropdownMenuItem(value: 1.0, child: Text('Normal (%100)')),
                DropdownMenuItem(value: 1.15, child: Text('Büyük (%115)')),
                DropdownMenuItem(value: 1.3, child: Text('Büyük (%130)')),
                DropdownMenuItem(value: 1.6, child: Text('Çok Büyük (%160)')),
                DropdownMenuItem(value: 2.0, child: Text('Dev (%200)')),
                DropdownMenuItem(value: 2.5, child: Text('Maksimum (%250)')),
              ],
              onChanged: (value) {
                if (value != null) {
                  appState.updateFontSizeMultiplier(value);
                }
              },
            ),
          ),
          const Divider(),
          const SizedBox(height: 16),
          const Text(
            'Veri Yönetimi (Yedekleme & Excel)',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue),
          ),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.download_rounded, color: Colors.green),
            title: const Text('Aktivite Tablosunu Dışa Aktar'),
            subtitle: const Text('Tüm proje puanlarını, sürelerini ve notlarını Excel/CSV formatında kopyalayın.'),
            onTap: () => _exportEvaluations(context, appState),
          ),
          ListTile(
            leading: const Icon(Icons.upload_rounded, color: Colors.blue),
            title: const Text('Aktivite Tablosunu İçe Aktar'),
            subtitle: const Text('Kopyaladığınız CSV/Excel tablosundaki verileri geri yükleyin.'),
            onTap: () => _importEvaluations(context, appState),
          ),
          ListTile(
            leading: const Icon(Icons.delete_forever, color: Colors.red),
            title: const Text('Tüm Verilerimi Sil'),
            subtitle: const Text('Cihazdaki ve buluttaki tüm verilerinizi kalıcı olarak sıfırlayın.'),
            onTap: () => _confirmClearAllData(context, appState),
          ),
          if (appState.firebaseUser != null)
            ListTile(
              leading: Icon(Icons.person_remove, color: Colors.red.shade900),
              title: const Text('Hesabımı Sil'),
              subtitle: const Text('Tüm verilerinizi ve bulut üzerindeki kullanıcı hesabınızı kalıcı olarak silin.'),
              onTap: () => _confirmDeleteAccount(context, appState),
            ),
          const Divider(),

          const SizedBox(height: 16),
          // Bulut Senkronizasyonu
          Card(
            margin: const EdgeInsets.symmetric(vertical: 8.0),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.cloud_sync, color: Colors.blue),
                      const SizedBox(width: 8),
                      Text(
                        'Bulut Senkronizasyonu',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade800,
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  if (appState.firebaseUser == null) ...[
                    const Text(
                      'Verilerinizi bulutta yedeklemek ve diğer cihazlarınızla eşitlemek için giriş yapın.',
                      style: TextStyle(color: Colors.black54),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.login),
                        label: const Text('Google ile Giriş Yap'),
                        onPressed: () async {
                          try {
                            await appState.loginWithGoogle();
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Google Girişi Başarılı!')),
                            );
                          } catch (e) {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Giriş Hatası: $e')),
                            );
                          }
                        },
                      ),
                    ),
                  ] else ...[
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundImage: appState.firebaseUser!.photoURL != null
                              ? NetworkImage(appState.firebaseUser!.photoURL!)
                              : null,
                          child: appState.firebaseUser!.photoURL == null
                              ? const Icon(Icons.person)
                              : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                appState.firebaseUser!.displayName ?? 'Kullanıcı',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              Text(
                                appState.firebaseUser!.email ?? '',
                                style: const TextStyle(color: Colors.black54, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: () async {
                            await appState.logout();
                          },
                          child: const Text('Çıkış', style: TextStyle(color: Colors.red)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Otomatik Eşitle'),
                      subtitle: const Text('Her değişiklikte buluta kaydet'),
                      value: appState.autoSync,
                      onChanged: (bool value) {
                        appState.toggleAutoSync(value);
                      },
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Manuel Eşitleme:'),
                        appState.isSyncing
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : ElevatedButton.icon(
                                icon: const Icon(Icons.sync),
                                label: const Text('Şimdi Eşitle'),
                                onPressed: () async {
                                  await appState.syncDataWithFirebase();
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Eşitleme Tamamlandı!')),
                                  );
                                },
                              ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Veri Yedekleme & Geri Yükleme
          Card(
            margin: const EdgeInsets.symmetric(vertical: 8.0),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.backup, color: Colors.green),
                      const SizedBox(width: 8),
                      Text(
                        'Veri Yedekleme & Geri Yükleme',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.green.shade800,
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  const Text(
                    'Tüm verilerinizi (Takvim, Görevler, Projeler ve Değerlendirmeler) Excel/Sheets ile açılabilir CSV dosyaları ve sistem yedek JSON dosyası olarak cihazınızda yedekleyin veya eski bir yedekten geri yükleyin.',
                    style: TextStyle(color: Colors.black54, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green.shade50,
                            foregroundColor: Colors.green.shade800,
                          ),
                          icon: const Icon(Icons.share),
                          label: const Text('Yedek Paylaş'),
                          onPressed: () async {
                            try {
                              await BackupService.exportAndShareBackup(
                                projects: appState.projects,
                                evaluations: appState.evaluations,
                                events: appState.events,
                                tasks: appState.tasks,
                              );
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Yedekleme Dosyaları Paylaşıldı!')),
                              );
                            } catch (e) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Yedekleme Hatası: $e')),
                              );
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue.shade50,
                            foregroundColor: Colors.blue.shade800,
                          ),
                          icon: const Icon(Icons.file_open),
                          label: const Text('Geri Yükle'),
                          onPressed: () async {
                            try {
                              final data = await BackupService.importBackup();
                              if (data == null) return; // Canceled
                              
                              await appState.restoreBackup(
                                projects: List<Project>.from(data['projects']!),
                                evaluations: List<ProjectEvaluation>.from(data['evaluations']!),
                                events: List<Event>.from(data['events']!),
                                tasks: List<TaskItem>.from(data['tasks']!),
                              );
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Tüm Veriler Başarıyla Geri Yüklendi!')),
                              );
                            } catch (e) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Geri Yükleme Hatası: $e')),
                              );
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

