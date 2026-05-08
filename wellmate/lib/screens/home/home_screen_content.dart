import 'dart:async';
import 'package:flutter/material.dart';
import '../../localization/app_localizations.dart';
import '../../core/theme/app_style.dart';
import '../../models/schedule_item_model.dart';
import '../../services/backend_service.dart';
import 'treatment_queue_widget.dart';
import 'soft_schedule_card.dart';

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
    _timer = Timer.periodic(const Duration(minutes: 1), (timer) {
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

      // فیلتر کردن فقط برای مامان جون
      final mamanJoonSchedules = rawList
          .where((item) => item['patient'] == 'مامان جون')
          .map((item) => ScheduleItemModel(
                id: item['id'].toString(),
                type: item['type'] == 'appointment' ? 'visit' : 'medicine',
                title: item['name'],
                time: item['time'],
                dosage: item['details'],
                isDone:
                    false, // لاجیک مصرف شده‌ها را بعدا می‌توانید اینجا اضافه کنید
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

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final font = AppTextStyles.body(context);
    final upcomingItems = scheduleList.where((item) => !item.isDone).toList();

    return Column(
      children: [
        SafeArea(
          bottom: false,
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(loc['home_greeting'] ?? 'سلام، مامان جون',
                        style: font.copyWith(
                            fontSize: 20, fontWeight: FontWeight.bold)),
                    Text(loc['home_subtitle'] ?? 'برنامه درمانی امروز شما',
                        style: font.copyWith(
                            fontSize: 14, color: AppColors.textSecondary)),
                  ],
                ),
                CircleAvatar(
                  radius: 24,
                  backgroundColor: AppColors.primary.withOpacity(0.1),
                  child: Icon(Icons.person, color: AppColors.primary),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (isLoading)
          const CircularProgressIndicator()
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0),
            child: TreatmentQueueWidget(schedules: scheduleList, font: font),
          ),
        const SizedBox(height: 30),
        Expanded(
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(30)),
              boxShadow: [
                BoxShadow(
                    color: AppColors.shadowDark.withOpacity(0.3),
                    blurRadius: 15,
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
                    loc['home_schedule_title'] ?? 'لیست داروهای امروز',
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
                                  loc['home_empty_list'] ?? 'دارویی نمانده',
                                  style: font))
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
