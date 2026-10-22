import '../../../models/data_models/activity.dart';

enum AutoPauseSignal { pause, resume }

/// Auto pause có hysteresis (G07): ngưỡng dừng và tiếp tục tách riêng, cần duy trì đủ lâu.
/// Mất GPS / fix kém KHÔNG được coi là đứng yên — bộ đếm bị reset.
class AutoPauseDetector {
  AutoPauseDetector({required this.stopSpeedMps, required this.resumeSpeedMps, this.stopAfterMs = 8000, this.resumeAfterMs = 3000})
    : assert(resumeSpeedMps > stopSpeedMps);

  factory AutoPauseDetector.forType(ActivityType type) =>
      type == ActivityType.walk ? AutoPauseDetector(stopSpeedMps: 0.3, resumeSpeedMps: 0.8) : AutoPauseDetector(stopSpeedMps: 0.6, resumeSpeedMps: 1.4);

  final double stopSpeedMps;
  final double resumeSpeedMps;
  final int stopAfterMs;
  final int resumeAfterMs;

  int? _belowSince;
  int? _aboveSince;

  void reset() {
    _belowSince = null;
    _aboveSince = null;
  }

  /// [autoPaused]: đang ở trạng thái pause do chính auto pause. [reliable]: fix đủ chính xác.
  AutoPauseSignal? feed({required int t, required double? speedMps, required bool reliable, required bool autoPaused}) {
    if (!reliable || speedMps == null) {
      reset();
      return null;
    }
    if (!autoPaused) {
      _aboveSince = null;
      if (speedMps < stopSpeedMps) {
        _belowSince ??= t;
        if (t - _belowSince! >= stopAfterMs) {
          reset();
          return AutoPauseSignal.pause;
        }
      } else {
        _belowSince = null;
      }
    } else {
      _belowSince = null;
      if (speedMps > resumeSpeedMps) {
        _aboveSince ??= t;
        if (t - _aboveSince! >= resumeAfterMs) {
          reset();
          return AutoPauseSignal.resume;
        }
      } else {
        _aboveSince = null;
      }
    }
    return null;
  }
}
