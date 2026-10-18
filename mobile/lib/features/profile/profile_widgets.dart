import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';

/// Chữ cái đầu từ tên (tối đa 2), rỗng → null để hiện icon người.
String? profileInitials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return null;
  final first = parts.first.characters.first;
  final last = parts.length > 1 ? parts.last.characters.first : '';
  return (first + last).toUpperCase();
}

/// Avatar: ảnh local nếu file còn tồn tại, ngược lại chữ cái đầu / icon.
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({super.key, required this.name, this.path, this.size = 72});
  final String name;
  final String? path;
  final double size;

  @override
  Widget build(BuildContext context) {
    final file = path == null ? null : File(path!);
    final hasFile = file != null && file.existsSync();
    final initials = profileInitials(name);
    return Semantics(
      image: true,
      label: name.trim().isEmpty ? 'Profile photo' : 'Profile photo of $name',
      excludeSemantics: true,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: StrideColors.subtle,
          image: hasFile ? DecorationImage(image: FileImage(file), fit: BoxFit.cover) : null,
        ),
        alignment: Alignment.center,
        child: hasFile
            ? null
            : initials == null
            ? Icon(Icons.person_outline, color: StrideColors.primary, size: size * 0.5)
            : Text(
                initials,
                style: StrideText.heading.copyWith(color: StrideColors.primary, fontSize: size * 0.34),
              ),
      ),
    );
  }
}

/// Khối nội dung có tiêu đề + mô tả (card trắng) dùng cho màn settings con.
class ProfileSection extends StatelessWidget {
  const ProfileSection({super.key, required this.title, this.subtitle, required this.child, this.trailing});
  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Material(
      color: StrideColors.surface,
      borderRadius: BorderRadius.circular(StrideRadius.card),
      child: Padding(
        padding: const EdgeInsets.all(StrideSpace.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: StrideText.subheading),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(subtitle!, style: StrideText.bodySecondary.copyWith(fontSize: 14, height: 20 / 14)),
                      ],
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    ),
  );
}

/// Hàng switch có tiêu đề + giải thích; toàn hàng bấm được, cao ≥ 56.
class ProfileSwitchRow extends StatelessWidget {
  const ProfileSwitchRow({super.key, required this.title, this.subtitle, required this.value, required this.onChanged, this.icon});
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: SwitchListTile(
      value: value,
      onChanged: onChanged,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      secondary: icon == null ? null : Icon(icon, color: StrideColors.primary),
      activeTrackColor: StrideColors.primary,
      title: Text(title, style: StrideText.body.copyWith(fontWeight: FontWeight.w600)),
      subtitle: subtitle == null ? null : Text(subtitle!, style: StrideText.caption.copyWith(fontSize: 13, color: StrideColors.textSecondary)),
    ),
  );
}

/// Ghi chú nhỏ có icon info.
class ProfileNote extends StatelessWidget {
  const ProfileNote(this.text, {super.key, this.icon = Icons.info_outline, this.title});
  final String text;
  final String? title;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: StrideColors.textSecondary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (title != null) Text(title!, style: StrideText.label),
              Text(text, style: StrideText.bodySecondary.copyWith(fontSize: 14, height: 20 / 14)),
            ],
          ),
        ),
      ],
    ),
  );
}
