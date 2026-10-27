import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:stride/controller/run/engine/auto_pause.dart';
import 'package:stride/controller/run/engine/run_audio.dart';
import 'package:stride/controller/run/engine/run_session_state.dart';
import 'package:stride/controller/run/engine/run_sources.dart';
import 'package:stride/models/data_models/activity.dart';
import 'package:stride/models/data_models/profile.dart';

class _SlowAudio implements RunAudio {
  final spoken = <String>[];
  final gates = <Completer<void>>[];
  int active = 0;
  int maxActive = 0;
  @override
  Future<void> speak(String text) async {
    active++;
    if (active > maxActive) maxActive = active;
    final c = Completer<void>();
    gates.add(c);
    await c.future;
    spoken.add(text);
    active--;
  }

  @override
  Future<void> stop() async {}
}

void main() {
  group('Mốc thông báo (G07)', () {
    test('mỗi mốc một lần, nhảy nhiều mốc chỉ đọc mốc mới nhất', () {
      expect(nextMilestone(distanceM: 999, everyM: 1000, announced: 0), isNull);
      expect(nextMilestone(distanceM: 1000, everyM: 1000, announced: 0), 1);
      expect(nextMilestone(distanceM: 1500, everyM: 1000, announced: 1), isNull);
      expect(nextMilestone(distanceM: 3200, everyM: 1000, announced: 1), 3);
      expect(nextMilestone(distanceM: null, everyM: 1000, announced: 0), isNull);
    });

    test('câu thông báo theo đơn vị', () {
      final s = milestoneSpeech(
        milestone: 2,
        everyUnits: 1,
        unit: DistanceUnit.km,
        movingMs: 12 * 60000 + 30000,
        avgPaceSecPerKm: 360,
        cues: const AudioCueSettings(),
      );
      expect(s, '2 kilometers. Time 12 minutes 30 seconds. Average pace 6 minutes per kilometer.');
      expect(milestoneMeters(const AudioCueSettings(everyKm: 0.5), DistanceUnit.mi), closeTo(804.672, 0.001));
    });

    test('hàng đợi không chồng tiếng và giới hạn độ dài', () async {
      final audio = _SlowAudio();
      final q = RunAudioQueue(audio, maxPending: 2);
      q.enqueue('a');
      await pumpEventQueue();
      q.enqueue('b');
      q.enqueue('c');
      q.enqueue('d'); // đầy → bỏ 'b'
      for (var i = 0; i < 3; i++) {
        await pumpEventQueue();
        audio.gates.last.complete();
      }
      await q.whenIdle();
      expect(audio.spoken, ['a', 'c', 'd']);
      expect(audio.maxActive, 1);
    });
  });

  group('Auto pause (G07)', () {
    test('dừng sau 8 s chậm; tiếp tục khi nhanh hơn ngưỡng resume 3 s (hysteresis)', () {
      final d = AutoPauseDetector.forType(ActivityType.run);
      AutoPauseSignal? last;
      for (var t = 0; t <= 8000; t += 1000) {
        last = d.feed(t: t, speedMps: 0.2, reliable: true, autoPaused: false);
      }
      expect(last, AutoPauseSignal.pause);
      // Tốc độ giữa hai ngưỡng không resume.
      for (var t = 9000; t < 20000; t += 1000) {
        expect(d.feed(t: t, speedMps: 1.0, reliable: true, autoPaused: true), isNull);
      }
      expect(d.feed(t: 20000, speedMps: 2.5, reliable: true, autoPaused: true), isNull);
      expect(d.feed(t: 22000, speedMps: 2.5, reliable: true, autoPaused: true), isNull);
      expect(d.feed(t: 23000, speedMps: 2.5, reliable: true, autoPaused: true), AutoPauseSignal.resume);
    });

    test('fix không tin cậy (mất GPS) reset bộ đếm, không pause', () {
      final d = AutoPauseDetector.forType(ActivityType.run);
      for (var t = 0; t <= 20000; t += 1000) {
        final reliable = t % 4000 != 0;
        expect(d.feed(t: t, speedMps: reliable ? 0.1 : null, reliable: reliable, autoPaused: false), isNull);
      }
    });
  });

  group('Tiện ích', () {
    test('tiêu đề mặc định theo buổi', () {
      expect(defaultActivityTitle(ActivityType.run, DateTime(2026, 10, 17, 7)), 'Morning run');
      expect(defaultActivityTitle(ActivityType.walk, DateTime(2026, 10, 17, 13)), 'Afternoon walk');
      expect(defaultActivityTitle(ActivityType.run, DateTime(2026, 10, 17, 19)), 'Evening run');
      expect(defaultActivityTitle(ActivityType.indoorRun, DateTime(2026, 10, 17, 23)), 'Night indoor run');
    });

    test('bước trong run chia tỉ lệ mẫu cắt mốc bắt đầu', () {
      final samples = [(startAt: 0, endAt: 1000, steps: 100), (startAt: 1000, endAt: 2000, steps: 50)];
      expect(stepsSince(samples, 500, 2000), 100);
      expect(stepsSince(samples, 2000, 3000), 0);
    });

    test('chất lượng GPS theo accuracy', () {
      expect(qualityForAccuracy(8), GpsQuality.good);
      expect(qualityForAccuracy(35), GpsQuality.weak);
    });
  });
}
