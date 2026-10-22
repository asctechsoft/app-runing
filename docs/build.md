# Build, flavor và vòng đời khởi động (STRIDE)

## Flavor
`alpha` (không quảng cáo), `dev`, `product`, `claude` — khai ở `mobile/android/app/build.gradle.kts`, đọc trong code qua `AppFigs` (`lib/configs/app_figs.dart`).
Cùng `applicationId` (`com.asc.app_runing`) nên chỉ cần một `android/app/google-services.json`.

```bash
cd mobile
flutter run --flavor dev
flutter build apk --release --flavor dev
```

`STRIDE_ENV` (dev/staging/production) nếu không truyền sẽ suy ra từ flavor: `product` → production, còn lại → dev.

## Build tự động (`python build.py`)
Cần Python 3, Flutter trong PATH và Firebase CLI (`npm i -g firebase-tools`) để phân phối.

```bash
cd mobile
python build.py                  # menu: NoAds/Dev/Product × Debug/Release, hoặc Translate
python build.py dev release      # không menu
python tool/build_aab.py         # AAB Product Release để lên store
```

Luồng: kiểm tra chuỗi thiếu dịch → tăng số build (`build_version.txt`, cục bộ) → ghi release notes từ git → `flutter build apk --flavor ... --build-name 1.<build>.<minor>`
→ phân phối lên Firebase App Distribution → báo Telegram/email. App ID Firebase đọc từ `google-services.json`.

### Secret — không commit
| Biến / file | Dùng cho |
|---|---|
| `mobile/build_auth.json` hoặc `GOOGLE_APPLICATION_CREDENTIALS` | Service account Firebase App Distribution |
| `ASC_TESTER_EMAILS` | Email tester (mặc định theo script gốc) |
| `ASC_TELEGRAM_BOT_TOKEN`, `ASC_TELEGRAM_CHAT_ID` | Thông báo Telegram (thiếu thì bỏ qua) |
| `ASC_BUILD_EMAIL_FROM`, `_TO`, `_PASSWORD` | Email báo build (Gmail App Password; thiếu thì bỏ qua) |
| `ASC_TRANSLATE_API_URL` | Máy chủ dịch nội bộ (có mặc định) |
| `mobile/android/debug_keystore.properties`, `*.jks` | Khóa ký; thiếu thì dùng khóa debug mặc định |

Các file trên đã nằm trong `.gitignore`.

### Ký và AdMob
- `debug_keystore.properties` (keyAlias, keyPassword, storeFile, storePassword, productKeyPath) — cùng quy ước smart_drink. `productKeyPath` trỏ file khóa upload của bản `product`.
  Thiếu khóa thì `product` **ký bằng khóa debug: chỉ để thử, không phát hành**.
- Manifest khai `com.google.android.gms.ads.APPLICATION_ID` qua placeholder `admobAppId`: mặc định ID test của Google; truyền ID thật bằng `-PADMOB_APP_ID=ca-app-pub-xxx~yyy`.
  Hiện app chưa hiển thị quảng cáo.

## Vòng đời khởi động
```
main()
 ├─ binding + AppLocaleConfig.configure()
 ├─ SharedPreferences + SQLite              (cục bộ, không chờ mạng)
 ├─ StrideBase.start()                      dsp_base: Firebase → App Check → Crashlytics; Remote Config chạy nền
 ├─ nối bộ bắt lỗi (StrideLog + Crashlytics)
 ├─ AppLocaleConfig.ensureConfigured() + AscLocale.loadTranslations()
 └─ runApp(ProviderScope → StrideApp)
      ├─ AppLifecycle: resumed → làm mới quyền; foreground/background → analytics
      ├─ RouteAnalytics: screen_view theo mẫu đường dẫn (không có id)
      └─ StartupScreen: appOpen → phiên chưa đóng → intro → thiết lập hồ sơ → Home (sync bắt đầu sau khi điều hướng)
```
Firebase chỉ khởi tạo trên Android (có `google-services.json`); lỗi/không mạng thì app chạy offline và ẩn tính năng tài khoản/đám mây.

## Chuỗi đa ngôn ngữ
XML kiểu Android ở `mobile/lib/xml_strings/values*/strings.xml` (khai trong `pubspec.yaml`): `values` là tiếng Anh, `values-vi` là tiếng Việt, khoảng 1.660 key.
Quy tắc thêm/sửa chuỗi: xem mục "Chuỗi giao diện" trong `CLAUDE.md`. Dùng trong code: `'app_tagline'.tr`, `'run_pace_value'.trArgs([pace])`
(`import` từ `utils/l10n.dart`). Thêm ngôn ngữ: thêm thư mục `values-xx`, khai asset, thêm `Locale` vào `AppLocaleConfig.supportedLocales`,
chạy `python build.py translate`.
