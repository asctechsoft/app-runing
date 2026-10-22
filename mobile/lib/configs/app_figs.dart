import 'package:asc_common/asc_common.dart';

/// Cờ flavor build — alias mỏng của [AscBuildFlavor] (asc_common), giống `AppFigs` ở các app ASC khác.
/// Tên flavor khớp `productFlavors` trong `android/app/build.gradle.kts`: `alpha` (không quảng cáo), `dev`, `product`, `claude`.
class AppFigs {
  AppFigs._();

  static const bool isAlpha = AscBuildFlavor.isAlpha;
  static const bool isDev = AscBuildFlavor.isDev;
  static const bool isProduct = AscBuildFlavor.isProduct;
  static const bool isClaude = AscBuildFlavor.isClaude;

  /// Mở các công cụ chỉ dành cho QA/dev — mọi nơi trừ bản Product phát hành.
  static const bool isShowTestOption = AscBuildFlavor.isShowTestOption;
}
