import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/routes.dart';
import '../../core/permissions/permission_coordinator.dart';
import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/models/steps.dart';
import 'profile_logic.dart';
import 'profile_widgets.dart';

/// Trạng thái cảm biến bước của điện thoại.
class PhoneSensorStatus {
  const PhoneSensorStatus({required this.permission, this.lastReceivedAt});
  final PermStatus permission;

  /// Lần cuối app nhận giá trị counter/mẫu bước từ cảm biến (UTC ms); null = chưa từng.
  final int? lastReceivedAt;
}

final profilePhoneSensorProvider = FutureProvider.autoDispose<PhoneSensorStatus>((ref) async {
  ref.watch(stepRevisionProvider);
  final perms = ref.watch(permissionsProvider);
  final sub = perms.changes.listen((_) => ref.invalidateSelf());
  ref.onDispose(sub.cancel);
  final owner = ref.watch(ownerProvider).ownerId;
  final db = ref.watch(databaseProvider).db;
  final status = await perms.status(PermKind.motion);
  final counter = await db.query('step_counter_state', columns: ['last_counter_at'], where: 'owner_id = ?', whereArgs: [owner]);
  final sample = await db.rawQuery('SELECT MAX(end_at) AS t FROM step_samples WHERE owner_id = ? AND source = ?', [owner, StepSource.phoneSensor.name]);
  final a = counter.isEmpty ? null : counter.first['last_counter_at'] as int?;
  final b = (sample.first['t'] as num?)?.toInt();
  final last = [a, b].whereType<int>().fold<int?>(null, (m, v) => m == null || v > m ? v : m);
  return PhoneSensorStatus(permission: status, lastReceivedAt: last);
});

final profileSourcePriorityProvider = FutureProvider.autoDispose<List<StepSource>>((ref) async {
  final owner = ref.watch(ownerProvider).ownerId;
  return loadStepSourcePriority(ref.watch(settingsRepositoryProvider), owner);
});

bool get _isIOS => !kIsWeb && Platform.isIOS;

/// Data sources (F19/L01 entry): cảm biến điện thoại, thiết bị, Health (theo flag), thứ tự ưu tiên nguồn.
class DataSourcesScreen extends ConsumerWidget {
  const DataSourcesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flags = ref.watch(flagsProvider);
    final sensor = ref.watch(profilePhoneSensorProvider);
    final clock = ref.watch(clockProvider);
    return StrideScreen(
      title: 'Data sources',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Gap(8),
          Text('Connect your health data', style: StrideText.title),
          const Gap(4),
          Text('Choose where STRIDE gets your steps and activity data.', style: StrideText.bodySecondary),
          const Gap(16),
          if (flags.devicesBle) ...[
            SettingsGroup(
              children: [
                SettingsRow(
                  icon: Icons.watch_outlined,
                  title: 'Connect a device',
                  subtitle: 'Bluetooth heart rate sensors',
                  onTap: () => context.push(Routes.devices),
                ),
              ],
            ),
            const Gap(12),
          ],
          SettingsGroup(
            children: [
              sensor.when(
                loading: () => const Padding(padding: EdgeInsets.all(16), child: Skeleton(height: 40)),
                error: (e, _) => SettingsRow(
                  icon: Icons.smartphone,
                  title: 'Phone',
                  subtitle: 'Couldn’t check the step sensor. Tap to retry.',
                  showChevron: false,
                  onTap: () => ref.invalidate(profilePhoneSensorProvider),
                ),
                data: (s) => _PhoneRow(status: s, nowMs: clock.nowMs()),
              ),
              if (flags.stepsHealth)
                SettingsRow(
                  icon: Icons.favorite_border,
                  title: _isIOS ? 'Apple Health' : 'Health Connect',
                  subtitle: 'Not connected. Health data import isn’t available in this version yet.',
                  showChevron: false,
                ),
            ],
          ),
          const Gap(20),
          _PriorityCard(isIOS: _isIOS),
          const Gap(12),
          const StrideCard(
            child: ProfileNote(
              'When the same activity is recorded by more than one source, STRIDE uses the source with the highest priority for that time, so steps aren’t counted twice.',
              title: 'Overlapping steps count once',
            ),
          ),
          const Gap(12),
          SettingsGroup(
            children: [
              SettingsRow(
                icon: Icons.lock_open_outlined,
                title: 'Manage permissions',
                subtitle: 'Open phone settings for STRIDE',
                onTap: () => ref.read(permissionsProvider).openSettings(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PhoneRow extends ConsumerWidget {
  const _PhoneRow({required this.status, required this.nowMs});
  final PhoneSensorStatus status;
  final int nowMs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final granted = status.permission == PermStatus.granted || status.permission == PermStatus.limited;
    String subtitle;
    VoidCallback? onTap;
    String? action;
    if (!granted) {
      subtitle = status.permission == PermStatus.blocked
          ? 'Motion access is off. Turn it on in phone settings to count steps.'
          : 'Motion access is needed to count steps.';
      action = status.permission == PermStatus.blocked ? 'Settings' : 'Allow';
      onTap = () async {
        final perms = ref.read(permissionsProvider);
        if (status.permission == PermStatus.blocked) {
          await perms.openSettings();
        } else {
          await perms.request(PermKind.motion);
        }
        ref.invalidate(profilePhoneSensorProvider);
      };
    } else if (status.lastReceivedAt == null) {
      subtitle = 'Connected · no steps received yet';
    } else {
      final age = nowMs - status.lastReceivedAt!;
      final when = DateFormat('MMM d, h:mm a').format(DateTime.fromMillisecondsSinceEpoch(status.lastReceivedAt!));
      subtitle = age < const Duration(hours: 6).inMilliseconds ? 'Connected · steps received $when' : 'Connected · last steps received $when';
    }
    return SettingsRow(
      icon: Icons.smartphone,
      title: 'Phone',
      subtitle: subtitle,
      showChevron: false,
      onTap: onTap,
      trailing: action == null
          ? Semantics(
              label: 'Connected',
              child: const Icon(Icons.check_circle, color: StrideColors.success, size: 22),
            )
          : TextButton(onPressed: onTap, child: Text(action)),
    );
  }
}

class _PriorityCard extends ConsumerStatefulWidget {
  const _PriorityCard({required this.isIOS});
  final bool isIOS;

  @override
  ConsumerState<_PriorityCard> createState() => _PriorityCardState();
}

class _PriorityCardState extends ConsumerState<_PriorityCard> {
  List<StepSource>? _full;

  Future<void> _persist(List<StepSource> visibleOrder) async {
    final full = _full!;
    final next = reorderVisible(full, visibleOrder);
    setState(() => _full = next);
    try {
      await saveStepSourcePriority(ref.read(settingsRepositoryProvider), ref.read(ownerProvider).ownerId, next);
    } catch (_) {
      if (!mounted) return;
      setState(() => _full = full);
      showStrideSnack(context, 'Couldn’t save source priority. Try again.', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final flags = ref.watch(flagsProvider);
    final loaded = ref.watch(profileSourcePriorityProvider);
    return ProfileSection(
      title: 'Source priority',
      subtitle: 'Choose which source to use when data overlaps.',
      child: loaded.when(
        loading: () => const Skeleton(height: 56),
        error: (e, _) => TextButton(onPressed: () => ref.invalidate(profileSourcePriorityProvider), child: const Text('Couldn’t load. Try again')),
        data: (saved) {
          final full = _full ??= saved;
          final allowed = visibleStepSources(flags, isIOS: widget.isIOS).toSet();
          final visible = full.where(allowed.contains).toList();
          if (visible.length < 2) {
            return Text('Only your phone is available as a step source right now.', style: StrideText.bodySecondary);
          }
          return ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            onReorder: (oldIndex, newIndex) {
              final list = [...visible];
              if (newIndex > oldIndex) newIndex -= 1;
              list.insert(newIndex, list.removeAt(oldIndex));
              _persist(list);
            },
            children: [
              for (var i = 0; i < visible.length; i++)
                ListTile(
                  key: ValueKey(visible[i]),
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    radius: 14,
                    backgroundColor: StrideColors.subtle,
                    child: Text('${i + 1}', style: StrideText.label.copyWith(color: StrideColors.primary)),
                  ),
                  title: Text(stepSourceLabel(visible[i]), style: StrideText.body),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Move ${stepSourceLabel(visible[i])} up',
                        icon: const Icon(Icons.arrow_upward),
                        onPressed: i == 0
                            ? null
                            : () {
                                final list = [...visible];
                                list.insert(i - 1, list.removeAt(i));
                                _persist(list);
                              },
                      ),
                      ReorderableDragStartListener(
                        index: i,
                        child: const Padding(
                          padding: EdgeInsets.all(12),
                          child: Icon(Icons.drag_handle, color: StrideColors.textMuted, semanticLabel: 'Drag to reorder'),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
