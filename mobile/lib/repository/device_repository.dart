import 'dart:async';

import 'package:uuid/uuid.dart';

import '../services/storage/app_database.dart';
import '../utils/clock.dart';

/// Loại thiết bị duy nhất đang hỗ trợ (L01): cảm biến Bluetooth LE Heart Rate Service.
const deviceKindBleHeartRate = 'bleHeartRate';

class PairedDevice {
  const PairedDevice({
    required this.id,
    required this.ownerId,
    required this.kind,
    required this.name,
    required this.remoteId,
    this.connectedAt,
    this.revokedAt,
  });

  final String id;
  final String ownerId;
  final String kind;
  final String name;
  final String remoteId;
  final int? connectedAt;
  final int? revokedAt;

  bool get revoked => revokedAt != null;

  factory PairedDevice.fromRow(Map<String, Object?> r) => PairedDevice(
    id: r['id'] as String,
    ownerId: r['owner_id'] as String,
    kind: r['kind'] as String,
    name: r['name'] as String,
    remoteId: r['remote_id'] as String,
    connectedAt: r['connected_at'] as int?,
    revokedAt: r['revoked_at'] as int?,
  );
}

class HeartRateSample {
  const HeartRateSample({required this.activityId, required this.t, required this.bpm, required this.deviceId});
  final String activityId;
  final int t;
  final int bpm;
  final String deviceId;
}

/// Bảng `devices` và `heart_rate_samples` (L02/L03). Thiết bị đã revoke không bao giờ được dùng để nhập dữ liệu.
class DeviceRepository {
  DeviceRepository(this._db, this._clock);

  final AppDatabase _db;
  final Clock _clock;
  final _uuid = const Uuid();
  final _changes = StreamController<String>.broadcast();

  /// Phát ownerId khi danh sách thiết bị đổi.
  Stream<String> get changes => _changes.stream;

  Future<List<PairedDevice>> list(String ownerId, {bool includeRevoked = false}) async {
    final rows = await _db.db.query(
      'devices',
      where: includeRevoked ? 'owner_id = ?' : 'owner_id = ? AND revoked_at IS NULL',
      whereArgs: [ownerId],
      orderBy: 'COALESCE(connected_at, 0) DESC',
    );
    return rows.map(PairedDevice.fromRow).toList();
  }

  /// Thiết bị kết nối gần nhất chưa bị revoke.
  Future<PairedDevice?> mostRecentActive(String ownerId, {String kind = deviceKindBleHeartRate}) async {
    final rows = await _db.db.query(
      'devices',
      where: 'owner_id = ? AND kind = ? AND revoked_at IS NULL',
      whereArgs: [ownerId, kind],
      orderBy: 'COALESCE(connected_at, 0) DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : PairedDevice.fromRow(rows.first);
  }

  Future<PairedDevice?> byId(String id) async {
    final rows = await _db.db.query('devices', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : PairedDevice.fromRow(rows.first);
  }

  /// Lưu sau khi kết nối thành công. Ghép lại cùng remoteId → dùng lại bản ghi (không tạo trùng) và bỏ revoke.
  Future<PairedDevice> savePaired({required String ownerId, required String name, required String remoteId, String kind = deviceKindBleHeartRate}) async {
    final now = _clock.nowMs();
    final existing = await _db.db.query('devices', where: 'owner_id = ? AND kind = ? AND remote_id = ?', whereArgs: [ownerId, kind, remoteId], limit: 1);
    final String id;
    if (existing.isNotEmpty) {
      id = existing.first['id'] as String;
      await _db.db.update('devices', {'name': name, 'connected_at': now, 'revoked_at': null}, where: 'id = ?', whereArgs: [id]);
    } else {
      id = _uuid.v4();
      await _db.db.insert('devices', {
        'id': id,
        'owner_id': ownerId,
        'kind': kind,
        'name': name,
        'remote_id': remoteId,
        'connected_at': now,
        'revoked_at': null,
      });
    }
    _changes.add(ownerId);
    return (await byId(id))!;
  }

  Future<void> markConnected(String id) async {
    final d = await byId(id);
    if (d == null || d.revoked) return;
    await _db.db.update('devices', {'connected_at': _clock.nowMs()}, where: 'id = ?', whereArgs: [id]);
    _changes.add(d.ownerId);
  }

  /// "Forget": đặt revoked_at; dữ liệu nhịp tim đã ghi giữ nguyên, thiết bị ngừng nhập.
  Future<void> revoke(String id) async {
    final d = await byId(id);
    if (d == null || d.revoked) return;
    await _db.db.update('devices', {'revoked_at': _clock.nowMs()}, where: 'id = ?', whereArgs: [id]);
    _changes.add(d.ownerId);
  }

  /// Ghi một mẫu; trùng (activity, t, device) thì bỏ qua để không double count.
  Future<void> addSample(HeartRateSample s) async {
    await _db.db.rawInsert('INSERT OR IGNORE INTO heart_rate_samples (activity_id, t, bpm, device_id) VALUES (?, ?, ?, ?)', [
      s.activityId,
      s.t,
      s.bpm,
      s.deviceId,
    ]);
  }

  Future<List<HeartRateSample>> samples(String activityId) async {
    final rows = await _db.db.query('heart_rate_samples', where: 'activity_id = ?', whereArgs: [activityId], orderBy: 't ASC');
    return [
      for (final r in rows) HeartRateSample(activityId: r['activity_id'] as String, t: r['t'] as int, bpm: r['bpm'] as int, deviceId: r['device_id'] as String),
    ];
  }
}
