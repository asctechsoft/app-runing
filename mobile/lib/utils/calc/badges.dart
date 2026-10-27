import '../../models/data_models/activity.dart';
import 'group_eligibility.dart';

/// Huy hiệu (TM40, ADR 0003: chỉ huy hiệu số, không giải thật). Tính lại hoàn toàn từ dữ liệu (hoạt động cục bộ, chuỗi,
/// thử thách đã hoàn thành) nên **idempotent**: cùng dữ liệu → cùng tập huy hiệu, không bao giờ trao hai lần. Lần đầu thấy
/// một huy hiệu được ghi lại (kv) để báo "mới" đúng một lần.

enum BadgeRarity { common, rare, epic }

enum BadgeKind {
  first5k(5000),
  first10k(10000),
  firstHalf(21097.5),
  total100km(100000),
  total500km(500000),
  streak7(7),
  streak30(30),
  streak100(100),
  challenge(1);

  const BadgeKind(this.threshold);

  /// m cho mốc quãng đường, ngày cho chuỗi.
  final double threshold;

  BadgeRarity get rarity => switch (this) {
    first5k || total100km || streak7 || challenge => BadgeRarity.common,
    first10k || total500km || streak30 => BadgeRarity.rare,
    firstHalf || streak100 => BadgeRarity.epic,
  };
}

/// Mốc cá nhân, theo thứ tự hiển thị trong tủ.
const personalBadges = [
  BadgeKind.first5k,
  BadgeKind.first10k,
  BadgeKind.firstHalf,
  BadgeKind.total100km,
  BadgeKind.total500km,
  BadgeKind.streak7,
  BadgeKind.streak30,
  BadgeKind.streak100,
];

class EarnedBadge {
  const EarnedBadge({required this.id, required this.kind, this.earnedAt, this.title});

  /// Khóa ổn định: tên mốc, hoặc `challenge:<id>`.
  final String id;
  final BadgeKind kind;

  /// Thời điểm đạt nếu suy ra được từ dữ liệu (mốc quãng đường, hoàn thành thử thách); null với chuỗi.
  final int? earnedAt;

  /// Tên thử thách (huy hiệu thử thách).
  final String? title;
}

/// Thử thách tôi đã hoàn thành (từ participant `completedAt`).
typedef CompletedChallenge = ({String id, String title, int completedAt});

/// Hoạt động tính cho mốc quãng đường: run/walk đã lưu, quãng đường GPS thật, không vị trí giả.
bool countsForDistanceBadges(Activity a) =>
    a.status == ActivityStatus.saved &&
    a.deletedAt == null &&
    a.type != ActivityType.indoorRun &&
    a.distanceSource == DistanceSource.gps &&
    !a.locationMocked &&
    (a.distanceM ?? 0) > 0;

List<EarnedBadge> evaluateBadges({required Iterable<Activity> activities, required int longestStreak, Iterable<CompletedChallenge> challenges = const []}) {
  // TM62: buổi chồng thời gian (ghi đôi) chỉ tính một lần cho mốc quãng đường.
  final acts = dropOverlapping(activities.where(countsForDistanceBadges));
  final out = <EarnedBadge>[];
  for (final k in [BadgeKind.first5k, BadgeKind.first10k, BadgeKind.firstHalf]) {
    final hit = acts.where((a) => a.distanceM! >= k.threshold).firstOrNull;
    if (hit != null) out.add(EarnedBadge(id: k.name, kind: k, earnedAt: hit.startedAt));
  }
  for (final k in [BadgeKind.total100km, BadgeKind.total500km]) {
    var sum = 0.0;
    for (final a in acts) {
      sum += a.distanceM!;
      if (sum >= k.threshold) {
        out.add(EarnedBadge(id: k.name, kind: k, earnedAt: a.startedAt));
        break;
      }
    }
  }
  for (final k in [BadgeKind.streak7, BadgeKind.streak30, BadgeKind.streak100]) {
    if (longestStreak >= k.threshold) out.add(EarnedBadge(id: k.name, kind: k));
  }
  for (final c in challenges) {
    out.add(EarnedBadge(id: 'challenge:${c.id}', kind: BadgeKind.challenge, earnedAt: c.completedAt, title: c.title));
  }
  return out;
}

/// Huy hiệu chưa từng thấy (so với [seen]) — để báo "mới" một lần.
List<EarnedBadge> newlyEarned(List<EarnedBadge> earned, Set<String> seen) => [
  for (final b in earned)
    if (!seen.contains(b.id)) b,
];
