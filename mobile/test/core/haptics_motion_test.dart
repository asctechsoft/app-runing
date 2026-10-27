import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stride/configs/pref_const.dart';
import 'package:stride/controller/profile/haptics_setting.dart';
import 'package:stride/controller/providers.dart';
import 'package:stride/models/data_models/activity.dart';
import 'package:stride/utils/haptics.dart';
import 'package:stride/values/tokens.dart';

import '../run/run_harness.dart';

/// T05 (haptic thống nhất) và M01 (giảm chuyển động).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<String> kinds;

  setUp(() {
    kinds = [];
    StrideHaptics.enabled = true;
    StrideHaptics.debugSink = kinds.add;
  });

  tearDown(() {
    StrideHaptics.debugSink = null;
    StrideHaptics.enabled = true;
  });

  test('tắt rung (T06) → không phát haptic nào', () {
    StrideHaptics.enabled = false;
    StrideHaptics.selection();
    StrideHaptics.heavy();
    expect(kinds, isEmpty);
  });

  test('engine: Pause = medium, Resume = light, đạt mục tiêu = medium (đúng bảng T05)', () async {
    final h = await RunHarness.create();
    addTearDown(h.close);
    await h.start(goal: const RunGoal(RunGoalType.distance, 300));
    await h.run(seconds: 5);
    kinds.clear();
    await h.ctl.pause();
    expect(kinds, ['medium']);
    await h.ctl.resume();
    expect(kinds, ['medium', 'light']);
    kinds.clear();
    await h.run(seconds: 110);
    expect(kinds, ['medium'], reason: 'đạt mục tiêu báo một lần');
  });

  testWidgets('StrideMotion.of: giảm chuyển động → 0; bình thường giữ token', (tester) async {
    late Duration normal;
    late Duration reduced;
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          normal = StrideMotion.of(context, StrideMotion.state);
          return MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Builder(
              builder: (context) {
                reduced = StrideMotion.of(context, StrideMotion.state);
                return const SizedBox();
              },
            ),
          );
        },
      ),
    );
    expect(normal, StrideMotion.state);
    expect(reduced, Duration.zero);
  });

  test('T06: tắt rung trong cài đặt → lưu theo thiết bị và chặn mọi haptic; bật lại thì rung xác nhận', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(overrides: [sharedPrefsProvider.overrideWithValue(prefs)]);
    addTearDown(c.dispose);
    expect(c.read(hapticsSettingProvider), isTrue);
    await c.read(hapticsSettingProvider.notifier).set(false);
    expect(prefs.getBool(PrefConst.hapticsEnabled), isFalse);
    StrideHaptics.heavy();
    expect(kinds, isEmpty);
    await c.read(hapticsSettingProvider.notifier).set(true);
    expect(kinds, ['selection']);
  });

  test('T05: mất GPS > 15 s → rung cảnh báo', () async {
    final h = await RunHarness.create();
    addTearDown(h.close);
    await h.start();
    await h.run(seconds: 3);
    kinds.clear();
    await h.idle(const Duration(seconds: 20));
    expect(kinds, ['medium']);
  });
}
