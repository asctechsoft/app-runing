/// Trạng thái phiên chạy phía UI/engine (C05, Full_luong §12).
/// `preparing`/`countdown` chưa có activity được ghi vào DB như hoạt động; draft chỉ tạo khi bấm Start.
enum SessionPhase { idle, preparing, countdown, recording, paused, awaitingSave, saved, discarded, recoveryNeeded }

enum SessionAction { open, start, countdownDone, cancel, pause, autoPause, resume, autoResume, finish, save, discard, recover, leave, crashDetected }

class InvalidTransition implements Exception {
  InvalidTransition(this.from, this.action);
  final SessionPhase from;
  final SessionAction action;
  @override
  String toString() => 'InvalidTransition($from --$action-->)';
}

/// Bảng chuyển trạng thái. Mọi chuyển khác ném [InvalidTransition] để bắt lỗi bấm lặp.
const Map<SessionPhase, Map<SessionAction, SessionPhase>> sessionTransitions = {
  SessionPhase.idle: {SessionAction.open: SessionPhase.preparing, SessionAction.crashDetected: SessionPhase.recoveryNeeded},
  SessionPhase.preparing: {SessionAction.start: SessionPhase.countdown, SessionAction.leave: SessionPhase.idle},
  SessionPhase.countdown: {SessionAction.countdownDone: SessionPhase.recording, SessionAction.cancel: SessionPhase.preparing},
  SessionPhase.recording: {
    SessionAction.pause: SessionPhase.paused,
    SessionAction.autoPause: SessionPhase.paused,
    SessionAction.crashDetected: SessionPhase.recoveryNeeded,
  },
  SessionPhase.paused: {
    SessionAction.resume: SessionPhase.recording,
    SessionAction.autoResume: SessionPhase.recording,
    SessionAction.finish: SessionPhase.awaitingSave,
    SessionAction.crashDetected: SessionPhase.recoveryNeeded,
  },
  SessionPhase.awaitingSave: {SessionAction.save: SessionPhase.saved, SessionAction.discard: SessionPhase.discarded},
  SessionPhase.recoveryNeeded: {
    SessionAction.recover: SessionPhase.recording,
    SessionAction.finish: SessionPhase.awaitingSave,
    SessionAction.discard: SessionPhase.discarded,
  },
  SessionPhase.saved: {SessionAction.open: SessionPhase.preparing},
  SessionPhase.discarded: {SessionAction.open: SessionPhase.preparing},
};

SessionPhase transition(SessionPhase from, SessionAction action) {
  final next = sessionTransitions[from]?[action];
  if (next == null) throw InvalidTransition(from, action);
  return next;
}

bool canTransition(SessionPhase from, SessionAction action) => sessionTransitions[from]?[action] != null;

/// Pause tự động chỉ tự tiếp tục khi chính nó gây ra pause; pause thủ công chỉ resume bằng người dùng (G07).
enum PauseKind { manual, auto }
