import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../providers.dart';
import '../../presentation/common_components/widgets.dart';
import '../../models/data_models/activity.dart';
import '../../services/application/activity_export.dart';
import '../../utils/activity_format.dart';

/// Xác nhận rồi xóa (tombstone + outbox). Trả true khi đã xóa thật trong DB.
/// Thống kê/records tự tính lại vì mọi màn đọc lại từ repository khi revision đổi.
Future<bool> confirmAndDeleteActivity(BuildContext context, WidgetRef ref, Activity a) async {
  final ok = await confirmDialog(
    context,
    title: 'Delete this activity?',
    message: 'This run will be removed from your history and progress. Your personal records may change.',
    confirmLabel: 'Delete activity',
    cancelLabel: 'Keep activity',
    destructive: true,
    icon: Icons.delete_outline,
  );
  if (!ok) return false;
  try {
    await ref.read(activityRepositoryProvider).deleteActivity(a.ownerId, a.id);
    return true;
  } catch (_) {
    if (context.mounted) showStrideSnack(context, 'Couldn\'t delete this activity. Please try again.', isError: true);
    return false;
  }
}

/// Xuất GPX: cảnh báo tệp chứa vị trí trước khi tạo; chỉ khi có GPS thật.
Future<void> exportGpx(BuildContext context, Activity a, List<TrackPoint> points) async {
  final gpx = buildGpx(a, points, title: activityDisplayTitle(a));
  if (gpx == null) {
    showStrideSnack(context, 'This activity has no GPS route to export.');
    return;
  }
  final ok = await confirmDialog(
    context,
    title: 'Export GPX file?',
    message: 'A GPX file contains your full route, including where you started and finished. Only share it with people you trust.',
    confirmLabel: 'Export GPX',
    cancelLabel: 'Cancel',
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
    if (r.status == ShareResultStatus.success && context.mounted) showStrideSnack(context, 'File sent to the app you chose.');
  } catch (_) {
    if (context.mounted) {
      showStrideSnack(context, 'Couldn\'t create the file. Please try again.', isError: true);
    }
  }
}
