/// Trạng thái bước của một ngày — tách biệt "không có dữ liệu" với "0 thật" (F05).
enum StepDayStatus { noPermission, noData, verifiedZero, populated }

enum StepSource { phoneSensor, healthConnect, healthKit, device }

class StepSample {
  const StepSample({
    required this.id,
    required this.ownerId,
    required this.source,
    required this.startAt,
    required this.endAt,
    required this.steps,
    required this.tzId,
    this.sourceId,
  });

  final String id;
  final String ownerId;
  final StepSource source;

  /// ID nguồn cụ thể (vd. device id) để dedup.
  final String? sourceId;
  final int startAt;
  final int endAt;
  final int steps;
  final String tzId;

  Map<String, Object?> toRow() => {
    'id': id,
    'owner_id': ownerId,
    'source': source.name,
    'source_id': sourceId,
    'start_at': startAt,
    'end_at': endAt,
    'steps': steps,
    'tz_id': tzId,
  };
  factory StepSample.fromRow(Map<String, Object?> r) => StepSample(
    id: r['id'] as String,
    ownerId: r['owner_id'] as String,
    source: StepSource.values.firstWhere((s) => s.name == r['source'], orElse: () => StepSource.phoneSensor),
    sourceId: r['source_id'] as String?,
    startAt: r['start_at'] as int,
    endAt: r['end_at'] as int,
    steps: r['steps'] as int,
    tzId: r['tz_id'] as String? ?? 'UTC',
  );
}

class StepDay {
  const StepDay({required this.date, required this.status, this.steps, this.hourly, this.lastSampleAt, this.sourceUsed});

  /// Ngày địa phương YYYY-MM-DD.
  final String date;
  final StepDayStatus status;

  /// null khi noPermission/noData.
  final int? steps;

  /// 24 phần tử; null ở giờ không có mẫu.
  final List<int?>? hourly;
  final int? lastSampleAt;
  final StepSource? sourceUsed;

  bool get hasValue => status == StepDayStatus.populated || status == StepDayStatus.verifiedZero;
}
