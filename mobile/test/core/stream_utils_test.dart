import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:stride/utils/stream_utils.dart';

void main() {
  test('cancelBounded: stream hủy bình thường thì chờ xong', () async {
    var cancelled = false;
    final c = StreamController<int>(onCancel: () => cancelled = true);
    final sub = c.stream.listen((_) {});
    await cancelBounded(sub);
    expect(cancelled, isTrue);
  });

  test('cancelBounded: cancel() không bao giờ hoàn thành thì vẫn trả về sau thời hạn (không treo Finish)', () async {
    final never = Completer<void>();
    final c = StreamController<int>(onCancel: () => never.future);
    final sub = c.stream.listen((_) {});
    final sw = Stopwatch()..start();
    await cancelBounded(sub, timeout: const Duration(milliseconds: 80));
    expect(sw.elapsedMilliseconds, lessThan(1500));
  });

  test('cancelBounded: null và lỗi khi hủy đều không ném', () async {
    await cancelBounded(null);
    final c = StreamController<int>(onCancel: () => throw StateError('boom'));
    final sub = c.stream.listen((_) {});
    await cancelBounded(sub);
  });
}
