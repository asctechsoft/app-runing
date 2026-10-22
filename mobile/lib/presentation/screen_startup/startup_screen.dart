import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../values/routes.dart';
import '../../utils/analytics.dart';
import '../../utils/logger.dart';
import '../../controller/providers.dart';
import '../../values/tokens.dart';
import '../common_components/widgets.dart';
import '../../repository/owner_repository.dart';
import '../../models/data_models/activity.dart';
import '../../controller/sync/sync_providers.dart';
import '../../utils/l10n.dart';

/// Quyết định màn đầu tiên (E01). Thuần, không I/O — để test.
/// Thứ tự: phiên chưa đóng → intro → thiết lập hồ sơ → Home.
String decideStartRoute({required OwnerState owner, Activity? unclosedSession}) {
  if (unclosedSession != null) return Routes.recovery;
  if (!owner.introSeen) return Routes.onboarding;
  if (!owner.profileSetupDone) return owner.isGuest ? Routes.welcome : Routes.setupProfile;
  return Routes.home;
}

/// Splash: chỉ đọc dữ liệu cục bộ, không bao giờ chờ mạng (offline-first).
class StartupScreen extends ConsumerStatefulWidget {
  const StartupScreen({super.key});

  @override
  ConsumerState<StartupScreen> createState() => _StartupScreenState();
}

class _StartupScreenState extends ConsumerState<StartupScreen> {
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _route());
  }

  Future<void> _route() async {
    setState(() => _failed = false);
    try {
      final owner = ref.read(ownerProvider);
      Analytics.appOpen(firstOpen: !owner.introSeen);
      Activity? session;
      try {
        session = await ref.read(activityRepositoryProvider).detectUnclosedSession(owner.ownerId);
      } catch (e, st) {
        // Lỗi đọc phiên không được chặn vào app; vẫn ghi log để điều tra.
        StrideLog.e('startup', e, st);
      }
      if (!mounted) return;
      context.go(decideStartRoute(owner: owner, unclosedSession: session));
      // Sync bắt đầu sau khi đã điều hướng — không ảnh hưởng thời gian vào app.
      ref.read(syncServiceProvider).start();
    } catch (e, st) {
      StrideLog.e('startup', e, st);
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: StrideColors.canvas,
      body: SafeArea(
        child: _failed
            ? ErrorState(title: 'startup_error_title'.tr, message: 'startup_error_msg'.tr, onRetry: _route)
            : Column(
                children: [
                  const Spacer(flex: 3),
                  Center(
                    child: Semantics(label: 'STRIDE', image: true, child: const StrideLogo(size: 120)),
                  ),
                  const Spacer(flex: 4),
                  Padding(
                    padding: const EdgeInsets.only(bottom: StrideSpace.s32),
                    child: Text('app_tagline'.tr, style: StrideText.bodySecondary),
                  ),
                ],
              ),
      ),
    );
  }
}
