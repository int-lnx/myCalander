class CsvHandler {
  /// Bir veri listesini CSV formatında stringe dönüştürür.
  static String convertToCsv(List<List<dynamic>> rows) {
    return rows.map((row) {
      return row.map((field) {
        if (field == null) return '';
        final str = field.toString();
        // Eğer alanda virgül veya yeni satır varsa çift tırnak içine al
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
}
