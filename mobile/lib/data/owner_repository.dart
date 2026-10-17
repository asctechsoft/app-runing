import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Chủ sở hữu dữ liệu hiện tại: khách (`guest:<uuid>`) hoặc user đã đăng nhập (E01, J05).
class OwnerState {
  const OwnerState({required this.ownerId, required this.isGuest, this.email, this.introSeen = false, this.profileSetupDone = false});

  final String ownerId;
  final bool isGuest;
  final String? email;
  final bool introSeen;
  final bool profileSetupDone;
}

class OwnerRepository {
  OwnerRepository(this._prefs);

  final SharedPreferences _prefs;

  static const _kGuestId = 'guest_id';
  static const _kUserId = 'user_id';
  static const _kEmail = 'user_email';
  static const _kIntroSeen = 'intro_seen';
  static const _kSetupPrefix = 'profile_setup_done:';

  /// Lấy (hoặc tạo) guest id ổn định trên thiết bị.
  String guestId() {
    var id = _prefs.getString(_kGuestId);
    if (id == null) {
      id = 'guest:${const Uuid().v4()}';
      _prefs.setString(_kGuestId, id);
    }
    return id;
  }

  OwnerState current() {
    final userId = _prefs.getString(_kUserId);
    final owner = userId ?? guestId();
    return OwnerState(
      ownerId: owner,
      isGuest: userId == null,
      email: _prefs.getString(_kEmail),
      introSeen: _prefs.getBool(_kIntroSeen) ?? false,
      profileSetupDone: _prefs.getBool('$_kSetupPrefix$owner') ?? false,
    );
  }

  /// intro_seen chỉ lưu khi người dùng đi qua đúng mốc (Skip/Get started).
  Future<void> markIntroSeen() => _prefs.setBool(_kIntroSeen, true);

  Future<void> markProfileSetupDone(String ownerId) => _prefs.setBool('$_kSetupPrefix$ownerId', true);

  Future<void> signIn({required String userId, required String email}) async {
    await _prefs.setString(_kUserId, userId);
    await _prefs.setString(_kEmail, email);
  }

  /// Đăng xuất: quay về owner khách; dữ liệu của user vẫn nằm local theo owner_id, không lộ cho khách.
  Future<void> signOut() async {
    await _prefs.remove(_kUserId);
    await _prefs.remove(_kEmail);
  }
}
