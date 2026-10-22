import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../utils/l10n.dart';
import '../../values/routes.dart';
import '../../services/native/permission_coordinator.dart';
import '../../controller/providers.dart';
import '../../values/tokens.dart';
import '../common_components/widgets.dart';
import '../../models/data_models/steps.dart';
import '../../controller/profile/profile_logic.dart';
import 'components/profile_widgets.dart';

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
      title: 'profile_data_sources_title'.tr,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Gap(8),
          Text('profile_ds_heading'.tr, style: StrideText.title),
          const Gap(4),
          Text('profile_ds_intro'.tr, style: StrideText.bodySecondary),
          const Gap(16),
          if (flags.devicesBle) ...[
            SettingsGroup(
              children: [
                SettingsRow(
                  icon: Icons.watch_outlined,
                  title: 'profile_ds_device_title'.tr,
                  subtitle: 'profile_ds_device_subtitle'.tr,
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
                  title: 'profile_source_phone'.tr,
                  subtitle: 'profile_ds_sensor_error'.tr,
                  showChevron: false,
                  onTap: () => ref.invalidate(profilePhoneSensorProvider),
                ),
                data: (s) => _PhoneRow(status: s, nowMs: clock.nowMs()),
              ),
              if (flags.stepsHealth)
                SettingsRow(
                  icon: Icons.favorite_border,
                  title: _isIOS ? 'profile_source_apple_health'.tr : 'profile_source_health_connect'.tr,
                  subtitle: 'profile_ds_health_unavailable'.tr,
                  showChevron: false,
                ),
            ],
          ),
          const Gap(20),
          _PriorityCard(isIOS: _isIOS),
          const Gap(12),
          StrideCard(child: ProfileNote('profile_ds_overlap_text'.tr, title: 'profile_ds_overlap_title'.tr)),
          const Gap(12),
          SettingsGroup(
            children: [
              SettingsRow(
                icon: Icons.lock_open_outlined,
                title: 'profile_ds_permissions_title'.tr,
                subtitle: 'profile_ds_permissions_subtitle'.tr,
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
      subtitle = status.permission == PermStatus.blocked ? 'profile_ds_motion_blocked'.tr : 'profile_ds_motion_needed'.tr;
      action = status.permission == PermStatus.blocked ? 'profile_ds_action_settings'.tr : 'profile_ds_action_allow'.tr;
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
      subtitle = 'profile_ds_connected_none'.tr;
    } else {
      final age = nowMs - status.lastReceivedAt!;
      final when = DateFormat('MMM d, h:mm a').format(DateTime.fromMillisecondsSinceEpoch(status.lastReceivedAt!));
      subtitle = age < const Duration(hours: 6).inMilliseconds ? 'profile_ds_connected_recent'.trArgs([when]) : 'profile_ds_connected_last'.trArgs([when]);
    }
    return SettingsRow(
      icon: Icons.smartphone,
      title: 'profile_source_phone'.tr,
      subtitle: subtitle,
      showChevron: false,
      onTap: onTap,
      trailing: action == null
          ? Semantics(
              label: 'profile_ds_connected'.tr,
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
      showStrideSnack(context, 'profile_ds_priority_save_error'.tr, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final flags = ref.watch(flagsProvider);
    final loaded = ref.watch(profileSourcePriorityProvider);
    return ProfileSection(
      title: 'profile_ds_priority_title'.tr,
      subtitle: 'profile_ds_priority_subtitle'.tr,
      child: loaded.when(
        loading: () => const Skeleton(height: 56),
        error: (e, _) => TextButton(onPressed: () => ref.invalidate(profileSourcePriorityProvider), child: Text('profile_load_retry'.tr)),
        data: (saved) {
          final full = _full ??= saved;
          final allowed = visibleStepSources(flags, isIOS: widget.isIOS).toSet();
          final visible = full.where(allowed.contains).toList();
          if (visible.length < 2) {
            return Text('profile_ds_only_phone'.tr, style: StrideText.bodySecondary);
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
                        tooltip: 'profile_ds_move_up'.trArgs([stepSourceLabel(visible[i])]),
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
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Icon(Icons.drag_handle, color: StrideColors.textMuted, semanticLabel: 'profile_ds_drag_reorder'.tr),
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
