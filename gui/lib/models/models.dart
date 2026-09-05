/// エンジン（Python）が書き出す JSON と 1:1 に対応するモデル。
/// 変換は手書き。未知のフィールドは読み捨てず `extra` に保持して書き戻す。
library;

class Line {
  Line({
    required this.panel,
    required this.speaker,
    required this.text,
    required this.confidence,
    this.basis,
    this.x,
    this.y,
    this.manual = false,
    Map<String, dynamic>? extra,
  }) : extra = extra ?? {};

  int panel;
  String speaker;
  String text;
  double confidence;
  String? basis;
  double? x;
  double? y;
  bool manual;
  final Map<String, dynamic> extra;

  static const _known = {'panel', 'speaker', 'text', 'confidence', 'basis', 'x', 'y', 'manual'};

  factory Line.fromJson(Map<String, dynamic> j) => Line(
        panel: (j['panel'] as num).toInt(),
        speaker: j['speaker'] as String,
        text: j['text'] as String,
        confidence: (j['confidence'] as num).toDouble(),
        basis: j['basis'] as String?,
        x: (j['x'] as num?)?.toDouble(),
        y: (j['y'] as num?)?.toDouble(),
        manual: j['manual'] as bool? ?? false,
        extra: {for (final e in j.entries) if (!_known.contains(e.key)) e.key: e.value},
      );

  Map<String, dynamic> toJson() => {
        'panel': panel,
        'speaker': speaker,
        'text': text,
        'confidence': confidence,
        'basis': basis,
        'x': x,
        'y': y,
        'manual': manual,
        ...extra,
      };

  Line copy() => Line.fromJson(toJson());
}

class PageResult {
  PageResult({
    required this.volume,
    required this.page,
    required this.image,
    required this.lines,
    this.repassed = false,
    this.manual = false,
    Map<String, dynamic>? extra,
  }) : extra = extra ?? {};

  int volume;
  int page;
  String image;
  List<Line> lines;
  bool repassed;
  bool manual;
  final Map<String, dynamic> extra;

  static const _known = {'volume', 'page', 'image', 'lines', 'repassed', 'manual'};

  factory PageResult.fromJson(Map<String, dynamic> j) => PageResult(
        volume: (j['volume'] as num?)?.toInt() ?? 1,
        page: (j['page'] as num).toInt(),
        image: j['image'] as String,
        lines: [for (final l in (j['lines'] as List)) Line.fromJson(l as Map<String, dynamic>)],
        repassed: j['repassed'] as bool? ?? false,
        manual: j['manual'] as bool? ?? false,
        extra: {for (final e in j.entries) if (!_known.contains(e.key)) e.key: e.value},
      );

  Map<String, dynamic> toJson() => {
        'volume': volume,
        'page': page,
        'image': image,
        'lines': [for (final l in lines) l.toJson()],
        ...extra,
        'repassed': repassed,
        'manual': manual,
      };

  bool get isLocked => manual || lines.any((l) => l.manual);
  int get unknownCount => lines.where((l) => l.speaker == '不明').length;
}

class Character {
  Character({required this.name, List<String>? aliases, this.appearance = ''}) : aliases = aliases ?? [];

  String name;
  List<String> aliases;
  String appearance;

  factory Character.fromJson(Map<String, dynamic> j) => Character(
        name: j['name'] as String,
        aliases: [for (final a in (j['aliases'] as List? ?? [])) a as String],
        appearance: j['appearance'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {'name': name, 'aliases': aliases, 'appearance': appearance};
  bool get isProvisional => name.contains('（仮）');

  /// 人が付けた別名（表示・編集の対象）
  List<String> get displayAliases => aliases.where((a) => !a.contains('（仮）')).toList();

  /// 統合前の仮名。同じ仮名で再登録されるのを防ぐためにデータとしては残す
  List<String> get mergedAliases => aliases.where((a) => a.contains('（仮）')).toList();
}

/// 話者として選べる固定の値
const specialSpeakers = ['不明', 'ナレーション', '文字'];

/// 台帳に昇格する前の仮名候補（candidates.json）
class Candidate {
  Candidate({required this.name, this.appearance = '', List<Map<String, dynamic>>? seen, Map<String, dynamic>? extra})
      : seen = seen ?? [],
        extra = extra ?? {};
  String name;
  String appearance;
  List<Map<String, dynamic>> seen;
  final Map<String, dynamic> extra;

  int get pageCount => seen.length;

  factory Candidate.fromJson(Map<String, dynamic> j) => Candidate(
        name: j['name'] as String,
        appearance: j['appearance'] as String? ?? '',
        seen: [for (final s in (j['seen'] as List? ?? [])) Map<String, dynamic>.from(s as Map)],
        extra: {for (final e in j.entries) if (!{'name', 'appearance', 'seen'}.contains(e.key)) e.key: e.value},
      );

  Map<String, dynamic> toJson() => {'name': name, 'appearance': appearance, 'seen': seen, ...extra};
}
