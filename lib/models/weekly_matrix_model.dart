class WeeklyKeywordRule {
  final String id;
  final String keyword;
  final int colorValue;
  final String? linkedProjectId;
  final String? linkedTag;
  final int? notificationMinutesBefore;

  const WeeklyKeywordRule({
    required this.id,
    required this.keyword,
    required this.colorValue,
    this.linkedProjectId,
    this.linkedTag,
    this.notificationMinutesBefore,
  });

  WeeklyKeywordRule copyWith({
    String? id,
    String? keyword,
    int? colorValue,
    String? linkedProjectId,
    String? linkedTag,
    int? notificationMinutesBefore,
    bool clearLinkedProject = false,
    bool clearLinkedTag = false,
    bool clearNotification = false,
  }) {
    return WeeklyKeywordRule(
      id: id ?? this.id,
      keyword: keyword ?? this.keyword,
      colorValue: colorValue ?? this.colorValue,
      linkedProjectId: clearLinkedProject
          ? null
          : (linkedProjectId ?? this.linkedProjectId),
      linkedTag: clearLinkedTag ? null : (linkedTag ?? this.linkedTag),
      notificationMinutesBefore: clearNotification
          ? null
          : (notificationMinutesBefore ?? this.notificationMinutesBefore),
    );
  }

  String? get notificationLabel {
    if (notificationMinutesBefore == null) return null;
    final mins = notificationMinutesBefore!;
    if (mins == 0) return 'Tam vaktinde';
    if (mins < 60) return '$mins dk önce';
    if (mins == 60) return '1 saat önce';
    if (mins == 120) return '2 saat önce';
    if (mins == 1440) return '1 gün önce';
    if (mins % 1440 == 0) return '${mins ~/ 1440} gün önce';
    if (mins % 60 == 0) return '${mins ~/ 60} saat önce';
    return '$mins dk önce';
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'keyword': keyword,
      'colorValue': colorValue,
      'linkedProjectId': linkedProjectId,
      'linkedTag': linkedTag,
      'notificationMinutesBefore': notificationMinutesBefore,
    };
  }

  factory WeeklyKeywordRule.fromJson(Map<String, dynamic> json) {
    return WeeklyKeywordRule(
      id: json['id'] as String? ?? '',
      keyword: json['keyword'] as String? ?? '',
      colorValue: (json['colorValue'] as num?)?.toInt() ?? 0xFF2196F3,
      linkedProjectId: json['linkedProjectId'] as String?,
      linkedTag: json['linkedTag'] as String?,
      notificationMinutesBefore: (json['notificationMinutesBefore'] as num?)?.toInt(),
    );
  }
}

class WeeklyCellSegment {
  final String title;
  final double ratio; // 0.0 .. 1.0
  final int? durationMinutes;
  final int? startMinute;
  final int? endMinute;
  final bool isGap;

  const WeeklyCellSegment({
    required this.title,
    required this.ratio,
    this.durationMinutes,
    this.startMinute,
    this.endMinute,
    this.isGap = false,
  });

  String get cleanLabel {
    if (isGap || title.trim().isEmpty) return '';
    if (durationMinutes != null && durationMinutes! < 60) {
      return '${title.trim()} (${durationMinutes}dk)';
    }
    return title.trim();
  }
}

class _RawParsedPart {
  final String title;
  final int? startMin;
  final int? endMin;
  final int? durationMin;
  final bool isRange;

  const _RawParsedPart({
    required this.title,
    this.startMin,
    this.endMin,
    this.durationMin,
    this.isRange = false,
  });
}

class WeeklyFormulaParser {
  // Örnek 1 (Aralık): 00-İş:-30 // 30-eve dönüş:-40 // 40-spor:
  // Örnek 2 (Süre): iş::30 // spor::15 // kitap::15
  // Örnek 3 (Eşit): ev // yemek
  static final RegExp _rangeWithEndRegex = RegExp(
    r'^(\d{1,2})\s*-\s*(.+?)\s*(?::-|[-:])\s*(\d{1,2})\s*:?\s*$',
  );
  static final RegExp _rangeOpenEndRegex = RegExp(
    r'^(\d{1,2})\s*-\s*(.+?)\s*:?\s*$',
  );
  static final RegExp _durationRegex = RegExp(r'^(.+?)\s*::\s*(\d{1,3})\s*$');

  static List<WeeklyCellSegment> parse(String rawText) {
    final trimmed = rawText.trim();
    if (trimmed.isEmpty) return const [];

    final parts = trimmed
        .split('//')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    if (parts.isEmpty) return const [];

    final List<_RawParsedPart> parsedParts = [];
    bool hasAnyRange = false;
    bool hasAnyDuration = false;

    for (final part in parts) {
      final rangeEndMatch = _rangeWithEndRegex.firstMatch(part);
      if (rangeEndMatch != null) {
        final start = int.tryParse(rangeEndMatch.group(1)!)?.clamp(0, 60) ?? 0;
        var rawTitle = rangeEndMatch.group(2)!.trim();
        if (rawTitle.endsWith(':')) {
          rawTitle = rawTitle.substring(0, rawTitle.length - 1).trim();
        }
        final end = int.tryParse(rangeEndMatch.group(3)!)?.clamp(0, 60) ?? 60;
        final dur = (end > start) ? (end - start) : 0;
        parsedParts.add(
          _RawParsedPart(
            title: rawTitle,
            startMin: start,
            endMin: end,
            durationMin: dur,
            isRange: true,
          ),
        );
        hasAnyRange = true;
        continue;
      }

      final durationMatch = _durationRegex.firstMatch(part);
      if (durationMatch != null) {
        final rawTitle = durationMatch.group(1)!.trim();
        final dur = int.tryParse(durationMatch.group(2)!)?.clamp(1, 600) ?? 15;
        parsedParts.add(
          _RawParsedPart(title: rawTitle, durationMin: dur, isRange: false),
        );
        hasAnyDuration = true;
        continue;
      }

      final rangeOpenMatch = _rangeOpenEndRegex.firstMatch(part);
      if (rangeOpenMatch != null) {
        final start = int.tryParse(rangeOpenMatch.group(1)!)?.clamp(0, 59) ?? 0;
        var rawTitle = rangeOpenMatch.group(2)!.trim();
        while (rawTitle.endsWith(':') || rawTitle.endsWith('-')) {
          rawTitle = rawTitle.substring(0, rawTitle.length - 1).trim();
        }
        if (rawTitle.isNotEmpty) {
          parsedParts.add(
            _RawParsedPart(
              title: rawTitle,
              startMin: start,
              endMin:
                  null, // Sonradan bir sonraki başlangıca veya 60'a tamamlanır
              isRange: true,
            ),
          );
          hasAnyRange = true;
          continue;
        }
      }

      // Düz metin
      parsedParts.add(_RawParsedPart(title: part));
    }

    // 1. Durum: Aralık (Range) bazlı ifadeler varsa
    if (hasAnyRange) {
      // Açık uçlu bitişleri (örn: 40-spor:) kendinden sonraki parçanın başlangıcı veya 60 ile doldur
      final List<_RawParsedPart> resolved = [];
      for (int i = 0; i < parsedParts.length; i++) {
        final p = parsedParts[i];
        if (p.isRange) {
          final start = p.startMin ?? 0;
          int end = p.endMin ?? 60;
          if (p.endMin == null) {
            // Sonraki range parçasının başlangıcı varsa onu bitiş al
            for (int j = i + 1; j < parsedParts.length; j++) {
              if (parsedParts[j].startMin != null &&
                  parsedParts[j].startMin! > start) {
                end = parsedParts[j].startMin!;
                break;
              }
            }
          }
          final dur = (end > start) ? (end - start) : (60 - start).clamp(1, 60);
          resolved.add(
            _RawParsedPart(
              title: p.title,
              startMin: start,
              endMin: start + dur,
              durationMin: dur,
              isRange: true,
            ),
          );
        } else {
          resolved.add(p);
        }
      }

      // Eğer tüm parçalar range ise ve toplam süre 60 dk içinde yerleşiyorsa boşlukları da kontrol et
      final allAreRanges = resolved.every((p) => p.isRange);
      if (allAreRanges) {
        final List<WeeklyCellSegment> segments = [];
        int currentCursor = 0;
        for (final p in resolved) {
          final st = p.startMin ?? currentCursor;
          final en = p.endMin ?? 60;
          final dur = (en > st) ? (en - st) : 0;
          if (dur <= 0) continue;

          if (st > currentCursor && resolved.length == 1) {
            // Tek bir aralık girilmiş ve 00'dan başlamıyorsa (örn: 30-İş:-60) ön boşluk bırak
            final gapDur = st - currentCursor;
            segments.add(
              WeeklyCellSegment(
                title: '',
                ratio: gapDur / 60.0,
                durationMinutes: gapDur,
                startMinute: currentCursor,
                endMinute: st,
                isGap: true,
              ),
            );
          }

          segments.add(
            WeeklyCellSegment(
              title: p.title,
              ratio: dur / 60.0,
              durationMinutes: dur,
              startMinute: st,
              endMinute: en,
            ),
          );
          currentCursor = en;
        }

        if (resolved.length == 1 && currentCursor < 60 && currentCursor > 0) {
          final gapDur = 60 - currentCursor;
          segments.add(
            WeeklyCellSegment(
              title: '',
              ratio: gapDur / 60.0,
              durationMinutes: gapDur,
              startMinute: currentCursor,
              endMinute: 60,
              isGap: true,
            ),
          );
        }

        // Oranları normalize et
        final totalRatio = segments.fold<double>(0.0, (s, e) => s + e.ratio);
        if (totalRatio > 0) {
          return segments
              .map(
                (s) => WeeklyCellSegment(
                  title: s.title,
                  ratio: s.ratio / totalRatio,
                  durationMinutes: s.durationMinutes,
                  startMinute: s.startMinute,
                  endMinute: s.endMinute,
                  isGap: s.isGap,
                ),
              )
              .toList();
        }
      }

      // Karışık (hem range hem düz metin) varsa süreler üzerinden oranla
      final knownSum = resolved
          .where((p) => p.durationMin != null)
          .fold<int>(0, (s, p) => s + p.durationMin!);
      final unknownCount = resolved.where((p) => p.durationMin == null).length;
      final remaining = (60 - knownSum).clamp(0, 60);
      final defaultUnknownDur = unknownCount > 0
          ? (remaining > 0 ? (remaining / unknownCount).round() : 15)
          : 0;

      final List<int> durs = resolved
          .map((p) => p.durationMin ?? defaultUnknownDur)
          .toList();
      final totalDur = durs.fold<int>(0, (a, b) => a + b);
      if (totalDur > 0) {
        return List.generate(resolved.length, (i) {
          return WeeklyCellSegment(
            title: resolved[i].title,
            ratio: durs[i] / totalDur,
            durationMinutes: durs[i],
            startMinute: resolved[i].startMin,
            endMinute: resolved[i].endMin,
          );
        });
      }
    }

    // 2. Durum: Süre (::) bazlı ifadeler varsa (örn: iş::30 // spor::15 // kitap::15)
    if (hasAnyDuration) {
      final knownSum = parsedParts
          .where((p) => p.durationMin != null)
          .fold<int>(0, (s, p) => s + p.durationMin!);
      final unknownCount = parsedParts
          .where((p) => p.durationMin == null)
          .length;
      final remaining = (60 - knownSum).clamp(0, 60);
      final defaultUnknownDur = unknownCount > 0
          ? (remaining > 0 ? (remaining / unknownCount).round() : 15)
          : 0;

      final List<int> durs = parsedParts
          .map((p) => p.durationMin ?? defaultUnknownDur)
          .toList();
      final totalDur = durs.fold<int>(0, (a, b) => a + b);

      // Eğer tek bir öğe varsa ve süresi < 60 ise (örn: iş::30), kalan kısmı boşluk yap
      if (parsedParts.length == 1 && totalDur > 0 && totalDur < 60) {
        return [
          WeeklyCellSegment(
            title: parsedParts.first.title,
            ratio: totalDur / 60.0,
            durationMinutes: totalDur,
          ),
          WeeklyCellSegment(
            title: '',
            ratio: (60 - totalDur) / 60.0,
            durationMinutes: 60 - totalDur,
            isGap: true,
          ),
        ];
      }

      if (totalDur > 0) {
        return List.generate(parsedParts.length, (i) {
          return WeeklyCellSegment(
            title: parsedParts[i].title,
            ratio: durs[i] / totalDur,
            durationMinutes: durs[i],
          );
        });
      }
    }

    // 3. Durum: Süresiz eşit dağılım (örn: ev // yemek veya tek kelime: İş)
    final count = parsedParts.length;
    final equalRatio = 1.0 / count;
    final equalMinutes = (60 / count).round();
    return parsedParts.map((p) {
      return WeeklyCellSegment(
        title: p.title,
        ratio: equalRatio,
        durationMinutes: count > 1 ? equalMinutes : null,
      );
    }).toList();
  }

  /// Düzenleme dışı temizlenmiş etiket görünümü:
  /// örn: "İş (30dk) • Eve Dönüş (10dk) • Spor (20dk)"
  static String formatCleanSummary(String rawText) {
    final segments = parse(rawText).where((s) => !s.isGap).toList();
    if (segments.isEmpty) return '';
    if (segments.length == 1) {
      return segments.first.cleanLabel;
    }
    return segments.map((s) => s.cleanLabel).join(' • ');
  }
}
