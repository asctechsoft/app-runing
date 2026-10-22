import 'dart:convert';

import '../../utils/l10n.dart';

/// Loại bước trong giáo án interval (docs/domain-model.md: warmup/run/walk/rest/cooldown/repeat).
enum IntervalKind { warmup, run, walk, rest, cooldown, repeat }

String intervalKindLabel(IntervalKind k) => switch (k) {
  IntervalKind.warmup => 'model_interval_warmup'.tr,
  IntervalKind.run => 'model_interval_run'.tr,
  IntervalKind.walk => 'model_interval_walk'.tr,
  IntervalKind.rest => 'model_interval_rest'.tr,
  IntervalKind.cooldown => 'model_interval_cooldown'.tr,
  IntervalKind.repeat => 'model_interval_repeat'.tr,
};

String intervalKindHint(IntervalKind k) => switch (k) {
  IntervalKind.warmup => 'model_interval_hint_easy'.tr,
  IntervalKind.run => 'model_interval_hint_comfortable'.tr,
  IntervalKind.walk => 'model_interval_hint_easy'.tr,
  IntervalKind.rest => 'model_interval_hint_rest'.tr,
  IntervalKind.cooldown => 'model_interval_hint_easy'.tr,
  IntervalKind.repeat => '',
};

int _localKeySeed = 0;
String _newKey() => 'k${++_localKeySeed}';

/// Một bước của giáo án. Bước thường có [durationMs]; bước repeat có [repeat] và [children].
class IntervalStep {
  IntervalStep({required this.kind, this.durationMs, this.repeat = 1, List<IntervalStep>? children, String? key})
    : children = children ?? const [],
      key = key ?? _newKey();

  /// Khóa cục bộ cho reorder trong editor (không lưu DB).
  final String key;
  final IntervalKind kind;
  final int? durationMs;
  final int repeat;
  final List<IntervalStep> children;

  bool get isRepeat => kind == IntervalKind.repeat;

  IntervalStep copyWith({IntervalKind? kind, int? durationMs, int? repeat, List<IntervalStep>? children}) => IntervalStep(
    kind: kind ?? this.kind,
    durationMs: durationMs ?? this.durationMs,
    repeat: repeat ?? this.repeat,
    children: children ?? this.children,
    key: key,
  );

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    if (!isRepeat) 'durationMs': durationMs,
    if (isRepeat) 'repeat': repeat,
    if (isRepeat) 'children': children.map((c) => c.toJson()).toList(),
  };

  factory IntervalStep.fromJson(Map<String, Object?> j) {
    final kind = IntervalKind.values.firstWhere((k) => k.name == j['kind'], orElse: () => IntervalKind.run);
    return IntervalStep(
      kind: kind,
      durationMs: (j['durationMs'] as num?)?.toInt(),
      repeat: (j['repeat'] as num?)?.toInt() ?? 1,
      children: (j['children'] as List?)?.map((c) => IntervalStep.fromJson((c as Map).cast<String, Object?>())).toList(),
    );
  }
}

/// Giáo án interval (preset lưu ở bảng workout_plans).
class WorkoutPlan {
  const WorkoutPlan({this.id, required this.name, required this.steps, this.audioCues = true});

  final String? id;
  final String name;
  final List<IntervalStep> steps;
  final bool audioCues;

  WorkoutPlan copyWith({String? id, String? name, List<IntervalStep>? steps, bool? audioCues}) =>
      WorkoutPlan(id: id ?? this.id, name: name ?? this.name, steps: steps ?? this.steps, audioCues: audioCues ?? this.audioCues);

  List<PlannedPhase> get phases => flattenPlan(steps);
  int get totalMs => planTotalMs(steps);

  /// Số khối lặp × lần (để hiển thị "6 intervals").
  int get intervalCount => steps.where((s) => s.isRepeat).fold(0, (a, s) => a + s.repeat);

  Map<String, Object?> toJson() => {'id': id, 'name': name, 'audioCues': audioCues, 'steps': steps.map((s) => s.toJson()).toList()};

  factory WorkoutPlan.fromJson(Map<String, Object?> j) => WorkoutPlan(
    id: j['id'] as String?,
    name: j['name'] as String? ?? 'model_workout_default_name'.tr,
    audioCues: j['audioCues'] as bool? ?? true,
    steps: ((j['steps'] as List?) ?? const []).map((s) => IntervalStep.fromJson((s as Map).cast<String, Object?>())).toList(),
  );

  String encode() => jsonEncode(toJson());
  static WorkoutPlan decode(String s) => WorkoutPlan.fromJson((jsonDecode(s) as Map).cast<String, Object?>());

  /// Giáo án mẫu theo mockup: 5 min warm-up + 6 × (2 min run + 1 min walk) + 5 min cool-down = 28 min.
  static WorkoutPlan starter() => WorkoutPlan(
    name: 'model_workout_default_name'.tr,
    steps: [
      IntervalStep(kind: IntervalKind.warmup, durationMs: 5 * 60000),
      IntervalStep(
        kind: IntervalKind.repeat,
        repeat: 6,
        children: [
          IntervalStep(kind: IntervalKind.run, durationMs: 2 * 60000),
          IntervalStep(kind: IntervalKind.walk, durationMs: 1 * 60000),
        ],
      ),
      IntervalStep(kind: IntervalKind.cooldown, durationMs: 5 * 60000),
    ],
  );
}

/// Một pha đã trải phẳng (repeat được mở ra) với mốc bắt đầu theo moving time.
class PlannedPhase {
  const PlannedPhase({required this.index, required this.kind, required this.plannedMs, required this.startMs, this.round, this.rounds});

  final int index;
  final IntervalKind kind;
  final int plannedMs;
  final int startMs;

  /// Lần lặp (1-based) nếu thuộc khối repeat.
  final int? round;
  final int? rounds;

  int get endMs => startMs + plannedMs;

  String get label => round == null ? intervalKindLabel(kind) : 'model_phase_round_of'.trArgs([intervalKindLabel(kind), round, rounds]);
}

/// Trải phẳng giáo án; bỏ qua bước không có thời lượng hợp lệ.
List<PlannedPhase> flattenPlan(List<IntervalStep> steps) {
  final out = <PlannedPhase>[];
  var t = 0;
  void add(IntervalStep s, {int? round, int? rounds}) {
    final d = s.durationMs ?? 0;
    if (d <= 0) return;
    out.add(PlannedPhase(index: out.length, kind: s.kind, plannedMs: d, startMs: t, round: round, rounds: rounds));
    t += d;
  }

  for (final s in steps) {
    if (s.isRepeat) {
      for (var r = 1; r <= s.repeat; r++) {
        for (final c in s.children) {
          if (!c.isRepeat) add(c, round: r, rounds: s.repeat);
        }
      }
    } else {
      add(s);
    }
  }
  return out;
}

int planTotalMs(List<IntervalStep> steps) => flattenPlan(steps).fold(0, (a, p) => a + p.plannedMs);

/// Vị trí trong giáo án theo moving time. [index] == phases.length nghĩa là đã xong.
class PhasePosition {
  const PhasePosition({required this.index, required this.elapsedInPhaseMs, required this.remainingMs});
  final int index;
  final int elapsedInPhaseMs;
  final int remainingMs;
}

/// Pha hiện tại xác định thuần bằng moving time — pause dừng tiến độ pha, recovery khôi phục đúng pha (K02).
PhasePosition phaseAt(List<PlannedPhase> phases, int movingMs) {
  for (final p in phases) {
    if (movingMs < p.endMs) {
      final el = movingMs - p.startMs;
      return PhasePosition(index: p.index, elapsedInPhaseMs: el < 0 ? 0 : el, remainingMs: p.endMs - movingMs);
    }
  }
  return PhasePosition(index: phases.length, elapsedInPhaseMs: 0, remainingMs: 0);
}

/// Kết quả một pha: planned vs actual (K03).
class PhaseResult {
  const PhaseResult({
    required this.index,
    required this.kind,
    required this.label,
    required this.plannedMs,
    required this.actualMs,
    this.distanceM,
    required this.completed,
  });

  final int index;
  final IntervalKind kind;
  final String label;
  final int plannedMs;
  final int actualMs;
  final double? distanceM;
  final bool completed;

  Map<String, Object?> toJson() => {
    'index': index,
    'kind': kind.name,
    'label': label,
    'plannedMs': plannedMs,
    'actualMs': actualMs,
    'distanceM': distanceM,
    'completed': completed,
  };

  factory PhaseResult.fromJson(Map<String, Object?> j) => PhaseResult(
    index: (j['index'] as num).toInt(),
    kind: IntervalKind.values.firstWhere((k) => k.name == j['kind'], orElse: () => IntervalKind.run),
    label: j['label'] as String? ?? '',
    plannedMs: (j['plannedMs'] as num?)?.toInt() ?? 0,
    actualMs: (j['actualMs'] as num?)?.toInt() ?? 0,
    distanceM: (j['distanceM'] as num?)?.toDouble(),
    completed: j['completed'] as bool? ?? false,
  );
}

/// Tính kết quả từng pha từ tổng moving time và quãng đường ghi tại lúc mỗi pha bắt đầu.
/// [distanceAtStart]: index pha → quãng đường (m) khi pha bắt đầu (từ event phaseStart). Thiếu → distance null.
/// Tổng actualMs ≤ movingMs; bằng movingMs khi chưa chạy quá giáo án.
List<PhaseResult> computePhaseResults(List<PlannedPhase> phases, {required int movingMs, Map<int, double> distanceAtStart = const {}, double? totalDistanceM}) {
  final out = <PhaseResult>[];
  for (final p in phases) {
    var actual = movingMs - p.startMs;
    if (actual < 0) actual = 0;
    if (actual > p.plannedMs) actual = p.plannedMs;
    double? dist;
    final start = distanceAtStart[p.index];
    if (start != null && actual > 0) {
      // Mốc kết thúc = lúc pha sau bắt đầu (phaseStart index+1; index == phases.length là mốc "xong giáo án").
      // Pha đang dở dùng tổng hiện tại; pha đã qua mà thiếu mốc thì để null thay vì đoán.
      final next = distanceAtStart[p.index + 1] ?? (movingMs < p.endMs ? totalDistanceM : null);
      if (next != null && next >= start) dist = next - start;
    }
    out.add(
      PhaseResult(index: p.index, kind: p.kind, label: p.label, plannedMs: p.plannedMs, actualMs: actual, distanceM: dist, completed: actual >= p.plannedMs),
    );
  }
  return out;
}

/// Thời lượng gọn cho editor: "5 min", "1 min 30 s", "45 s".
String formatStepDuration(int ms) {
  final s = ms ~/ 1000;
  final m = s ~/ 60;
  final r = s % 60;
  if (m == 0) return 'fmt_step_sec'.trArgs([r]);
  if (r == 0) return 'fmt_step_min'.trArgs([m]);
  return 'fmt_step_min_sec'.trArgs([m, r]);
}
