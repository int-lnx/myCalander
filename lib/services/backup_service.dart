import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../utils/csv_handler.dart';

class BackupService {
  /// Verilen başlıklar ve satırları cihaza geçici bir CSV yedek dosyası olarak yazar.
  static Future<File> createBackupFile(String fileName, List<String> headers, List<List<dynamic>> data) async {
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/$fileName.csv');
    
    final List<List<dynamic>> csvData = [headers, ...data];
    final csvString = CsvHandler.convertToCsv(csvData);
    
    return await file.writeAsString(csvString);
  }
}
