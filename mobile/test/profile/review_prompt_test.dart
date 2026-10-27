import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stride/controller/profile/review_prompt.dart';
import 'package:stride/utils/clock.dart';

/// X23: hỏi đánh giá từ buổi đã lưu thứ 3, tối đa mỗi 90 ngày.
void main() {
  test('chính sách thuần: chưa đủ buổi / trong cooldown thì không hỏi', () {
    const day = 24 * 3600 * 1000;
    expect(shouldAskForReview(savedRuns: 2, lastAskedMs: null, nowMs: 0), isFalse);
    expect(shouldAskForReview(savedRuns: 3, lastAskedMs: null, nowMs: 0), isTrue);
    expect(shouldAskForReview(savedRuns: 9, lastAskedMs: 0, nowMs: 89 * day), isFalse);
    expect(shouldAskForReview(savedRuns: 9, lastAskedMs: 0, nowMs: 90 * day), isTrue);
  });

  test('đếm buổi đã lưu, hỏi đúng một lần ở buổi thứ 3, lần sau chờ cooldown', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final clock = FakeClock(DateTime(2026, 10, 27).millisecondsSinceEpoch);
    var asked = 0;
    final p = ReviewPrompt(prefs, clock, request: () async => asked++);
    for (var i = 0; i < 5; i++) {
      await p.onRunSaved();
    }
    expect(asked, 1);
    clock.advance(ReviewPrompt.cooldown);
    await p.onRunSaved();
    expect(asked, 2);
  });

  test('plugin lỗi không làm hỏng luồng lưu', () async {
    SharedPreferences.setMockInitialValues({'stride_review_saved_runs': 5});
    final prefs = await SharedPreferences.getInstance();
    final p = ReviewPrompt(prefs, FakeClock(0), request: () async => throw StateError('no store'));
    await p.onRunSaved();
  });
}
