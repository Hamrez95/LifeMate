import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';

import '../core/constants/app_colors.dart';
import '../core/utils/string_extensions.dart';
import '../models/care_home_snapshot.dart';

class CareHomeTreatmentQueueCard extends StatelessWidget {
  const CareHomeTreatmentQueueCard({
    super.key,
    required this.current,
    required this.next,
    required this.isPersian,
    required this.font,
  });

  final CareHomeTreatmentItem? current;
  final CareHomeTreatmentItem? next;
  final bool isPersian;
  final TextStyle font;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 286),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      decoration: _cardDecoration(radius: 30),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _QueueSection(
            label: 'درمان فعلی',
            item: current,
            emptyText: 'درمان برنامه‌ریزی‌شده‌ای در صف نیست.',
            showCountdown: true,
            isPersian: isPersian,
            font: font,
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 15),
            child: Divider(height: 1, color: Color(0xFFE8EEF6)),
          ),
          _QueueSection(
            label: 'درمان بعدی',
            item: next,
            emptyText: current == null
                ? 'پس از ثبت درمان، نوبت بعدی اینجا نمایش داده می‌شود.'
                : 'درمان بعدی ثبت نشده است.',
            showCountdown: false,
            isPersian: isPersian,
            font: font,
          ),
        ],
      ),
    );
  }
}

class _QueueSection extends StatelessWidget {
  const _QueueSection({
    required this.label,
    required this.item,
    required this.emptyText,
    required this.showCountdown,
    required this.isPersian,
    required this.font,
  });

  final String label;
  final CareHomeTreatmentItem? item;
  final String emptyText;
  final bool showCountdown;
  final bool isPersian;
  final TextStyle font;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: font.copyWith(
            fontSize: 14,
            fontWeight: FontWeight.w900,
            color: const Color(0xFF7185C5),
          ),
        ),
        const SizedBox(height: 10),
        if (item == null)
          SizedBox(
            height: 70,
            child: Row(
              children: [
                const CircleAvatar(
                  radius: 25,
                  backgroundColor: Color(0xFFF1F6FC),
                  child: Icon(Icons.event_available_rounded, color: Color(0xFF91A5BF)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    emptyText,
                    style: font.copyWith(
                      fontSize: 12,
                      height: 1.45,
                      color: const Color(0xFF68778C),
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          _QueueTreatmentRow(
            item: item!,
            showCountdown: showCountdown,
            isPersian: isPersian,
            font: font,
          ),
      ],
    );
  }
}

class _QueueTreatmentRow extends StatelessWidget {
  const _QueueTreatmentRow({
    required this.item,
    required this.showCountdown,
    required this.isPersian,
    required this.font,
  });

  final CareHomeTreatmentItem item;
  final bool showCountdown;
  final bool isPersian;
  final TextStyle font;

  @override
  Widget build(BuildContext context) {
    final visual = _typeVisual(item.type);
    final details = Row(
      children: [
        LifeMateProfileAvatar(
          photoUrl: item.patientProfilePhotoUrl,
          avatarKey: item.patientAvatarKey,
          radius: 25,
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.patientDisplayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: font.copyWith(fontSize: 15.5, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 3),
              Row(
                children: [
                  Icon(visual.icon, size: 16, color: visual.color),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      '${item.title} • ${visual.label}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: font.copyWith(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF68778C),
                      ),
                    ),
                  ),
                ],
              ),
              if (item.subtitle.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  item.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: font.copyWith(fontSize: 10, color: const Color(0xFF8894A6)),
                ),
              ],
            ],
          ),
        ),
      ],
    );
    final timing = _QueueTiming(
      item: item,
      showCountdown: showCountdown,
      isPersian: isPersian,
      font: font,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 300) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              details,
              const SizedBox(height: 8),
              Align(alignment: AlignmentDirectional.centerEnd, child: timing),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: details),
            const SizedBox(width: 8),
            timing,
          ],
        );
      },
    );
  }
}

class _QueueTiming extends StatelessWidget {
  const _QueueTiming({
    required this.item,
    required this.showCountdown,
    required this.isPersian,
    required this.font,
  });

  final CareHomeTreatmentItem item;
  final bool showCountdown;
  final bool isPersian;
  final TextStyle font;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (showCountdown) ...[
          Container(
            constraints: const BoxConstraints(maxWidth: 138),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFFFEDEF),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Text(
              _countdown(item.scheduledAt).toPersianDigit(isPersian),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: font.copyWith(
                fontSize: 10.5,
                fontWeight: FontWeight.w900,
                color: const Color(0xFFD74F60),
              ),
            ),
          ),
          const SizedBox(height: 6),
        ],
        Directionality(
          textDirection: TextDirection.ltr,
          child: Text(
            item.scheduledLocalTime.toPersianDigit(isPersian),
            style: font.copyWith(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: const Color(0xFF5F6570),
            ),
          ),
        ),
      ],
    );
  }

  String _countdown(DateTime target) {
    final difference = target.difference(DateTime.now());
    if (difference.isNegative) {
      final value = difference.abs();
      if (value.inDays > 0) return '${value.inDays} روز گذشته';
      if (value.inHours > 0) {
        return '${value.inHours} ساعت و ${value.inMinutes % 60} دقیقه گذشته';
      }
      return '${math.max(1, value.inMinutes)} دقیقه گذشته';
    }
    if (difference.inDays > 0) {
      return '${difference.inDays} روز و ${difference.inHours % 24} ساعت';
    }
    if (difference.inHours > 0) {
      return '${difference.inHours} ساعت و ${difference.inMinutes % 60} دقیقه';
    }
    return '${math.max(0, difference.inMinutes)} دقیقه';
  }
}

class CareHomeCompanionCard extends StatelessWidget {
  const CareHomeCompanionCard({
    super.key,
    required this.summary,
    required this.isPersian,
    required this.font,
    this.onTap,
  });

  final CareCompanionHomeSummary summary;
  final bool isPersian;
  final TextStyle font;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: onTap != null,
      label: 'وضعیت همدم',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(28),
          child: Container(
            height: 194 * math.max(1.0, MediaQuery.textScalerOf(context).scale(1)),
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFFF1FA), Color(0xFFF6F0FF)],
              ),
              borderRadius: BorderRadius.circular(28),
              boxShadow: const [
                BoxShadow(color: Color(0x129A5B98), blurRadius: 20, offset: Offset(0, 8)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'وضعیت همدم',
                  style: font.copyWith(fontSize: 14, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 7),
                if (!summary.hasPermission)
                  const Expanded(
                    child: _CenteredState(
                      icon: Icons.lock_outline_rounded,
                      text: 'دسترسی اشتراک تقویم فعال نیست',
                    ),
                  )
                else if (!summary.available)
                  const Expanded(
                    child: _CenteredState(
                      icon: Icons.favorite_border_rounded,
                      text: 'خلاصه همدم فعلاً در دسترس نیست',
                    ),
                  )
                else ...[
                  Center(
                    child: _CycleRing(
                      day: summary.cycleDay,
                      length: summary.cycleLength,
                      isPersian: isPersian,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _moodLabel(summary).toPersianDigit(isPersian),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: font.copyWith(
                      fontSize: 10.5,
                      height: 1.35,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF5B4B6B),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _moodLabel(CareCompanionHomeSummary value) {
    if (value.mood == null) return 'حال امروز ثبت نشده است';
    const labels = <String, String>{
      'great': 'خیلی خوب',
      'good': 'خوب',
      'neutral': 'معمولی',
      'low': 'کم‌انرژی',
      'overwhelmed': 'تحت فشار',
    };
    final mood = labels[value.mood!.toLowerCase()] ?? value.mood!;
    return value.energyLevel == null
        ? 'حال همدم: $mood'
        : 'حال همدم: $mood • انرژی ${value.energyLevel} از ۵';
  }
}

class _CenteredState extends StatelessWidget {
  const _CenteredState({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: const Color(0xFFA278AD), size: 34),
        const SizedBox(height: 9),
        Text(
          text,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 10.5, height: 1.35, color: Color(0xFF796681)),
        ),
      ],
    );
  }
}

class _CycleRing extends StatelessWidget {
  const _CycleRing({required this.day, required this.length, required this.isPersian});

  final int? day;
  final int? length;
  final bool isPersian;

  @override
  Widget build(BuildContext context) {
    final safeLength = length == null || length! <= 0 ? 28 : length!;
    final progress = (day == null ? 0.0 : day! / safeLength).clamp(0.0, 1.0).toDouble();
    return SizedBox.square(
      dimension: 80,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(painter: _CycleRingPainter(progress)),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  day == null ? '—' : '$day'.toPersianDigit(isPersian),
                  style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
                ),
                const Text('روز چرخه', style: TextStyle(fontSize: 8.5, color: Color(0xFF7D7284))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CycleRingPainter extends CustomPainter {
  const _CycleRingPainter(this.progress);
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCircle(center: size.center(Offset.zero), radius: size.width / 2 - 5);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFF0DDEA);
    final active = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFD84AB4);
    canvas.drawArc(rect, 0, math.pi * 2, false, base);
    canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * progress, false, active);
  }

  @override
  bool shouldRepaint(covariant _CycleRingPainter oldDelegate) => oldDelegate.progress != progress;
}

class CareHomeChildPreviewCard extends StatelessWidget {
  const CareHomeChildPreviewCard({super.key, required this.font});
  final TextStyle font;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'وضعیت فرزند، به زودی',
      child: Container(
        height: 194 * math.max(1.0, MediaQuery.textScalerOf(context).scale(1)),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFFF0F8FF), Color(0xFFF7FAFF)]),
          borderRadius: BorderRadius.circular(28),
          boxShadow: const [
            BoxShadow(color: Color(0x115B89B7), blurRadius: 20, offset: Offset(0, 8)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('وضعیت فرزند', style: font.copyWith(fontSize: 14, fontWeight: FontWeight.w900)),
            const Spacer(),
            Center(
              child: Opacity(
                opacity: 0.28,
                child: Image.asset(
                  'assets/images/child_avatar.png',
                  width: 58,
                  height: 58,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.child_care_rounded,
                    color: Color(0xFF6FA6D9),
                    size: 44,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 7),
            Text(
              'به زودی',
              textAlign: TextAlign.center,
              style: font.copyWith(fontSize: 17, fontWeight: FontWeight.w900, color: const Color(0xFF5D7FA9)),
            ),
            const SizedBox(height: 3),
            Text(
              'این بخش به‌زودی فعال می‌شود.',
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: font.copyWith(fontSize: 9, color: const Color(0xFF8393A6)),
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}

class CareHomeWomenCalendarCard extends StatelessWidget {
  const CareHomeWomenCalendarCard({
    super.key,
    required this.summary,
    required this.font,
    this.onTap,
  });

  final CareCompanionHomeSummary summary;
  final TextStyle font;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final name = summary.relationship?.patientDisplayName;
    final title = summary.hasPermission && name != null ? 'تقویم $name' : 'تقویم همدم';
    final subtitle = summary.hasPermission
        ? 'مشاهده خلاصه مجاز و ثبت حمایت‌های غیرپزشکی'
        : 'اشتراک‌گذاری تقویم باید توسط صاحب حساب فعال شود.';
    return Semantics(
      button: onTap != null,
      label: title,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(28),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsetsDirectional.fromSTEB(18, 17, 18, 17),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFFFFEDF6), Color(0xFFF2EDFF)]),
              borderRadius: BorderRadius.circular(28),
              boxShadow: const [
                BoxShadow(color: Color(0x129B6AA6), blurRadius: 20, offset: Offset(0, 8)),
              ],
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: Colors.white.withValues(alpha: 0.90),
                  child: Icon(
                    summary.hasPermission ? Icons.water_drop_rounded : Icons.lock_outline_rounded,
                    color: const Color(0xFFD95B93),
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: font.copyWith(fontSize: 16, fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: font.copyWith(fontSize: 11, height: 1.4, color: const Color(0xFF7C89A6)),
                      ),
                    ],
                  ),
                ),
                if (onTap != null) const Icon(Icons.arrow_back_ios_new_rounded, size: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class CareHomeSummaryCard extends StatelessWidget {
  const CareHomeSummaryCard({
    super.key,
    required this.snapshot,
    required this.isPersian,
    required this.font,
  });

  final CareHomeSnapshot snapshot;
  final bool isPersian;
  final TextStyle font;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(
            icon: Icons.monitor_heart_rounded,
            iconColor: AppColors.primaryBlue,
            iconBackground: const Color(0xFFEAF4FF),
            title: 'خلاصه امروز',
            subtitle: 'نمای کلی همه افراد تحت مراقبت',
            font: font,
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Pill('کل ${snapshot.todayItems.length}'.toPersianDigit(isPersian), AppColors.primaryBlue),
              _Pill('انجام‌شده ${snapshot.completedToday}'.toPersianDigit(isPersian), const Color(0xFF2E9D72)),
              _Pill('در انتظار ${snapshot.pendingToday}'.toPersianDigit(isPersian), const Color(0xFF6F86C7)),
              _Pill('نیازمند توجه ${snapshot.alertsToday}'.toPersianDigit(isPersian), const Color(0xFFD75A67)),
            ],
          ),
        ],
      ),
    );
  }
}

class CareHomeTodayPlanCard extends StatelessWidget {
  const CareHomeTodayPlanCard({
    super.key,
    required this.items,
    required this.isPersian,
    required this.font,
  });

  final List<CareHomeTreatmentItem> items;
  final bool isPersian;
  final TextStyle font;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(
            icon: Icons.event_available_rounded,
            iconColor: const Color(0xFF48B89A),
            iconBackground: const Color(0xFFEAFBF6),
            title: 'برنامه درمانی امروز',
            subtitle: 'داروها، ویزیت‌ها و تزریق‌های همه عزیزان',
            font: font,
          ),
          const SizedBox(height: 12),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Center(
                child: Text(
                  'برای امروز درمانی ثبت نشده است.',
                  style: font.copyWith(fontSize: 12, color: const Color(0xFF7D8B9D)),
                ),
              ),
            )
          else
            ...items.map((item) => CareHomeTreatmentListTile(item: item, isPersian: isPersian)),
        ],
      ),
    );
  }
}

class CareHomeTreatmentListTile extends StatelessWidget {
  const CareHomeTreatmentListTile({
    super.key,
    required this.item,
    required this.isPersian,
    this.compact = false,
  });

  final CareHomeTreatmentItem item;
  final bool isPersian;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final type = _typeVisual(item.type);
    final status = _statusVisual(item.status);
    return Container(
      margin: const EdgeInsets.only(bottom: 7),
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: compact ? 7 : 9),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(17),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: type.color.withValues(alpha: 0.11),
            child: Icon(type.icon, color: type.color, size: 21),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${item.patientDisplayName} • ${item.title}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 3),
                Text(
                  '${type.label} • ${item.scheduledLocalTime}'.toPersianDigit(isPersian),
                  textDirection: TextDirection.rtl,
                  style: const TextStyle(fontSize: 10.5, color: Color(0xFF778599)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Text(
            status.label,
            style: TextStyle(color: status.color, fontSize: 9.5, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.icon,
    required this.iconColor,
    required this.iconBackground,
    required this.title,
    required this.subtitle,
    required this.font,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBackground;
  final String title;
  final String subtitle;
  final TextStyle font;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(backgroundColor: iconBackground, child: Icon(icon, color: iconColor)),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: font.copyWith(fontSize: 16, fontWeight: FontWeight.w900)),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: font.copyWith(fontSize: 10.5, color: const Color(0xFF7D8B9D)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.label, this.color);
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 10.5, fontWeight: FontWeight.w900),
      ),
    );
  }
}

class _Visual {
  const _Visual(this.label, this.icon, this.color);
  final String label;
  final IconData icon;
  final Color color;
}

_Visual _typeVisual(CareItemType type) {
  switch (type) {
    case CareItemType.injection:
      return const _Visual('تزریق', Icons.vaccines_rounded, Color(0xFF7D73D9));
    case CareItemType.visit:
      return const _Visual('ویزیت', Icons.medical_services_rounded, Color(0xFF45A5C9));
    case CareItemType.medication:
      return const _Visual('دارو', Icons.medication_rounded, AppColors.primaryBlue);
  }
}

_Visual _statusVisual(String status) {
  switch (status.toLowerCase()) {
    case 'taken':
    case 'completed':
      return const _Visual('انجام شد', Icons.check_rounded, Color(0xFF2E9D72));
    case 'missed':
      return const _Visual('فراموش شد', Icons.error_rounded, Color(0xFFD75A67));
    case 'skipped':
      return const _Visual('انجام نشد', Icons.remove_rounded, Color(0xFFE39A2D));
    default:
      return const _Visual('در انتظار', Icons.schedule_rounded, AppColors.primaryBlue);
  }
}

BoxDecoration _cardDecoration({double radius = 28}) => BoxDecoration(
  color: Colors.white.withValues(alpha: 0.94),
  borderRadius: BorderRadius.circular(radius),
  border: Border.all(color: Colors.white.withValues(alpha: 0.85)),
  boxShadow: [
    BoxShadow(
      color: AppColors.primaryBlue.withValues(alpha: 0.075),
      blurRadius: 24,
      offset: const Offset(0, 9),
    ),
  ],
);
