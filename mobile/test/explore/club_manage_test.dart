import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stride/controller/explore/explore_logic.dart';
import 'package:stride/controller/providers.dart';
import 'package:stride/models/ui_models/explore_models.dart';
import 'package:stride/presentation/screens_explore/club_members_screen.dart';
import 'package:stride/presentation/screens_explore/create_club_screen.dart';
import 'package:stride/repository/explore_repository.dart';
import 'package:stride/services/native/permission_coordinator.dart';
import 'package:stride/services/storage/app_database.dart';

class _FakeRepo extends ExploreRepository {
  _FakeRepo({this.myRole = 'owner', this.members = const [], this.pending = const []})
    : super(ready: () => false, firestore: () => throw UnimplementedError(), uid: () => null);

  final String myRole;
  List<ClubMember> members;
  List<ClubMember> pending;
  final created = <Map<String, Object?>>[];
  final updated = <Map<String, Object?>>[];
  final calls = <String>[];
  Completer<void>? gate;

  @override
  Future<String> createClub({required String name, required String description, required String region, required bool isPrivate}) async {
    created.add({'name': name, 'description': description, 'region': region, 'private': isPrivate});
    await gate?.future;
    return 'new-id';
  }

  @override
  Future<Club> club(String id) async => Club(
    id: id,
    name: 'Morning Crew',
    description: '',
    regionText: '',
    memberCount: members.length,
    membership: ClubMembership(role: myRole, status: MembershipStatus.approved),
    isPrivate: true,
    rulesText: 'Be kind',
  );

  @override
  Future<void> updateClub(
    String clubId, {
    required String name,
    required String description,
    required String region,
    required bool isPrivate,
    required String rulesText,
  }) async => updated.add({'id': clubId, 'name': name, 'private': isPrivate, 'rules': rulesText});

  @override
  Future<ExplorePage<ClubMember>> clubMembers(String clubId, {bool pending = false, String? cursor}) async =>
      ExplorePage(pending ? this.pending : members, null);

  @override
  Future<void> approveMember(String clubId, String userId) async {
    calls.add('approve:$userId');
    final m = pending.firstWhere((p) => p.userId == userId);
    pending = pending.where((p) => p.userId != userId).toList();
    members = [...members, ClubMember(userId: m.userId, displayName: m.displayName, role: 'member', status: 'active', joinedAt: m.joinedAt)];
  }

  @override
  Future<void> removeMember(String clubId, String userId, {bool ban = false}) async => calls.add('${ban ? 'ban' : 'remove'}:$userId');

  @override
  Future<void> setMemberRole(String clubId, String userId, String role) async => calls.add('role:$userId:$role');

  @override
  Future<void> transferOwnership(String clubId, String newOwnerId) async => calls.add('transfer:$newOwnerId');
}

ClubMember _m(String id, String role, {String status = 'active'}) =>
    ClubMember(userId: id, displayName: id[0].toUpperCase() + id.substring(1), role: role, status: status, joinedAt: 1);

void main() {
  group('TM01: logic tạo club', () {
    test('tên 3–40 ký tự (cắt khoảng trắng), mô tả ≤ 300, vùng ≤ 60', () {
      expect(validateClubDraft(name: 'Morning Crew', description: '', region: ''), isEmpty);
      expect(validateClubDraft(name: '  ab ', description: '', region: ''), {ClubDraftError.nameTooShort});
      expect(validateClubDraft(name: 'a' * 41, description: '', region: ''), {ClubDraftError.nameTooLong});
      expect(validateClubDraft(name: 'Crew', description: 'x' * 301, region: 'y' * 61), {ClubDraftError.descriptionTooLong, ClubDraftError.regionTooLong});
    });

    test('document club khớp rules: nameLower, memberCount 1, visibility', () {
      final d = newClubDoc(ownerId: 'u', name: ' Morning Crew ', description: ' x ', region: 'Hanoi', isPrivate: true, nowMs: 5);
      expect(d, {
        'name': 'Morning Crew',
        'nameLower': 'morning crew',
        'description': 'x',
        'region': 'Hanoi',
        'visibility': 'private',
        'memberCount': 1,
        'ownerId': 'u',
        'createdAt': 5,
      });
    });

    test('hạn mức: tối đa 5 club, cách nhau ≥ 1 giờ', () {
      const h = 3600000;
      expect(checkClubQuota(ownedCount: 0, lastCreatedAtMs: null, nowMs: 0), isNull);
      expect(checkClubQuota(ownedCount: 1, lastCreatedAtMs: 0, nowMs: h - 1), ClubQuotaBlock.tooSoon);
      expect(checkClubQuota(ownedCount: 1, lastCreatedAtMs: 0, nowMs: h), isNull);
      expect(checkClubQuota(ownedCount: maxOwnedClubs, lastCreatedAtMs: 0, nowMs: 10 * h), ClubQuotaBlock.limitReached);
    });
  });

  group('TM04: sửa club', () {
    test('nội quy quá dài → lỗi; patch chỉ gồm trường được sửa, đã cắt khoảng trắng', () {
      expect(validateClubDraft(name: 'Crew', description: '', region: '', rulesText: 'x' * (clubRulesMax + 1)), {ClubDraftError.rulesTooLong});
      expect(validateClubDraft(name: 'Crew', description: '', region: '', rulesText: 'x' * clubRulesMax), isEmpty);
      expect(clubEditPatch(name: ' Evening Crew ', description: ' d ', region: '', isPrivate: false, rulesText: ' Be kind '), {
        'name': 'Evening Crew',
        'nameLower': 'evening crew',
        'description': 'd',
        'region': '',
        'visibility': 'public',
        'rulesText': 'Be kind',
      });
    });
  });

  group('TM02: hành động theo vai trò (khớp rules)', () {
    Set<MemberAction> acts(String myRole, ClubMember t) => availableMemberActions(myRole: myRole, myUid: 'me', target: t);

    test('owner: duyệt yêu cầu; đổi vai trò; chuyển quyền; xóa/cấm', () {
      expect(acts('owner', _m('pete', 'member', status: 'pending')), {MemberAction.approve, MemberAction.reject, MemberAction.ban});
      expect(acts('owner', _m('mia', 'member')), {MemberAction.makeAdmin, MemberAction.transferOwnership, MemberAction.remove, MemberAction.ban});
      expect(acts('owner', _m('adam', 'admin')), {MemberAction.makeMember, MemberAction.transferOwnership, MemberAction.remove, MemberAction.ban});
    });

    test('admin: duyệt và xóa member, không đụng admin/owner, không đổi vai trò', () {
      expect(acts('admin', _m('pete', 'member', status: 'pending')), {MemberAction.approve, MemberAction.reject, MemberAction.ban});
      expect(acts('admin', _m('mia', 'member')), {MemberAction.remove, MemberAction.ban});
      expect(acts('admin', _m('ann', 'admin')), isEmpty);
      expect(acts('admin', _m('olly', 'owner')), isEmpty);
    });

    test('member/người ngoài không có hành động; không ai thao tác lên chính mình', () {
      expect(acts('member', _m('mia', 'member')), isEmpty);
      expect(acts('none', _m('mia', 'member')), isEmpty);
      expect(availableMemberActions(myRole: 'owner', myUid: 'mia', target: _m('mia', 'member')), isEmpty);
    });
  });

  group('TM03: mã mời', () {
    test('mã 8 ký tự từ bảng chữ không gây nhầm; chuẩn hóa chữ thường/khoảng trắng/gạch', () {
      var i = 0;
      final code = generateInviteCode((max) => (i++ * 7) % max);
      expect(code, hasLength(inviteCodeLength));
      expect(code.split('').every(inviteAlphabet.contains), isTrue);
      expect(normalizeInviteCode(' abcd-efgh '), 'ABCDEFGH');
      expect(normalizeInviteCode('ABCD'), isNull);
      expect(normalizeInviteCode('ABCDEFG0'), isNull, reason: 'số 0 dễ nhầm chữ O nên không có trong bảng');
      expect(inviteAlphabet.contains(RegExp('[01IOL]')), isFalse);
    });

    test('hết hạn / hết lượt', () {
      expect(checkInvite(expiresAt: 100, uses: 0, maxUses: 5, nowMs: 50), isNull);
      expect(checkInvite(expiresAt: 100, uses: 0, maxUses: 5, nowMs: 100), InviteProblem.expired);
      expect(checkInvite(expiresAt: 100, uses: 5, maxUses: 5, nowMs: 50), InviteProblem.usedUp);
    });
  });

  group('widget', () {
    sqfliteFfiInit();
    late AppDatabase db;
    setUp(() async => db = await AppDatabase.open(name: inMemoryDatabasePath, factory: databaseFactoryFfiNoIsolate));
    tearDown(() => db.close());

    Future<void> pump(WidgetTester tester, Widget screen, ExploreRepository repo) async {
      SharedPreferences.setMockInitialValues({'guest_id': 'guest:test', 'user_id': 'me', 'user_email': 'x@y.z'});
      final prefs = await SharedPreferences.getInstance();
      await tester.binding.setSurfaceSize(const Size(420, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (c, s) => screen),
          GoRoute(path: '/profile/explore/clubs/:id', builder: (c, s) => Text('club:${s.pathParameters['id']}')),
          GoRoute(
            path: '/edit/:id',
            builder: (c, s) => CreateClubScreen(clubId: s.pathParameters['id']),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            sharedPrefsProvider.overrideWithValue(prefs),
            permissionsProvider.overrideWithValue(FakePermissionCoordinator()),
            exploreRepositoryProvider.overrideWithValue(repo),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    testWidgets('TM01: tên quá ngắn báo lỗi, không gửi; hợp lệ → tạo một lần (chạm đúp) rồi mở club mới', (tester) async {
      final repo = _FakeRepo()..gate = Completer<void>();
      await pump(tester, const CreateClubScreen(), repo);
      await tester.enterText(find.byKey(const Key('club-name')), 'ab');
      await tester.tap(find.byKey(const Key('club-create')));
      await tester.pump();
      expect(find.text('Use at least 3 characters.'), findsOneWidget);
      expect(repo.created, isEmpty);

      await tester.enterText(find.byKey(const Key('club-name')), 'Morning Crew');
      await tester.tap(find.byKey(const Key('club-private')));
      await tester.pump();
      expect(find.text('People must request to join and be approved by you or an admin.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('club-create')));
      await tester.tap(find.byKey(const Key('club-create')), warnIfMissed: false);
      repo.gate!.complete();
      await tester.pumpAndSettle();
      expect(repo.created, [
        {'name': 'Morning Crew', 'description': '', 'region': '', 'private': true},
      ]);
      expect(find.text('club:new-id'), findsOneWidget);
    });

    testWidgets('TM04: sửa club — điền sẵn dữ liệu (cả nội quy), lưu rồi quay lại', (tester) async {
      final repo = _FakeRepo();
      await pump(tester, const Text('home'), repo);
      unawaited(GoRouter.of(tester.element(find.text('home'))).push('/edit/c1'));
      await tester.pumpAndSettle();
      expect(find.text('Edit club'), findsOneWidget);
      expect(find.text('Be kind'), findsOneWidget);
      expect(find.text('Save changes'), findsOneWidget);
      // T01/T08: vùng chạm ≥ 48 (Android) / 44 (iOS), mọi vùng chạm có nhãn.
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      expect(find.textContaining('You can own up to'), findsNothing);

      await tester.enterText(find.byKey(const Key('club-rules')), 'No ads');
      await tester.enterText(find.byKey(const Key('club-name')), 'Evening Crew');
      await tester.tap(find.byKey(const Key('club-create')));
      await tester.pumpAndSettle();
      expect(repo.updated, [
        {'id': 'c1', 'name': 'Evening Crew', 'private': true, 'rules': 'No ads'},
      ]);
      expect(find.text('home'), findsOneWidget);
    });

    testWidgets('TM02: owner duyệt yêu cầu, menu có Make admin/Make owner; admin không đổi được vai trò', (tester) async {
      final repo = _FakeRepo(
        members: [_m('me', 'owner'), _m('mia', 'member')],
        pending: [_m('pete', 'member', status: 'pending')],
      );
      await pump(tester, const ClubMembersScreen(clubId: 'c1'), repo);
      expect(find.text('Join requests (1)'), findsOneWidget);
      await tester.tap(find.text('Approve'));
      await tester.pumpAndSettle();
      expect(repo.calls, ['approve:pete']);
      expect(find.text('Join requests (1)'), findsNothing);

      await tester.tap(find.byKey(const Key('member-menu-mia')));
      await tester.pumpAndSettle();
      expect(find.text('Make admin'), findsOneWidget);
      expect(find.text('Make owner'), findsOneWidget);
      await tester.tap(find.text('Make admin'));
      await tester.pumpAndSettle();
      expect(repo.calls.last, 'role:mia:admin');
      expect(find.byKey(const Key('member-menu-me')), findsNothing, reason: 'không có hành động lên chính mình');
    });

    testWidgets('TM02: cấm cần xác nhận; admin thấy Remove/Ban nhưng không thấy Make admin', (tester) async {
      final repo = _FakeRepo(myRole: 'admin', members: [_m('olly', 'owner'), _m('me', 'admin'), _m('mia', 'member')]);
      await pump(tester, const ClubMembersScreen(clubId: 'c1'), repo);
      expect(find.byKey(const Key('member-menu-olly')), findsNothing);
      await tester.tap(find.byKey(const Key('member-menu-mia')));
      await tester.pumpAndSettle();
      expect(find.text('Make admin'), findsNothing);
      await tester.tap(find.text('Ban from club'));
      await tester.pumpAndSettle();
      expect(find.text('Ban Mia?'), findsOneWidget);
      expect(repo.calls, isEmpty);
      await tester.tap(find.text('Ban from club').last);
      await tester.pumpAndSettle();
      expect(repo.calls, ['ban:mia']);
    });
  });
}
