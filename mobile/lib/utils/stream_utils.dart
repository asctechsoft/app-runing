import 'dart:async';

import 'logger.dart';

/// Hủy subscription của stream cảm biến NHƯNG có thời hạn: `StreamSubscription.cancel()` của plugin nền tảng (đếm bước, vị trí)
/// có thể không bao giờ hoàn thành (kênh native không trả lời lệnh hủy). Nếu `await` thẳng thì thao tác gọi nó treo vĩnh viễn —
/// ví dụ nút "Kết thúc & xem lại" không làm gì. Hết thời hạn thì bỏ qua (subscription vẫn đã bị gỡ ở phía Dart).
Future<void> cancelBounded(StreamSubscription<dynamic>? sub, {Duration timeout = const Duration(seconds: 2), String tag = 'stream'}) async {
  if (sub == null) return;
  try {
    await sub.cancel().timeout(timeout);
  } on TimeoutException {
    StrideLog.d(tag, 'cancel() không phản hồi sau ${timeout.inMilliseconds} ms — bỏ qua để không treo');
  } catch (e) {
    StrideLog.d(tag, 'cancel() lỗi: $e');
  }
}
