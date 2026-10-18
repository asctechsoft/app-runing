/// Bluetooth LE Heart Rate Service chuẩn (L01): chỉ hỗ trợ đúng service này, không hỗ trợ theo tên hãng.
const heartRateServiceUuid = '180d';

/// Characteristic "Heart Rate Measurement".
const heartRateMeasurementUuid = '2a37';

/// Trạng thái tiếp xúc da theo bit 1–2 của flags.
enum SensorContact {
  /// Cảm biến không báo tính năng sensor contact.
  notSupported,

  /// Có hỗ trợ nhưng hiện không tiếp xúc (đeo lỏng / chưa đeo) → giá trị bpm không tin cậy.
  notDetected,
  detected,
}

class HeartRateMeasurement {
  const HeartRateMeasurement({required this.bpm, required this.contact, this.energyExpendedKj});

  final int bpm;
  final SensorContact contact;
  final int? energyExpendedKj;

  /// Chỉ ghi mẫu khi bpm hợp lệ và không bị báo "không tiếp xúc".
  bool get isReliable => bpm > 0 && contact != SensorContact.notDetected;

  @override
  String toString() => 'HeartRateMeasurement($bpm, $contact)';
}

/// Parse giá trị characteristic 0x2A37 theo spec Bluetooth SIG.
/// - flags bit0: 0 → bpm uint8, 1 → bpm uint16 little-endian.
/// - flags bit1–2: sensor contact (bit2 = supported, bit1 = detected).
/// - flags bit3: có Energy Expended (uint16).
/// - flags bit4: có RR-interval — hiện bỏ qua.
/// Trả về null nếu dữ liệu thiếu byte (không đoán giá trị).
HeartRateMeasurement? parseHeartRateMeasurement(List<int> data) {
  if (data.isEmpty) return null;
  final flags = data[0];
  final is16 = flags & 0x01 != 0;
  var i = 1;
  int bpm;
  if (is16) {
    if (data.length < i + 2) return null;
    bpm = (data[i] & 0xFF) | ((data[i + 1] & 0xFF) << 8);
    i += 2;
  } else {
    if (data.length < i + 1) return null;
    bpm = data[i] & 0xFF;
    i += 1;
  }
  final contactSupported = flags & 0x04 != 0;
  final contactDetected = flags & 0x02 != 0;
  final contact = !contactSupported
      ? SensorContact.notSupported
      : contactDetected
      ? SensorContact.detected
      : SensorContact.notDetected;
  int? energy;
  if (flags & 0x08 != 0 && data.length >= i + 2) {
    energy = (data[i] & 0xFF) | ((data[i + 1] & 0xFF) << 8);
  }
  return HeartRateMeasurement(bpm: bpm, contact: contact, energyExpendedKj: energy);
}
