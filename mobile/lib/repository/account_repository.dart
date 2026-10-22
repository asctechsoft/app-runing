import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../services/application/firebase_providers.dart';
import '../services/application/api_client.dart';
import '../controller/providers.dart';
import '../utils/clock.dart';
import 'settings_repository.dart';
import 'auth_repository.dart';

/// Job export / xóa tài khoản: queued | running | succeeded | failed (H06). Nay chạy ở client nên thường đi thẳng tới
/// succeeded/failed, nhưng giữ dạng cũ để UI không đổi.
class AccountJob {
  const AccountJob({required this.id, required this.kind, required this.status, this.createdAt, this.finishedAt, this.expiresAt, this.error});

  final String id;
  final String kind;
  final String status;
  final int? createdAt;
  final int? finishedAt;
  final int? expiresAt;
  final String? error;

  bool get isOpen => status == 'queued' || status == 'running';
  bool get succeeded => status == 'succeeded';
  bool get failed => status == 'failed';
  bool isExpired(int nowMs) => expiresAt != null && expiresAt! <= nowMs;

  factory AccountJob.fromJson(Map<String, Object?> j) => AccountJob(
    id: j['id'] as String,
    kind: j['kind'] as String? ?? '',
    status: j['status'] as String? ?? 'queued',
    createdAt: (j['createdAt'] as num?)?.toInt(),
    finishedAt: (j['finishedAt'] as num?)?.toInt(),
    expiresAt: (j['expiresAt'] as num?)?.toInt(),
    error: j['error'] as String?,
  );
}

/// Đổi giá trị Firestore sang giá trị JSON được: Timestamp → epoch ms, GeoPoint → {lat, lon}, đệ quy qua Map/List.
Object? exportJsonSafe(Object? v) {
  if (v is Timestamp) return v.millisecondsSinceEpoch;
  if (v is GeoPoint) return {'lat': v.latitude, 'lon': v.longitude};
  if (v is Map) return {for (final e in v.entries) '${e.key}': exportJsonSafe(e.value)};
  if (v is Iterable) return [for (final e in v) exportJsonSafe(e)];
  return v;
}

/// Dựng cấu trúc export từ dữ liệu đã đọc (thuần, test được). Mỗi activity có `trackChunks`: list `{seq, count, sha256, json}`;
/// `json` (chuỗi) được giải mã thành `points` để file đọc được; chunk hỏng giữ nguyên chuỗi gốc.
Map<String, Object?> buildExportMap({
  required String uid,
  required int exportedAt,
  required Map<String, Object?>? user,
  required List<Map<String, Object?>> goals,
  required List<Map<String, Object?>> activities,
}) {
  Map<String, Object?> chunk(Map<String, Object?> c) {
    final raw = c['json'];
    Object? parsed;
    if (raw is String) {
      try {
        parsed = jsonDecode(raw);
      } catch (_) {
        parsed = null;
      }
    }
    return {'seq': c['seq'], 'count': c['count'], 'sha256': c['sha256'], if (parsed != null) 'points': parsed else 'raw': raw};
  }

  return {
    'format': 'stride-export',
    'version': 1,
    'exportedAt': exportedAt,
    'uid': uid,
    'user': exportJsonSafe(user),
    'goals': [for (final g in goals) exportJsonSafe(g)],
    'activities': [
      for (final a in activities)
        {
          for (final e in a.entries)
            if (e.key != 'trackChunks') e.key: exportJsonSafe(e.value),
          'trackChunks': [for (final c in (a['trackChunks'] as List? ?? const [])) chunk((c as Map).cast<String, Object?>())],
        },
    ],
  };
}

final accountRepositoryProvider = Provider<AccountRepository>(
  (ref) => AccountRepository(
    auth: ref.watch(authRepositoryProvider),
    settings: ref.watch(settingsRepositoryProvider),
    firestore: () => ref.read(firestoreProvider),
    firebaseAuth: () => ref.read(firebaseAuthProvider),
    clock: ref.watch(clockProvider),
  ),
);

/// Export dữ liệu và xóa tài khoản chạy ở client trên Firestore (H06, I07). Không bao giờ báo thành công khi chưa xong.
class AccountRepository {
  AccountRepository({
    required this.auth,
    required SettingsRepository settings,
    required FirebaseFirestore Function() firestore,
    required FirebaseAuth Function() firebaseAuth,
    required Clock clock,
  }) : _settings = settings,
       _fsFn = firestore,
       _authFn = firebaseAuth,
       _clock = clock;

  final AuthRepository auth;
  final SettingsRepository _settings;
  final FirebaseFirestore Function() _fsFn;
  final FirebaseAuth Function() _authFn;
  final Clock _clock;

  static const _kExportJob = 'account.export_job';
  static const _batchLimit = 400;

  /// Export đã tạo, giữ trong bộ nhớ (không lưu đĩa: file chứa vị trí GPS).
  final Map<String, Uint8List> _exports = {};
  final Map<String, AccountJob> _exportJobs = {};

  String _requireUid() {
    if (!auth.available) throw ApiException(0, 'not_configured', 'Firebase is not configured for this build');
    final uid = auth.uid;
    if (uid == null) throw ApiException(401, 'unauthorized', 'Not signed in');
    return uid;
  }

  Future<String?> lastExportId(String owner) => _settings.kvGet(owner, _kExportJob);

  /// Gom toàn bộ `users/{uid}` thành JSON và trả job `succeeded` ngay khi đọc xong.
  Future<AccountJob> createExport(String owner) => guardFirebase(() async {
    final uid = _requireUid();
    final userRef = _fsFn().collection('users').doc(uid);
    final userSnap = await userRef.get();
    final goals = await userRef.collection('goals').get();
    final acts = await userRef.collection('activities').get();
    final activities = <Map<String, Object?>>[];
    for (final a in acts.docs) {
      final chunks = await a.reference.collection('trackChunks').get();
      final list = [for (final c in chunks.docs) c.data().cast<String, Object?>()]
        ..sort((x, y) => ((x['seq'] as num?) ?? 0).compareTo((y['seq'] as num?) ?? 0));
      activities.add({'id': a.id, ...a.data().cast<String, Object?>(), 'trackChunks': list});
    }
    final now = _clock.nowMs();
    final map = buildExportMap(
      uid: uid,
      exportedAt: now,
      user: userSnap.data()?.cast<String, Object?>(),
      goals: [
        for (final g in goals.docs) {'id': g.id, ...g.data().cast<String, Object?>()},
      ],
      activities: activities,
    );
    final bytes = Uint8List.fromList(utf8.encode(const JsonEncoder.withIndent('  ').convert(map)));
    final id = 'export-${const Uuid().v4()}';
    final job = AccountJob(id: id, kind: 'export', status: 'succeeded', createdAt: now, finishedAt: now);
    _exports[id] = bytes;
    _exportJobs[id] = job;
    await _settings.kvSet(owner, _kExportJob, id);
    return job;
  });

  /// Export chỉ giữ trong bộ nhớ: sau khi khởi động lại app không còn → 404 (UI chỉ hiện nút tạo mới).
  Future<AccountJob> getExport(String id) async {
    final job = _exportJobs[id];
    if (job == null) throw ApiException(404, 'not_found', 'Export is no longer available');
    return job;
  }

  /// Nội dung JSON (UTF-8) của export.
  Future<Uint8List> downloadExport(String id) async {
    final bytes = _exports[id];
    if (bytes == null) throw ApiException(404, 'not_found', 'Export is no longer available');
    return bytes;
  }

  Future<AccountJob> requestDeletion(String password) async {
    await auth.reauth(password);
    return _deleteEverything();
  }

  /// Biến thể cho tài khoản Google (không có mật khẩu): xác thực lại bằng credential Google.
  Future<AccountJob> requestDeletionWithGoogle(AuthCredential credential) async {
    await auth.reauthWithGoogle(credential);
    return _deleteEverything();
  }

  /// Xóa subcollection → `userLookup` → `users/{uid}` → tài khoản Auth. Chỉ trả succeeded khi `user.delete()` xong.
  Future<AccountJob> _deleteEverything() => guardFirebase(() async {
    final uid = _requireUid();
    final user = _authFn().currentUser;
    if (user == null) throw ApiException(401, 'unauthorized', 'Not signed in');
    final fs = _fsFn();
    final userRef = fs.collection('users').doc(uid);
    final start = _clock.nowMs();
    // Dấu "đang xóa": nếu bị gián đoạn, deletionStatus báo thất bại thay vì im lặng.
    await userRef.set({'deletionRequestedAt': start}, SetOptions(merge: true));
    for (final sub in const ['goals', 'blocks', 'savedRoutes', 'challengeJoins']) {
      await _deleteCollection(fs, userRef.collection(sub));
    }
    await _deleteCollection(fs, userRef.collection('activities'), nested: const ['trackChunks']);
    final email = user.email;
    if (email != null && email.isNotEmpty) {
      final lookup = fs.collection('userLookup').doc(emailLowerOf(email));
      final snap = await lookup.get();
      if (snap.exists && snap.data()?['uid'] == uid) await lookup.delete();
    }
    await userRef.delete();
    await user.delete();
    return AccountJob(id: 'delete-$uid', kind: 'deleteAccount', status: 'succeeded', createdAt: start, finishedAt: _clock.nowMs());
  });

  /// Xóa mọi document của [col] theo lô ≤ [_batchLimit]; [nested] là các subcollection con xóa trước.
  Future<void> _deleteCollection(FirebaseFirestore fs, CollectionReference<Map<String, dynamic>> col, {List<String> nested = const []}) async {
    while (true) {
      final snap = await col.limit(_batchLimit).get();
      if (snap.docs.isEmpty) return;
      for (final d in snap.docs) {
        for (final n in nested) {
          await _deleteCollection(fs, d.reference.collection(n));
        }
      }
      final batch = fs.batch();
      for (final d in snap.docs) {
        batch.delete(d.reference);
      }
      await batch.commit();
    }
  }

  /// Trạng thái yêu cầu xóa; null nếu chưa từng yêu cầu. Dấu còn lại mà không đang chạy = bị gián đoạn → failed.
  Future<AccountJob?> deletionStatus() async {
    final uid = auth.uid;
    if (uid == null) return null;
    try {
      final snap = await _fsFn().collection('users').doc(uid).get();
      final at = (snap.data()?['deletionRequestedAt'] as num?)?.toInt();
      if (at == null) return null;
      return AccountJob(id: 'delete-$uid', kind: 'deleteAccount', status: 'failed', createdAt: at, error: 'Deletion was interrupted. Try again.');
    } catch (e) {
      final err = mapFirebaseError(e);
      if (err.isNotFound) return null;
      throw err;
    }
  }
}

/// Thông báo lỗi cho các thao tác tài khoản.
String accountErrorMessage(Object e) {
  if (e is FirebaseException) e = mapFirebaseError(e);
  if (e is ApiException) {
    if (e.code == 'not_configured') return "Accounts aren't available in this build.";
    if (e.isNetwork) return "You're offline. Connect to the internet and try again.";
    switch (e.code) {
      case 'invalid_credentials':
        return 'That password is incorrect.';
      case 'reauth_required':
        return 'Confirm your password again to continue.';
      case 'export_not_ready':
        return 'Your export is still being prepared.';
      case 'export_expired':
        return 'This export has expired. Create a new one.';
      case 'rate_limited':
        return 'Too many attempts. Wait a minute and try again.';
      case 'account_disabled':
        return 'This account is being deleted or has been deleted.';
      case 'validation_error':
        return 'Some details are not valid. Check and try again.';
      case 'forbidden':
        return "You don't have permission to do that.";
      case 'unauthorized':
      case 'invalid_token':
        return 'Your session has expired. Log in again.';
    }
    if (e.status >= 500) return 'Something went wrong on our side. Please try again.';
  }
  return 'Something went wrong. Please try again.';
}
