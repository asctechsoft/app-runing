import 'package:flutter_test/flutter_test.dart';
import 'package:stride/models/data_models/profile.dart';
import 'package:stride/services/application/sync_service.dart';

/// Hồ sơ đồng bộ lên Firestore (`users/{uid}.profile`): giới tính, quốc gia, ngày sinh đi theo tài khoản sang máy khác.
void main() {
  const base = UserSettings(ownerId: 'u1', displayName: 'Linh', heightCm: 165, weightKg: 58.5);

  test('payload có giới tính, quốc gia, ngày sinh (null khi chưa điền)', () {
    final p = profilePayloadForServer(base);
    expect((p['gender'], p['countryCode'], p['birthDate']), (null, null, null));
    final full = profilePayloadForServer(base.copyWith(gender: Gender.female, countryCode: 'VN', birthDate: '1997-01-01'));
    expect((full['gender'], full['countryCode'], full['birthDate']), ('female', 'VN', '1997-01-01'));
  });

  test('khứ hồi: hồ sơ từ server khôi phục giới tính/quốc gia/ngày sinh trên máy mới', () {
    final server = profilePayloadForServer(base.copyWith(gender: Gender.male, countryCode: 'US', birthDate: '1990-12-31'));
    final restored = settingsFromServerProfile(const UserSettings(ownerId: 'u1'), server);
    expect((restored.displayName, restored.gender, restored.countryCode, restored.birthDate), ('Linh', Gender.male, 'US', '1990-12-31'));
  });

  test('server chưa có các trường mới (tài khoản cũ) → giữ giá trị đang có trên máy', () {
    final local = base.copyWith(gender: Gender.female, countryCode: 'VN', birthDate: '1997-01-01');
    final restored = settingsFromServerProfile(local, {'displayName': 'Linh', 'weightKg': 60});
    expect((restored.gender, restored.countryCode, restored.birthDate), (Gender.female, 'VN', '1997-01-01'));
  });

  test('lưu cục bộ (toRow) rồi đọc lại giữ nguyên các trường mới', () {
    final s = base.copyWith(gender: Gender.female, countryCode: 'VN', birthDate: '1997-01-01');
    final back = UserSettings.fromRow(s.toRow());
    expect((back.gender, back.countryCode, back.birthDate), (Gender.female, 'VN', '1997-01-01'));
  });
}
