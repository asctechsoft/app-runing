import 'package:asc_common/asc_common.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../configs/pref_const.dart';
import '../../utils/analytics.dart';
import '../../utils/clock.dart';
import '../../utils/logger.dart';
import '../providers.dart';

/// X23: thời điểm hỏi đánh giá. Thuần để test: đủ [minSavedRuns] buổi đã lưu và cách lần hỏi trước ≥ [cooldown].
@visibleForTesting
bool shouldAskForReview({required int savedRuns, required int? lastAskedMs, required int nowMs}) {
  if (savedRuns < ReviewPrompt.minSavedRuns) return false;
  return lastAskedMs == null || nowMs - lastAskedMs >= ReviewPrompt.cooldown.inMilliseconds;
}

/// Gọi SAU khi lưu buổi chạy thành công (không bao giờ trong lúc đang ghi). Hệ điều hành vẫn tự quyết có hiện popup hay không.
class ReviewPrompt {
  ReviewPrompt(this._prefs, this._clock, {Future<void> Function()? request}) : _request = request ?? AscReview.requestReview;

  static const minSavedRuns = 3;
  static const cooldown = Duration(days: 90);

  final SharedPreferences _prefs;
  final Clock _clock;
  final Future<void> Function() _request;

  Future<void> onRunSaved() async {
    final runs = (_prefs.getInt(PrefConst.reviewSavedRuns) ?? 0) + 1;
    await _prefs.setInt(PrefConst.reviewSavedRuns, runs);
    final now = _clock.nowMs();
    if (!shouldAskForReview(savedRuns: runs, lastAskedMs: _prefs.getInt(PrefConst.reviewLastAskedMs), nowMs: now)) return;
    await _prefs.setInt(PrefConst.reviewLastAskedMs, now);
    Analytics.reviewPrompt();
    try {
      await _request();
    } catch (e) {
      StrideLog.d('review', 'requestReview lỗi: $e');
    }
  }
}

final reviewPromptProvider = Provider<ReviewPrompt>((ref) => ReviewPrompt(ref.watch(sharedPrefsProvider), ref.watch(clockProvider)));
