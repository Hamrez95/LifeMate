import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/backend_service.dart';
import 'profile_screen.dart'; // اضافه کردن ایمپورت صفحه پروفایل

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int currentIndex = 0;
  int secondsLeft = 90; // طبق عکس 01:30 تنظیم کردم برای تست
  bool isDone = false;
  bool isLoading = false;
  Timer? _timer;

  // رنگ‌های استخراج شده از تصویر
  final Color bgLight = const Color(0xFFF2F4F8); // پس‌زمینه کلی
  final Color textDark = const Color(0xFF2D3243); // رنگ متن‌های تیره
  final Color textGrey = const Color(0xFF9EA3B0); // رنگ متن‌های فرعی
  final Color accentBlue = const Color(0xFF7B93DB); // رنگ آبی ملایم

  // دیتای سمپل (می‌توانی همان دیتای خودت را جایگزین کنی)
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
          scheduleList = List<Map<String, dynamic>>.from(list.map((e) => Map<String, dynamic>.from(e)));
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
      await BackendService.updateStatus(currentIndex: currentIndex, status: 'done');
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
      await BackendService.updateStatus(currentIndex: currentIndex, status: 'pending');
    } catch (e) {
      debugPrint("Backend Error: $e");
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return "$minutes:$seconds"; // طبق عکس فقط دقیقه و ثانیه
  }

  // استایل متن‌ها (اگر گوگل فونت نداری، GoogleFonts.poppins را با TextStyle معمولی عوض کن)
  TextStyle get _headerStyle => GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.w700, color: const Color(0xFF283054));
  TextStyle get _timerTextStyle => GoogleFonts.poppins(fontSize: 56, fontWeight: FontWeight.bold, color: const Color(0xFF6D7696));
  TextStyle get _subTextStyle => GoogleFonts.poppins(fontSize: 14, color: textGrey, fontWeight: FontWeight.w500);

  @override
  Widget build(BuildContext context) {
    final currentItem = (scheduleList.isNotEmpty && currentIndex < scheduleList.length)
      ? scheduleList[currentIndex]
      : {'name': '-', 'type': '-'};
    final nextItems = (scheduleList.isNotEmpty && currentIndex + 1 < scheduleList.length)
      ? scheduleList.sublist(currentIndex + 1)
      : <Map<String, dynamic>>[];
    const initialSeconds = 3600;

    return Scaffold(
      backgroundColor: bgLight,
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Column(
              children: [
                // --- Header (WellMate) ---
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _neumorphicButton(icon: Icons.notifications_none_rounded),
                      Text("WellMate", style: _headerStyle),
                      GestureDetector(
                        onTap: () {
                          Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProfileScreen()));
                        },
                        child: _neumorphicAvatar(),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // --- Timer Section (Soft UI Ring) ---
                Stack(
                  alignment: Alignment.center,
                  children: [
                    // دایره پس‌زمینه با سایه برجسته (Neumorphism)
                    Container(
                      width: 260,
                      height: 260,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: bgLight,
                        boxShadow: [
                          BoxShadow(color: Colors.white, offset: const Offset(-10, -10), blurRadius: 20),
                          BoxShadow(color: Colors.black.withOpacity(0.08), offset: const Offset(10, 10), blurRadius: 20),
                        ],
                      ),
                    ),
                    // نقاشی دایره و پراگرس
                    SizedBox(
                      width: 220,
                      height: 220,
                      child: CustomPaint(
                        painter: _SoftTimerPainter(
                          progress: secondsLeft / initialSeconds,
                          trackColor: Colors.white, // رنگ مسیر سفید داخل عکس
                        ),
                      ),
                    ),
                    // متن داخل تایمر
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text("Time for next dose", style: _subTextStyle),
                        const SizedBox(height: 4),
                        Text(_formatDuration(Duration(seconds: secondsLeft)), style: _timerTextStyle),
                        const SizedBox(height: 4),
                        Text(currentItem['name']!, style: _subTextStyle.copyWith(color: const Color(0xFFA0A5B5))),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 40),

                // --- Mark as Done Button ---
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Container(
                    height: 55,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(30),
                      color: bgLight, // رنگ زمینه دکمه روشن است
                      border: Border.all(color: Colors.black, width: 1.5), // بوردر مشکی طبق عکس
                      boxShadow: [
                         BoxShadow(color: Colors.black.withOpacity(0.05), offset: const Offset(0, 4), blurRadius: 8),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(30),
                        onTap: (isDone || isLoading) ? _handleNext : _onMarkAsDone, // لاجیک دکمه نکست را اینجا ترکیب کردم برای سادگی UI
                        child: Center(
                          child: isLoading
                              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                              : Text(
                                  isDone ? "Next Dose" : "Mark as Done",
                                  style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.black),
                                ),
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 30),

                // --- Today's Schedule List ---
                Expanded(
                  child: Container(
                    width: double.infinity,
                    decoration: const BoxDecoration(
                      color: Colors.white70, // یک لایه شیشه‌ای ملایم زیر لیست
                      borderRadius: BorderRadius.only(topLeft: Radius.circular(30), topRight: Radius.circular(30)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(left: 28, top: 24, bottom: 16),
                          child: Text("Today's Schedule", style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF6B7280))),
                        ),
                        Expanded(
                          child: ListView.separated(
                            padding: const EdgeInsets.fromLTRB(24, 0, 24, 120), // فضای خالی پایین برای نوار ابزار
                            itemCount: nextItems.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 16),
                            itemBuilder: (context, i) {
                              final item = nextItems[i];
                              return _SoftScheduleCard(item: item, index: i);
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            // --- Bottom Navigation Bar (Floating) ---
            const Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _GlassBottomNav(),
            ),
          ],
        ),
      ),
    );
  }

  // ویجت دکمه نئومورفیک کوچک (مثل دکمه زنگ)
  Widget _neumorphicButton({required IconData icon}) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: bgLight,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: Colors.white, offset: const Offset(-4, -4), blurRadius: 10),
          BoxShadow(color: Colors.black.withOpacity(0.05), offset: const Offset(4, 4), blurRadius: 10),
        ],
      ),
      child: Icon(icon, color: const Color(0xFF4B5563), size: 24),
    );
  }

  // ویجت آواتار نئومورفیک
  Widget _neumorphicAvatar() {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: bgLight,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: Colors.white, offset: const Offset(-4, -4), blurRadius: 10),
          BoxShadow(color: Colors.black.withOpacity(0.1), offset: const Offset(4, 4), blurRadius: 10),
        ],
      ),
      child: const CircleAvatar(
        radius: 18,
        backgroundColor: Color(0xFFE2D4C8), // رنگ پوست آواتار در عکس
        child: Icon(Icons.person, color: Colors.white), // یا عکس واقعی
      ),
    );
  }
}

// --------------------------------------------------------------------------
// ویجت‌های سفارشی برای ظاهر خاص برنامه
// --------------------------------------------------------------------------

class _SoftTimerPainter extends CustomPainter {
  final double progress;
  final Color trackColor;

  _SoftTimerPainter({required this.progress, required this.trackColor});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width / 2, size.height / 2);

    // 1. حلقه سفید داخلی (مسیر)
    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 24
      ..strokeCap = StrokeCap.round;

    // کشیدن یک دایره کامل سفید به عنوان پس زمینه نوار
    canvas.drawCircle(center, radius, trackPaint);

    // 2. نوار پیشرفت (رنگ ملایم نارنجی/کرم در عکس)
    final progressPaint = Paint()
      ..color = const Color(0xFFFDE6D6) // رنگ کرم/نارنجی ملایم عکس
      ..style = PaintingStyle.stroke
      ..strokeWidth = 24
      ..strokeCap = StrokeCap.round;

    // محاسبه زاویه
    // در عکس پراگرس بار از بالا شروع شده و به سمت راست می‌رود
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -pi / 2, // شروع از بالا (ساعت ۱۲)
      2 * pi * 0.35, // مقدار ثابت برای شباهت به عکس (می‌توانید progress وصل کنید)
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}


class _SoftScheduleCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final int index;

  const _SoftScheduleCard({Key? key, required this.item, required this.index}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // تعیین رنگ و آیکون بر اساس ایندکس برای شبیه‌سازی عکس
    Color iconBgColor;
    Color barColor;
    IconData iconData;

    if (index == 0) { // Cetirizine (صورتی)
      iconBgColor = const Color(0xFFFFE4E6);
      barColor = const Color(0xFFFB7185);
      iconData = Icons.medication;
    } else if (index == 1) { // Dermatologist (آبی)
      iconBgColor = const Color(0xFFDBEAFE);
      barColor = const Color(0xFF60A5FA);
      iconData = Icons.medical_services_outlined;
    } else { // Antibiotic (نارنجی/کرم)
      iconBgColor = const Color(0xFFFEF3C7);
      barColor = const Color(0xFFF59E0B);
      iconData = Icons.vaccines;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F4F8), // رنگ کارت‌ها در عکس کمی تیره‌تر از سفید است
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          // سایه داخلی برای فرورفتگی یا برجستگی نرم
          BoxShadow(color: Colors.white, offset: const Offset(-5, -5), blurRadius: 10),
          BoxShadow(color: Colors.black.withOpacity(0.03), offset: const Offset(5, 5), blurRadius: 10),
        ],
      ),
      child: Row(
        children: [
          // آیکون با گوشه‌های نرم
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: iconBgColor,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(color: iconBgColor.withOpacity(0.4), offset: const Offset(0, 4), blurRadius: 8),
              ],
            ),
            child: Icon(iconData, color: barColor, size: 28),
          ),
          const SizedBox(width: 16),
          // متن و نوار پیشرفت
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item['name']!,
                  style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600, color: const Color(0xFF1F2937)),
                ),
                const SizedBox(height: 8),
                // نوار پیشرفت سفارشی
                Stack(
                  children: [
                    Container(
                      height: 6,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    Container(
                      height: 6,
                      width: 80 + (index * 20.0), // طول تصادفی برای زیبایی
                      decoration: BoxDecoration(
                        color: barColor,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GlassBottomNav extends StatelessWidget {
  const _GlassBottomNav({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 90,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white.withOpacity(0.0), Colors.white],
        ),
      ),
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          // نوار اصلی
          Container(
            height: 70,
            margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF2F7), // رنگ نوار پایین در عکس
              borderRadius: BorderRadius.circular(35),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, 10)),
                const BoxShadow(color: Colors.white, blurRadius: 10, offset: Offset(0, -5)),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // دکمه Home (فعال - مشکی)
                _navItem(Icons.home_filled, isActive: true),
                _navItem(Icons.person, isActive: false),
                const SizedBox(width: 60), // فضای خالی برای دکمه وسط
                _navItem(Icons.calendar_today_rounded, isActive: false),
                _navItem(Icons.medication_outlined, isActive: false),
              ],
            ),
          ),
          
          // دکمه شناور وسط (Add Medicine)
          Positioned(
            bottom: 25,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 65,
                  height: 65,
                  decoration: BoxDecoration(
                    color: const Color(0xFF283054), // رنگ سرمه‌ای تیره دکمه وسط
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(color: const Color(0xFF283054).withOpacity(0.4), blurRadius: 15, offset: const Offset(0, 8)),
                    ],
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: const [
                       Icon(Icons.medication, color: Colors.white, size: 28), // آیکون قرص
                       Positioned(
                         right: 14,
                         bottom: 14,
                         child: Icon(Icons.add_circle, color: Colors.white, size: 14), // پلاس کوچک
                       ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text("Add Medicine", style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w500, color: const Color(0xFF283054))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _navItem(IconData icon, {required bool isActive}) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: isActive 
          ? BoxDecoration(
              color: Colors.black, // در عکس دکمه فعال مشکی است
              borderRadius: BorderRadius.circular(14),
            )
          : null,
      child: Icon(
        icon,
        size: 26,
        color: isActive ? Colors.white : const Color(0xFFA0A5B5), // خاکستری برای غیرفعال‌ها
      ),
    );
  }
}
