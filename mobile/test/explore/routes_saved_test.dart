import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stride/controller/providers.dart';
import 'package:stride/models/ui_models/explore_models.dart';
import 'package:stride/presentation/screens_explore/routes_screen.dart';
import 'package:stride/repository/explore_repository.dart';
import 'package:stride/services/native/permission_coordinator.dart';
import 'package:stride/services/storage/app_database.dart';

const _lake = RouteSummary(id: 'r1', name: 'Lake loop', region: 'Hanoi', distanceM: 5000, attribution: '', saved: false);
const _park = RouteSummary(id: 'r2', name: 'Park run', region: 'Hanoi', distanceM: 3000, attribution: '', saved: true);

class _FakeRoutesRepository extends ExploreRepository {
  _FakeRoutesRepository({this.saved = const [_park]}) : super(ready: () => false, firestore: () => throw UnimplementedError(), uid: () => null);
  final List<RouteSummary> saved;
  int savedCalls = 0;

  @override
  Future<ExplorePage<RouteSummary>> searchRoutes({String? region, double? minDistanceM, double? maxDistanceM, String? surface, String? cursor}) async =>
      const ExplorePage([_lake, _park], null);

  @override
  Future<List<RouteSummary>> savedRoutes() async {
    savedCalls++;
    return saved;
  }
}

/// F05: màn tuyến có bộ lọc "Saved" đọc `users/{uid}/savedRoutes`.
void main() {
  sqfliteFfiInit();
  late AppDatabase db;
  setUp(() async => db = await AppDatabase.open(name: inMemoryDatabasePath, factory: databaseFactoryFfiNoIsolate));
  tearDown(() => db.close());

  Future<void> pump(WidgetTester tester, ExploreRepository repo) async {
    SharedPreferences.setMockInitialValues({'guest_id': 'guest:test', 'user_id': 'u-me', 'user_email': 'x@y.z'});
    final prefs = await SharedPreferences.getInstance();
    await tester.binding.setSurfaceSize(const Size(420, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          sharedPrefsProvider.overrideWithValue(prefs),
          permissionsProvider.overrideWithValue(FakePermissionCoordinator()),
          exploreRepositoryProvider.overrideWithValue(repo),
        ],
        child: const MaterialApp(home: RoutesScreen()),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('bật "Saved" → chỉ tuyến đã lưu, ẩn bộ lọc; tắt → lại tìm kiếm', (tester) async {
    final repo = _FakeRoutesRepository();
    await pump(tester, repo);
    expect(find.text('Lake loop'), findsOneWidget);
    await tester.tap(find.byKey(const Key('routes-saved-only')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(repo.savedCalls, 1);
    expect(find.text('Park run'), findsOneWidget);
    expect(find.text('Lake loop'), findsNothing);
    await tester.tap(find.byKey(const Key('routes-saved-only')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Lake loop'), findsOneWidget);
  });

  testWidgets('chưa lưu tuyến nào → trạng thái rỗng riêng', (tester) async {
    await pump(tester, _FakeRoutesRepository(saved: const []));
    await tester.tap(find.byKey(const Key('routes-saved-only')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('No saved routes yet'), findsOneWidget);
  });
}
