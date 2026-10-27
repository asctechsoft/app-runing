import 'package:flutter/material.dart';

import '../../utils/calc/streak.dart';
import '../../utils/l10n.dart';
import '../../values/tokens.dart';
import 'cards.dart';

/// TM20: chuỗi hiện tại / dài nhất / ngày bảo lưu — dùng chung ở Home, Profile, Progress. Màn gọi tự lo tải/lỗi
/// (ẩn khối khi chưa có dữ liệu) vì chuỗi luôn tính lại được từ dữ liệu cục bộ.
class StreakSummaryView extends StatelessWidget {
  const StreakSummaryView({super.key, required this.summary, this.card = false});

  final StreakSummary summary;

  /// `true`: bọc trong `StrideCard` kèm tiêu đề (Profile/Progress); `false`: dòng phụ dưới chấm tuần ở Home.
  final bool card;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (card) ...[const Icon(Icons.local_fire_department_outlined, color: StrideColors.primary), const SizedBox(width: StrideSpace.s8)],
            Expanded(
              child: Text(
                s.current > 0 ? 'home_streak_current'.trPlural(s.current, [s.current]) : 'home_streak_none'.tr,
                style: (card ? StrideText.heading : StrideText.label).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
              ),
            ),
            Text('home_streak_best'.trArgs([s.longest]), style: StrideText.caption),
          ],
        ),
        if (s.current > 0) ...[
          const SizedBox(height: StrideSpace.s4),
          Text(s.atRisk ? 'home_streak_at_risk'.tr : 'home_streak_today_done'.tr, style: StrideText.caption),
          Text('home_streak_freezes'.trArgs([s.freezesLeftThisMonth]), style: StrideText.caption),
        ] else if (card) ...[
          const SizedBox(height: StrideSpace.s4),
          Text('home_streak_subtitle'.tr, style: StrideText.caption),
        ],
      ],
    );
    return card
        ? StrideCard(key: const Key('streak-card'), child: body)
        : Padding(
            padding: const EdgeInsets.only(top: StrideSpace.s12),
            child: body,
          );
  }
}
