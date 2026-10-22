import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../controller/providers.dart';
import '../../values/tokens.dart';
import '../common_components/widgets.dart';
import '../../models/data_models/activity.dart';
import '../../controller/run/engine/run_session_controller.dart';
import '../../controller/run/engine/run_session_state.dart';

/// Chọn loại hoạt động → Confirm → về prepare. Indoor chỉ hiện khi flag run.indoor bật (L04).
class ActivitySelectorScreen extends ConsumerStatefulWidget {
  const ActivitySelectorScreen({super.key});

  @override
  ConsumerState<ActivitySelectorScreen> createState() => _ActivitySelectorScreenState();
}

class _ActivitySelectorScreenState extends ConsumerState<ActivitySelectorScreen> {
  late ActivityType _selected = ref.read(runSessionProvider).setup.type;

  @override
  Widget build(BuildContext context) {
    final flags = ref.watch(flagsProvider);
    final active = ref.watch(runSessionProvider).isActive;
    final options = <(ActivityType, IconData, String)>[
      (ActivityType.run, Icons.directions_run, 'Run outside with GPS tracking.'),
      (ActivityType.walk, Icons.directions_walk, 'Walk outside with GPS tracking.'),
      if (flags.runIndoor) (ActivityType.indoorRun, Icons.home_outlined, 'Treadmill or indoor track. No GPS map; distance is estimated from steps.'),
    ];
    return StrideScreen(
      title: 'Activity',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Choose what you\'re recording.', style: StrideText.bodySecondary),
          const SizedBox(height: 16),
          for (final (type, icon, desc) in options) ...[
            StrideCard(
              semanticLabel: '${activityTypeLabel(type)}${type == _selected ? ', selected' : ''}',
              onTap: active ? null : () => setState(() => _selected = type),
              child: Row(
                children: [
                  IconBadge(icon: icon, background: type == _selected ? StrideColors.lime : StrideColors.subtle),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(activityTypeLabel(type), style: StrideText.subheading),
                        Text(desc, style: StrideText.bodySecondary.copyWith(fontSize: 14)),
                      ],
                    ),
                  ),
                  Icon(
                    type == _selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                    color: type == _selected ? StrideColors.primary : StrideColors.textMuted,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (active) const StatusBanner(tone: BannerTone.info, message: 'You can\'t change the activity type while recording.'),
        ],
      ),
      bottom: PrimaryButton(
        label: 'Confirm',
        onPressed: active
            ? null
            : () {
                ref.read(runSessionProvider.notifier).setType(_selected);
                context.pop();
              },
      ),
    );
  }
}
