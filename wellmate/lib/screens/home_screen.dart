import 'dart:async';
import 'package:flutter/material.dart';
import '../localization/app_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../services/backend_service.dart';
import 'profile_screen.dart';
import '../localization/locale_provider.dart';
import 'home_widgets.dart'; // فایل ویجت‌هایی که در ادامه می‌سازیم

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int currentIndex = 0;
  int secondsLeft = 90; // برای تست: 01:30
  bool isDone = false;
  bool isLoading = false;
  Timer? _timer;

  // لیست داروها
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
      if (secondsLeft > 0) {
        setState(() {
          secondsLeft--;
        });
      } else {
        timer.cancel();
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
  final Color primaryText = const Color(0xFF2B3A60);

  @override
  Widget build(BuildContext context) {
   final loc = AppLocalizations.of(context);
    final localeProvider = Provider.of<LocaleProvider>(context);
    final isPersian = localeProvider.locale.languageCode == 'fa';

    // انتخاب فونت بر اساس زبان
    final TextStyle mainFont = isPersian
        ? TextStyle(fontFamily: 'Vazir', color: primaryText)
        : GoogleFonts.quicksand(color: primaryText);

    final TextStyle titleFont = isPersian
        ? TextStyle(fontFamily: 'Vazir', fontSize: 24, fontWeight: FontWeight.bold, color: const Color(0xFF33416E))
        : GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.bold, color: const Color(0xFF33416E));


    // آیتم فعلی و لیست بعدی
    final currentItem =
        (scheduleList.isNotEmpty && currentIndex < scheduleList.length)
            ? scheduleList[currentIndex]
            : {'name': '-', 'type': '-'};
            
    final nextItems =
        (scheduleList.isNotEmpty && currentIndex + 1 < scheduleList.length)
            ? scheduleList.sublist(currentIndex + 1)
            : <Map<String, dynamic>>[];

    const initialSeconds = 3600;
    
    // رنگ پس‌زمینه اصلی (طبق عکس)
    final Color bgLight = const Color(0xFFF2F4F8); 

    return Scaffold(
      backgroundColor: bgLight,
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Column(
              children: [
                // 1. Header Section
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 10),
                  child: HomeHeader(
                    title: loc['home_title'], // ترجمه شده: WellMate / ول‌میت
                    font: mainFont,
                    onProfileTap: () {
                      Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => const ProfileScreen()));
                    },
                  ),
                ),

                const SizedBox(height: 10),

                // 2. Timer Section (Neumorphic)
                TimerSection(
                  progress: secondsLeft / initialSeconds,
                  secondsLeft: secondsLeft,
                  medicineName: currentItem['name'] ?? '',
                  titleText: loc['home_time_dose'],
                  font: titleFont,
                ),

                const SizedBox(height: 30),

                // 3. Action Button
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: NeumorphicActionButton(
                    text: isDone ? loc['home_next_dose_btn'] : loc['home_mark_done'],
                    isLoading: isLoading,
                    onTap: (isDone || isLoading) ? _handleNext : _onMarkAsDone,
                    font: titleFont,
                  ),
                ),

                const SizedBox(height: 30),

                // 4. Schedule List
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
                            loc['home_schedule_title'],
                            style: mainFont.copyWith(
                              fontSize: 18, 
                              color: const Color(0xFF6B7280)
                            ),
                          ),
                        ),
                        Expanded(
                          child: nextItems.isEmpty
                              ? Center(
                                  child: Text(loc['home_empty_list'],
                                      style: titleFont.copyWith(color: Colors.grey)))
                              : ListView.separated(
                                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 130),
                                  itemCount: nextItems.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(height: 16),
                                  itemBuilder: (context, i) {
                                    return SoftScheduleCard(
                                      item: nextItems[i],
                                      index: i,
                                      font: titleFont,
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

            // 5. Floating Bottom Navigation
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: GlassBottomNav(
                addText: loc['home_add_medicine'],
                font: titleFont,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
