import 'dart:async';
import 'package:flutter/material.dart';
import 'package:wellmate/screens/home/swipe_to_confirm.dart';
import '../../localization/app_localizations.dart';
import '../../core/theme/app_style.dart';
import '../../models/schedule_item_model.dart';
import '../../services/backend_service.dart';
import 'soft_schedule_card.dart';
import 'timer_section.dart';

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

  Future<void> _markAsDone(ScheduleItemModel item) async {
    setState(() {
      final index = scheduleList.indexWhere((element) => element.id == item.id);
      if (index != -1) {
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
    return diff > 0 ? diff : 0;
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final font = AppTextStyles.body(context);

    final upcomingItems = scheduleList.where((item) => !item.isDone).toList()
      ..sort((a, b) => a.time.compareTo(b.time));

    ScheduleItemModel? nextItem =
        upcomingItems.isNotEmpty ? upcomingItems.first : null;

    return Container(
      color: AppColors.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              // استفاده از EdgeInsetsDirectional برای پشتیبانی خودکار از RTL/LTR
              padding: const EdgeInsetsDirectional.fromSTEB(24, 10, 24, 10),
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start, // چینش صحیح متن‌ها بر اساس زبان
                children: [
                  Text('سلام مریم جان،',
                      style: font.copyWith(
                          fontSize: 14, color: AppColors.textSecondary)),
                  const SizedBox(height: 4),
                  Text('برنامه امروزِ مامان جون',
                      style: font.copyWith(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary)),
                ],
              ),
            ),
          ),

          if (isLoading)
            const Expanded(
                child: Center(
                    child: CircularProgressIndicator(color: AppColors.primary)))
          else if (nextItem != null)
            Padding(
              // کاهش فاصله‌های عمودی برای باز شدن فضا
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              child: Column(
                children: [
                  TimerSection(
                    progress: 1.0 -
                        (_calculateSecondsLeft(nextItem.time) / 86400)
                            .clamp(0.0, 1.0),
                    secondsLeft: _calculateSecondsLeft(nextItem.time),
                    medicineName: nextItem.title,
                    titleText: 'درمان بعدی',
                    font: font,
                  ),
                  const SizedBox(height: 16), // کاهش چشمگیر فاصله
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: SwipeToConfirm(
                      text: 'درمان انجام شد',
                      onConfirm: () => _markAsDone(nextItem),
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 20), // کاهش فاصله تا لیست

          // بخش پایینی (لیست داروها)
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsetsDirectional.only(
                        start: 24, end: 24, top: 20, bottom: 16),
                    child: Text(
                      'برنامه امروز',
                      style: font.copyWith(
                          fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                  Expanded(
                    child: upcomingItems.isEmpty
                        ? Center(
                            child: Text('همه داروها مصرف شدند!',
                                style: font.copyWith(
                                    color: AppColors.primary, fontSize: 16)))
                        : ListView.separated(
                            padding: const EdgeInsetsDirectional.fromSTEB(
                                24,
                                0,
                                24,
                                100), // اضافه شدن فضای خالی در پایین برای جلوگیری از رفتن زیر نویگیشن بار
                            itemCount: upcomingItems.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 12),
                            itemBuilder: (context, i) => SoftScheduleCard(
                                item: upcomingItems[i], index: i, font: font),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
