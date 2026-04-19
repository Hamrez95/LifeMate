import 'dart:async';
import 'package:flutter/material.dart';

// --- ایمپورت‌های پروژه شما ---
import '../localization/app_localizations.dart';
import '../services/backend_service.dart';
import 'profile_screen.dart';
import 'calendar_screen.dart'; 
import 'app_style.dart';
import 'shared_widgets.dart';

// 👇 این ایمپورت را بر اساس مسیری که فایل را ساختید اضافه کنید 👇
import '../utils/string_extensions.dart'; 

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int currentIndex = 0;
  int secondsLeft = 90; 
  bool isDone = false;
  bool isLoading = false;
  Timer? _timer;

  List<Map<String, dynamic>> scheduleList = [];

  @override
  void initState() {
    super.initState();
    _fetchScheduleList();
    _startTimer();
  }

  Future<void> _fetchScheduleList() async {
    try {
      final status = await BackendService.getStatus();
      final list = status['scheduleList'] as List?;
      if (list != null) {
        setState(() {
          scheduleList = List<Map<String, dynamic>>.from(
              list.map((e) => Map<String, dynamic>.from(e)));
        });
      }
    } catch (e) {
      debugPrint('Failed to fetch scheduleList: $e');
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        if (secondsLeft > 0) {
          setState(() {
            secondsLeft--;
          });
        } else {
          timer.cancel();
        }
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _onMarkAsDone() async {
    setState(() => isLoading = true);
    try {
      await BackendService.updateStatus(
          currentIndex: currentIndex, status: 'done');
      if (mounted) {
        setState(() {
          isDone = true;
          isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _handleNext() async {
    setState(() {
      currentIndex = (currentIndex + 1) % scheduleList.length;
      secondsLeft = 3600; 
      isDone = false;
      isLoading = false;
    });
    _startTimer();
    try {
      await BackendService.updateStatus(
          currentIndex: currentIndex, status: 'pending');
    } catch (e) {
      debugPrint("Backend Error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    
    final currentItem =
        (scheduleList.isNotEmpty && currentIndex < scheduleList.length)
            ? scheduleList[currentIndex]
            : {'name': '-', 'type': '-'};
            
    final nextItems =
        (scheduleList.isNotEmpty && currentIndex + 1 < scheduleList.length)
            ? scheduleList.sublist(currentIndex + 1)
            : <Map<String, dynamic>>[];

    const initialSeconds = 3600; 

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 10),
                  child: CustomHeader(
                    title: loc['home_title'] ?? 'WellMate',
                    onProfileTap: () {
                      Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => const ProfileScreen()));
                    },
                  ),
                ),
                const SizedBox(height: 10),
                TimerSection(
                  progress: secondsLeft > 0 ? (secondsLeft / initialSeconds) : 0,
                  secondsLeft: secondsLeft,
                  medicineName: currentItem['name'] ?? '',
                  titleText: loc['home_time_dose'] ?? 'Next Dose',
                ),
                const SizedBox(height: 30),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: NeumorphicButton(
                    text: isDone 
                        ? (loc['home_next_dose_btn'] ?? 'Next Dose') 
                        : (loc['home_mark_done'] ?? 'Take Medicine'),
                    isLoading: isLoading,
                    onTap: (isDone || isLoading) ? _handleNext : _onMarkAsDone,
                  ),
                ),
                const SizedBox(height: 30),
                Expanded(
                  child: Container(
                    width: double.infinity,
                    decoration: const BoxDecoration(
                      color: Colors.white70, 
                      borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(
                              left: 28, right: 28, top: 24, bottom: 16),
                          child: Text(
                            loc['home_schedule_title'] ?? 'Upcoming Schedule',
                            style: AppTextStyles.header(context),
                          ),
                        ),
                        Expanded(
                          child: nextItems.isEmpty
                              ? Center(
                                  child: Text(
                                    loc['home_empty_list'] ?? 'No more medicines',
                                    style: AppTextStyles.body(context),
                                  ),
                                )
                              : ListView.separated(
                                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 130), 
                                  itemCount: nextItems.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(height: 16),
                                  itemBuilder: (context, i) {
                                    return SoftScheduleCard(
                                      item: nextItems[i],
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            // Navigation Bar
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: GlobalBottomNav(
                currentIndex: 0, // 0 = Home
                addBtnLabel: loc['home_add_medicine'] ?? 'Add',
                onTap: (index) {
                   if (index == 1) { // 1 = Calendar
                     Navigator.pushReplacement(
                       context,
                       PageRouteBuilder(
                         pageBuilder: (context, animation1, animation2) => const CalendarScreen(),
                         transitionDuration: Duration.zero, 
                         reverseTransitionDuration: Duration.zero,
                       ),
                     );
                   }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// 1. TimerSection (اعمال تغییرات فارسی‌سازی)
class TimerSection extends StatelessWidget {
  final double progress;
  final int secondsLeft;
  final String medicineName;
  final String titleText;

  const TimerSection({
    Key? key,
    required this.progress,
    required this.secondsLeft,
    required this.medicineName,
    required this.titleText,
  }) : super(key: key);

  String get timerText {
    if (secondsLeft <= 0) return "00:00:00";
    final h = (secondsLeft ~/ 3600).toString().padLeft(2, '0');
    final m = ((secondsLeft % 3600) ~/ 60).toString().padLeft(2, '0');
    final s = (secondsLeft % 60).toString().padLeft(2, '0');
    return "$h:$m:$s";
  }

  @override
  Widget build(BuildContext context) {
    // تشخیص زبان فارسی
    final isPersian = Localizations.localeOf(context).languageCode == 'fa';

    return Column(
      children: [
        Container(
          width: 220,
          height: 220,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.bgLight,
            boxShadow: [
              BoxShadow(
                color: AppColors.shadowDark,
                offset: const Offset(8, 8),
                blurRadius: 16,
              ),
              BoxShadow(
                color: AppColors.shadowLight,
                offset: const Offset(-8, -8),
                blurRadius: 16,
              ),
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 180,
                height: 180,
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 8,
                  backgroundColor: Colors.transparent,
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.accentBlue),
                ),
              ),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.medication_liquid, size: 32, color: AppColors.accentBlue),
                  const SizedBox(height: 10),
                  // تبدیل اعداد تایمر به فارسی
                  Text(
                    timerText.toPersianDigit(isPersian),
                    style: AppTextStyles.get(context, fontSize: 28, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    titleText,
                    style: AppTextStyles.body(context),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        // اعمال توابع برای تبدیل اعداد موجود در نام دارو (مثلا 10mg)
        Text(
          medicineName.toPersianDigit(isPersian),
          style: AppTextStyles.title(context),
        ),
      ],
    );
  }
}

// 2. SoftScheduleCard (اعمال تغییرات فارسی‌سازی)
class SoftScheduleCard extends StatelessWidget {
  final Map<String, dynamic> item;

  const SoftScheduleCard({
    Key? key,
    required this.item,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // تشخیص زبان فارسی
    final isPersian = Localizations.localeOf(context).languageCode == 'fa';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgLight, 
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowDark.withOpacity(0.05),
            offset: const Offset(4, 4),
            blurRadius: 10,
          ),
          BoxShadow(
            color: Colors.white,
            offset: const Offset(-4, -4),
            blurRadius: 10,
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFE0E5EC),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(Icons.medication_outlined, color: AppColors.accentBlue),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // تبدیل اعداد موجود در اسم دارو (مثلاً آموکسی‌سیلین 500)
                Text(
                  (item['name'] ?? 'Unknown').toString().toPersianDigit(isPersian),
                  style: AppTextStyles.get(context, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                // تبدیل اعداد مربوط به دوز و ساعت مصرف دارو
                Text(
                  "${item['dose'] ?? ''} • ${item['time'] ?? ''}".toPersianDigit(isPersian),
                  style: AppTextStyles.body(context),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              "Pending", // اگر برای این بخش هم ترجمه دارید، می‌توانید از loc استفاده کنید
              style: AppTextStyles.get(context, fontSize: 12, color: Colors.orange),
            ),
          ),
        ],
      ),
    );
  }
}
