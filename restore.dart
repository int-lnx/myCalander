import 'dart:convert';
import 'dart:io';

void main() async {
  final transcriptPath =
      r'C:\Users\deneme\.gemini\antigravity-ide\brain\5d4606f9-fd46-4833-a99e-ac23811a54e1\.system_generated\logs\transcript_full.jsonl';
  final projectRoot =
      r'C:\Users\deneme\Desktop\Flutter-Deneme\1_deneme\my_plan';

  // filePath (lowercase) -> lineNumber -> code
  final fileChunks = <String, Map<int, String>>{};

  final lineRegex = RegExp(r'^(\d+): (.*)$');
  final filePathRegex = RegExp(r'File Path: `file:///([^`]+)`');

  final file = File(transcriptPath);
  final lines = await file.readAsLines(encoding: utf8);

  print('Total transcript lines: ${lines.length}');

  for (int i = 0; i < lines.length; i++) {
    final rawLine = lines[i];
    if (!rawLine.contains('"type":"VIEW_FILE"')) continue;

    Map<String, dynamic> obj;
    try {
      obj = json.decode(rawLine) as Map<String, dynamic>;
    } catch (e) {
      continue;
    }

    final content = obj['content'] as String?;
    if (content == null) continue;

    // Extract file path
    final fpMatch = filePathRegex.firstMatch(content);
    if (fpMatch == null) continue;
    final filePath = fpMatch.group(1)!.replaceAll('/', r'\').toLowerCase();

    // Extract code lines
    bool inCode = false;
    final codeLines = <int, String>{};
    for (final cl in content.split('\n')) {
      final trimmed = cl.trimRight();
      if (trimmed.startsWith('The following code')) {
        inCode = true;
        continue;
      }
      if (trimmed.startsWith('The above content')) {
        inCode = false;
        break;
      }
      if (!inCode) continue;

      final m = lineRegex.firstMatch(trimmed);
      if (m != null) {
        codeLines[int.parse(m.group(1)!)] = m.group(2)!;
      }
    }

    if (codeLines.isEmpty) continue;

    fileChunks.putIfAbsent(filePath, () => {});
    for (final kv in codeLines.entries) {
      fileChunks[filePath]![kv.key] = kv.value;
    }

    final name = filePath.split(r'\').last;
    print('  chunk L${i+1}: $name (${codeLines.length} lines)');
  }

  print('\nFiles collected: ${fileChunks.length}');
  for (final fp in fileChunks.keys) {
    print('  $fp -> ${fileChunks[fp]!.length} lines');
  }

  // Write files
  final projectPrefix =
      projectRoot.toLowerCase() + r'\';
  print('\nWriting files...');
  for (final fp in fileChunks.keys) {
    final chunks = fileChunks[fp]!;
    if (chunks.isEmpty) continue;

    final maxLine = chunks.keys.reduce((a, b) => a > b ? a : b);
    final sb = StringBuffer();
    for (int i = 1; i <= maxLine; i++) {
      sb.writeln(chunks[i] ?? '');
    }

    if (!fp.startsWith(projectPrefix)) {
      print('  SKIP (outside project): $fp');
      continue;
    }

    final relPath = fp.substring(projectPrefix.length);
    final outPath = '$projectRoot\\$relPath';
    final outFile = File(outPath);
    await outFile.parent.create(recursive: true);
    await outFile.writeAsString(sb.toString(), encoding: utf8);
    print('  OK: $relPath ($maxLine lines)');
  }

  print('\nDone!');
}
