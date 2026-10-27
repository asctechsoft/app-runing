"""Q09: kiểm ngưỡng độ phủ test theo thư mục từ coverage/lcov.info.

Chạy:  flutter test --coverage && python tool/check_coverage.py
Ngưỡng đặt thấp hơn mức hiện tại một chút để chặn tụt; nâng dần khi thêm test.
"""
import sys
from collections import defaultdict
from pathlib import Path

# Mức đo 2026-10-27: calc 95.8%, repository 59.5% (Explore Firestore có test bằng fake_cloud_firestore), controller 79.0%.
THRESHOLDS = {
    'lib/utils/calc/': 90.0,
    'lib/repository/': 55.0,
    'lib/controller/': 75.0,
}


def main() -> int:
    sys.stdout.reconfigure(encoding='utf-8')  # console Windows mặc định cp1252
    lcov = Path(__file__).resolve().parent.parent / 'coverage' / 'lcov.info'
    if not lcov.exists():
        print(f'Không thấy {lcov} — chạy `flutter test --coverage` trước.')
        return 2
    hit = defaultdict(int)
    found = defaultdict(int)
    current = None
    for line in lcov.read_text(encoding='utf-8').splitlines():
        if line.startswith('SF:'):
            current = line[3:].replace('\\', '/')
        elif line.startswith('DA:') and current:
            count = int(line[3:].split(',')[1])
            for prefix in THRESHOLDS:
                if prefix in current:
                    found[prefix] += 1
                    hit[prefix] += count > 0
    failed = False
    for prefix, minimum in THRESHOLDS.items():
        pct = 100.0 * hit[prefix] / found[prefix] if found[prefix] else 0.0
        ok = pct >= minimum
        failed |= not ok
        print(f"{'OK  ' if ok else 'FAIL'} {prefix:<20} {pct:5.1f}% (ngưỡng {minimum:.0f}%, {hit[prefix]}/{found[prefix]} dòng)")
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
