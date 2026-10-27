import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../repository/explore_repository.dart';
import '../../utils/calc/group_stats.dart';
import '../../utils/logger.dart';
import '../home/home_providers.dart';
import '../providers.dart';

/// Khóa kv: danh sách club tôi đã bật "chia sẻ tiến độ hằng ngày" (TM21/TM22, TM60 — mặc định tắt).
const groupShareKey = 'groupShareClubs';

/// Bật/tắt chia sẻ số liệu nhóm và đẩy số liệu mới nhất (khi mở app, khi bật chia sẻ). Lựa chọn lưu cục bộ theo owner;
/// tắt thì xóa luôn số liệu đã chia sẻ trên Firestore.
class GroupSharing {
  GroupSharing(this._ref);
  final Ref _ref;

  Future<Set<String>> clubs() async {
    final raw = await _ref.read(settingsRepositoryProvider).kvGet(_ref.read(ownerProvider).ownerId, groupShareKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      return (jsonDecode(raw) as List).whereType<String>().toSet();
    } catch (_) {
      return {};
    }
  }

  Future<void> _save(Set<String> ids) =>
      _ref.read(settingsRepositoryProvider).kvSet(_ref.read(ownerProvider).ownerId, groupShareKey, jsonEncode((ids.toList()..sort())));

  /// Bật: ghi số liệu ngay (lỗi → không lưu lựa chọn, ném lỗi cho UI). Tắt: xóa số liệu trên club rồi mới bỏ lựa chọn.
  Future<void> set(String clubId, bool on) async {
    final ids = await clubs();
    final repo = _ref.read(exploreRepositoryProvider);
    if (on) {
      await repo.publishMemberStats(clubId, await _days());
      await _save({...ids, clubId});
    } else {
      await repo.stopSharingStats(clubId);
      await _save(ids..remove(clubId));
    }
  }

  Future<Map<String, MemberDay>> _days() async {
    final (achieved, acts) = await loadAchievedDays(_ref, historyDays: groupStatsDays);
    return buildMemberDays(today: _ref.read(clockProvider).nowLocal(), achieved: achieved, activities: acts);
  }

  /// Đẩy số liệu tới mọi club đang chia sẻ. Khách / tắt cờ clubs → không làm gì; lỗi từng club (offline, đã rời club) chỉ ghi log.
  Future<void> publishAll() async {
    if (_ref.read(ownerProvider).isGuest || !_ref.read(flagsProvider).exploreClubs) return;
    final ids = await clubs();
    if (ids.isEmpty) return;
    final days = await _days();
    final repo = _ref.read(exploreRepositoryProvider);
    for (final id in ids) {
      try {
        await repo.publishMemberStats(id, days);
      } catch (e) {
        StrideLog.d('group', 'publish stats skipped: $e');
      }
    }
  }
}

final groupSharingProvider = Provider<GroupSharing>(GroupSharing.new);
