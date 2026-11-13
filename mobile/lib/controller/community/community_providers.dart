import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../configs/pref_const.dart';

import '../../models/ui_models/community_models.dart';
import '../../repository/community_repository.dart';
import '../../services/application/firebase_providers.dart';
import '../explore/explore_logic.dart';
import '../providers.dart';

/// Cộng đồng chỉ mở cho tài khoản đã đăng nhập (Firebase sẵn sàng và không phải khách).
final communitySignedInProvider = Provider<bool>((ref) => ref.watch(firebaseReadyProvider) && !ref.watch(ownerProvider).isGuest);

/// Bảng tin đã tải: các bài, cursor trang kế (null khi hết) và cờ đang tải thêm.
class CommunityFeed {
  const CommunityFeed({this.posts = const [], this.nextCursor, this.loadingMore = false});
  final List<CommunityPost> posts;
  final int? nextCursor;
  final bool loadingMore;

  bool get hasMore => nextCursor != null;

  CommunityFeed copyWith({List<CommunityPost>? posts, int? nextCursor, bool clearCursor = false, bool? loadingMore}) =>
      CommunityFeed(posts: posts ?? this.posts, nextCursor: clearCursor ? null : (nextCursor ?? this.nextCursor), loadingMore: loadingMore ?? this.loadingMore);
}

/// Bảng tin Cộng đồng. Chưa đăng nhập → rỗng, không gọi Firestore. Thả tim cập nhật ngay (lạc quan) rồi hoàn lại nếu lỗi.
class CommunityFeedController extends AsyncNotifier<CommunityFeed> {
  @override
  Future<CommunityFeed> build() async {
    if (!ref.watch(communitySignedInProvider)) return const CommunityFeed();
    final page = await ref.read(communityRepositoryProvider).feed();
    return CommunityFeed(posts: page.posts, nextCursor: page.nextCursor);
  }

  Future<void> refresh() async {
    if (!ref.read(communitySignedInProvider)) return;
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final page = await ref.read(communityRepositoryProvider).feed();
      return CommunityFeed(posts: page.posts, nextCursor: page.nextCursor);
    });
  }

  /// Tải trang kế. Trả null khi thành công (hoặc không có gì để tải), ngược lại là câu lỗi đã dịch; danh sách hiện có được giữ nguyên.
  Future<String?> loadMore() async {
    final cur = state.value;
    if (cur == null || !cur.hasMore || cur.loadingMore) return null;
    state = AsyncData(cur.copyWith(loadingMore: true));
    try {
      final page = await ref.read(communityRepositoryProvider).feed(beforeCreatedAt: cur.nextCursor);
      final seen = {for (final p in cur.posts) p.id};
      state = AsyncData(CommunityFeed(posts: [...cur.posts, ...page.posts.where((p) => !seen.contains(p.id))], nextCursor: page.nextCursor));
      return null;
    } catch (e) {
      state = AsyncData(cur.copyWith(loadingMore: false));
      return communityErrorMessage(e);
    }
  }

  /// Trả null khi thành công, ngược lại là câu lỗi đã dịch (UI hiển thị). Trạng thái được hoàn lại khi lỗi.
  Future<String?> toggleLike(String postId) async {
    final before = state.value;
    if (before == null) return null;
    final i = before.posts.indexWhere((p) => p.id == postId);
    if (i < 0) return null;
    final old = before.posts[i];
    final on = !old.likedByMe;
    _replace(postId, old.copyWith(likedByMe: on, likeCount: nextCounter(old.likeCount, on ? 1 : -1)));
    try {
      final server = await ref.read(communityRepositoryProvider).setLike(postId, on);
      _replace(postId, server);
      return null;
    } catch (e) {
      _replace(postId, old);
      return communityErrorMessage(e);
    }
  }

  /// Xóa bài của mình. Trả null khi thành công, ngược lại là câu lỗi đã dịch.
  Future<String?> delete(String postId) async {
    try {
      await ref.read(communityRepositoryProvider).delete(postId);
      _removeWhere((p) => p.id == postId);
      await ref.read(communitySharesProvider.notifier).forgetPost(postId);
      return null;
    } catch (e) {
      return communityErrorMessage(e);
    }
  }

  /// Báo cáo bài [post] (hoặc người đăng khi [user] = true). Trả null khi thành công.
  Future<String?> report(CommunityPost post, String reason, {bool user = false}) async {
    try {
      await ref
          .read(communityRepositoryProvider)
          .report(targetType: user ? 'user' : 'community_post', targetId: user ? post.authorId : post.id, reason: reason);
      return null;
    } catch (e) {
      return communityErrorMessage(e);
    }
  }

  /// Chặn người đăng [authorId]: bài của họ biến mất khỏi bảng tin ngay. Trả null khi thành công.
  Future<String?> block(String authorId) async {
    try {
      await ref.read(communityRepositoryProvider).blockUser(authorId);
      _removeWhere((p) => p.authorId == authorId);
      return null;
    } catch (e) {
      return communityErrorMessage(e);
    }
  }

  void _removeWhere(bool Function(CommunityPost p) test) {
    final cur = state.value;
    if (cur == null) return;
    state = AsyncData(
      cur.copyWith(
        posts: [
          for (final p in cur.posts)
            if (!test(p)) p,
        ],
      ),
    );
  }

  void _replace(String id, CommunityPost p) {
    final cur = state.value;
    if (cur == null) return;
    state = AsyncData(cur.copyWith(posts: [for (final x in cur.posts) x.id == id ? p : x]));
  }
}

final communityFeedProvider = AsyncNotifierProvider.autoDispose<CommunityFeedController, CommunityFeed>(CommunityFeedController.new);

/// Các buổi đã chia sẻ lên Cộng đồng từ máy này: `activityId → postId`, lưu trong SharedPreferences. Dùng để hiện
/// "Ngừng chia sẻ" cho từng buổi và không đăng trùng. Chỉ phản ánh bài đăng từ máy này (không đồng bộ qua máy khác).
class CommunitySharesController extends Notifier<Map<String, String>> {
  @override
  Map<String, String> build() {
    final raw = ref.read(sharedPrefsProvider).getString(PrefConst.communityShared);
    if (raw == null) return const {};
    try {
      return (jsonDecode(raw) as Map).map((k, v) => MapEntry(k as String, v as String));
    } catch (_) {
      return const {};
    }
  }

  Future<void> _save(Map<String, String> next) async {
    state = next;
    await ref.read(sharedPrefsProvider).setString(PrefConst.communityShared, jsonEncode(next));
  }

  Future<void> record(String activityId, String postId) => _save({...state, activityId: postId});

  Future<void> forgetActivity(String activityId) => _save({...state}..remove(activityId));

  /// Bài bị xóa từ bảng tin: bỏ mọi buổi trỏ tới bài đó.
  Future<void> forgetPost(String postId) async {
    if (!state.containsValue(postId)) return;
    await _save({...state}..removeWhere((_, v) => v == postId));
  }
}

final communitySharesProvider = NotifierProvider<CommunitySharesController, Map<String, String>>(CommunitySharesController.new);
