import 'package:flutter_test/flutter_test.dart';
import 'package:stride/features/progress/period.dart';

void main() {
  // Thứ Năm 15/10/2026.
  final thu = DateTime(2026, 10, 15, 14, 30);

  group('periodFor (I04)', () {
    test('tuần bắt đầu thứ Hai', () {
      final r = periodFor(ProgressPeriod.week, thu, DateTime.monday);
      expect(r.start, DateTime(2026, 10, 12));
      expect(r.end, DateTime(2026, 10, 19));
      expect(bucketsFor(r).length, 7);
    });

    test('tuần bắt đầu Chủ nhật', () {
      final r = periodFor(ProgressPeriod.week, thu, DateTime.sunday);
      expect(r.start, DateTime(2026, 10, 11));
      expect(r.end, DateTime(2026, 10, 18));
      // Chủ nhật là ngày đầu tuần của chính nó.
      expect(periodFor(ProgressPeriod.week, DateTime(2026, 10, 18), DateTime.sunday).start, DateTime(2026, 10, 18));
      // Với thứ Hai, Chủ nhật 18/10 thuộc tuần bắt đầu 12/10.
      expect(periodFor(ProgressPeriod.week, DateTime(2026, 10, 18), DateTime.monday).start, DateTime(2026, 10, 12));
    });

    test('tháng và năm', () {
      final m = periodFor(ProgressPeriod.month, DateTime(2028, 2, 10), DateTime.monday);
      expect(m.start, DateTime(2028, 2));
      expect(m.end, DateTime(2028, 3));
      expect(bucketsFor(m).length, 29); // năm nhuận
      final y = periodFor(ProgressPeriod.year, thu, DateTime.monday);
      expect(y.start, DateTime(2026));
      expect(y.end, DateTime(2027));
      expect(bucketsFor(y).length, 12);
      expect(bucketsFor(y)[11].start, DateTime(2026, 12));
    });

    test('shift qua ranh giới năm', () {
      final w = periodFor(ProgressPeriod.week, DateTime(2026, 1, 1), DateTime.monday);
      expect(w.start, DateTime(2025, 12, 29));
      expect(shiftPeriod(w, -1, DateTime.monday).start, DateTime(2025, 12, 22));
      final m = periodFor(ProgressPeriod.month, DateTime(2026, 1, 20), DateTime.monday);
      expect(shiftPeriod(m, -1, DateTime.monday).start, DateTime(2025, 12));
      expect(shiftPeriod(m, 1, DateTime.monday).start, DateTime(2026, 2));
    });
  });

  group('comparableCoverage (F16)', () {
    test('tuần đang diễn ra so với cùng số ngày của tuần trước', () {
      final r = periodFor(ProgressPeriod.week, thu, DateTime.monday);
      final c = comparableCoverage(r, thu, DateTime.monday);
      expect(c.ongoing, isTrue);
      expect(c.currentEnd, DateTime(2026, 10, 16));
      expect(c.previous.start, DateTime(2026, 10, 5));
      expect(c.previousEnd, DateTime(2026, 10, 9)); // Mon..Thu tuần trước
    });

    test('tuần trước (đã qua) so trọn kỳ', () {
      final r = shiftPeriod(periodFor(ProgressPeriod.week, thu, DateTime.monday), -1, DateTime.monday);
      final c = comparableCoverage(r, thu, DateTime.monday);
      expect(c.ongoing, isFalse);
      expect(c.previousEnd, c.previous.end);
    });

    test('ngày 31 so với tháng trước ngắn hơn không vượt quá cuối tháng', () {
      final now = DateTime(2026, 3, 31, 9);
      final c = comparableCoverage(periodFor(ProgressPeriod.month, now, DateTime.monday), now, DateTime.monday);
      expect(c.previous.start, DateTime(2026, 2));
      expect(c.previousEnd, DateTime(2026, 3)); // hết tháng 2
    });

    test('năm đang diễn ra so đến cùng ngày năm trước', () {
      final c = comparableCoverage(periodFor(ProgressPeriod.year, thu, DateTime.monday), thu, DateTime.monday);
      expect(c.previous.start, DateTime(2025));
      expect(c.previousEnd, DateTime(2025, 10, 16));
    });
  });

  test('nhãn kỳ', () {
    expect(periodLabel(periodFor(ProgressPeriod.week, thu, DateTime.monday)), 'Oct 12 – 18, 2026');
    expect(periodLabel(periodFor(ProgressPeriod.week, DateTime(2026, 10, 1), DateTime.monday)), 'Sep 28 – Oct 4, 2026');
    expect(periodLabel(periodFor(ProgressPeriod.week, DateTime(2026, 1, 1), DateTime.monday)), 'Dec 29, 2025 – Jan 4, 2026');
    expect(periodLabel(periodFor(ProgressPeriod.month, thu, DateTime.monday)), 'October 2026');
    expect(periodLabel(periodFor(ProgressPeriod.year, thu, DateTime.monday)), '2026');
  });
}
