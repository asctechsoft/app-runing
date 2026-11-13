import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../configs/pref_const.dart';
import '../../utils/analytics.dart';
import '../providers.dart';

/// Id của widget mà tour làm nổi bật; màn hình bọc widget đó bằng `TourAnchor` với đúng id.
class TourAnchors {
  TourAnchors._();

  static const String homeSteps = 'home_steps';
  static const String progressPeriod = 'progress_period';
  static const String runButton = 'run_button';
  static const String profileTab = 'profile_tab';
}

class TourStep {
  const TourStep({required this.anchorId, required this.titleKey, required this.textKey, this.tab, this.radius = 20});

  /// Tab của AppShell chứa anchor (tour mở tab này trước khi đo); null = anchor luôn có ở mọi tab (thanh tab dưới).
  final int? tab;
  final String anchorId;
  final String titleKey;
  final String textKey;

  /// Bo góc của vùng sáng.
  final double radius;
}

/// Tour lần đầu: chỉ các phần chính — số bước ở Home, đổi kỳ ở Progress, nút Run, Profile.
const List<TourStep> tourSteps = [
  TourStep(tab: 0, anchorId: TourAnchors.homeSteps, titleKey: 'tour_home_t', textKey: 'tour_home', radius: 24),
  TourStep(tab: 1, anchorId: TourAnchors.progressPeriod, titleKey: 'tour_progress_t', textKey: 'tour_progress'),
  TourStep(anchorId: TourAnchors.runButton, titleKey: 'tour_run_t', textKey: 'tour_run', radius: 40),
  TourStep(anchorId: TourAnchors.profileTab, titleKey: 'tour_profile_t', textKey: 'tour_profile'),
];

/// Điều khiển tour: đang ở bước nào, anchor nào đang gắn. `AppShell` gọi [start] một lần; `TourOverlay` vẽ theo state này.
class TourController extends ChangeNotifier {
  TourController(this._ref);

  final Ref _ref;

  bool _active = false;
  int _index = 0;
  bool _moving = false;

  /// Tăng khi có anchor đăng ký để overlay đo lại.
  int anchorGeneration = 0;

  final Map<String, GlobalKey> _anchors = {};

  /// Do `AppShell` gán: mở một tab.
  void Function(int tab)? selectTab;

  bool get active => _active;
  int get index => _index;
  TourStep get step => tourSteps[_index];
  int get count => tourSteps.length;
  bool get isFirst => _index == 0;
  bool get isLast => _index == tourSteps.length - 1;

  bool get shouldStart => !(_ref.read(sharedPrefsProvider).getBool(PrefConst.tourSeen) ?? false);

  Future<void> _markSeen() => _ref.read(sharedPrefsProvider).setBool(PrefConst.tourSeen, true);

  /// Anchor đăng ký từ `initState` (giữa lúc build): chỉ báo ở cuối frame để overlay không dựng lại trong lúc build.
  void registerAnchor(String id, GlobalKey key) {
    _anchors[id] = key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      anchorGeneration++;
      notifyListeners();
    });
  }

  void unregisterAnchor(String id, GlobalKey key) {
    if (_anchors[id] == key) _anchors.remove(id);
  }

  /// Xong khi [id] đã đăng ký; false sau [timeout].
  Future<bool> waitForAnchor(String id, {Duration timeout = const Duration(seconds: 6)}) async {
    final deadline = DateTime.now().add(timeout);
    while (!_anchors.containsKey(id)) {
      if (DateTime.now().isAfter(deadline)) return false;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return true;
  }

  /// Hình chữ nhật (toạ độ màn hình) của anchor, null nếu chưa layout.
  Rect? anchorRect(String id) {
    final box = _anchors[id]?.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  /// Bắt đầu tour nếu chưa xem. [force] chạy lại.
  Future<bool> start({bool force = false}) async {
    if (_active || (!force && !shouldStart)) return false;
    final first = tourSteps.first;
    if (first.tab != null) selectTab?.call(first.tab!);
    if (!await waitForAnchor(first.anchorId)) return false;
    _index = 0;
    _active = true;
    Analytics.tourStepView(1);
    notifyListeners();
    return true;
  }

  Future<void> next() {
    Analytics.tourAction(_index + 1, isLast ? 'done' : 'next');
    return _go(1);
  }

  Future<void> previous() {
    Analytics.tourAction(_index + 1, 'previous');
    return _go(-1);
  }

  /// Sang bước kế tiếp hiển thị được theo hướng [dir]: mở tab của bước đó và chờ anchor. Bước không có anchor
  /// (vd. tab chưa dựng được) bị bỏ qua; hết bước khi đi tới thì kết thúc tour.
  Future<void> _go(int dir) async {
    if (!_active || _moving) return;
    _moving = true;
    try {
      var i = _index + dir;
      while (i >= 0 && i < tourSteps.length) {
        final s = tourSteps[i];
        if (s.tab != null) selectTab?.call(s.tab!);
        if (await waitForAnchor(s.anchorId, timeout: const Duration(seconds: 2))) {
          _index = i;
          Analytics.tourStepView(i + 1);
          notifyListeners();
          return;
        }
        i += dir;
      }
      if (dir > 0) {
        _active = false;
        notifyListeners();
        await _markSeen();
      }
    } finally {
      _moving = false;
    }
  }

  /// Kết thúc tour (xong hoặc bỏ qua); không hiện lại.
  Future<void> finish() async {
    if (_active) Analytics.tourAction(_index + 1, 'close');
    _active = false;
    notifyListeners();
    await _markSeen();
  }
}

final tourControllerProvider = Provider<TourController>((ref) {
  final controller = TourController(ref);
  ref.onDispose(controller.dispose);
  return controller;
});
