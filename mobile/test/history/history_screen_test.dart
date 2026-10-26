import 'package:flutter_test/flutter_test.dart';
import 'package:stride/models/data_models/activity.dart';
import 'package:stride/presentation/screen_history/history_screen.dart';

import '../activity/fixtures.dart';
import '../activity/widget_harness.dart';

void main() {
  testWidgets('chưa có hoạt động → "Your first run starts here" với Start a run', (tester) async {
    final h = await WidgetHarness.create(tester);
    await tester.pumpWidget(h.wrap(const HistoryScreen()));
    await h.settle(tester);
    expect(find.text('Your first run starts here'), findsOneWidget);
    expect(find.text('Start a run'), findsOneWidget);
    expect(find.text('Daily steps are available on Home'), findsOneWidget);
    expect(find.text('Clear filters'), findsNothing);
    await h.dispose(tester);
  });

  testWidgets('danh sách + tổng theo filter; filter rỗng khác empty ban đầu và Clear filters khôi phục', (tester) async {
    final h = await WidgetHarness.create(tester);
    await tester.runAsync(() async {
      await saveFixtureActivity(h.repo, owner: testOwner, start: DateTime(2026, 10, 14, 7), distanceM: 5200, title: 'Morning park run');
      await saveFixtureActivity(h.repo, owner: testOwner, start: DateTime(2026, 10, 12, 7), distanceM: 3000, title: 'Easy evening run');
    });
    await tester.pumpWidget(h.wrap(const HistoryScreen()));
    await h.settle(tester);

    expect(find.text('Your activities'), findsOneWidget);
    expect(find.text('October 2026'), findsOneWidget);
    expect(find.text('Morning park run'), findsOneWidget);
    expect(find.text('Easy evening run'), findsOneWidget);
    expect(find.text('8.20 km'), findsOneWidget); // tổng quãng đường
    expect(find.text('activities'), findsOneWidget);

    await tester.tap(find.text('Walk'));
    await h.settle(tester);
    expect(find.text('No activities found'), findsOneWidget);
    expect(find.text('Your first run starts here'), findsNothing);

    await tester.ensureVisible(find.text('Clear filters'));
    await tester.pump();
    await tester.tap(find.text('Clear filters'));
    await h.settle(tester);
    expect(find.text('Morning park run'), findsOneWidget);

    // Calendar: chạm ngày lọc danh sách theo ngày.
    final semantics = tester.ensureSemantics();
    await tester.tap(find.text('Calendar'));
    await h.settle(tester);
    final day = find.bySemanticsLabel(RegExp(r'^Wednesday, October 14, 1 activity'));
    await tester.ensureVisible(day);
    await tester.pump();
    await tester.tap(day);
    await h.settle(tester);
    expect(find.text('Morning park run'), findsOneWidget);
    expect(find.text('Easy evening run'), findsNothing);
    semantics.dispose();
    await h.dispose(tester);
  });

  testWidgets('xóa hoạt động → danh sách và tổng tự cập nhật', (tester) async {
    final h = await WidgetHarness.create(tester);
    late Activity a;
    await tester.runAsync(() async {
      a = await saveFixtureActivity(h.repo, owner: testOwner, start: DateTime(2026, 10, 14, 7), title: 'To delete');
    });
    await tester.pumpWidget(h.wrap(const HistoryScreen()));
    await h.settle(tester);
    expect(find.text('To delete'), findsOneWidget);
    await tester.runAsync(() => h.repo.deleteActivity(testOwner, a.id));
    await h.settle(tester);
    expect(find.text('To delete'), findsNothing);
    expect(find.text('Your first run starts here'), findsOneWidget);
    await h.dispose(tester);
  });
}
