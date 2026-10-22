import '../../utils/l10n.dart';

/// Người được chọn theo dõi (tài khoản STRIDE đã xác minh, do backend xác nhận).
class LiveShareViewer {
  const LiveShareViewer({required this.userId, required this.label, this.email});

  final String userId;

  /// Tên hiển thị do backend trả; nếu không có thì là email người dùng đã nhập.
  final String label;
  final String? email;

  @override
  bool operator ==(Object other) => other is LiveShareViewer && other.userId == userId;
  @override
  int get hashCode => userId.hashCode;
}

/// Thời hạn chia sẻ. Mặc định: khi buổi chạy kết thúc.
enum LiveShareExpiry {
  whenRunEnds,
  oneHour,
  twoHours,
  fourHours;

  String get label => switch (this) {
    whenRunEnds => 'model_live_share_when_run_ends'.tr,
    oneHour => 'model_live_share_1h'.tr,
    twoHours => 'model_live_share_2h'.tr,
    fourHours => 'model_live_share_4h'.tr,
  };

  /// Cụm dùng trong câu xác nhận ("... for 1 hour"); mỗi ngôn ngữ có key riêng, không suy ra từ [label].
  String get untilPhrase => switch (this) {
    whenRunEnds => 'live_until_run_ends'.tr,
    oneHour => 'model_live_share_for_1h'.tr,
    twoHours => 'model_live_share_for_2h'.tr,
    fourHours => 'model_live_share_for_4h'.tr,
  };

  /// TTL gửi server. "Khi run kết thúc": client dừng chủ động khi end run; TTL 6 giờ chỉ là chốt an toàn
  /// nếu app bị tắt giữa chừng (server giới hạn tối đa 12 giờ).
  int get ttlMinutes => switch (this) {
    whenRunEnds => 6 * 60,
    oneHour => 60,
    twoHours => 120,
    fourHours => 240,
  };
}

/// Cấu hình chờ cho buổi chạy kế tiếp. Mặc định TẮT; plugin đọc lúc bắt đầu phiên rồi xóa (không tự áp cho run sau).
class LiveShareConfig {
  const LiveShareConfig({this.enabled = false, this.viewers = const [], this.expiry = LiveShareExpiry.whenRunEnds, this.consentedAt});

  final bool enabled;
  final List<LiveShareViewer> viewers;
  final LiveShareExpiry expiry;

  /// Thời điểm người dùng xác nhận đồng ý chia sẻ; null → chưa đồng ý → không chia sẻ.
  final int? consentedAt;

  bool get ready => enabled && viewers.isNotEmpty && consentedAt != null;

  LiveShareConfig copyWith({bool? enabled, List<LiveShareViewer>? viewers, LiveShareExpiry? expiry, int? Function()? consentedAt}) => LiveShareConfig(
    enabled: enabled ?? this.enabled,
    viewers: viewers ?? this.viewers,
    expiry: expiry ?? this.expiry,
    consentedAt: consentedAt != null ? consentedAt() : this.consentedAt,
  );
}

/// Bản ghi live share do server trả về.
class LiveShareSession {
  const LiveShareSession({
    required this.id,
    required this.activityId,
    required this.expiresAt,
    required this.active,
    this.lastUpdateAt,
    this.viewerIds = const [],
  });

  final String id;
  final String activityId;
  final int expiresAt;
  final bool active;
  final int? lastUpdateAt;
  final List<String> viewerIds;

  factory LiveShareSession.fromJson(Map<String, Object?> j) => LiveShareSession(
    id: j['id'] as String,
    activityId: j['activityId'] as String,
    expiresAt: (j['expiresAt'] as num).toInt(),
    active: j['active'] as bool? ?? false,
    lastUpdateAt: (j['lastUpdateAt'] as num?)?.toInt(),
    viewerIds: [for (final v in (j['viewerIds'] as List?) ?? const []) v as String],
  );
}

enum LiveSharePhase {
  /// Không chia sẻ trong phiên này.
  off,
  starting,
  active,
  paused,

  /// Mất mạng: chỉ giữ điểm mới nhất trong hàng đợi, hiển thị "last update".
  interrupted,

  /// Hết hạn / đã dừng.
  ended,

  /// Không bắt đầu được (vd. người xem không hợp lệ) — không tự thử lại.
  failed,
}

class LiveShareStatus {
  const LiveShareStatus({this.phase = LiveSharePhase.off, this.lastUpdateAt, this.message, this.expiresAt});

  final LiveSharePhase phase;

  /// Lần cập nhật cuối được server xác nhận (UTC ms).
  final int? lastUpdateAt;
  final String? message;
  final int? expiresAt;

  bool get sharing => phase == LiveSharePhase.active || phase == LiveSharePhase.paused || phase == LiveSharePhase.interrupted;
}
