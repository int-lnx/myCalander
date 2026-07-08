import 'package:uuid/uuid.dart';

class IdGenerator {
  static const Uuid _uuid = Uuid();

  /// Benzersiz bir ID üretir. Eğer isim ve tarih verilirse, anlamlı bir ID oluşturur.
  static String generate(String prefix, {DateTime? date}) {
    final cleanPrefix = prefix.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_').toLowerCase();
    if (date != null) {
      final dateStr = "${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}";
      return "${cleanPrefix}_${dateStr}_${_uuid.v4().substring(0, 8)}";
    }
    return "${cleanPrefix}_${_uuid.v4()}";
  }
}
