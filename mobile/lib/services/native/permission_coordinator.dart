import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

/// Trạng thái quyền chuẩn hóa giữa nền tảng (E05).
enum PermStatus { unknown, granted, denied, blocked, restricted, limited }

enum PermKind {
  motion,
  location,
  locationAlways,
  notification,
  bluetooth,

  /// X20: app được miễn tối ưu pin (Android `isIgnoringBatteryOptimizations`). Chỉ KIỂM TRA; không xin bằng
  /// `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` (Google Play hạn chế quyền này) — hướng người dùng vào Cài đặt.
  batteryUnrestricted,
}

/// Xin quyền theo ngữ cảnh và kiểm tra lại khi app resume — không tin giá trị đã lưu.
abstract class PermissionCoordinator {
  Future<PermStatus> status(PermKind kind);
  Future<PermStatus> request(PermKind kind);
  Future<bool> openSettings();
  Future<bool> locationServiceEnabled();

  /// Phát khi trạng thái có thể đã đổi (gọi [refresh] khi app resume).
  Stream<void> get changes;
  void refresh();
}

class DevicePermissionCoordinator implements PermissionCoordinator {
  final _changes = StreamController<void>.broadcast();

  @override
  Stream<void> get changes => _changes.stream;

  @override
  void refresh() => _changes.add(null);

  ph.Permission _map(PermKind k) => switch (k) {
    PermKind.motion => ph.Permission.activityRecognition,
    PermKind.location => ph.Permission.locationWhenInUse,
    PermKind.locationAlways => ph.Permission.locationAlways,
    PermKind.notification => ph.Permission.notification,
    PermKind.bluetooth => ph.Permission.bluetoothConnect,
    PermKind.batteryUnrestricted => ph.Permission.ignoreBatteryOptimizations,
  };

  PermStatus _norm(ph.PermissionStatus s) => switch (s) {
    ph.PermissionStatus.granted => PermStatus.granted,
    ph.PermissionStatus.denied => PermStatus.denied,
    ph.PermissionStatus.permanentlyDenied => PermStatus.blocked,
    ph.PermissionStatus.restricted => PermStatus.restricted,
    ph.PermissionStatus.limited => PermStatus.limited,
    ph.PermissionStatus.provisional => PermStatus.limited,
  };

  @override
  Future<PermStatus> status(PermKind kind) async {
    // iOS không có tối ưu pin kiểu Android → coi như không bị hạn chế.
    if (kind == PermKind.batteryUnrestricted && defaultTargetPlatform != TargetPlatform.android) return PermStatus.granted;
    if (kind == PermKind.location) {
      // Vị trí gần đúng (iOS/Android 12+) → limited.
      final p = await Geolocator.checkPermission();
      if (p == LocationPermission.deniedForever) return PermStatus.blocked;
      if (p == LocationPermission.denied) return PermStatus.denied;
      try {
        final acc = await Geolocator.getLocationAccuracy();
        if (acc == LocationAccuracyStatus.reduced) return PermStatus.limited;
      } catch (_) {}
      return PermStatus.granted;
    }
    return _norm(await _map(kind).status);
  }

  @override
  Future<PermStatus> request(PermKind kind) async {
    // Không xin trực tiếp (xem PermKind.batteryUnrestricted): mở Cài đặt ứng dụng → Pin.
    if (kind == PermKind.batteryUnrestricted) {
      await openSettings();
      return status(kind);
    }
    if (kind == PermKind.location) {
      await Geolocator.requestPermission();
      final s = await status(kind);
      refresh();
      return s;
    }
    if (kind == PermKind.bluetooth) {
      final r = await [ph.Permission.bluetoothScan, ph.Permission.bluetoothConnect].request();
      refresh();
      return r.values.every((s) => s.isGranted) ? PermStatus.granted : _norm(r.values.first);
    }
    final s = _norm(await _map(kind).request());
    refresh();
    return s;
  }

  @override
  Future<bool> openSettings() => ph.openAppSettings();

  @override
  Future<bool> locationServiceEnabled() => Geolocator.isLocationServiceEnabled();
}

/// Bản giả cho test/UI preview.
class FakePermissionCoordinator implements PermissionCoordinator {
  FakePermissionCoordinator([Map<PermKind, PermStatus>? initial]) : statuses = {...?initial};
  final Map<PermKind, PermStatus> statuses;
  final _changes = StreamController<void>.broadcast();
  bool serviceEnabled = true;

  @override
  Stream<void> get changes => _changes.stream;
  @override
  void refresh() => _changes.add(null);
  @override
  Future<PermStatus> status(PermKind kind) async => statuses[kind] ?? PermStatus.unknown;
  @override
  Future<PermStatus> request(PermKind kind) async {
    final s = statuses[kind] ?? PermStatus.granted;
    statuses[kind] = s == PermStatus.unknown ? PermStatus.granted : s;
    refresh();
    return statuses[kind]!;
  }

  @override
  Future<bool> openSettings() async => true;
  @override
  Future<bool> locationServiceEnabled() async => serviceEnabled;
}
