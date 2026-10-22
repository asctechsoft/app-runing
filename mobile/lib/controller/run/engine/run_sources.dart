import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../../utils/logger.dart';
import '../../providers.dart';
import '../../../models/data_models/activity.dart';
import '../../../services/application/step_tracking_service.dart';

/// Một fix vị trí thô từ OS. [t] là UTC ms của fix.
class RawFix {
  const RawFix({required this.t, required this.lat, required this.lon, this.accuracyM, this.altitudeM, this.speedMps});

  final int t;
  final double lat;
  final double lon;
  final double? accuracyM;
  final double? altitudeM;
  final double? speedMps;
}

/// Chất lượng GPS hiển thị ở prepare/live (G01, G09).
enum GpsQuality { searching, good, weak, lost, notUsed }

/// Ngưỡng hiển thị: ≤ 20 m là Good, lớn hơn là Weak.
GpsQuality qualityForAccuracy(double? accuracyM) {
  if (accuracyM == null) return GpsQuality.weak;
  return accuracyM <= 20 ? GpsQuality.good : GpsQuality.weak;
}

/// Nguồn vị trí — tách khỏi engine để test bằng fixture (G03).
abstract class RunLocationSource {
  /// Stream xem trước ở màn chuẩn bị (không bật foreground service, không ghi).
  Stream<RawFix> previewPositions();

  /// Stream ghi chính thức: Android foreground notification + wake lock, iOS background updates.
  Stream<RawFix> recordingPositions(ActivityType type);

  Future<RawFix?> lastKnown();

  Future<bool> openLocationSettings();
}

class GeolocatorRunLocationSource implements RunLocationSource {
  geo.LocationSettings _settings({required bool recording}) {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return geo.AndroidSettings(
        accuracy: geo.LocationAccuracy.best,
        distanceFilter: 0,
        intervalDuration: const Duration(seconds: 1),
        foregroundNotificationConfig: recording
            ? const geo.ForegroundNotificationConfig(
                notificationTitle: 'STRIDE is recording your activity',
                notificationText: 'Location is used only while this activity is recording.',
                notificationChannelName: 'Activity recording',
                enableWakeLock: true,
                setOngoing: true,
              )
            : null,
      );
    }
    if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS)) {
      return geo.AppleSettings(
        accuracy: geo.LocationAccuracy.bestForNavigation,
        activityType: geo.ActivityType.fitness,
        distanceFilter: 0,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: recording,
        allowBackgroundLocationUpdates: recording,
      );
    }
    return const geo.LocationSettings(accuracy: geo.LocationAccuracy.best, distanceFilter: 0);
  }

  RawFix _map(geo.Position p) => RawFix(
    t: p.timestamp.millisecondsSinceEpoch,
    lat: p.latitude,
    lon: p.longitude,
    accuracyM: p.accuracy <= 0 ? null : p.accuracy,
    altitudeM: p.altitude == 0 ? null : p.altitude,
    speedMps: p.speed < 0 ? null : p.speed,
  );

  @override
  Stream<RawFix> previewPositions() => geo.Geolocator.getPositionStream(locationSettings: _settings(recording: false)).map(_map);

  @override
  Stream<RawFix> recordingPositions(ActivityType type) => geo.Geolocator.getPositionStream(locationSettings: _settings(recording: true)).map(_map);

  @override
  Future<RawFix?> lastKnown() async {
    try {
      final p = await geo.Geolocator.getLastKnownPosition();
      return p == null ? null : _map(p);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> openLocationSettings() => geo.Geolocator.openLocationSettings();
}

final runLocationSourceProvider = Provider<RunLocationSource>((ref) => GeolocatorRunLocationSource());

/// Bước trong lúc chạy: chỉ là "view" trên cùng dữ liệu bước hằng ngày (step_samples),
/// nên bước trong run không bao giờ cộng thêm lần hai vào tổng ngày.
abstract class RunStepSource {
  /// Phát tổng bước kể từ [fromMs] (UTC); null khi không có quyền/cảm biến.
  Stream<int?> watchSteps(String ownerId, int fromMs);
}

/// Cộng step_samples phần nằm trong [fromMs, now], chia tỉ lệ mẫu cắt ngang mốc bắt đầu.
int stepsSince(Iterable<({int startAt, int endAt, int steps})> samples, int fromMs, int toMs) {
  var total = 0.0;
  for (final s in samples) {
    final a = s.startAt < fromMs ? fromMs : s.startAt;
    final b = s.endAt > toMs ? toMs : s.endAt;
    if (b <= a) continue;
    final span = s.endAt - s.startAt;
    total += span <= 0 ? s.steps : s.steps * (b - a) / span;
  }
  return total.round();
}

class RepositoryRunStepSource implements RunStepSource {
  RepositoryRunStepSource(this._ref);
  final Ref _ref;

  @override
  Stream<int?> watchSteps(String ownerId, int fromMs) async* {
    final tracking = _ref.read(stepTrackingServiceProvider);
    StepTrackingStatus status;
    try {
      status = await tracking.start();
    } catch (e, st) {
      StrideLog.e('run.steps', e, st);
      status = StepTrackingStatus.unavailable;
    }
    if (status != StepTrackingStatus.running) {
      yield null;
      return;
    }
    final repo = _ref.read(stepRepositoryProvider);
    final clock = _ref.read(clockProvider);
    Future<int> read() async {
      final samples = await repo.samplesBetween(ownerId, fromMs, clock.nowMs());
      return stepsSince(samples.map((s) => (startAt: s.startAt, endAt: s.endAt, steps: s.steps)), fromMs, clock.nowMs());
    }

    yield await read();
    await for (final owner in repo.changes) {
      if (owner == ownerId) yield await read();
    }
  }
}

final runStepSourceProvider = Provider<RunStepSource>((ref) => RepositoryRunStepSource(ref));

/// Sao chép ảnh vào thư mục tài liệu của app để ảnh không mất khi file gốc bị xóa.
abstract class RunPhotoStore {
  Future<({String path, int bytes})> importPhoto(String sourcePath, String activityId);
}

class DocumentsRunPhotoStore implements RunPhotoStore {
  @override
  Future<({String path, int bytes})> importPhoto(String sourcePath, String activityId) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'activity_photos', activityId));
    await dir.create(recursive: true);
    final ext = p.extension(sourcePath).isEmpty ? '.jpg' : p.extension(sourcePath);
    final dest = p.join(dir.path, '${const Uuid().v4()}$ext');
    final f = await File(sourcePath).copy(dest);
    return (path: f.path, bytes: await f.length());
  }
}

final runPhotoStoreProvider = Provider<RunPhotoStore>((ref) => DocumentsRunPhotoStore());

/// Đoán mime từ đuôi file ảnh.
String mimeForPath(String path) => switch (p.extension(path).toLowerCase()) {
  '.png' => 'image/png',
  '.heic' => 'image/heic',
  '.webp' => 'image/webp',
  _ => 'image/jpeg',
};

/// Tắt layer tile (test widget không có mạng).
final runMapTilesEnabledProvider = Provider<bool>((ref) => true);
