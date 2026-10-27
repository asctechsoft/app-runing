import 'package:flutter/material.dart';

/// Token màu từ STRIDE Design System v1 (mục 01). Không hard-code HEX ở nơi khác.
abstract final class StrideColors {
  static const primary = Color(0xFF137A4B);
  static const primaryPressed = Color(0xFF0D603A);
  static const lime = Color(0xFFD6F45B);
  static const canvas = Color(0xFFF8FAF8);
  static const surface = Color(0xFFFFFFFF);
  static const subtle = Color(0xFFEAF2EC);
  static const textPrimary = Color(0xFF14221C);
  static const textSecondary = Color(0xFF59675F);
  static const textMuted = Color(0xFF68776E);
  static const borderSubtle = Color(0xFFDCE5DF);
  static const borderControl = Color(0xFF7A8A80);
  static const iconNavy = Color(0xFF102134);
  static const iconLime = Color(0xFFC8FF16);

  // Màu ngữ nghĩa
  static const success = Color(0xFF137A4B);
  static const successBg = Color(0xFFEAF2EC);
  static const warning = Color(0xFF8A4B00);
  static const warningBg = Color(0xFFFFF1D6);
  static const error = Color(0xFFB42318);
  static const errorBg = Color(0xFFFEECE9);
  static const info = Color(0xFF1D4ED8);
  static const infoBg = Color(0xFFEAF0FF);

  // Disabled (DS mục 04: dùng disabledBg/disabledText, không chỉ giảm opacity)
  static const disabledBg = Color(0xFFDCE5DF);
  static const disabledText = Color(0xFF68776E);

  // Bản đồ (DS mục 07)
  static const mapCurrent = Color(0xFF1D4ED8);
  static const chartBar = Color(0xFFB9D3C2);

  /// Màu đội (TM32) theo chỉ số 0–7 lưu trong `teams/{id}.color`. Luôn đi kèm tên đội (không chỉ dựa vào màu).
  static const teams = [
    Color(0xFF137A4B),
    Color(0xFF1D4ED8),
    Color(0xFFB42318),
    Color(0xFF8A4B00),
    Color(0xFF6D28D9),
    Color(0xFF0F766E),
    Color(0xFFBE185D),
    Color(0xFF102134),
  ];
}

/// Lưới 4: 4 8 12 16 20 24 32 40 48 64.
abstract final class StrideSpace {
  static const double s4 = 4;
  static const double s8 = 8;
  static const double s12 = 12;
  static const double s16 = 16;
  static const double s20 = 20;
  static const double s24 = 24;
  static const double s32 = 32;
  static const double s40 = 40;
  static const double s48 = 48;
  static const double s64 = 64;

  static const double gutter = 20;
  static const double gutterSmall = 16;
  static const double cardPadding = 16;
  static const double maxContentWidth = 560;
  static const double touchTarget = 48;
}

/// Radius 8 / 12 / 20 / 28 / pill.
abstract final class StrideRadius {
  static const double small = 8;
  static const double control = 12;
  static const double card = 20;
  static const double sheet = 28;
  static const double pill = 999;
}

abstract final class StrideMotion {
  static const press = Duration(milliseconds: 100);
  static const state = Duration(milliseconds: 180);
  static const sheet = Duration(milliseconds: 240);
  static const screen = Duration(milliseconds: 250);

  /// M01: thời lượng đã tính chế độ giảm chuyển động của hệ điều hành (`MediaQuery.disableAnimations`) → 0 (đổi tức thời).
  /// Chỉ ảnh hưởng hiệu ứng; dữ liệu (timer, lộ trình) vẫn cập nhật bình thường.
  static Duration of(BuildContext context, Duration d) => reduced(context) ? Duration.zero : d;

  static bool reduced(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;
}

/// Typography (DS mục 02). Số dùng tabular figures.
abstract final class StrideText {
  static const fontFamily = 'Inter';
  static const _tabular = [FontFeature.tabularFigures()];

  static const title = TextStyle(fontFamily: fontFamily, fontSize: 28, height: 36 / 28, fontWeight: FontWeight.w700, color: StrideColors.textPrimary);
  static const heading = TextStyle(fontFamily: fontFamily, fontSize: 22, height: 28 / 22, fontWeight: FontWeight.w700, color: StrideColors.textPrimary);
  static const subheading = TextStyle(fontFamily: fontFamily, fontSize: 18, height: 24 / 18, fontWeight: FontWeight.w600, color: StrideColors.textPrimary);
  static const body = TextStyle(fontFamily: fontFamily, fontSize: 16, height: 24 / 16, fontWeight: FontWeight.w400, color: StrideColors.textPrimary);
  static const bodySecondary = TextStyle(fontFamily: fontFamily, fontSize: 16, height: 24 / 16, fontWeight: FontWeight.w400, color: StrideColors.textSecondary);
  static const label = TextStyle(fontFamily: fontFamily, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600, color: StrideColors.textPrimary);
  static const caption = TextStyle(fontFamily: fontFamily, fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w400, color: StrideColors.textMuted);
  static const metric = TextStyle(
    fontFamily: fontFamily,
    fontSize: 48,
    height: 56 / 48,
    fontWeight: FontWeight.w700,
    color: StrideColors.textPrimary,
    fontFeatures: _tabular,
  );
  static const metricMedium = TextStyle(
    fontFamily: fontFamily,
    fontSize: 28,
    height: 36 / 28,
    fontWeight: FontWeight.w700,
    color: StrideColors.textPrimary,
    fontFeatures: _tabular,
  );
  static const metricSmall = TextStyle(
    fontFamily: fontFamily,
    fontSize: 18,
    height: 24 / 18,
    fontWeight: FontWeight.w700,
    color: StrideColors.textPrimary,
    fontFeatures: _tabular,
  );
  static const runTimer = TextStyle(
    fontFamily: fontFamily,
    fontSize: 64,
    height: 72 / 64,
    fontWeight: FontWeight.w700,
    color: StrideColors.textPrimary,
    fontFeatures: _tabular,
  );
  static const countdown = TextStyle(
    fontFamily: fontFamily,
    fontSize: 96,
    height: 1.1,
    fontWeight: FontWeight.w700,
    color: StrideColors.textPrimary,
    fontFeatures: _tabular,
  );
}
