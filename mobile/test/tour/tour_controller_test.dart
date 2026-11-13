import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stride/configs/pref_const.dart';
import 'package:stride/controller/providers.dart';
import 'package:stride/controller/tour/tour_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(ProviderContainer, TourController, SharedPreferences)> setup([Map<String, Object> values = const {}]) async {
    SharedPreferences.setMockInitialValues(values);
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [sharedPrefsProvider.overrideWithValue(prefs)]);
    addTearDown(container.dispose);
    return (container, container.read(tourControllerProvider), prefs);
  }

  test('đã xem tour thì không tự bắt đầu lại', () async {
    final (_, tour, _) = await setup({PrefConst.tourSeen: true});
    expect(tour.shouldStart, isFalse);
    expect(await tour.start(), isFalse);
    expect(tour.active, isFalse);
  });

  test('bắt đầu khi anchor đầu có mặt; Next đi hết các bước rồi ghi đã xem; bước thiếu anchor bị bỏ qua', () async {
    final (_, tour, prefs) = await setup();
    final tabs = <int>[];
    tour.selectTab = tabs.add;
    // Chỉ đăng ký anchor của bước 1, 3 (bước 2 thiếu: bị bỏ qua), 4.
    final keys = {
      for (final id in [TourAnchors.homeSteps, TourAnchors.runButton, TourAnchors.profileTab]) id: GlobalKey(),
    };
    keys.forEach(tour.registerAnchor);

    expect(await tour.start(), isTrue);
    expect(tour.active, isTrue);
    expect(tour.index, 0);
    expect(tabs, [0]);

    await tour.next();
    expect(tour.step.anchorId, TourAnchors.runButton); // bỏ qua progress_period
    await tour.next();
    expect(tour.isLast, isTrue);
    await tour.next(); // bước cuối: Xong
    expect(tour.active, isFalse);
    expect(prefs.getBool(PrefConst.tourSeen), isTrue);
  });

  test('Bỏ qua kết thúc tour và ghi đã xem', () async {
    final (_, tour, prefs) = await setup();
    tour.registerAnchor(TourAnchors.homeSteps, GlobalKey());
    await tour.start();
    await tour.finish();
    expect(tour.active, isFalse);
    expect(prefs.getBool(PrefConst.tourSeen), isTrue);
  });
}
