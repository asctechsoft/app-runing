import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../controller/tour/tour_controller.dart';

/// Đánh dấu widget mà tour làm nổi bật cho [id]: đăng ký một `GlobalKey` với [TourController] khi đang hiển thị.
class TourAnchor extends ConsumerStatefulWidget {
  const TourAnchor({required this.id, required this.child, super.key});

  final String id;
  final Widget child;

  @override
  ConsumerState<TourAnchor> createState() => _TourAnchorState();
}

class _TourAnchorState extends ConsumerState<TourAnchor> {
  final GlobalKey _key = GlobalKey();
  late final TourController _controller = ref.read(tourControllerProvider);

  @override
  void initState() {
    super.initState();
    _controller.registerAnchor(widget.id, _key);
  }

  @override
  void dispose() {
    _controller.unregisterAnchor(widget.id, _key);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => KeyedSubtree(key: _key, child: widget.child);
}
