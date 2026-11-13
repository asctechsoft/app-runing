import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../controller/explore/explore_logic.dart';
import '../controller/providers.dart';
import '../models/data_models/activity.dart';
import '../models/ui_models/community_models.dart';
import '../services/application/api_client.dart';
import '../services/application/firebase_providers.dart';
import '../utils/l10n.dart';
import 'explore_repository.dart' show ExploreFailure, mapExploreError, maxBlocksRead;

/// Ảnh tuyến đường tối đa (byte PNG): base64 phải ≤ 262144 ký tự theo `firestore.rules` (4/3 kích thước gốc).
const maxCommunityImageBytes = 190000;

/// Số bài mỗi trang (chi phí Firestore: 1 đọc/bài + 1 đọc "tim của tôi"/bài).
const communityPageSize = 20;

Map<String, Object?> _data(DocumentSnapshot<Map<String, dynamic>> d) => Map<String, Object?>.from(d.data() ?? const {});

/// Cộng đồng trên Cloud Firestore (`communityPosts`, schema: docs/firestore-schema.md). Chỉ người đã đăng nhập đọc/đăng/thả tim.
/// Lỗi luôn là [ExploreFailure] để UI dùng chung thông báo.
class CommunityRepository {
  CommunityRepository({
    required this._ready,
    required this._firestore,
    required this._uid,
    this._displayName,
    int Function()? nowMs,
    this._timeout = const Duration(seconds: 20),
  }) : _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  final bool Function() _ready;
  final FirebaseFirestore Function() _firestore;
  final String? Function() _uid;
  final String? Function()? _displayName;
  final int Function() _nowMs;
  final Duration _timeout;
  static const _uuid = Uuid();

  Future<T> _run<T>(Future<T> Function(FirebaseFirestore db, String uid) f) async {
    try {
      if (!_ready()) throw ApiException(0, 'not_configured', 'Firebase is not configured for this build');
      final uid = _uid();
      if (uid == null) throw ApiException(401, 'unauthorized', 'Sign in required');
      return await f(_firestore(), uid).timeout(_timeout);
    } catch (e) {
      throw mapExploreError(e);
    }
  }

  CollectionReference<Map<String, dynamic>> _posts(FirebaseFirestore db) => db.collection('communityPosts');

  /// Một trang bài mới nhất trước ([beforeCreatedAt] = cursor của trang trước). Bỏ bài đã xóa mềm và bài của người đã chặn
  /// (danh sách chặn dùng chung với Explore); mỗi bài hỏi thêm "tôi đã thả tim chưa".
  Future<CommunityPage> feed({int? beforeCreatedAt, int limit = communityPageSize}) => _run((db, uid) async {
    Query<Map<String, dynamic>> q = _posts(db);
    // Cursor = createdAt (ms) của bài cuối trang trước; điều kiện + sắp xếp cùng một trường nên không cần composite index.
    if (beforeCreatedAt != null) q = q.where('createdAt', isLessThan: beforeCreatedAt);
    final snap = await q.orderBy('createdAt', descending: true).limit(limit).get();
    final blocked = await _blockedIds(db, uid);
    final docs = snap.docs.where((d) => d.data()['deletedAt'] == null && !blocked.contains(d.data()['authorId'])).toList();
    final posts = await Future.wait(
      docs.map((d) async {
        final like = await d.reference.collection('likes').doc(uid).get();
        return CommunityPost.fromDoc(d.id, _data(d), likedByMe: like.exists);
      }),
    );
    // Trang đầy (kể cả khi lọc bớt) → còn trang sau; cursor lấy từ document quét cuối cùng.
    final next = snap.docs.length >= limit ? (snap.docs.last.data()['createdAt'] as num?)?.toInt() : null;
    return CommunityPage(posts, next);
  });

  Future<Set<String>> _blockedIds(FirebaseFirestore db, String uid) async {
    final snap = await db.collection('users').doc(uid).collection('blocks').limit(maxBlocksRead).get();
    return {for (final d in snap.docs) d.id};
  }

  /// Đăng buổi chạy [a] (đã lưu) lên Cộng đồng. Gửi số liệu tóm tắt và, nếu có, ảnh tuyến đường [image] (PNG, ≤ [maxCommunityImageBytes]).
  /// Hoạt động chưa lưu hoặc đã xóa bị từ chối.
  Future<CommunityPost> publish(Activity a, {String text = '', Uint8List? image}) => _run((db, uid) async {
    if (a.status != ActivityStatus.saved || a.deletedAt != null) {
      throw ApiException(400, 'validation_error', 'Only saved activities can be shared');
    }
    if (image != null && image.length > maxCommunityImageBytes) {
      throw ApiException(400, 'validation_error', 'Image is too large to share');
    }
    final id = _uuid.v4();
    final data = <String, Object?>{
      'authorId': uid,
      'authorName': _displayName?.call() ?? '',
      'text': text.trim(),
      'createdAt': _nowMs(),
      'likeCount': 0,
      'deletedAt': null,
      'activity': CommunityPost.activityDoc(a),
      if (image != null) 'image': base64Encode(image),
    };
    await _posts(db).doc(id).set(data);
    return CommunityPost.fromDoc(id, data);
  });

  /// Thả tim ([on]) hoặc bỏ tim. Idempotent: thả lần hai không tăng thêm. Counter chỉ ±1 theo `firestore.rules`.
  Future<CommunityPost> setLike(String postId, bool on) => _run((db, uid) {
    final postRef = _posts(db).doc(postId);
    final likeRef = postRef.collection('likes').doc(uid);
    return db.runTransaction<CommunityPost>((tx) async {
      final post = await tx.get(postRef);
      if (!post.exists) throw ApiException(404, 'not_found', 'Post not found');
      final liked = await tx.get(likeRef);
      final d = _data(post);
      var count = (d['likeCount'] as num?)?.toInt() ?? 0;
      var now = liked.exists;
      if (on && !liked.exists) {
        tx.set(likeRef, {'createdAt': _nowMs()});
        count = nextCounter(count, 1);
        tx.update(postRef, {'likeCount': count});
        now = true;
      } else if (!on && liked.exists) {
        tx.delete(likeRef);
        count = nextCounter(count, -1);
        tx.update(postRef, {'likeCount': count});
        now = false;
      }
      return CommunityPost.fromDoc(postId, {...d, 'likeCount': count}, likedByMe: now);
    });
  });

  /// Báo cáo bài ([targetType] `community_post`) hoặc người dùng (`user`) cho đội STRIDE xem xét.
  Future<void> report({required String targetType, required String targetId, required String reason}) => _run((db, uid) async {
    await db.collection('reports').doc(_uuid.v4()).set({
      'reporterId': uid,
      'targetType': targetType,
      'targetId': targetId,
      'reason': reason,
      'createdAt': _nowMs(),
    });
  });

  /// Chặn [userId]: bài của họ biến mất khỏi bảng tin của tôi (và khỏi Explore — chung danh sách chặn).
  Future<void> blockUser(String userId) => _run((db, uid) async {
    if (userId == uid) throw ApiException(400, 'validation_error', 'explore_err_block_self'.tr);
    await db.collection('users').doc(uid).collection('blocks').doc(userId).set({'createdAt': _nowMs()});
  });

  /// Ngừng chia sẻ (xóa mềm): chỉ tác giả; đặt `deletedAt` và xóa luôn ảnh tuyến đường khỏi document.
  Future<void> delete(String postId) => _run((db, uid) => _posts(db).doc(postId).update({'deletedAt': _nowMs(), 'image': FieldValue.delete()}));
}

final communityRepositoryProvider = Provider<CommunityRepository>((ref) {
  bool ready() => ref.read(firebaseReadyProvider);
  return CommunityRepository(
    ready: ready,
    firestore: () => ref.read(firestoreProvider),
    uid: () => ready() ? ref.read(firebaseAuthProvider).currentUser?.uid : null,
    displayName: () {
      final n = ref.read(settingsProvider).value?.displayName.trim() ?? '';
      if (n.isNotEmpty) return n;
      return ready() ? ref.read(firebaseAuthProvider).currentUser?.displayName : null;
    },
  );
});

/// Lỗi hiển thị cho người dùng (đã dịch) từ mọi exception của luồng Cộng đồng.
String communityErrorMessage(Object e) => e is ExploreFailure ? e.userMessage : mapExploreError(e).userMessage;
