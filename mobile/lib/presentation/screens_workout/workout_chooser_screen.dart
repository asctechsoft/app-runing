import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../values/routes.dart';
import '../../controller/providers.dart';
import '../../values/tokens.dart';
import '../common_components/widgets.dart';
import '../../controller/run/engine/run_session_controller.dart';
import '../../models/ui_models/workout_models.dart';
import '../../repository/workout_repository.dart';

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
          semanticLabel: '$title${selected ? ', selected' : ''}',
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
      title: 'Workout',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Choose how you want to train.', style: StrideText.bodySecondary),
          const SizedBox(height: 16),
          option(
            icon: Icons.directions_run,
            title: 'Free run',
            subtitle: 'No structure. Run at your own pace.',
            selected: current == null,
            onTap: () {
              ref.read(runSessionProvider.notifier).setPlan(null);
              context.pop();
            },
          ),
          if (flags.workoutIntervals) ...[
            option(
              icon: Icons.timer_outlined,
              title: 'Intervals',
              subtitle: 'Alternate running and walking with timed phases.',
              selected: current != null && current.id == null,
              onTap: () => context.push(Routes.runIntervals),
            ),
            const SectionHeader(title: 'Your presets'),
            plans!.when(
              loading: () => const Column(children: [LoadingCard(height: 72), SizedBox(height: 8), LoadingCard(height: 72)]),
              error: (e, _) => ErrorState(
                title: 'Couldn\'t load your presets',
                message: 'Your saved workouts are still on this device.',
                onRetry: () => ref.invalidate(workoutPlansProvider),
              ),
              data: (list) => list.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text('Interval workouts you save as presets appear here.', style: StrideText.bodySecondary),
                    )
                  : Column(
                      children: [
                        for (final p in list)
                          option(
                            icon: Icons.bookmark_outline,
                            title: p.name,
                            subtitle: '${formatStepDuration(p.totalMs)} · ${p.phases.length} phases',
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
