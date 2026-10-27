import 'package:flutter_test/flutter_test.dart';
import 'package:stride/repository/explore_repository.dart';
import 'package:stride/repository/live_share_repository.dart';
import 'package:stride/services/application/api_client.dart';
import 'package:stride/utils/l10n.dart';

/// L12: lỗi từ Firebase/server không hiện nguyên văn (tiếng Anh, có thể chứa dữ liệu) — luôn là câu đã dịch.
void main() {
  const raw = 'INVALID_ARGUMENT: field "viewerIds" for alice@example.com';

  test('Explore: validation/conflict có message gốc vẫn hiện câu đã dịch', () {
    expect(const ExploreFailure(ExploreErrorKind.validation, message: raw).userMessage, 'explore_err_validation_message'.tr);
    expect(const ExploreFailure(ExploreErrorKind.conflict, code: 'x', message: raw).userMessage, 'explore_err_conflict_message'.tr);
    expect(const ExploreFailure(ExploreErrorKind.conflict, code: 'challenge_ended', message: raw).userMessage, 'explore_err_challenge_ended'.tr);
  });

  test('Live share: 422/409 lạ/lỗi không rõ → câu đã dịch, không lộ chuỗi gốc', () {
    for (final e in [ApiException(422, 'bad', raw), ApiException(409, 'other', raw), StateError(raw)]) {
      final m = LiveShareRepository.mapError(e).message;
      expect(m, isNot(contains('INVALID_ARGUMENT')));
      expect(m, isNot(contains('@')));
    }
  });
}
