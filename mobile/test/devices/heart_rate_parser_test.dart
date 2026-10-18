import 'package:flutter_test/flutter_test.dart';
import 'package:stride/features/devices/heart_rate_parser.dart';
import 'package:stride/features/devices/heart_rate_transport.dart';

void main() {
  group('parseHeartRateMeasurement (0x2A37)', () {
    test('uint8, không hỗ trợ sensor contact', () {
      final m = parseHeartRateMeasurement([0x00, 72])!;
      expect(m.bpm, 72);
      expect(m.contact, SensorContact.notSupported);
      expect(m.isReliable, isTrue);
    });

    test('uint16 little-endian (flags bit0 = 1)', () {
      // 0x00B4 = 180; 0x0104 = 260 (kiểm tra byte cao được đọc đúng).
      expect(parseHeartRateMeasurement([0x01, 0xB4, 0x00])!.bpm, 180);
      expect(parseHeartRateMeasurement([0x01, 0x04, 0x01])!.bpm, 260);
    });

    test('contact supported + detected', () {
      final m = parseHeartRateMeasurement([0x06, 150])!;
      expect(m.contact, SensorContact.detected);
      expect(m.isReliable, isTrue);
    });

    test('contact supported nhưng không phát hiện → không tin cậy', () {
      final m = parseHeartRateMeasurement([0x04, 0])!;
      expect(m.contact, SensorContact.notDetected);
      expect(m.isReliable, isFalse);
      // Kể cả có bpm khác 0, không tiếp xúc vẫn không ghi.
      expect(parseHeartRateMeasurement([0x04, 95])!.isReliable, isFalse);
    });

    test('bỏ qua RR-interval và đọc energy expended', () {
      // flags: uint8 | contact detected | energy | RR = 0x1E
      final m = parseHeartRateMeasurement([0x1E, 140, 0x10, 0x00, 0x00, 0x04, 0x10, 0x04])!;
      expect(m.bpm, 140);
      expect(m.energyExpendedKj, 16);
    });

    test('dữ liệu thiếu byte → null (không đoán)', () {
      expect(parseHeartRateMeasurement([]), isNull);
      expect(parseHeartRateMeasurement([0x00]), isNull);
      expect(parseHeartRateMeasurement([0x01, 0x50]), isNull);
    });

    test('bpm 0 không tin cậy', () {
      expect(parseHeartRateMeasurement([0x00, 0])!.isReliable, isFalse);
    });
  });

  group('FoundSensor', () {
    test('tên trống → "Heart rate sensor" + đuôi id', () {
      expect(const FoundSensor(remoteId: 'AA:BB:CC:DD:EE:F1', advertisedName: '').displayName, 'Heart rate sensor EEF1');
      expect(const FoundSensor(remoteId: 'x', advertisedName: '  My strap ').displayName, 'My strap');
    });
  });
}
