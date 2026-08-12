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
      constraints: BoxConstraints(minHeight: 286),
      padding: EdgeInsets.fromLTRB(20, 20, 20, 18),
      decoration: _cardDecoration(radius: 30),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _QueueSection(
            label: LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'درمان فعلی',
                en: "Current treatment",
              ),
              en: "Current treatment",
            ),
            item: current,
            emptyText: LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'درمان برنامه‌ریزی‌شده‌ای در صف نیست.',
                en: "There is no scheduled treatment lined up.",
              ),
              en: "There is no scheduled treatment lined up.",
            ),
            showCountdown: true,
            isPersian: isPersian,
            font: font,
          ),
          Padding(
            padding: EdgeInsets.symmetric(vertical: 15),
            child: Divider(height: 1, color: Color(0xFFE8EEF6)),
          ),
          _QueueSection(
            label: LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'درمان بعدی',
                en: "Next treatment",
              ),
              en: "Next treatment",
            ),
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
                  child: Icon(
                    Icons.event_available_rounded,
                    color: Color(0xFF91A5BF),
                  ),
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
                style: font.copyWith(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w900,
                ),
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
                  style: font.copyWith(
                    fontSize: 10,
                    color: const Color(0xFF8894A6),
                  ),
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
      if (value.inDays > 0)
        return LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: '${value.inDays} روز گذشته',
            en: "${value.inDays} days ago",
          ),
          en: "${value.inDays} yesterday",
        );
      if (value.inHours > 0) {
        return LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: '${value.inHours} ساعت و ${value.inMinutes % 60} دقیقه گذشته',
            en: "${value.inHours} hours and ${value.inMinutes % 60} minutes passed",
          ),
          en: "${value.inHours} hours and ${value.inMinutes % 60} minutes passed",
        );
      }
      return LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: '${math.max(1, value.inMinutes)} دقیقه گذشته',
          en: "${math.max(1, value.inMinutes)} minutes ago",
        ),
        en: "${math.max(1, value.inMinutes)} last minute",
      );
    }
    if (difference.inDays > 0) {
      return LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: '${difference.inDays} روز و ${difference.inHours % 24} ساعت',
          en: "${difference.inDays} day and ${difference.inHours % 24} hour",
        ),
        en: "${difference.inDays} day and ${difference.inHours % 24} hour",
      );
    }
    if (difference.inHours > 0) {
      return LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: '${difference.inHours} ساعت و ${difference.inMinutes % 60} دقیقه',
          en: "${difference.inHours} hours and ${difference.inMinutes % 60} minutes",
        ),
        en: "${difference.inHours} hours and ${difference.inMinutes % 60} minutes",
      );
    }
    return LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: '${math.max(0, difference.inMinutes)} دقیقه',
        en: "${math.max(0, difference.inMinutes)} min",
      ),
      en: "${math.max(0, difference.inMinutes)} min",
    );
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
      label: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'وضعیت همدم',
          en: "companion status",
        ),
        en: "companion status",
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(28),
          child: Container(
            height:
                194 * math.max(1.0, MediaQuery.textScalerOf(context).scale(1)),
            padding: EdgeInsets.all(15),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFFFF1FA), Color(0xFFF6F0FF)],
              ),
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: Color(0x129A5B98),
                  blurRadius: 20,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'وضعیت همدم',
                      en: "companion status",
                    ),
                    en: "companion status",
                  ),
                  style: font.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 7),
                if (!summary.hasPermission)
                  Expanded(
                    child: _CenteredState(
                      icon: Icons.lock_outline_rounded,
                      text: LifeMateRuntimeLocale.select(
                        fa: LifeMateRuntimeLocale.select(
                          fa: 'دسترسی اشتراک تقویم فعال نیست',
                          en: "Calendar subscription access is not enabled",
                        ),
                        en: "Calendar subscription access is not enabled",
                      ),
                    ),
                  )
                else if (!summary.available)
                  Expanded(
                    child: _CenteredState(
                      icon: Icons.favorite_border_rounded,
                      text: LifeMateRuntimeLocale.select(
                        fa: LifeMateRuntimeLocale.select(
                          fa: 'خلاصه همدم فعلاً در دسترس نیست',
                          en: "Companion summary is currently unavailable",
                        ),
                        en: "Companion summary is currently unavailable",
                      ),
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
                  Spacer(),
                  Text(
                    _moodLabel(summary).toPersianDigit(isPersian),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: font.copyWith(
                      fontSize: 10.5,
                      height: 1.35,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF5B4B6B),
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
    if (value.mood == null)
      return LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'حال امروز ثبت نشده است',
          en: "No mood recorded today",
        ),
        en: "No mood recorded today",
      );
    final labels = <String, String>{
      'great': LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(fa: 'خیلی خوب', en: "very good"),
        en: "very good",
      ),
      'good': LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(fa: 'خوب', en: "good"),
        en: "good",
      ),
      'neutral': LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(fa: 'معمولی', en: "normal"),
        en: "normal",
      ),
      'low': LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(fa: 'کم‌انرژی', en: "low energy"),
        en: "low energy",
      ),
      'overwhelmed': LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(fa: 'تحت فشار', en: "under pressure"),
        en: "under pressure",
      ),
    };
    final mood = labels[value.mood!.toLowerCase()] ?? value.mood!;
    return value.energyLevel == null
        ? LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'حال همدم: $mood',
              en: "Companion mood: $mood",
            ),
            en: "Companion mood: $mood",
          )
        : LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'حال همدم: $mood • انرژی ${value.energyLevel} از ۵',
              en: "Companion mood: $mood • Energy ${value.energyLevel}/5",
            ),
            en: "Companion mood: $mood • Energy ${value.energyLevel}/5",
          );
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
          style: const TextStyle(
            fontSize: 10.5,
            height: 1.35,
            color: Color(0xFF796681),
          ),
        ),
      ],
    );
  }
}

class _CycleRing extends StatelessWidget {
  const _CycleRing({
    required this.day,
    required this.length,
    required this.isPersian,
  });

  final int? day;
  final int? length;
  final bool isPersian;

  @override
  Widget build(BuildContext context) {
    final safeLength = length == null || length! <= 0 ? 28 : length!;
    final progress = (day == null ? 0.0 : day! / safeLength)
        .clamp(0.0, 1.0)
        .toDouble();
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
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
                ),
                Text(
                  LifeMateRuntimeLocale.select(fa: 'روز چرخه', en: "cycle day"),
                  style: TextStyle(fontSize: 8.5, color: Color(0xFF7D7284)),
                ),
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
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: size.width / 2 - 5,
    );
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
  bool shouldRepaint(covariant _CycleRingPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class CareHomeChildPreviewCard extends StatelessWidget {
  const CareHomeChildPreviewCard({super.key, required this.font});
  final TextStyle font;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'وضعیت فرزند، به زودی',
          en: "Child status, coming soon",
        ),
        en: "Child status, coming soon",
      ),
      child: Container(
        height: 194 * math.max(1.0, MediaQuery.textScalerOf(context).scale(1)),
        padding: EdgeInsets.all(15),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFF0F8FF), Color(0xFFF7FAFF)],
          ),
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Color(0x115B89B7),
              blurRadius: 20,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'وضعیت فرزند',
                  en: "Child status",
                ),
                en: "Child status",
              ),
              style: font.copyWith(fontSize: 14, fontWeight: FontWeight.w900),
            ),
            Spacer(),
            Center(
              child: Opacity(
                opacity: 0.28,
                child: Image.asset(
                  'assets/images/child_avatar.png',
                  width: 58,
                  height: 58,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Icon(
                    Icons.child_care_rounded,
                    color: Color(0xFF6FA6D9),
                    size: 44,
                  ),
                ),
              ),
            ),
            SizedBox(height: 7),
            Text(
              LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(fa: 'به زودی', en: "soon"),
                en: "soon",
              ),
              textAlign: TextAlign.center,
              style: font.copyWith(
                fontSize: 17,
                fontWeight: FontWeight.w900,
                color: Color(0xFF5D7FA9),
              ),
            ),
            SizedBox(height: 3),
            Text(
              LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'این بخش به‌زودی فعال می‌شود.',
                  en: "This section will be activated soon.",
                ),
                en: "This section will be activated soon.",
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: font.copyWith(fontSize: 9, color: Color(0xFF8393A6)),
            ),
            Spacer(),
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
    final title = summary.hasPermission && name != null
        ? LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'تقویم $name',
              en: "Calendar $name",
            ),
            en: "Calendar $name",
          )
        : LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'تقویم همدم',
              en: "companion calendar",
            ),
            en: "companion calendar",
          );
    final subtitle = summary.hasPermission
        ? LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'مشاهده خلاصه مجاز و ثبت حمایت‌های غیرپزشکی',
              en: "View the authorized summary and record non-medical support",
            ),
            en: "View the authorized summary and record non-medical support",
          )
        : LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'اشتراک‌گذاری تقویم باید توسط صاحب حساب فعال شود.',
              en: "Calendar sharing must be enabled by the account owner.",
            ),
            en: "Calendar sharing must be enabled by the account owner.",
          );
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
              gradient: const LinearGradient(
                colors: [Color(0xFFFFEDF6), Color(0xFFF2EDFF)],
              ),
              borderRadius: BorderRadius.circular(28),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x129B6AA6),
                  blurRadius: 20,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: Colors.white.withValues(alpha: 0.90),
                  child: Icon(
                    summary.hasPermission
                        ? Icons.water_drop_rounded
                        : Icons.lock_outline_rounded,
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
                        style: font.copyWith(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: font.copyWith(
                          fontSize: 11,
                          height: 1.4,
                          color: const Color(0xFF7C89A6),
                        ),
                      ),
                    ],
                  ),
                ),
                if (onTap != null)
                  const Icon(Icons.arrow_back_ios_new_rounded, size: 16),
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
      padding: EdgeInsets.all(18),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(
            icon: Icons.monitor_heart_rounded,
            iconColor: AppColors.primaryBlue,
            iconBackground: Color(0xFFEAF4FF),
            title: LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'خلاصه امروز',
                en: "Today's summary",
              ),
              en: "Today's summary",
            ),
            subtitle: LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'نمای کلی همه افراد تحت مراقبت',
                en: "Overview of all people under care",
              ),
              en: "Overview of all people under care",
            ),
            font: font,
          ),
          SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Pill(
                LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'کل ${snapshot.todayItems.length}',
                    en: "Total ${snapshot.todayItems.length}",
                  ),
                  en: "Total ${snapshot.todayItems.length}",
                ).toPersianDigit(isPersian),
                AppColors.primaryBlue,
              ),
              _Pill(
                LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'انجام‌شده ${snapshot.completedToday}',
                    en: "Done ${snapshot.completedToday}",
                  ),
                  en: "Done ${snapshot.completedToday}",
                ).toPersianDigit(isPersian),
                Color(0xFF2E9D72),
              ),
              _Pill(
                LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'در انتظار ${snapshot.pendingToday}',
                    en: "Awaiting ${snapshot.pendingToday}",
                  ),
                  en: "Awaiting ${snapshot.pendingToday}",
                ).toPersianDigit(isPersian),
                Color(0xFF6F86C7),
              ),
              _Pill(
                LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'نیازمند توجه ${snapshot.alertsToday}',
                    en: "Need attention ${snapshot.alertsToday}",
                  ),
                  en: "Need attention ${snapshot.alertsToday}",
                ).toPersianDigit(isPersian),
                Color(0xFFD75A67),
              ),
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
      padding: EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(
            icon: Icons.event_available_rounded,
            iconColor: Color(0xFF48B89A),
            iconBackground: Color(0xFFEAFBF6),
            title: LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'برنامه درمانی امروز',
                en: "Today's treatment plan",
              ),
              en: "Today's treatment plan",
            ),
            subtitle: LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'داروها، ویزیت‌ها و تزریق‌های همه عزیزان',
                en: "Medicines, visits and injections of all loved ones",
              ),
              en: "Medicines, visits and injections of all loved ones",
            ),
            font: font,
          ),
          SizedBox(height: 12),
          if (items.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Center(
                child: Text(
                  LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'برای امروز درمانی ثبت نشده است.',
                      en: "No treatment has been registered for today.",
                    ),
                    en: "No treatment has been registered for today.",
                  ),
                  style: font.copyWith(fontSize: 12, color: Color(0xFF7D8B9D)),
                ),
              ),
            )
          else
            ...items.map(
              (item) =>
                  CareHomeTreatmentListTile(item: item, isPersian: isPersian),
            ),
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
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${type.label} • ${item.scheduledLocalTime}'.toPersianDigit(
                    isPersian,
                  ),
                  textDirection: LifeMateRuntimeLocale.isPersian
                      ? TextDirection.rtl
                      : TextDirection.ltr,
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: Color(0xFF778599),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Text(
            status.label,
            style: TextStyle(
              color: status.color,
              fontSize: 9.5,
              fontWeight: FontWeight.w900,
            ),
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
        CircleAvatar(
          backgroundColor: iconBackground,
          child: Icon(icon, color: iconColor),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: font.copyWith(fontSize: 16, fontWeight: FontWeight.w900),
              ),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: font.copyWith(
                  fontSize: 10.5,
                  color: const Color(0xFF7D8B9D),
                ),
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
        style: TextStyle(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.w900,
        ),
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
      return _Visual(
        LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(fa: 'تزریق', en: "Injection"),
          en: "Injection",
        ),
        Icons.vaccines_rounded,
        Color(0xFF7D73D9),
      );
    case CareItemType.visit:
      return _Visual(
        LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(fa: 'ویزیت', en: "Appointment"),
          en: "visit",
        ),
        Icons.medical_services_rounded,
        Color(0xFF45A5C9),
      );
    case CareItemType.medication:
      return _Visual(
        LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(fa: 'دارو', en: "Medication"),
          en: "medicine",
        ),
        Icons.medication_rounded,
        AppColors.primaryBlue,
      );
  }
}

_Visual _statusVisual(String status) {
  switch (status.toLowerCase()) {
    case 'taken':
    case 'completed':
      return _Visual(
        LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(fa: 'انجام شد', en: "Done"),
          en: "done",
        ),
        Icons.check_rounded,
        Color(0xFF2E9D72),
      );
    case 'missed':
      return _Visual(
        LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'فراموش شد',
            en: "It was forgotten",
          ),
          en: "It was forgotten",
        ),
        Icons.error_rounded,
        Color(0xFFD75A67),
      );
    case 'skipped':
      return _Visual(
        LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(fa: 'انجام نشد', en: "not done"),
          en: "not done",
        ),
        Icons.remove_rounded,
        Color(0xFFE39A2D),
      );
    default:
      return _Visual(
        LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(fa: 'در انتظار', en: "waiting"),
          en: "waiting",
        ),
        Icons.schedule_rounded,
        AppColors.primaryBlue,
      );
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
