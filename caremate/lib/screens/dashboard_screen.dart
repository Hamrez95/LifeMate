// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'package:caremate/widgets/custom_app_header.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/backend_service.dart';
import '../../core/localization/app_localizations.dart';
import '../../core/localization/locale_provider.dart';
import '../../core/utils/string_extensions.dart';
import '../../core/constants/app_colors.dart';
import '../../data/app_mock_data.dart';
import '../widgets/custom_ui_components.dart';
import '../widgets/caremate_bottom_nav.dart';
import 'calendar/calendar_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({Key? key}) : super(key: key);

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Map<String, dynamic>? backendStatus;
  bool syncing = false;
  Timer? _autoRefreshTimer;

  final DateTime _simulatedCurrentTime = DateTime(2024, 1, 1, 7, 0);

  Future<void> _onRefresh() async {
    setState(() {
      syncing = true;
    });
    try {
      final data = await BackendService.getStatus();

      if (mounted) {
        setState(() {
          backendStatus = data;
        });
      }
    } catch (e) {
      debugPrint("Sync Error: $e");
    }
    await Future.delayed(const Duration(milliseconds: 500));
    if (mounted) {
      setState(() {
        syncing = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _onRefresh();
    _autoRefreshTimer =
        Timer.periodic(const Duration(seconds: 1), (_) => _onRefresh());
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  // تابع کمکی برای پیدا کردن آواتار از کلاس AppMockData بر اساس نام بیمار در بک‌اند
  String _getAvatarPath(String patientName) {
    const String defaultAvatar =
        '../../assets/images/mother_avatar.png'; // مسیر آواتار پیش‌فرض
    try {
      if (patientName.contains('مامان جون')) {
        return AppMockData.familyMembers
                .firstWhere((u) => u.role == 'مادر')
                .avatarPath ??
            defaultAvatar;
      } else if (patientName.contains('بابا جون')) {
        return AppMockData.familyMembers
                .firstWhere((u) => u.role == 'پدر')
                .avatarPath ??
            defaultAvatar;
      } else if (patientName.contains('سارا')) {
        return AppMockData.familyMembers
                .firstWhere((u) => u.role == 'فرزند')
                .avatarPath ??
            defaultAvatar;
      }
    } catch (e) {
      // اگر هیچ عضوی با شروط بالا پیدا نشد، خطای No element رخ می‌دهد که اینجا مهار می‌شود
      debugPrint("Avatar not found for $patientName, using default.");
      return defaultAvatar;
    }

    return defaultAvatar; // پیش‌فرض برای سایرین
  }

  // تابع کمکی برای محاسبه زمان باقی‌مانده از ساعت ۷ صبح تا زمان دارو
  String _calculateTimeLeft(String targetTime, bool isPersian) {
    try {
      final now = DateTime.now(); // دریافت زمان واقعی و زنده سیستم
      final parts = targetTime.split(':');

      // تنظیم زمان دارو بر اساس سال، ماه و روزِ همین الان
      final targetDate = DateTime(now.year, now.month, now.day,
          int.parse(parts[0]), int.parse(parts[1]));

      final difference = targetDate.difference(now);

      if (difference.isNegative) return "گذشته";

      final hours = difference.inHours;
      final minutes = difference.inMinutes % 60;

      String result = "";
      if (hours > 0) result += "$hours ساعت و ";
      result += "$minutes دقیقه";
      return result.toPersianDigit(isPersian);
    } catch (e) {
      return "-";
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final localeProvider = Provider.of<LocaleProvider>(context);
    final isPersian = localeProvider.locale.languageCode == 'fa';

    final TextStyle mainFont = TextStyle(
        fontFamily: isPersian ? 'Vazir' : 'Poppins',
        color: AppColors.primaryText);

    final String patientName =
        "${loc['dashboard_patient']}: ${MockData.patientNameEn}";
    //برای محاسبه درصد پیشرفت
    double progressValue = 0.0;
    String progressText = "۰٪";

    if (backendStatus != null && backendStatus!['scheduleList'] != null) {
      final List<dynamic> scheduleList = backendStatus!['scheduleList'];
      // 👈 نام کلید به consumedIndices تغییر کرد
      final List<dynamic> consumed =
          backendStatus!['consumedIndices'] ?? backendStatus!['consumed'] ?? [];

      final int totalItems = scheduleList.length;
      final int doneItems = consumed.length;

      if (totalItems > 0) {
        progressValue = doneItems / totalItems;
        progressText =
            "${(progressValue * 100).toInt()}٪".toPersianDigit(isPersian);
      }
    }
    return Scaffold(
      backgroundColor: AppColors.background,
      // اینجا با extendBody: true به محتوا اجازه می‌دهیم تا زیر نویگیشن بار برود
      extendBody: true,

      // حذف Stack و قرار دادن مستقیم بدنه
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 0),
          child: Column(
            children: [
              // --- Header ---
              const CustomAppHeader(),
              const SizedBox(height: 30),
              //ویجت صف درمان
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Column(
                  children: [
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(
                            24), // گوشه های گرد هماهنگ با کل اپ
                        boxShadow: [
                          // سایه ملایم به جای بوردر مشکی
                          BoxShadow(
                            color: Colors.blue.withOpacity(0.06),
                            blurRadius: 15,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(20),
                      child: backendStatus == null
                          ? const Center(child: CircularProgressIndicator())
                          : _buildStatusContent(loc, isPersian, mainFont),
                    ),
                    const SizedBox(height: 24),

                    // --- Partner Status & Baby Tracker ---
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            height: 210,
                            padding: const EdgeInsets.all(16),
                            decoration: AppColors.softDecoration(
                                color: const Color(0xFFF0F2F5)),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(loc['dashboard_partner_status'],
                                    style: mainFont.copyWith(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold)),
                                const SizedBox(height: 15),
                                Center(
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      const SizedBox(
                                        width: 90,
                                        height: 90,
                                        child: CircularProgressIndicator(
                                            value: MockData.partnerStatusValue,
                                            strokeWidth: 10,
                                            backgroundColor: Colors.white,
                                            valueColor:
                                                AlwaysStoppedAnimation<Color>(
                                                    Color(0xFFE598D8))),
                                      ),
                                      Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(loc['dashboard_week'],
                                              style: mainFont.copyWith(
                                                  fontSize: 12,
                                                  color:
                                                      AppColors.secondaryText)),
                                          Text(
                                              MockData.pregnancyWeek
                                                  .toPersianDigit(isPersian),
                                              style: mainFont.copyWith(
                                                  fontSize: 22,
                                                  fontWeight: FontWeight.bold)),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                    "${loc['dashboard_mood']} ${loc['dashboard_mood_happy']}",
                                    style: mainFont.copyWith(fontSize: 12)),
                                Text(
                                    "${loc['dashboard_craving']} ${loc['dashboard_craving_sweets']}",
                                    style: mainFont.copyWith(fontSize: 12)),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Container(
                            height: 210,
                            padding: const EdgeInsets.all(16),
                            decoration: AppColors.softDecoration(),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(loc['dashboard_baby_tracker'],
                                    style: mainFont.copyWith(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold)),
                                const SizedBox(height: 15),
                                GlassItem(
                                    icon: Icons.baby_changing_station,
                                    iconColor: Colors.blueAccent,
                                    text: loc['dashboard_supply_low'],
                                    hasDot: true,
                                    font: mainFont),
                                const SizedBox(height: 12),
                                GlassItem(
                                    icon: Icons.vaccines,
                                    iconColor: Colors.orangeAccent,
                                    text: loc['dashboard_vaccine_tomo'],
                                    hasDot: false,
                                    font: mainFont),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // --- Quick Summary ---
                    SectionHeader(
                        title: loc['dashboard_quick_summary'],
                        font: mainFont,
                        textDirection:
                            isPersian ? TextDirection.rtl : TextDirection.ltr),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: AppColors.softDecoration(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(progressText, // استفاده از متغیر داینامیک جدید
                              style: mainFont.copyWith(
                                  fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: LinearProgressIndicator(
                                value:
                                    progressValue, // استفاده از مقدار داینامیک جدید
                                minHeight: 12,
                                backgroundColor: Colors.grey[200],
                                valueColor: const AlwaysStoppedAnimation<Color>(
                                    Color(0xFF6FCF97))),
                          ),
                          const SizedBox(height: 12),
                          Text(loc['dashboard_total_meds'],
                              style: mainFont.copyWith(
                                  color: AppColors.secondaryText,
                                  fontSize: 13)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 120),
                  ],
                ), //
              ), //
            ],
          ),
        ),
      ),

      // نویگیشن بار مستقیماً اینجا به Scaffold متصل می‌شود
      bottomNavigationBar: CareMateBottomNav(
        currentIndex: 4,
        onTap: (index) {
          if (index == 0) {
            Navigator.pushReplacement(
                context,
                PageRouteBuilder(
                    pageBuilder: (_, __, ___) => const CalendarScreen(),
                    transitionDuration: Duration.zero,
                    reverseTransitionDuration: Duration.zero));
          }
        },
      ),
    );
  }

  //       Expanded(
  //         flex: 2,
  //         child: Column(
  //           mainAxisAlignment: MainAxisAlignment.center,
  //           children: [
  //             Text(currentPatientName.toPersianDigit(isPersian),
  //                 style: mainFont.copyWith(
  //                     fontSize: 16, fontWeight: FontWeight.bold)),
  //             const SizedBox(height: 8),
  //             Container(
  //               decoration: BoxDecoration(
  //                 shape: BoxShape.circle,
  //                 border: Border.all(
  //                     color: Colors.black, width: 3), // حاشیه دور آواتار
  //               ),
  //               child: CircleAvatar(
  //                 radius: 35,
  //                 backgroundColor: Colors.white,
  //                 backgroundImage: AssetImage(currentAvatar),
  //               ),
  //             ),
  //           ],
  //         ),
  //       ),
  //     ],
  //   );
  // }

  Widget _buildStatusContent(dynamic loc, bool isPersian, TextStyle mainFont) {
    if (backendStatus == null || backendStatus!['scheduleList'] == null) {
      return const Center(child: Text("دیتای برنامه یافت نشد."));
    }

    final List<dynamic> scheduleList = backendStatus!['scheduleList'];
    // 👈 نام کلید به consumedIndices تغییر کرد
    final List<dynamic> consumedIds =
        backendStatus!['consumedIndices'] ?? backendStatus!['consumed'] ?? [];

    final now = DateTime.now();

    // ۱. فیلتر کردن داروهایی که هنوز مصرف نشده‌اند و زمانشان هم نگذشته است
    List<dynamic> pendingItems = scheduleList.where((item) {
      final itemId = item['id'];

      // اگر قبلاً مصرف شده، در صف نمایش نده
      if (consumedIds.contains(itemId)) return false;

      // بررسی گذشت زمان
      try {
        final parts = item['time'].toString().split(':');
        final itemTime = DateTime(now.year, now.month, now.day,
            int.parse(parts[0]), int.parse(parts[1]));

        // 👈 اگر زمان دارو گذشته باشد، از صف اصلی (فعلی/بعدی) خارج می‌شود
        if (itemTime.isBefore(now)) {
          return false;
        }
      } catch (e) {
        // در صورت خطای فرمت، صرف نظر می‌کنیم
      }

      return true;
    }).toList();

    // ۲. مرتب‌سازی صف بر اساس زمان (تا نزدیک‌ترین دارو اول صف باشد)
    pendingItems.sort((a, b) {
      try {
        final tA = a['time'].toString().split(':');
        final tB = b['time'].toString().split(':');
        final timeA = DateTime(
            now.year, now.month, now.day, int.parse(tA[0]), int.parse(tA[1]));
        final timeB = DateTime(
            now.year, now.month, now.day, int.parse(tB[0]), int.parse(tB[1]));
        return timeA.compareTo(timeB);
      } catch (e) {
        return 0;
      }
    });

    final currentItem = pendingItems.isNotEmpty ? pendingItems.first : null;
    final nextItem = pendingItems.length > 1 ? pendingItems[1] : null;

    if (currentItem == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Text("تمام مراقبت‌های امروز انجام شده است! 🎉",
              style: mainFont.copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.green)),
        ),
      );
    }

    // ویجت سازنده ردیف‌های درمان برای یکپارچگی UI
    Widget buildTreatmentRow({
      required String title,
      required dynamic item,
      required bool isCurrent,
    }) {
      if (item == null) return const SizedBox();

      final patientName = (item['patient'] ?? 'نامشخص').toString();
      final medName = (item['name'] ?? '-').toString();
      final time = (item['time'] ?? '00:00').toString();
      final avatarPath = _getAvatarPath(patientName);

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // عنوان بخش (درمان فعلی / بعدی)
          Text(
            title,
            style: mainFont.copyWith(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Colors.grey[500],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // سمت راست: آواتار با سایز یکسان
              CircleAvatar(
                radius: 24,
                backgroundColor: Colors.blue.shade50,
                backgroundImage: AssetImage(avatarPath),
              ),
              const SizedBox(width: 12),

              // وسط: نام بیمار و نام دارو
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      patientName.toPersianDigit(isPersian),
                      style: mainFont.copyWith(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      medName.toPersianDigit(isPersian),
                      style: mainFont.copyWith(
                          fontSize: 13, color: Colors.grey[700]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

              // سمت چپ: زمان و تایمر
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (isCurrent) ...[
                    // کپسول (Badge) زمان باقیمانده
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _calculateTimeLeft(time, isPersian)
                            .toPersianDigit(isPersian),
                        style: mainFont.copyWith(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.red.shade400),
                      ),
                    ),
                    const SizedBox(height: 6),
                  ],
                  // ساعت دقیق
                  Row(
                    children: [
                      Icon(Icons.access_time_rounded,
                          size: 14, color: Colors.grey[400]),
                      const SizedBox(width: 4),
                      Text(
                        time.toPersianDigit(isPersian),
                        style: mainFont.copyWith(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ],
      );
    }

    return Column(
      textDirection: isPersian ? TextDirection.rtl : TextDirection.ltr,
      children: [
        buildTreatmentRow(
            title: "درمان فعلی", item: currentItem, isCurrent: true),
        if (nextItem != null) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Divider(color: Colors.grey.shade200, height: 1),
          ),
          buildTreatmentRow(
              title: "درمان بعدی", item: nextItem, isCurrent: false),
        ]
      ],
    );
  }
}
