import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../common_components/widgets.dart';
import '../../../models/ui_models/live_share_models.dart';
import '../../../services/application/live_share_plugin.dart';
import '../../../controller/live/live_share_providers.dart';

/// Banner trạng thái chia sẻ trực tiếp để đặt trong màn đang chạy (integrator chèn). Ẩn khi không chia sẻ.
class LiveShareStatusBanner extends ConsumerWidget {
  const LiveShareStatusBanner({super.key});

  static String lastUpdateText(int? ms) => ms == null ? '—' : DateFormat.jm().format(DateTime.fromMillisecondsSinceEpoch(ms));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(liveShareStatusProvider);
    final plugin = ref.watch(liveShareRunPluginProvider);
    VoidCallback? stop;
    if (plugin is LiveSharePlugin && (s.sharing || s.phase == LiveSharePhase.starting)) stop = () => plugin.stopSharing();
    return switch (s.phase) {
      LiveSharePhase.off => const SizedBox.shrink(),
      LiveSharePhase.starting => StatusBanner(
        tone: BannerTone.info,
        icon: Icons.location_on_outlined,
        message: 'Starting live sharing…',
        actionLabel: 'Stop',
        onAction: stop,
      ),
      LiveSharePhase.active => StatusBanner(
        tone: BannerTone.success,
        icon: Icons.location_on_outlined,
        message: 'Live sharing on · last update ${lastUpdateText(s.lastUpdateAt)}',
        actionLabel: 'Stop',
        onAction: stop,
      ),
      LiveSharePhase.paused => StatusBanner(
        tone: BannerTone.info,
        icon: Icons.pause_circle_outline,
        message: 'Live sharing paused with your run',
        actionLabel: 'Stop',
        onAction: stop,
      ),
      LiveSharePhase.interrupted => StatusBanner(
        tone: BannerTone.warning,
        message: 'Live sharing interrupted — last update ${lastUpdateText(s.lastUpdateAt)}',
        actionLabel: 'Stop',
        onAction: stop,
      ),
      LiveSharePhase.ended => StatusBanner(tone: BannerTone.info, icon: Icons.location_off_outlined, message: s.message ?? 'Live sharing has ended.'),
      LiveSharePhase.failed => StatusBanner(tone: BannerTone.error, message: s.message ?? 'Live sharing couldn\'t start.'),
    };
  }
}
