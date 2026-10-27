import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stride/presentation/common_components/buttons.dart';

/// M03 / T14: "giữ để xác nhận" đo bằng thời gian thật — kể cả khi bật giảm chuyển động (Flutter rút thời lượng của
/// AnimationController thường về 0, khiến một cái chạm nhẹ cũng kích hoạt).
void main() {
  Future<List<int>> pump(WidgetTester tester) async {
    final done = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HoldButton(label: 'Hold to finish', onCompleted: () => done.add(1)),
        ),
      ),
    );
    return done;
  }

  for (final reduced in [false, true]) {
    testWidgets('giảm chuyển động = $reduced: giữ ngắn không kích hoạt, giữ đủ 800 ms thì kích hoạt một lần', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue = FakeAccessibilityFeatures(disableAnimations: reduced);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      final done = await pump(tester);
      final g = await tester.startGesture(tester.getCenter(find.byType(HoldButton)));
      await tester.pump(); // khung đầu: ticker bắt đầu đếm
      await tester.pump(const Duration(milliseconds: 300));
      expect(done, isEmpty);
      await g.up();
      await tester.pumpAndSettle();
      expect(done, isEmpty);

      final g2 = await tester.startGesture(tester.getCenter(find.byType(HoldButton)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      expect(done, isEmpty);
      await tester.pump(const Duration(milliseconds: 150));
      expect(done, [1]);
      await g2.up();
      await tester.pumpAndSettle();
    });
  }
}
