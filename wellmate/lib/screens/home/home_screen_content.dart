import 'dart:async';
import 'package:flutter/material.dart';
import '../../localization/app_localizations.dart';
import '../../core/theme/app_style.dart';
import '../../models/schedule_item_model.dart';
import '../../core/widgets/custom_header.dart';
import '../../core/widgets/neumorphic_action_button.dart';
import 'timer_section.dart';
import 'soft_schedule_card.dart';
import '../profile/profile_screen.dart';

class HomeScreenContent extends StatefulWidget {
  const HomeScreenContent({Key? key}) : super(key: key);

  @override
  State<HomeScreenContent> createState() => _HomeScreenContentState();
}

class _HomeScreenContentState extends State<HomeScreenContent> {
  int currentIndex = 0;
  int secondsLeft = 3600;
  bool isDone = false;
  bool isLoading = false;
  Timer? _timer;
  List<ScheduleItemModel> scheduleList = [];

  @override
  void initState() {
    super.initState();
    _fetchScheduleList();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _fetchScheduleList() {
    setState(() {
      scheduleList = [
        ScheduleItemModel(
            id: '1',
            type: 'medicine',
            title: 'آموکسی‌سیلین (کپسول ۵۰۰)',
            time: '08:00',
            dosage: '۱ عدد'),
        ScheduleItemModel(
            id: '2',
            type: 'medicine',
            title: 'ویتامین C (قرص جوشان)',
            time: '14:00',
            dosage: '۱ عدد'),
        ScheduleItemModel(
            id: '3',
            type: 'medicine',
            title: 'آسپرین (قرص)',
            time: '20:00',
            dosage: '۱ عدد'),
      ];
    });
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          if (secondsLeft > 0) {
            secondsLeft--;
          } else {
            timer.cancel();
          }
        });
      }
    });
  }

  Future<void> _onMarkAsDone() async {
    setState(() => isLoading = true);
    await Future.delayed(const Duration(seconds: 1));
    if (mounted)
      setState(() {
        isLoading = false;
        isDone = true;
      });
  }

  void _handleNext() {
    setState(() {
      if (currentIndex < scheduleList.length - 1) {
        currentIndex++;
        secondsLeft = 3600;
        isDone = false;
        _startTimer();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('برنامه دارویی امروز به پایان رسید.')),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final font = AppTextStyles.body(context);

    final currentItem = (scheduleList.isNotEmpty &&
            currentIndex < scheduleList.length)
        ? scheduleList[currentIndex]
        : ScheduleItemModel(id: '', type: '', title: '-', time: '', dosage: '');

    final nextItems =
        (scheduleList.isNotEmpty && currentIndex + 1 < scheduleList.length)
            ? scheduleList.sublist(currentIndex + 1)
            : <ScheduleItemModel>[];

    const initialSeconds = 3600;
    final progress =
        secondsLeft > 0 ? (1 - (secondsLeft / initialSeconds)) : 1.0;

    return Column(
      children: [
        // Appbar/Header
        SafeArea(
          bottom: false,
          child: CustomHeader(
            title: loc['home_title'] ?? 'WellMate',
            font: font,
            onProfileTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const ProfileScreen())),
          ),
        ),
        const SizedBox(height: 10),
        TimerSection(
          progress: progress,
          secondsLeft: secondsLeft,
          medicineName: currentItem.title,
          titleText: loc['home_time_dose'] ?? 'Next Dose',
          font: font,
        ),
        const SizedBox(height: 30),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: NeumorphicActionButton(
            text: isDone
                ? (loc['home_next_dose_btn'] ?? 'Next Dose')
                : (loc['home_mark_done'] ?? 'Take Medicine'),
            isLoading: isLoading,
            font: font,
            onTap: (isDone || isLoading) ? _handleNext : _onMarkAsDone,
          ),
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
                    color: AppColors.shadowDark.withOpacity(0.5),
                    blurRadius: 10,
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
                    loc['home_schedule_title'] ?? 'Upcoming Schedule',
                    style: font.copyWith(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary),
                  ),
                ),
                Expanded(
                  child: nextItems.isEmpty
                      ? Center(
                          child: Text(
                              loc['home_empty_list'] ?? 'No more medicines',
                              style: font))
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                          itemCount: nextItems.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 16),
                          itemBuilder: (context, i) => SoftScheduleCard(
                              item: nextItems[i], index: i, font: font),
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
