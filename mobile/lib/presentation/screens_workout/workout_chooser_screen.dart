import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../controller/providers.dart';
import '../../controller/run/engine/run_session_controller.dart';
import '../../models/ui_models/workout_models.dart';
import '../../repository/workout_repository.dart';
import '../../utils/l10n.dart';
import '../../values/routes.dart';
import '../../values/tokens.dart';
import '../common_components/widgets.dart';

/// Run → Workout: Free run / Intervals (flag workout.intervals) / preset đã lưu (K01).
class WorkoutChooserScreen extends ConsumerWidget {
  const WorkoutChooserScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flags = ref.watch(flagsProvider);
    final current = ref.watch(runSessionProvider).setup.plan;
    final plans = flags.workoutIntervals ? ref.watch(workoutPlansProvider) : null;

    Widget option({required IconData icon, required String title, required String subtitle, required bool selected, required VoidCallback onTap}) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: StrideCard(
          semanticLabel: '$title${selected ? 'workout_selected_suffix'.tr : ''}',
          onTap: onTap,
          child: Row(
            children: [
              IconBadge(icon: icon, background: selected ? StrideColors.lime : StrideColors.subtle),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: StrideText.subheading),
                    Text(subtitle, style: StrideText.bodySecondary.copyWith(fontSize: 14)),
                  ],
                ),
              ),
              Icon(selected ? Icons.check_circle : Icons.chevron_right, color: selected ? StrideColors.primary : StrideColors.textMuted),
            ],
          ),
        ),
      );
    }

    return StrideScreen(
      title: 'workout_title'.tr,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('workout_choose_subtitle'.tr, style: StrideText.bodySecondary),
          const SizedBox(height: 16),
          option(
            icon: Icons.directions_run,
            title: 'workout_free_run'.tr,
            subtitle: 'workout_free_run_desc'.tr,
            selected: current == null,
            onTap: () {
              ref.read(runSessionProvider.notifier).setPlan(null);
              context.pop();
            },
          ),
          if (flags.workoutIntervals) ...[
            option(
              icon: Icons.timer_outlined,
              title: 'workout_intervals'.tr,
              subtitle: 'workout_intervals_desc'.tr,
              selected: current != null && current.id == null,
              onTap: () => context.push(Routes.runIntervals),
            ),
            SectionHeader(title: 'workout_presets'.tr),
            plans!.when(
              loading: () => const Column(children: [LoadingCard(height: 72), SizedBox(height: 8), LoadingCard(height: 72)]),
              error: (e, _) => ErrorState(
                title: 'workout_presets_error_title'.tr,
                message: 'workout_presets_error_message'.tr,
                onRetry: () => ref.invalidate(workoutPlansProvider),
              ),
              data: (list) => list.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text('workout_presets_empty'.tr, style: StrideText.bodySecondary),
                    )
                  : Column(
                      children: [
                        for (final p in list)
                          option(
                            icon: Icons.bookmark_outline,
                            title: p.name,
                            subtitle: 'workout_preset_subtitle'.trArgs([formatStepDuration(p.totalMs), p.phases.length]),
                            selected: current?.id == p.id,
                            onTap: () => context.push('${Routes.runIntervals}?planId=${p.id}'),
                          ),
                      ],
                    ),
            ),
          ],
        ],
      ),
    );
  }
}
