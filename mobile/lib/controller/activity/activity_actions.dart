import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/data_models/activity.dart';
import '../../presentation/common_components/widgets.dart';
import '../../services/application/activity_export.dart';
import '../../utils/activity_format.dart';
import '../../utils/l10n.dart';
import '../providers.dart';

/// Xác nhận rồi xóa (tombstone + outbox). Trả true khi đã xóa thật trong DB.
/// Thống kê/records tự tính lại vì mọi màn đọc lại từ repository khi revision đổi.
Future<bool> confirmAndDeleteActivity(BuildContext context, WidgetRef ref, Activity a) async {
  final ok = await confirmDialog(
    context,
    title: 'activity_delete_confirm_title'.tr,
    message: 'activity_delete_confirm_message'.tr,
    confirmLabel: 'activity_delete_activity'.tr,
    cancelLabel: 'activity_delete_keep'.tr,
    destructive: true,
    icon: Icons.delete_outline,
  );
  if (!ok) return false;
  try {
    await ref.read(activityRepositoryProvider).deleteActivity(a.ownerId, a.id);
    return true;
  } catch (_) {
    if (context.mounted) showStrideSnack(context, 'activity_delete_failed'.tr, isError: true);
    return false;
  }
}

/// Xuất GPX: cảnh báo tệp chứa vị trí trước khi tạo; chỉ khi có GPS thật.
Future<void> exportGpx(BuildContext context, Activity a, List<TrackPoint> points) async {
  final gpx = buildGpx(a, points, title: activityDisplayTitle(a));
  if (gpx == null) {
    showStrideSnack(context, 'activity_export_no_gps'.tr);
    return;
  }
  final ok = await confirmDialog(
    context,
    title: 'activity_export_gpx_title'.tr,
    message: 'activity_export_gpx_message'.tr,
    confirmLabel: 'activity_export_gpx'.tr,
    cancelLabel: 'action_cancel'.tr,
    icon: Icons.location_on_outlined,
  );
  if (!ok || !context.mounted) return;
  await _share(context, Uint8List.fromList(utf8.encode(gpx)), '${exportFileStem(a)}.gpx', 'application/gpx+xml');
}

/// Xuất CSV tổng quan một hoạt động (không chứa toạ độ).
Future<void> exportCsv(BuildContext context, Activity a) async {
  final csv = buildActivityCsv([a]);
  // BOM UTF-8 để Excel đọc đúng ký tự có dấu.
  final bytes = Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(csv)]);
  await _share(context, bytes, '${exportFileStem(a)}.csv', 'text/csv');
}

Future<void> _share(BuildContext context, Uint8List bytes, String name, String mime) async {
  try {
    final r = await shareBytesAsFile(bytes: bytes, fileName: name, mime: mime, subject: name);
    // Chỉ báo khi hệ thống xác nhận đã chọn ứng dụng nhận; hủy thì im lặng.
    if (r.status == ShareResultStatus.success && context.mounted) showStrideSnack(context, 'activity_file_sent'.tr);
  } catch (_) {
    if (context.mounted) {
      showStrideSnack(context, 'activity_file_failed'.tr, isError: true);
    }
  }
}
