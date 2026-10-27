import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../repository/explore_repository.dart';
import '../../utils/calc/badges.dart';
import '../home/home_providers.dart';
import '../providers.dart';

/// Khóa kv: id huy hiệu → lần đầu thấy (ms). Dùng làm ngày nhận khi dữ liệu không suy ra được và để báo "mới" một lần.
const badgesSeenKey = 'badges.seen';

class BadgeCabinet {
  const BadgeCabinet({required this.earned, required this.seen});
  final List<EarnedBadge> earned;
  final Map<String, int> seen;

  /// Chưa báo lần nào.
  List<EarnedBadge> get fresh => newlyEarned(earned, seen.keys.toSet());

  /// Ngày nhận hiển thị: suy từ dữ liệu, nếu không có thì lần đầu thấy.
  int? earnedAtOf(EarnedBadge b) => b.earnedAt ?? seen[b.id];
}

Future<Map<String, int>> _readSeen(Ref ref) async {
  final raw = await ref.read(settingsRepositoryProvider).kvGet(ref.read(ownerProvider).ownerId, badgesSeenKey);
  if (raw == null || raw.isEmpty) return {};
  try {
    return {for (final e in (jsonDecode(raw) as Map).entries) '${e.key}': (e.value as num).toInt()};
  } catch (_) {
    return {};
  }
}

/// TM40: huy hiệu tính lại từ hoạt động cục bộ + chuỗi dài nhất + thử thách đã hoàn thành (khi đăng nhập; lỗi mạng → bỏ
/// phần thử thách, không báo lỗi cả tủ).
final badgesProvider = FutureProvider.autoDispose<BadgeCabinet>((ref) async {
  ref.watch(activityRevisionProvider);
  final owner = ref.watch(ownerProvider);
  final streak = await ref.watch(personalStreakProvider.future);
  final acts = await ref.read(activityRepositoryProvider).allInRange(owner.ownerId, 0, ref.read(clockProvider).nowMs() + 1);
  var challenges = const <CompletedChallenge>[];
  if (!owner.isGuest && ref.read(flagsProvider).exploreChallenges) {
    try {
      challenges = await ref.read(exploreRepositoryProvider).myCompletedChallenges();
    } catch (_) {}
  }
  return BadgeCabinet(
    earned: evaluateBadges(activities: acts, longestStreak: streak.longest, challenges: challenges),
    seen: await _readSeen(ref),
  );
});

/// Đánh dấu đã báo (ghi lần đầu thấy = [nowMs]); không ghi đè mốc cũ.
final markBadgesSeenProvider = Provider<Future<void> Function(Iterable<String> ids)>((ref) {
  return (ids) async {
    final seen = await _readSeen(ref);
    final now = ref.read(clockProvider).nowMs();
    for (final id in ids) {
      seen.putIfAbsent(id, () => now);
    }
    await ref.read(settingsRepositoryProvider).kvSet(ref.read(ownerProvider).ownerId, badgesSeenKey, jsonEncode(seen));
  };
});
