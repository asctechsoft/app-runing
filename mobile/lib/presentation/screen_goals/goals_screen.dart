import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../utils/formatters.dart';
import '../../controller/providers.dart';
import '../../values/tokens.dart';
import '../../utils/clock.dart';
import '../common_components/widgets.dart';
import '../../models/data_models/profile.dart';
import '../../controller/goals/goals_logic.dart';

/// Mục tiêu hiện hành (hôm nay) của owner.
final goalsCurrentProvider = FutureProvider.autoDispose<GoalDraft>((ref) async {
  ref.watch(settingsProvider);
  final owner = ref.watch(ownerProvider).ownerId;
  final versions = await ref.read(settingsRepositoryProvider).goals(owner);
  final today = localDateKey(ref.read(clockProvider).nowLocal());
  return GoalDraft(
    dailySteps: goalForDate(versions, GoalType.dailySteps, today)?.value.round(),
    weeklyRuns: goalForDate(versions, GoalType.weeklyRuns, today)?.value.round(),
    weeklyDistanceM: goalForDate(versions, GoalType.weeklyDistanceM, today)?.value,
  );
});

/// Your goals (F06) — dùng chung cho /home/goals và /profile/goals. Save → quay về màn gọi.
class GoalsScreen extends ConsumerWidget {
  const GoalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(goalsCurrentProvider);
    return async.when(
      loading: () => const StrideScreen(
        title: 'Your goals',
        body: Column(children: [Gap(16), LoadingCard(height: 200), Gap(16), LoadingCard(height: 200)]),
      ),
      error: (e, _) => StrideScreen(
        title: 'Your goals',
        body: ErrorState(
          title: "Couldn't load your goals",
          message: 'Goals saved on this device could not be read.',
          onRetry: () => ref.invalidate(goalsCurrentProvider),
        ),
      ),
      data: (g) => _GoalsForm(original: g),
    );
  }
}

class _GoalsForm extends ConsumerStatefulWidget {
  const _GoalsForm({required this.original});
  final GoalDraft original;

  @override
  ConsumerState<_GoalsForm> createState() => _GoalsFormState();
}

class _GoalsFormState extends ConsumerState<_GoalsForm> {
  late GoalDraft _draft;
  final _guard = OnceGuard();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // Chưa từng đặt → điểm khởi đầu hợp lý để chỉnh; chỉ được lưu khi người dùng bấm Save.
    _draft = GoalDraft(
      dailySteps: widget.original.dailySteps ?? 8000,
      weeklyRuns: widget.original.weeklyRuns ?? 3,
      weeklyDistanceM: widget.original.weeklyDistanceM ?? 20000,
    );
  }

  Future<void> _save() async {
    if (!_draft.isValid) return;
    await _guard.run(() async {
      setState(() => _saving = true);
      try {
        final owner = ref.read(ownerProvider).ownerId;
        final repo = ref.read(settingsRepositoryProvider);
        final changed = _draft.changedFrom(widget.original);
        for (final e in changed.entries) {
          await repo.setGoal(owner, e.key, e.value);
        }
        if (!mounted) return;
        showStrideSnack(context, changed.isEmpty ? 'No changes to save' : 'Goals updated');
        if (context.canPop()) context.pop();
      } catch (e) {
        if (mounted) showStrideSnack(context, "Couldn't save goals. Try again.", isError: true);
      } finally {
        if (mounted) setState(() => _saving = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final fmt = ref.watch(formatProvider);
    final errors = _draft.errors();
    final steps = _draft.dailySteps!;
    final runs = _draft.weeklyRuns!;
    final distUnit = fmt.metersToUnit(_draft.weeklyDistanceM!);
    final distMinU = fmt.metersToUnit(GoalLimits.minDistanceKm * 1000);
    final distMaxU = fmt.metersToUnit(GoalLimits.maxDistanceKm * 1000);
    final unitLong = fmt.distanceUnitLabel == 'km' ? 'kilometres per week' : 'miles per week';
    final nf = NumberFormat.decimalPattern(fmt.locale);

    void setDistUnit(double u) {
      final clamped = u.clamp(distMinU, distMaxU).toDouble();
      setState(() => _draft = _draft.copyWith(weeklyDistanceM: fmt.unitToMeters(clamped)));
    }

    return StrideScreen(
      title: 'Your goals',
      bottom: PrimaryButton(label: 'Save changes', loading: _saving, onPressed: _draft.isValid && !_saving ? _save : null),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Gap(StrideSpace.s8),
          _GoalCard(
            icon: Icons.directions_walk,
            title: 'Daily steps',
            subtitle: 'Stay active and build healthy habits.',
            error: errors[GoalType.dailySteps],
            stepper: ValueStepper(
              valueText: nf.format(steps),
              unitLabel: 'steps per day',
              semanticLabel: 'Daily steps',
              onDecrement: steps > GoalLimits.minSteps
                  ? () => setState(() => _draft = _draft.copyWith(dailySteps: clampSteps(steps - GoalLimits.stepIncrement)))
                  : null,
              onIncrement: steps < GoalLimits.maxSteps
                  ? () => setState(() => _draft = _draft.copyWith(dailySteps: clampSteps(steps + GoalLimits.stepIncrement)))
                  : null,
            ),
            presets: PresetChips<int>(
              values: GoalLimits.stepPresets,
              selected: steps,
              labelOf: nf.format,
              onSelected: (v) => setState(() => _draft = _draft.copyWith(dailySteps: v)),
            ),
          ),
          const Gap(StrideSpace.s16),
          _GoalCard(
            icon: Icons.directions_run,
            title: 'Weekly runs',
            subtitle: 'Set how many runs you want to complete each week.',
            error: errors[GoalType.weeklyRuns],
            stepper: ValueStepper(
              valueText: '$runs',
              unitLabel: 'runs per week',
              semanticLabel: 'Weekly runs',
              onDecrement: runs > GoalLimits.minRuns ? () => setState(() => _draft = _draft.copyWith(weeklyRuns: clampRuns(runs - 1))) : null,
              onIncrement: runs < GoalLimits.maxRuns ? () => setState(() => _draft = _draft.copyWith(weeklyRuns: clampRuns(runs + 1))) : null,
            ),
            presets: PresetChips<int>(
              values: GoalLimits.runPresets,
              selected: runs,
              labelOf: (v) => '$v',
              onSelected: (v) => setState(() => _draft = _draft.copyWith(weeklyRuns: v)),
            ),
          ),
          const Gap(StrideSpace.s16),
          _GoalCard(
            icon: Icons.place_outlined,
            title: 'Weekly distance',
            subtitle: 'Set a running distance goal for the week.',
            error: errors[GoalType.weeklyDistanceM],
            stepper: ValueStepper(
              valueText: _distText(distUnit, fmt.locale),
              unitLabel: unitLong,
              semanticLabel: 'Weekly distance',
              onDecrement: distUnit > distMinU + 1e-6 ? () => setDistUnit((distUnit - 1).roundToDouble().clamp(distMinU, distMaxU)) : null,
              onIncrement: distUnit < distMaxU - 1e-6 ? () => setDistUnit((distUnit + 1).roundToDouble()) : null,
            ),
            presets: PresetChips<int>(
              values: GoalLimits.distancePresets,
              selected: (distUnit - distUnit.roundToDouble()).abs() < 0.01 ? distUnit.round() : null,
              labelOf: (v) => '$v',
              onSelected: (v) => setDistUnit(v.toDouble()),
            ),
          ),
          const Gap(StrideSpace.s16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline, color: StrideColors.textSecondary, size: 20),
              const SizedBox(width: StrideSpace.s8),
              Expanded(child: Text('Changes apply from today. Past days keep their original goals.', style: StrideText.bodySecondary)),
            ],
          ),
          const Gap(StrideSpace.s16),
        ],
      ),
    );
  }

  String _distText(double v, String locale) {
    final isWhole = (v - v.roundToDouble()).abs() < 0.01;
    return isWhole ? '${v.round()}' : NumberFormat('0.0', locale).format(v);
  }
}

class _GoalCard extends StatelessWidget {
  const _GoalCard({required this.icon, required this.title, required this.subtitle, required this.stepper, required this.presets, this.error});
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget stepper;
  final Widget presets;
  final String? error;

  @override
  Widget build(BuildContext context) => StrideCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconBadge(icon: icon, size: 48),
            const SizedBox(width: StrideSpace.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: StrideText.subheading),
                  Text(subtitle, style: StrideText.bodySecondary.copyWith(fontSize: 14)),
                ],
              ),
            ),
          ],
        ),
        const Gap(StrideSpace.s16),
        stepper,
        const Gap(StrideSpace.s12),
        Text('Quick presets', style: StrideText.caption),
        const Gap(StrideSpace.s8),
        presets,
        if (error != null) ...[const Gap(StrideSpace.s8), Text(error!, style: StrideText.label.copyWith(color: StrideColors.error))],
      ],
    ),
  );
}

/// Định dạng nhỏ để màn khác hiển thị mục tiêu quãng đường theo đơn vị.
String goalDistanceLabel(StrideFormat fmt, double meters) => '${fmt.distanceValue(meters)} ${fmt.distanceUnitLabel}';
