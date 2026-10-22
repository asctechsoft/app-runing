import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../../../utils/formatters.dart';
import '../../../utils/logger.dart';
import '../../../models/data_models/profile.dart';

/// Phát giọng nói. Tách interface để test không cần plugin.
abstract class RunAudio {
  Future<void> speak(String text);
  Future<void> stop();
}

class TtsRunAudio implements RunAudio {
  final _tts = FlutterTts();
  bool _ready = false;

  Future<void> _init() async {
    if (_ready) return;
    _ready = true;
    await _tts.awaitSpeakCompletion(true);
    await _tts.setLanguage('en-US');
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      // Hạ âm nhạc khác khi đọc (audio focus) thay vì cắt ngang.
      await _tts.setIosAudioCategory(IosTextToSpeechAudioCategory.playback, [
        IosTextToSpeechAudioCategoryOptions.duckOthers,
        IosTextToSpeechAudioCategoryOptions.mixWithOthers,
      ], IosTextToSpeechAudioMode.voicePrompt);
    }
  }

  @override
  Future<void> speak(String text) async {
    await _init();
    // focus: true → Android xin audio focus (duck) trong lúc đọc.
    await _tts.speak(text, focus: true);
  }

  @override
  Future<void> stop() async => _tts.stop();
}

final runAudioProvider = Provider<RunAudio>((ref) => TtsRunAudio());

/// Hàng đợi ngắn: đọc tuần tự, không chồng tiếng; khi đầy thì bỏ thông báo cũ nhất (G07).
class RunAudioQueue {
  RunAudioQueue(this._audio, {this.maxPending = 2, this.timeout = const Duration(seconds: 15)});

  final RunAudio _audio;
  final int maxPending;
  final Duration timeout;
  final _pending = Queue<String>();
  bool _busy = false;
  Completer<void>? _idle;

  int get pendingCount => _pending.length;
  bool get busy => _busy;

  void enqueue(String text) {
    while (_pending.length >= maxPending) {
      _pending.removeFirst();
    }
    _pending.add(text);
    unawaited(_pump());
  }

  Future<void> _pump() async {
    if (_busy) return;
    _busy = true;
    while (_pending.isNotEmpty) {
      final t = _pending.removeFirst();
      try {
        await _audio.speak(t).timeout(timeout);
      } catch (e, st) {
        StrideLog.e('run.audio', e, st);
      }
    }
    _busy = false;
    _idle?.complete();
    _idle = null;
  }

  /// Chờ hàng đợi rỗng (test).
  Future<void> whenIdle() {
    if (!_busy && _pending.isEmpty) return Future.value();
    return (_idle ??= Completer<void>()).future;
  }

  void clear() => _pending.clear();
}

/// Mốc thông báo đã vượt (1-based). Trả mốc mới cần đọc hoặc null; mỗi mốc chỉ đọc một lần.
int? nextMilestone({required double? distanceM, required double everyM, required int announced}) {
  if (distanceM == null || everyM <= 0) return null;
  final reached = (distanceM / everyM).floor();
  return reached > announced ? reached : null;
}

/// Độ dài một mốc theo đơn vị người dùng.
double milestoneMeters(AudioCueSettings cues, DistanceUnit unit) => cues.everyKm * (unit == DistanceUnit.km ? 1000 : metersPerMile);

String _spokenDuration(int ms) {
  final s = ms ~/ 1000;
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final sec = s % 60;
  final parts = <String>[
    if (h > 0) plural(h, 'hour', 'hours'),
    if (m > 0) plural(m, 'minute', 'minutes'),
    if (h == 0 && (sec > 0 || m == 0)) plural(sec, 'second', 'seconds'),
  ];
  return parts.join(' ');
}

/// Câu thông báo mốc quãng đường.
String milestoneSpeech({
  required int milestone,
  required double everyUnits,
  required DistanceUnit unit,
  required int movingMs,
  required double? avgPaceSecPerKm,
  required AudioCueSettings cues,
}) {
  final value = milestone * everyUnits;
  final valueText = value == value.roundToDouble() ? value.round().toString() : value.toStringAsFixed(1);
  final unitWord = unit == DistanceUnit.km ? (value == 1 ? 'kilometer' : 'kilometers') : (value == 1 ? 'mile' : 'miles');
  final b = StringBuffer('$valueText $unitWord.');
  if (cues.announceTime) b.write(' Time ${_spokenDuration(movingMs)}.');
  if (cues.announcePace && avgPaceSecPerKm != null) {
    final perUnit = unit == DistanceUnit.km ? avgPaceSecPerKm : avgPaceSecPerKm * metersPerMile / 1000;
    final total = perUnit.round();
    if (total < 3600) {
      b.write(' Average pace ${_spokenDuration(total * 1000)} per ${unit == DistanceUnit.km ? 'kilometer' : 'mile'}.');
    }
  }
  return b.toString();
}

String phaseSpeech(String label, int plannedMs) => '$label. ${_spokenDuration(plannedMs)}.';
