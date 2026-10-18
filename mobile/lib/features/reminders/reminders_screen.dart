import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/permissions/permission_coordinator.dart';
import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';
import 'reminder_logic.dart';
import 'reminder_repository.dart';
import 'reminder_scheduler.dart';

/// Quyền notification hiện tại (kiểm tra lại khi coordinator báo đổi).
final remindersNotificationPermissionProvider = StreamProvider<PermStatus>((ref) async* {
  final perms = ref.watch(permissionsProvider);
  yield await perms.status(PermKind.notification);
  await for (final _ in perms.changes) {
    yield await perms.status(PermKind.notification);
  }
});

class _RemindersData {
  const _RemindersData(this.reminders, this.quiet);
  final Map<ReminderKind, Reminder> reminders;
  final QuietHours quiet;
}

final _remindersDataProvider = FutureProvider.autoDispose<_RemindersData>((ref) async {
  final owner = ref.watch(ownerProvider).ownerId;
  final repo = ref.read(remindersRepositoryProvider);
  return _RemindersData(await repo.load(owner), await repo.loadQuietHours(owner));
});

/// Move reminders (J02).
class RemindersScreen extends ConsumerWidget {
  const RemindersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_remindersDataProvider);
    return async.when(
      loading: () => const StrideScreen(
        title: 'Move reminders',
        body: Column(children: [Gap(16), LoadingCard(height: 180), Gap(16), LoadingCard(height: 180)]),
      ),
      error: (e, _) => StrideScreen(
        title: 'Move reminders',
        body: ErrorState(
          title: "Couldn't load reminders",
          message: 'Reminders saved on this device could not be read.',
          onRetry: () => ref.invalidate(_remindersDataProvider),
        ),
      ),
      data: (d) => _RemindersForm(initial: d),
    );
  }
}

class _RemindersForm extends ConsumerStatefulWidget {
  const _RemindersForm({required this.initial});
  final _RemindersData initial;

  @override
  ConsumerState<_RemindersForm> createState() => _RemindersFormState();
}

class _RemindersFormState extends ConsumerState<_RemindersForm> {
  late Map<ReminderKind, Reminder> _reminders;
  late QuietHours _quiet;
  final _guard = OnceGuard();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _reminders = {...widget.initial.reminders};
    _quiet = widget.initial.quiet;
  }

  Future<void> _toggle(ReminderKind k, bool on, PermStatus perm) async {
    setState(() => _reminders[k] = _reminders[k]!.copyWith(enabled: on));
    // Chỉ xin quyền khi người dùng chủ động bật một nhắc.
    if (on && !isNotificationGranted(perm)) await _askPermission(perm);
  }

  Future<void> _askPermission(PermStatus perm) async {
    final perms = ref.read(permissionsProvider);
    if (perm == PermStatus.blocked || perm == PermStatus.restricted) {
      final go = await confirmDialog(
        context,
        title: 'Notifications are off',
        message: 'Allow notifications for STRIDE in your phone settings to receive reminders.',
        confirmLabel: 'Open phone settings',
        cancelLabel: 'Not now',
      );
      if (go) await perms.openSettings();
    } else {
      await perms.request(PermKind.notification);
    }
  }

  Future<void> _pickTime(int current, ValueChanged<int> onPicked) async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current ~/ 60, minute: current % 60),
    );
    if (t != null && mounted) onPicked(t.hour * 60 + t.minute);
  }

  Future<void> _save() async {
    await _guard.run(() async {
      setState(() => _saving = true);
      try {
        final owner = ref.read(ownerProvider).ownerId;
        final repo = ref.read(remindersRepositoryProvider);
        final now = ref.read(clockProvider).nowMs();
        for (final r in _reminders.values) {
          await repo.save(owner, r.copyWith(updatedAt: now));
        }
        await repo.saveQuietHours(owner, _quiet);
        await ref.read(remindersSyncProvider)();
        final perm = await ref.read(permissionsProvider).status(PermKind.notification);
        if (!mounted) return;
        final anyOn = _reminders.values.any((r) => r.enabled);
        showStrideSnack(context, anyOn && !isNotificationGranted(perm) ? 'Saved. Reminders stay off until notifications are allowed.' : 'Reminders saved');
        if (context.canPop()) context.pop();
      } catch (e) {
        if (mounted) showStrideSnack(context, "Couldn't save reminders. Try again.", isError: true);
      } finally {
        if (mounted) setState(() => _saving = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final perm = ref.watch(remindersNotificationPermissionProvider).value ?? PermStatus.unknown;
    final granted = isNotificationGranted(perm);
    final now = ref.watch(clockProvider).nowLocal();
    return StrideScreen(
      title: 'Move reminders',
      bottom: PrimaryButton(label: 'Save reminder', loading: _saving, onPressed: _saving ? null : _save),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Gap(StrideSpace.s8),
          _reminderCard(
            ReminderKind.dailySteps,
            icon: Icons.directions_walk,
            title: 'Daily step reminder',
            subtitle: 'Get a reminder to move and reach your daily step goal.',
            perm: perm,
            granted: granted,
            now: now,
          ),
          const Gap(StrideSpace.s16),
          _reminderCard(
            ReminderKind.run,
            icon: Icons.directions_run,
            title: 'Run reminder',
            subtitle: 'Get a reminder to go for a run.',
            perm: perm,
            granted: granted,
            now: now,
          ),
          const Gap(StrideSpace.s16),
          _quietCard(),
          const Gap(StrideSpace.s16),
          SettingsGroup(
            children: [
              SettingsRow(
                icon: Icons.notifications_none,
                title: 'Notifications',
                subtitle: 'Allow STRIDE to send you reminders and updates.',
                trailing: Text(switch (perm) {
                  PermStatus.granted || PermStatus.limited => 'Allowed',
                  PermStatus.blocked || PermStatus.restricted => 'Blocked',
                  PermStatus.denied => 'Off',
                  PermStatus.unknown => 'Not set',
                }, style: StrideText.label.copyWith(color: granted ? StrideColors.primary : StrideColors.warning)),
                onTap: granted ? () => ref.read(permissionsProvider).openSettings() : () => _askPermission(perm),
              ),
            ],
          ),
          const Gap(StrideSpace.s12),
          Row(
            children: [
              const Icon(Icons.public, size: 18, color: StrideColors.textSecondary),
              const SizedBox(width: StrideSpace.s8),
              Expanded(child: Text('Follows your local time (${now.timeZoneName}).', style: StrideText.caption)),
            ],
          ),
          const Gap(StrideSpace.s16),
        ],
      ),
    );
  }

  Widget _reminderCard(
    ReminderKind k, {
    required IconData icon,
    required String title,
    required String subtitle,
    required PermStatus perm,
    required bool granted,
    required DateTime now,
  }) {
    final r = _reminders[k]!;
    final active = r.enabled && granted;
    String? status;
    BannerTone tone = BannerTone.info;
    if (r.enabled && !granted) {
      status = 'Not active — notifications are off';
      tone = BannerTone.warning;
    } else if (r.enabled && r.weekdays.isEmpty) {
      status = 'Choose at least one day.';
      tone = BannerTone.warning;
    } else if (r.enabled && isInQuietHours(r.minuteOfDay, _quiet)) {
      status = "This time is during quiet hours, so it won't be sent.";
      tone = BannerTone.warning;
    } else if (active) {
      final next = nextReminderFire(r, _quiet, now);
      if (next != null) status = 'Next reminder: ${DateFormat('EEE').format(next)} ${formatMinuteOfDay(r.minuteOfDay)}';
    }
    return StrideCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(icon: icon),
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
              // Không bao giờ hiển thị "bật" khi chưa có quyền notification.
              Switch(value: active, onChanged: (v) => _toggle(k, v, perm)),
            ],
          ),
          if (r.enabled) ...[
            const Gap(StrideSpace.s12),
            Text('Reminder time', style: StrideText.caption),
            const Gap(StrideSpace.s4),
            _TimeField(
              label: formatMinuteOfDay(r.minuteOfDay),
              semantic: '$title time',
              onTap: () => _pickTime(r.minuteOfDay, (m) => setState(() => _reminders[k] = r.copyWith(minuteOfDay: m))),
            ),
            const Gap(StrideSpace.s12),
            Text('Repeat on', style: StrideText.caption),
            const Gap(StrideSpace.s4),
            _WeekdayPicker(
              selected: r.weekdays,
              onToggle: (d) {
                final next = {...r.weekdays};
                next.contains(d) ? next.remove(d) : next.add(d);
                setState(() => _reminders[k] = r.copyWith(weekdays: next));
              },
            ),
          ],
          if (status != null) ...[
            const Gap(StrideSpace.s12),
            StatusBanner(
              tone: tone,
              message: status,
              // Khi chưa có quyền, switch hiển thị tắt; cho phép bỏ hẳn ý định bật nhắc.
              actionLabel: r.enabled && !granted ? 'Turn off' : null,
              onAction: r.enabled && !granted ? () => setState(() => _reminders[k] = r.copyWith(enabled: false)) : null,
            ),
          ],
        ],
      ),
    );
  }

  Widget _quietCard() => StrideCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const IconBadge(icon: Icons.bedtime_outlined),
            const SizedBox(width: StrideSpace.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Quiet hours', style: StrideText.subheading),
                  Text('Pause all move reminders during these hours.', style: StrideText.bodySecondary.copyWith(fontSize: 14)),
                ],
              ),
            ),
            Switch(
              value: _quiet.enabled,
              onChanged: (v) => setState(() => _quiet = _quiet.copyWith(enabled: v)),
            ),
          ],
        ),
        if (_quiet.enabled) ...[
          const Gap(StrideSpace.s12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Start time', style: StrideText.caption),
                    const Gap(StrideSpace.s4),
                    _TimeField(
                      label: formatMinuteOfDay(_quiet.startMin),
                      semantic: 'Quiet hours start',
                      onTap: () => _pickTime(_quiet.startMin, (m) => setState(() => _quiet = _quiet.copyWith(startMin: m))),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: StrideSpace.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('End time', style: StrideText.caption),
                    const Gap(StrideSpace.s4),
                    _TimeField(
                      label: formatMinuteOfDay(_quiet.endMin),
                      semantic: 'Quiet hours end',
                      onTap: () => _pickTime(_quiet.endMin, (m) => setState(() => _quiet = _quiet.copyWith(endMin: m))),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ],
    ),
  );
}

class _TimeField extends StatelessWidget {
  const _TimeField({required this.label, required this.semantic, required this.onTap});
  final String label;
  final String semantic;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '$semantic, $label',
    excludeSemantics: true,
    child: Material(
      color: StrideColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(StrideRadius.control),
        side: const BorderSide(color: StrideColors.borderSubtle),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(StrideRadius.control),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                const Icon(Icons.schedule, size: 20, color: StrideColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(label, style: StrideText.body.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                ),
                const Icon(Icons.chevron_right, size: 20, color: StrideColors.textSecondary),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _WeekdayPicker extends StatelessWidget {
  const _WeekdayPicker({required this.selected, required this.onToggle});
  final Set<int> selected;
  final ValueChanged<int> onToggle;

  static const _short = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
  static const _long = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (var i = 0; i < 7; i++)
        Expanded(
          child: Semantics(
            button: true,
            selected: selected.contains(i + 1),
            label: _long[i],
            excludeSemantics: true,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => onToggle(i + 1),
              child: SizedBox(
                height: StrideSpace.touchTarget,
                child: Center(
                  child: Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selected.contains(i + 1) ? StrideColors.lime : StrideColors.surface,
                      border: Border.all(color: selected.contains(i + 1) ? StrideColors.lime : StrideColors.borderSubtle),
                    ),
                    child: Text(_short[i], style: StrideText.label),
                  ),
                ),
              ),
            ),
          ),
        ),
    ],
  );
}
