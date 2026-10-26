import 'package:flutter_test/flutter_test.dart';
import 'package:stride/presentation/screens_progress/progress_screen.dart';
import 'package:stride/presentation/screens_progress/records_screen.dart';

import '../activity/fixtures.dart';
import '../activity/widget_harness.dart';

void main() {
  testWidgets('Running tuần: tổng, đổi kỳ tại chỗ, Steps không quyền → permission state', (tester) async {
    final h = await WidgetHarness.create(tester);
    await tester.runAsync(() async {
      await saveFixtureActivity(h.repo, owner: testOwner, start: DateTime(2026, 10, 13, 7), distanceM: 6400, title: 'Tuesday tempo');
      await saveFixtureActivity(h.repo, owner: testOwner, start: DateTime(2026, 9, 2, 7), distanceM: 3000, title: 'September run');
    });
    await tester.pumpWidget(h.wrap(const ProgressScreen()));
    await h.settle(tester);

    expect(find.text('Your progress'), findsOneWidget);
    expect(find.text('Oct 12 – 18, 2026'), findsOneWidget);
    expect(find.text('6.40 km'), findsWidgets);
    expect(find.text('Runs this week'), findsOneWidget);
    expect(find.text('Tuesday tempo'), findsOneWidget);
    expect(find.text('This week through Thu, Oct 15'), findsOneWidget);

    // Kỳ trước đổi tại chỗ (không push).
    await tester.tap(find.byTooltip('Previous week'));
    await h.settle(tester);
    expect(find.text('Oct 5 – 11, 2026'), findsOneWidget);
    expect(find.text('No runs this week'), findsOneWidget);

    await tester.tap(find.text('Year'));
    await h.settle(tester);
    expect(find.text('2026'), findsOneWidget);
    expect(find.text('9.40 km'), findsWidgets);

    await tester.tap(find.text('Steps'));
    await h.settle(tester);
    expect(find.text('Allow motion access'), findsOneWidget);
    await h.dispose(tester);
  });

  testWidgets('Records: empty state và danh sách sau khi có run GPS', (tester) async {
    final h = await WidgetHarness.create(tester);
    await tester.pumpWidget(h.wrap(const RecordsScreen()));
    await h.settle(tester);
    expect(find.text('No records yet'), findsOneWidget);
    expect(find.text('How records work'), findsOneWidget);

    await tester.runAsync(() async {
      final start = DateTime(2026, 10, 10, 7);
      final a = await saveFixtureActivity(h.repo, owner: testOwner, start: start, distanceM: 1500, movingMs: 450000, silent: true);
      await addFixtureTrack(h.repo, a, [straightTrack(meters: 1500, startT: start.millisecondsSinceEpoch)]);
      h.repo.notifyChanged(testOwner);
    });
    await h.settle(tester, rounds: 12);
    expect(find.text('Longest run'), findsOneWidget);
    expect(find.text('1.50 km'), findsOneWidget);
    expect(find.text('05:00'), findsOneWidget); // fastest 1 km, không kèm "/km"
    expect(find.text('Run at least 5 km continuously with GPS.'), findsOneWidget);
    await h.dispose(tester);
  });
}
