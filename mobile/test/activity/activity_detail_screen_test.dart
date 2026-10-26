import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stride/models/data_models/activity.dart';
import 'package:stride/presentation/screens_activity/activity_detail_screen.dart';

import 'fixtures.dart';
import 'widget_harness.dart';

/// Tìm widget Semantics theo tiền tố nhãn (nhãn đọc cho trình đọc màn hình).
Finder _label(String prefix) => find.byWidgetPredicate((w) => w is Semantics && (w.properties.label?.startsWith(prefix) ?? false));

void main() {
  testWidgets('ID không tồn tại → not found', (tester) async {
    final h = await WidgetHarness.create(tester);
    await tester.pumpWidget(h.wrap(const ActivityDetailScreen(activityId: 'missing')));
    await h.settle(tester);
    expect(find.text('Activity not found'), findsOneWidget);
    await h.dispose(tester);
  });

  testWidgets('Overview / Splits (split lẻ có độ dài thật) / Charts (ẩn kèm lý do)', (tester) async {
    final h = await WidgetHarness.create(tester);
    late Activity a;
    await tester.runAsync(() async {
      final start = DateTime(2026, 10, 14, 7);
      a = await saveFixtureActivity(h.repo, owner: testOwner, start: start, distanceM: 1200, movingMs: 360000, title: 'Riverside run', avgPace: 300);
      await addFixtureTrack(h.repo, a, [straightTrack(meters: 1200, startT: start.millisecondsSinceEpoch)]);
    });
    await tester.pumpWidget(h.wrap(ActivityDetailScreen(activityId: a.id)));
    await h.settle(tester);

    expect(find.text('Riverside run'), findsOneWidget);
    expect(find.text('Distance'), findsWidgets);
    expect(find.text('Saved on this device'), findsOneWidget); // trạng thái sync thật (local)
    expect(find.textContaining('Calories'), findsWidgets);

    await tester.tap(find.text('Splits'));
    await h.settle(tester);
    expect(_label('Split 1, pace 5:00'), findsOneWidget);
    expect(_label('Final partial split, 0.20 km'), findsOneWidget);

    await tester.tap(find.text('Charts'));
    await h.settle(tester);
    expect(find.textContaining('No heart rate data'), findsOneWidget);
    expect(find.textContaining('didn\'t record altitude'), findsOneWidget);
    await h.dispose(tester);
  });

  testWidgets('hoạt động không GPS: không bản đồ, splits giải thích lý do', (tester) async {
    final h = await WidgetHarness.create(tester);
    late Activity a;
    await tester.runAsync(() async {
      a = await saveFixtureActivity(
        h.repo,
        owner: testOwner,
        start: DateTime(2026, 10, 14, 7),
        type: ActivityType.indoorRun,
        hasGps: false,
        source: DistanceSource.steps,
      );
    });
    await tester.pumpWidget(h.wrap(ActivityDetailScreen(activityId: a.id)));
    await h.settle(tester);
    expect(find.text('No GPS route'), findsOneWidget);
    expect(find.text('Distance · estimated'), findsOneWidget);
    await tester.tap(find.text('Splits'));
    await h.settle(tester);
    expect(find.text('Splits need GPS'), findsOneWidget);
    await h.dispose(tester);
  });
}
