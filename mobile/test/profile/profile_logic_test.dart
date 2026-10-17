import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stride/core/config/env.dart';
import 'package:stride/core/db/app_database.dart';
import 'package:stride/core/permissions/permission_coordinator.dart';
import 'package:stride/core/time/clock.dart';
import 'package:stride/data/activity_repository.dart';
import 'package:stride/data/settings_repository.dart';
import 'package:stride/domain/models/activity.dart';
import 'package:stride/domain/models/profile.dart';
import 'package:stride/domain/models/steps.dart';
import 'package:stride/features/profile/profile_logic.dart';

void main() {
  sqfliteFfiInit();

  group('Đổi đơn vị (J03)', () {
    test('kg ↔ lb và cm ↔ ft-in quy đổi hai chiều trong sai số làm tròn hiển thị', () {
      for (final kg in [25.0, 68.0, 72.5, 300.0]) {
        expect(lbToKg(kgToLb(kg)), closeTo(kg, 1e-9));
      }
      final (ft, inch) = cmToFtIn(172);
      expect((ft, inch), (5, 8));
      expect(ftInToCm(ft, inch), closeTo(172.72, 0.01));
    });

    test('ô chưa sửa giữ nguyên giá trị gốc, không trôi do làm tròn ft-in', () {
      final (a, b) = heightFieldText(172, HeightUnit.ftin);
      final parsed = parseHeightInput(HeightUnit.ftin, a, b).value;
      expect(parsed, isNot(172)); // làm tròn inch sẽ làm lệch
      expect(keepStoredIfUnchanged(stored: 172, unchanged: true, parsed: parsed), 172);
      expect(keepStoredIfUnchanged(stored: 172, unchanged: false, parsed: parsed), parsed);
    });

    test('đổi units trong settings không đổi số đo hay hoạt động đã lưu', () async {
      final db = await AppDatabase.open(name: inMemoryDatabasePath, factory: databaseFactoryFfi);
      addTearDown(db.close);
      final clock = FakeClock(DateTime(2026, 10, 17, 7).millisecondsSinceEpoch);
      final settings = SettingsRepository(db, clock);
      final activities = ActivityRepository(db, clock);
      await settings.save(const UserSettings(ownerId: 'o', displayName: 'A', heightCm: 172, weightKg: 68));
      final (a, _) = await activities.createSession(ownerId: 'o', type: ActivityType.run, goal: const RunGoal.free(), monoMs: 0, tzId: 'UTC', tzOffsetMin: 0);
      final summary = a.copyWith(distanceM: 5200, movingMs: 1800000, elapsedMs: 1800000, endedAt: clock.nowMs(), title: 'Run', hasGps: true);
      await activities.finalizeSummary(summary);
      await activities.saveActivity(summary);

      final before = await settings.load('o');
      await settings.save(
        applyUnitPreferences(before, distanceUnit: DistanceUnit.mi, weightUnit: WeightUnit.lb, heightUnit: HeightUnit.ftin, weekStart: DateTime.sunday),
      );
      final after = await settings.load('o');
      expect(after.distanceUnit, DistanceUnit.mi);
      expect(after.weekStart, DateTime.sunday);
      expect(after.heightCm, 172);
      expect(after.weightKg, 68);
      final totals = await activities.totals(const ActivityQuery(ownerId: 'o'));
      expect(totals.distanceM, 5200);
    });

    test('khoảng audio cue quy đổi km ↔ mi', () {
      expect(cueIntervalInUnit(1.0, DistanceUnit.km), 1.0);
      final km = cueIntervalToKm(1, DistanceUnit.mi);
      expect(km, closeTo(1.609344, 1e-9));
      expect(cueIntervalInUnit(km, DistanceUnit.mi), 1.0);
    });
  });

  group('Validation hồ sơ (J01)', () {
    test('tên bắt buộc', () {
      expect(validateDisplayName('  '), isNotNull);
      expect(validateDisplayName('Alex'), isNull);
      expect(validateDisplayName('a' * 61), isNotNull);
    });

    test('chiều cao optional, trong khoảng 100–250 cm', () {
      expect(parseHeightInput(HeightUnit.cm, '').value, isNull);
      expect(parseHeightInput(HeightUnit.cm, '').error, isNull);
      expect(parseHeightInput(HeightUnit.cm, '99').error, isNotNull);
      expect(parseHeightInput(HeightUnit.cm, '251').error, isNotNull);
      expect(parseHeightInput(HeightUnit.cm, 'abc').error, isNotNull);
      expect(parseHeightInput(HeightUnit.cm, '172').value, 172);
      expect(parseHeightInput(HeightUnit.ftin, '5', '8').value, closeTo(172.72, 0.01));
      expect(parseHeightInput(HeightUnit.ftin, '5', '12').error, isNotNull);
      expect(parseHeightInput(HeightUnit.ftin, '2', '0').error, isNotNull);
    });

    test('cân nặng optional, 25–300 kg (kể cả khi nhập lb)', () {
      expect(parseWeightInput(WeightUnit.kg, '').value, isNull);
      expect(parseWeightInput(WeightUnit.kg, '24.9').error, isNotNull);
      expect(parseWeightInput(WeightUnit.kg, '300').value, 300);
      expect(parseWeightInput(WeightUnit.kg, '68,5').value, 68.5);
      expect(parseWeightInput(WeightUnit.lb, '150').value, closeTo(68.04, 0.01));
      expect(parseWeightInput(WeightUnit.lb, '700').error, isNotNull);
    });
  });

  group('Ưu tiên nguồn bước', () {
    test('parse bỏ tên lạ/trùng và bổ sung nguồn thiếu', () {
      final l = parseStepSourcePriority('phoneSensor,bogus,phoneSensor,device');
      expect(l.first, StepSource.phoneSensor);
      expect(l[1], StepSource.device);
      expect(l.toSet(), StepSource.values.toSet());
      expect(l.length, StepSource.values.length);
      expect(parseStepSourcePriority(null).toSet(), StepSource.values.toSet());
    });

    test('lưu và đọc lại qua kv theo owner', () async {
      final db = await AppDatabase.open(name: inMemoryDatabasePath, factory: databaseFactoryFfi);
      addTearDown(db.close);
      final repo = SettingsRepository(db, FakeClock());
      await saveStepSourcePriority(repo, 'o', [StepSource.phoneSensor, StepSource.device]);
      expect(await repo.kvGet('o', kvStepSourcePriority), startsWith('phoneSensor,device'));
      final loaded = await loadStepSourcePriority(repo, 'o');
      expect(loaded.take(2), [StepSource.phoneSensor, StepSource.device]);
      // Owner khác không bị ảnh hưởng.
      expect((await loadStepSourcePriority(repo, 'other')).first, isNot(StepSource.phoneSensor));
    });

    test('đổi thứ tự nguồn hiển thị giữ vị trí nguồn bị ẩn', () {
      final full = [StepSource.healthConnect, StepSource.healthKit, StepSource.device, StepSource.phoneSensor];
      final next = reorderVisible(full, [StepSource.phoneSensor, StepSource.device]);
      expect(next, [StepSource.healthConnect, StepSource.healthKit, StepSource.phoneSensor, StepSource.device]);
    });

    test('nguồn hiển thị theo flag', () {
      expect(visibleStepSources(const FeatureFlags(devicesBle: false), isIOS: false), [StepSource.phoneSensor]);
      expect(visibleStepSources(const FeatureFlags(stepsHealth: true), isIOS: true), contains(StepSource.healthKit));
    });
  });

  group('Privacy mặc định (J04)', () {
    test('mặc định Only me khi chưa lưu hoặc giá trị lạ', () async {
      final db = await AppDatabase.open(name: inMemoryDatabasePath, factory: databaseFactoryFfi);
      addTearDown(db.close);
      final repo = SettingsRepository(db, FakeClock());
      expect(await loadDefaultPrivacy(repo, 'o'), Privacy.onlyMe);
      expect(parseDefaultPrivacy('weird'), Privacy.onlyMe);
      await saveDefaultPrivacy(repo, 'o', Privacy.followers);
      expect(await loadDefaultPrivacy(repo, 'o'), Privacy.followers);
    });
  });

  test('chẩn đoán không chứa token/tọa độ/email', () {
    final text = buildDiagnostics(
      env: 'dev',
      platform: 'android 14',
      flags: const FeatureFlags(),
      permissions: {PermKind.motion: PermStatus.granted, PermKind.location: PermStatus.denied},
      isGuest: false,
      savedActivities: 3,
      stepSamples: 10,
      pendingSync: 1,
      distanceUnit: 'km',
    );
    expect(text, contains('App version: 1.0.0 (1)'));
    expect(text, contains('motion: granted'));
    expect(text, contains('explore.clubs: on'));
    expect(text.toLowerCase(), isNot(contains('token')));
    expect(text, isNot(contains('@')));
    expect(text.toLowerCase(), isNot(contains('latitude')));
    expect(RegExp(r'-?\d+\.\d{4,}').hasMatch(text), isFalse); // không có số dạng tọa độ
  });
}
