import 'dart:async';
import 'package:flutter/material.dart';
import '../../localization/app_localizations.dart';
import '../../core/theme/app_style.dart';
import '../../models/schedule_item_model.dart';
import '../../services/backend_service.dart';
import 'soft_schedule_card.dart';
import 'timer_section.dart'; // حتما این فایل را ایمپورت کنید

class HomeScreenContent extends StatefulWidget {
  const HomeScreenContent({Key? key}) : super(key: key);

  @override
  State<HomeScreenContent> createState() => _HomeScreenContentState();
}

class _HomeScreenContentState extends State<HomeScreenContent> {
  List<ScheduleItemModel> scheduleList = [];
  Timer? _timer;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchScheduleFromBackend();
    // تایمر برای آپدیت لحظه‌ای زمان باقی‌مانده
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _fetchScheduleFromBackend() async {
    try {
      final data = await BackendService.getStatus();
      final List<dynamic> rawList = data['scheduleList'] ?? [];

      final mamanJoonSchedules = rawList
          .where((item) => item['patient'] == 'مامان جون')
          .map((item) => ScheduleItemModel(
                id: item['id'].toString(),
                type: item['type'] == 'appointment' ? 'visit' : 'medicine',
                title: item['name'],
                time: item['time'],
                dosage: item['details'],
                isDone: false,
              ))
          .toList();

      setState(() {
        scheduleList = mamanJoonSchedules;
        isLoading = false;
      });
    } catch (e) {
      debugPrint('Error: $e');
      setState(() => isLoading = false);
    }
  }

  // فانکشن ثبت مصرف دارو در بک‌اند
  Future<void> _markAsDone(ScheduleItemModel item) async {
    // در اینجا درخواست به بک‌اند را ارسال می‌کنید:
    // await BackendService.markItemAsDone(item.id);

    // آپدیت UI با استفاده از copyWith:
    setState(() {
      // پیدا کردن ایندکس داروی فعلی در لیست اصلی
      final index = scheduleList.indexWhere((element) => element.id == item.id);
      if (index != -1) {
        // جایگزین کردن آیتم با یک کپی جدید که isDone آن true شده است
        scheduleList[index] = item.copyWith(isDone: true);
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${item.title} به عنوان مصرف‌شده ثبت شد.',
            style: AppTextStyles.body(context).copyWith(color: Colors.white)),
        backgroundColor: Colors.green.shade600,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  int _calculateSecondsLeft(String time) {
    final now = DateTime.now();
    final parts = time.split(':');
    final scheduleTime = DateTime(
        now.year, now.month, now.day, int.parse(parts[0]), int.parse(parts[1]));

    final diff = scheduleTime.difference(now).inSeconds;
    return diff > 0 ? diff : 0; // اگر زمان گذشته باشد، 0 برمی‌گرداند
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final font = AppTextStyles.body(context);

    // مرتب‌سازی لیست بر اساس زمان برای پیدا کردن داروی بعدی
    final upcomingItems = scheduleList.where((item) => !item.isDone).toList()
      ..sort((a, b) => a.time.compareTo(b.time));

    ScheduleItemModel? nextItem =
        upcomingItems.isNotEmpty ? upcomingItems.first : null;

    return Column(
      children: [
        SafeArea(
          bottom: false,
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                'مامان جون عزیز، سلام! 👋', // متن صمیمی و دوستانه
                style: font.copyWith(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary),
              ),
            ),
          ),
        ),

        if (isLoading)
          const Padding(
            padding: EdgeInsets.all(40.0),
            child: CircularProgressIndicator(),
          )
        else if (nextItem != null)
          // بخش جذاب تایمر و دکمه اقدام
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10),
            child: Column(
              children: [
                TimerSection(
                  // محاسبه پراگرس بر اساس 24 ساعت (یا هر مقیاسی که دارید)
                  progress: 1.0 -
                      (_calculateSecondsLeft(nextItem.time) / 86400)
                          .clamp(0.0, 1.0),
                  secondsLeft: _calculateSecondsLeft(nextItem.time),
                  medicineName: nextItem.title,
                  titleText: 'نوبت داروی بعدی',
                  font: font,
                ),
                const SizedBox(height: 24),
                // دکمه بزرگ و واضح برای سالمند
                SizedBox(
                  width: double.infinity,
                  height: 60,
                  child: ElevatedButton(
                    onPressed: () => _markAsDone(nextItem),
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          Colors.green.shade500, // رنگ سبز WellMate
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20)),
                      elevation: 5,
                      shadowColor: Colors.green.withOpacity(0.4),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.check_circle_outline, size: 28),
                        const SizedBox(width: 10),
                        Text('دارو رو خوردم',
                            style: font.copyWith(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.white)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

        const SizedBox(height: 30),

        // لیست سایر داروها
        Expanded(
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(30)),
              boxShadow: [
                BoxShadow(
                    color: AppColors.shadowDark.withOpacity(0.1),
                    blurRadius: 20,
                    offset: const Offset(0, -5))
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(
                      left: 28, right: 28, top: 24, bottom: 16),
                  child: Text(
                    loc['home_schedule_title'] ?? 'لیست برنامه‌های امروز',
                    style: font.copyWith(
                        fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                Expanded(
                  child: isLoading
                      ? const SizedBox()
                      : upcomingItems.isEmpty
                          ? Center(
                              child: Text(
                                  'همه داروها رو به موقع خوردی، آفرین! 🌿',
                                  style: font.copyWith(
                                      color: AppColors.primary, fontSize: 16)))
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                              itemCount: upcomingItems.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 16),
                              itemBuilder: (context, i) => SoftScheduleCard(
                                  item: upcomingItems[i], index: i, font: font),
                            ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
