import '../../models/data_models/activity.dart';

/// Quy tắc hoạt động hợp lệ cho chuỗi, nhóm và thử thách (TM24, ADR 0003 câu 2, 5, 6).

/// Ngưỡng tối thiểu của một buổi: ≥ 1 km HOẶC ≥ 10 phút di chuyển.
const minEligibleDistanceM = 1000.0;
const minEligibleMovingMs = 10 * 60 * 1000;

/// Pace trung bình nhanh hơn ngưỡng này (giây/km) coi như đi xe → không tính.
const fastestPlausiblePaceSecPerKm = {ActivityType.run: 150.0, ActivityType.walk: 360.0};

/// Lý do một hoạt động không được tính. Thứ tự kiểm tra theo bảng dưới (lý do đầu tiên khớp được trả về).
enum IneligibleReason {
  /// Chưa lưu (đang ghi, chờ lưu, đã bỏ) hoặc đã xóa.
  notSaved,

  /// `indoorRun`: quãng đường ước lượng từ bước, không có GPS thật.
  indoor,

  /// Không có điểm GPS hợp lệ hoặc quãng đường không đến từ GPS.
  noGps,

  /// Có điểm từ ứng dụng vị trí giả.
  mockedLocation,

  /// Dưới 1 km và dưới 10 phút.
  tooShort,

  /// Nhanh bất thường so với loại hoạt động.
  implausibleSpeed,

  /// Riêng tư (`onlyMe`) — chỉ áp dụng khi đóng góp cho nhóm/thử thách.
  private,
}

/// Lý do hoạt động không tính cho **chuỗi cá nhân**; null = hợp lệ. Quyền riêng tư không ảnh hưởng chuỗi của chính mình.
IneligibleReason? streakIneligibility(Activity a) {
  if (a.status != ActivityStatus.saved || a.deletedAt != null) return IneligibleReason.notSaved;
  if (a.type == ActivityType.indoorRun) return IneligibleReason.indoor;
  final d = a.distanceM;
  if (!a.hasGps || a.distanceSource != DistanceSource.gps || d == null) return IneligibleReason.noGps;
  if (a.locationMocked) return IneligibleReason.mockedLocation;
  if (d < minEligibleDistanceM && a.movingMs < minEligibleMovingMs) return IneligibleReason.tooShort;
  final limit = fastestPlausiblePaceSecPerKm[a.type];
  if (limit != null && d > 0 && a.movingMs > 0) {
    final pace = (a.movingMs / 1000) / (d / 1000);
    if (pace < limit) return IneligibleReason.implausibleSpeed;
  }
  return null;
}

/// Lý do hoạt động không được **đóng góp cho nhóm/thử thách**; null = hợp lệ. Thêm điều kiện không riêng tư (TM00.5).
IneligibleReason? groupIneligibility(Activity a) => streakIneligibility(a) ?? (a.privacy == Privacy.onlyMe ? IneligibleReason.private : null);

bool isStreakEligible(Activity a) => streakIneligibility(a) == null;
bool isGroupEligible(Activity a) => groupIneligibility(a) == null;

/// TM62 "lộ trình trùng": hai hoạt động của cùng một người **chồng thời gian** (ghi đôi, nhập lại, hai máy cùng ghi) chỉ
/// tính một — giữ buổi có quãng đường dài hơn (bằng nhau → bắt đầu sớm hơn, rồi id). Khoảng của buổi =
/// [startedAt, endedAt] (thiếu endedAt → startedAt + elapsedMs). Trả danh sách theo thứ tự bắt đầu.
List<Activity> dropOverlapping(Iterable<Activity> activities) {
  int endOf(Activity a) => a.endedAt ?? a.startedAt + a.elapsedMs;
  bool better(Activity a, Activity b) {
    final c = (a.distanceM ?? 0).compareTo(b.distanceM ?? 0);
    if (c != 0) return c > 0;
    if (a.startedAt != b.startedAt) return a.startedAt < b.startedAt;
    return a.id.compareTo(b.id) < 0;
  }

  final sorted = [...activities]..sort((a, b) => a.startedAt.compareTo(b.startedAt));
  final kept = <Activity>[];
  for (final a in sorted) {
    if (kept.isNotEmpty && a.startedAt < endOf(kept.last)) {
      if (better(a, kept.last)) kept[kept.length - 1] = a;
      continue;
    }
    kept.add(a);
  }
  return kept;
}
