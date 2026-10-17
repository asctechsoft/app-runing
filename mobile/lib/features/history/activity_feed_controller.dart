import 'package:flutter/foundation.dart';

import '../../data/activity_repository.dart';
import '../../domain/models/activity.dart';

/// Bộ lọc danh sách hoạt động (owner + loại + khoảng [from, to)).
class ActivityFilter {
  const ActivityFilter({required this.ownerId, this.types, this.fromMs, this.toMs});

  final String ownerId;
  final Set<ActivityType>? types;
  final int? fromMs;
  final int? toMs;

  /// Cùng một query cho list và totals (I01: summary theo đúng filter).
  ActivityQuery query({int limit = 30, int? beforeStartedAt, String? beforeId}) =>
      ActivityQuery(ownerId: ownerId, types: types, fromMs: fromMs, toMs: toMs, limit: limit, beforeStartedAt: beforeStartedAt, beforeId: beforeId);

  @override
  bool operator ==(Object other) =>
      other is ActivityFilter && other.ownerId == ownerId && setEquals(other.types, types) && other.fromMs == fromMs && other.toMs == toMs;

  @override
  int get hashCode => Object.hash(ownerId, types == null ? null : Object.hashAllUnordered(types!), fromMs, toMs);
}

/// Danh sách phân trang keyset (started_at DESC, id DESC) + tổng theo cùng filter.
/// Giữ trong State của màn để back từ chi tiết không mất trang đã tải.
class ActivityFeedController extends ChangeNotifier {
  ActivityFeedController(this._repo, {this.pageSize = 20});

  final ActivityRepository _repo;
  final int pageSize;

  ActivityFilter? _filter;
  List<Activity> _items = const [];
  ActivityTotals? _totals;
  int? _ownerTotal;
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = false;
  Object? _error;
  int _gen = 0;
  bool _disposed = false;

  ActivityFilter? get filter => _filter;
  List<Activity> get items => _items;
  ActivityTotals? get totals => _totals;

  /// Tổng số hoạt động đã lưu của owner (không filter) — phân biệt "chưa có gì" với "filter không ra kết quả".
  int? get ownerTotal => _ownerTotal;
  bool get loading => _loading;
  bool get loadingMore => _loadingMore;
  bool get hasMore => _hasMore;
  Object? get error => _error;
  bool get initialized => _filter != null && !_loading && _error == null;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Tải lại trang đầu. [keepItems] giữ danh sách cũ trong lúc tải (refresh khi dữ liệu đổi) để không nhảy scroll.
  Future<void> load(ActivityFilter filter, {bool keepItems = false}) async {
    final gen = ++_gen;
    final sameFilter = _filter == filter;
    _filter = filter;
    _loading = !(keepItems && sameFilter);
    _error = null;
    if (!keepItems || !sameFilter) {
      _items = const [];
      _totals = null;
    }
    _notify();
    try {
      // Refresh giữ số trang đã tải để danh sách ổn định.
      final limit = keepItems && sameFilter && _items.length > pageSize ? _items.length : pageSize;
      final results = await Future.wait<Object>([_repo.list(filter.query(limit: limit)), _repo.totals(filter.query()), _repo.countSaved(filter.ownerId)]);
      if (gen != _gen || _disposed) return;
      final page = results[0] as List<Activity>;
      _items = page;
      _totals = results[1] as ActivityTotals;
      _ownerTotal = results[2] as int;
      _hasMore = page.length >= limit;
    } catch (e) {
      if (gen != _gen || _disposed) return;
      _error = e;
    } finally {
      if (gen == _gen) {
        _loading = false;
        _notify();
      }
    }
  }

  Future<void> refresh() async {
    final f = _filter;
    if (f != null) await load(f, keepItems: true);
  }

  /// Tải trang tiếp theo sau bản ghi cuối (keyset), bỏ qua khi đang tải.
  Future<void> loadMore() async {
    final f = _filter;
    if (f == null || !_hasMore || _loading || _loadingMore || _items.isEmpty) return;
    final gen = _gen;
    _loadingMore = true;
    _notify();
    try {
      final last = _items.last;
      final page = await _repo.list(f.query(limit: pageSize, beforeStartedAt: last.startedAt, beforeId: last.id));
      if (gen != _gen || _disposed) return;
      _items = [..._items, ...page];
      _hasMore = page.length >= pageSize;
    } catch (e) {
      if (gen != _gen || _disposed) return;
      _error = e;
    } finally {
      _loadingMore = false;
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
