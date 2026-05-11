import 'package:flutter/material.dart';
import '../core/constants/app_colors.dart';

class SectionHeader extends StatelessWidget {
  final String title;
  final TextStyle font;
  final TextDirection? textDirection;

  const SectionHeader(
      {Key? key, required this.title, required this.font, this.textDirection})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: textDirection == TextDirection.rtl
          ? Alignment.centerRight
          : Alignment.centerLeft,
      child: Text(
        title,
        style: font.copyWith(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.primaryText),
        textDirection: textDirection,
      ),
    );
  }
}

class GlassIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final double size;
  final double iconSize;

  const GlassIconButton(
      {Key? key,
      required this.icon,
      required this.onTap,
      this.size = 48,
      this.iconSize = 24})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: AppColors.glassBackground,
          shape: BoxShape.circle,
          boxShadow: [
            const BoxShadow(
                color: Colors.white, offset: Offset(-4, -4), blurRadius: 8),
            BoxShadow(
                color: Colors.black.withOpacity(0.05),
                offset: const Offset(4, 4),
                blurRadius: 8),
          ],
        ),
        child: Icon(icon, color: Colors.black54, size: iconSize),
      ),
    );
  }
}

class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.glassBackground,
        boxShadow: [
          const BoxShadow(
              color: Colors.white, offset: Offset(-4, -4), blurRadius: 8),
          BoxShadow(
              color: Colors.black.withOpacity(0.1),
              offset: const Offset(4, 4),
              blurRadius: 8),
        ],
      ),
      padding: const EdgeInsets.all(4),
      child: const CircleAvatar(
        backgroundColor: Color(0xFFE2D4C8),
        backgroundImage: AssetImage('../../assets/images/CaregiverWoman.png'),
      ),
    );
  }
}

class GlassItem extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String text;
  final bool hasDot;
  final TextStyle font;

  const GlassItem(
      {Key? key,
      required this.icon,
      required this.iconColor,
      required this.text,
      required this.hasDot,
      required this.font})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.blue[50]!.withOpacity(0.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    font.copyWith(fontSize: 12, fontWeight: FontWeight.w600)),
          ),
          if (hasDot)
            Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                    color: Colors.redAccent, shape: BoxShape.circle))
        ],
      ),
    );
  }
}
