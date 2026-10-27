import 'package:stride/models/data_models/activity.dart';
import 'package:stride/repository/activity_repository.dart';
import 'package:stride/utils/calc/geo.dart';
import 'package:uuid/uuid.dart';

/// Fixture dùng chung cho test history/activity/progress.

int _n = 0;

/// Lưu thẳng một hoạt động đã chốt (status saved) qua repository.
Future<Activity> saveFixtureActivity(
  ActivityRepository repo, {
  required String owner,
  required DateTime start,
  double? distanceM = 5000,
  int movingMs = 1800000,
  ActivityType type = ActivityType.run,
  bool hasGps = true,
  DistanceSource source = DistanceSource.gps,
  String? id,
  String title = '',
  double? avgPace,
  bool silent = false,
}) async {
  final startMs = start.millisecondsSinceEpoch;
  final a = Activity(
    id: id ?? '${(_n++).toString().padLeft(6, '0')}-${const Uuid().v4()}',
    ownerId: owner,
    type: type,
    status: ActivityStatus.saved,
    startedAt: startMs,
    endedAt: startMs + movingMs,
    tzId: 'UTC',
    tzOffsetMin: start.timeZoneOffset.inMinutes,
    distanceM: distanceM,
    movingMs: movingMs,
    elapsedMs: movingMs,
    avgPaceSecPerKm: avgPace,
    title: title,
    hasGps: hasGps,
    distanceSource: source,
    createdAt: startMs,
    updatedAt: startMs,
  );
  // silent: ghi thẳng không phát change (để thêm track trước rồi mới notifyChanged).
  if (silent) {
    await repo.raw.insert('activities', a.toRow());
    return a;
  }
  return repo.saveActivity(a, enqueueSync: false);
}

/// Điểm thẳng theo hướng [bearing]: mỗi [stepM] mét một điểm, mỗi điểm cách [msPerStep].
List<(double, double, int)> straightTrack({
  double lat = 21.0285,
  double lon = 105.8542,
  double bearing = 90,
  required double meters,
  double stepM = 10,
  required int startT,
  int msPerStep = 3000,
}) {
  final out = <(double, double, int)>[];
  final n = (meters / stepM).round();
  for (var i = 0; i <= n; i++) {
    final (la, lo) = offsetPoint(lat, lon, i * stepM, bearing);
    out.add((la, lo, startT + i * msPerStep));
  }
  return out;
}

/// Ghi track: mỗi phần tử ngoài là một segment; [rejectedEvery] đánh dấu điểm bị loại để kiểm tra lọc.
Future<List<TrackPoint>> addFixtureTrack(
  ActivityRepository repo,
  Activity a,
  List<List<(double, double, int)>> segments, {
  double? altitude,
  int rejectedEvery = 0,
}) async {
  final pts = <TrackPoint>[];
  var seq = 0;
  for (var s = 0; s < segments.length; s++) {
    final segId = '${a.id}-seg$s';
    await repo.raw.insert(
      'track_segments',
      TrackSegment(id: segId, activityId: a.id, seq: s, startedAt: segments[s].first.$3, reason: SegmentReason.start).toRow(),
    );
    for (var i = 0; i < segments[s].length; i++) {
      final (la, lo, t) = segments[s][i];
      final rejected = rejectedEvery > 0 && i % rejectedEvery == rejectedEvery - 1;
      pts.add(
        TrackPoint(
          activityId: a.id,
          segmentId: segId,
          seq: seq++,
          t: t,
          lat: la,
          lon: lo,
          accuracyM: 5,
          altitudeM: altitude,
          accepted: !rejected,
          rejectReason: rejected ? 'accuracy' : null,
        ),
      );
    }
  }
  await repo.insertPoints(pts);
  return pts;
}
