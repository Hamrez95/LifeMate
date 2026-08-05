import 'package:flutter/material.dart';

import '../theme/app_style.dart';

class WellMateLabeledField extends StatelessWidget {
  const WellMateLabeledField({
    super.key,
    required this.label,
    required this.icon,
    required this.child,
    this.helperText,
    this.required = false,
    this.bottomSpacing = 12,
  });

  final String label;
  final IconData icon;
  final Widget child;
  final String? helperText;
  final bool required;
  final double bottomSpacing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: bottomSpacing),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 17, color: AppColors.primary),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    text: label,
                    children: required
                        ? const [
                            TextSpan(
                              text: '  *',
                              style: TextStyle(color: Colors.redAccent),
                            ),
                          ]
                        : const [],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.darkBlue,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          child,
          if (helperText?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 4),
              child: Text(
                helperText!,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                  height: 1.45,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

InputDecoration wellMateFieldDecoration({
  String? hint,
  Widget? suffixIcon,
  Widget? prefixIcon,
  EdgeInsetsGeometry? contentPadding,
}) {
  return InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(
      color: AppColors.textSecondary.withValues(alpha: 0.74),
      fontSize: 13,
    ),
    prefixIcon: prefixIcon,
    suffixIcon: suffixIcon,
    filled: true,
    fillColor: const Color(0xFFF8FCFA),
    isDense: false,
    contentPadding:
        contentPadding ??
        const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(17),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(17),
      borderSide: BorderSide(color: AppColors.primary.withValues(alpha: 0.10)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(17),
      borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(17),
      borderSide: BorderSide(color: Colors.red.shade300),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(17),
      borderSide: BorderSide(color: Colors.red.shade500, width: 1.5),
    ),
  );
}
