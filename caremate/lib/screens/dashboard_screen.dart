import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart'; // پیشنهاد می‌شود این پکیج را داشته باشید
import '../services/backend_service.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({Key? key}) : super(key: key);

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {

  Map<String, dynamic>? backendStatus;
  bool syncing = false;

  // رنگ‌های استخراج شده از تصویر
  final Color bgColor = const Color(0xFFDFE9F5); // آبی خیلی روشن پس‌زمینه
  final Color cardColor = Colors.white.withOpacity(0.9);
  final Color primaryText = const Color(0xFF2B3A60); // سرمه‌ای تیره
  final Color secondaryText = const Color(0xFF6B7280);

  Future<void> _onRefresh() async {
    setState(() { syncing = true; });
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
    if (mounted) setState(() { syncing = false; });
  }

  @override
  void initState() {
    super.initState();
    _onRefresh();
  }

  @override
  Widget build(BuildContext context) {
    // استفاده از فونت گرد و مدرن
    final TextStyle mainFont = GoogleFonts.quicksand(color: primaryText);

    // Patient name (example: replace with actual patient name from backend/user model)
    const String patientName = "Patient: John Doe";
    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Column(
                children: [
                  // --- Header ---
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _GlassIconButton(icon: Icons.notifications_none_rounded, onTap: () {}),
                      Text(
                        'CareMate',
                        style: GoogleFonts.poppins(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF33416E),
                        ),
                      ),
                      _ProfileAvatar(),
                    ],
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 10, bottom: 20),
                      child: _GlassIconButton(
                        icon: Icons.tune_rounded,
                        size: 38,
                        iconSize: 20,
                        onTap: _onRefresh,
                      ),
                    ),
                  ),

                  // --- Patient Name ---
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        patientName,
                        style: mainFont.copyWith(fontSize: 12, color: secondaryText),
                      ),
                    ),
                  ),

                  // --- Synced Med/Appointments Section ---
                  _SectionHeader(title: "Current Status"),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    decoration: _softDecoration(),
                    padding: const EdgeInsets.all(20),
                    child: backendStatus == null
                        ? const Center(child: CircularProgressIndicator())
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                backendStatus!['item']?['type'] == 'med'
                                    ? 'Current Medicine:'
                                    : 'Current Appointment:',
                                style: mainFont.copyWith(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                backendStatus!['item']?['name'] ?? '-',
                                style: mainFont.copyWith(fontSize: 18, color: Colors.blueGrey[800]),
                              ),
                              const SizedBox(height: 8),
                              if (backendStatus!['status'] == 'done' || backendStatus!['status'] == 'attended')
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.green.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    backendStatus!['status'] == 'done'
                                        ? 'Medicine Taken!'
                                        : 'Appointment Attended!',
                                    style: mainFont.copyWith(fontSize: 14, color: Colors.green[800], fontWeight: FontWeight.bold),
                                  ),
                                ),
                              if (backendStatus!['status'] == 'pending')
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    'Pending',
                                    style: mainFont.copyWith(fontSize: 14, color: Colors.orange[800], fontWeight: FontWeight.bold),
                                  ),
                                ),
                              const SizedBox(height: 16),
                              Text(
                                'Next Medications:',
                                style: mainFont.copyWith(fontWeight: FontWeight.bold, fontSize: 15),
                              ),
                              const SizedBox(height: 6),
                              ...((backendStatus!['nextMedications'] as List?)?.isNotEmpty == true
                                  ? (backendStatus!['nextMedications'] as List)
                                      .map((med) => Text(
                                            med['name'] ?? '-',
                                            style: mainFont.copyWith(fontSize: 16, color: Colors.blueGrey[600]),
                                          ))
                                      .toList()
                                  : [
                                      Text('-', style: mainFont.copyWith(fontSize: 16, color: Colors.blueGrey[600]))
                                    ]),
                            ],
                          ),
                  ),
                  const SizedBox(height: 24),

                  // --- Grid Section (Partner Status & Baby Tracker) ---
                  Row(
                    children: [
                      // Partner Status Card
                      Expanded(
                        child: Container(
                          height: 210,
                          padding: const EdgeInsets.all(16),
                          decoration: _softDecoration(color: const Color(0xFFF0F2F5)), // کمی متفاوت
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("Partner Status", style: mainFont.copyWith(fontSize: 15, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 15),
                              // Circular Progress
                              Center(
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    SizedBox(
                                      width: 90,
                                      height: 90,
                                      child: CircularProgressIndicator(
                                        value: 0.75, // Week 12 approx
                                        strokeWidth: 10,
                                        backgroundColor: Colors.white,
                                        valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFE598D8)), // صورتی
                                      ),
                                    ),
                                    // Gradient Mockup using ShaderMask if needed, or simple color
                                    Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text("Week", style: mainFont.copyWith(fontSize: 12, color: secondaryText)),
                                        Text("12", style: mainFont.copyWith(fontSize: 22, fontWeight: FontWeight.bold)),
                                      ],
                                    ),
                                    // Baby Icon floating
                                    Positioned(
                                      right: 0,
                                      bottom: 5,
                                      child: CircleAvatar(
                                        radius: 14,
                                        backgroundColor: const Color(0xFFFFE0B2),
                                        child: Icon(Icons.child_care, size: 18, color: Colors.orange[800]),
                                      ),
                                    )
                                  ],
                                ),
                              ),
                              const Spacer(),
                              Text("Mood: Happy", style: mainFont.copyWith(fontSize: 12)),
                              Text("Craving: Sweets", style: mainFont.copyWith(fontSize: 12)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Baby Tracker Card
                      Expanded(
                        child: Container(
                          height: 210,
                          padding: const EdgeInsets.all(16),
                          decoration: _softDecoration(),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("Baby Tracker", style: mainFont.copyWith(fontSize: 15, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 15),
                              // Tracker Item 1
                              _GlassItem(
                                icon: Icons.baby_changing_station, 
                                iconColor: Colors.blueAccent,
                                text: "+ Supply Low",
                                hasDot: true,
                              ),
                              const SizedBox(height: 12),
                              // Tracker Item 2
                              _GlassItem(
                                icon: Icons.vaccines, 
                                iconColor: Colors.orangeAccent,
                                text: "+ Vaccine: Tomo...", // Truncated as per image style
                                hasDot: false,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // --- Quick Summary ---
                  _SectionHeader(title: "Quick Summary"),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: _softDecoration(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text("80%", style: mainFont.copyWith(fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // Linear Bar
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: LinearProgressIndicator(
                            value: 0.8,
                            minHeight: 12,
                            backgroundColor: Colors.grey[200],
                            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF6FCF97)), // سبز
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text("Total Meds Taken Today", style: mainFont.copyWith(color: secondaryText, fontSize: 13)),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 120), // فضای خالی برای نوار پایین
                ],
              ),
            ),

            // --- Bottom Navigation Bar ---
            Positioned(
              bottom: 30,
              left: 20,
              right: 20,
              child: _CustomBottomNav(),
            ),
          ],
        ),
      ),
    );
  }

  BoxDecoration _softDecoration({Color color = Colors.white}) {
    return BoxDecoration(
      color: color.withOpacity(0.85),
      borderRadius: BorderRadius.circular(24),
      boxShadow: [
        BoxShadow(color: Colors.white.withOpacity(0.8), offset: const Offset(-6, -6), blurRadius: 12),
        BoxShadow(color: const Color(0xFFA6BCCF).withOpacity(0.3), offset: const Offset(6, 6), blurRadius: 12),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// ویجت‌های کمکی برای ظاهر ۳ بعدی و Glassy
// -----------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        title,
        style: GoogleFonts.quicksand(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: const Color(0xFF2B3A60),
        ),
      ),
    );
  }
}

class _GlassIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final double size;
  final double iconSize;

  const _GlassIconButton({required this.icon, required this.onTap, this.size = 48, this.iconSize = 24});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: const Color(0xFFF0F4FA),
          shape: BoxShape.circle,
          boxShadow: [
            const BoxShadow(color: Colors.white, offset: Offset(-4, -4), blurRadius: 8),
            BoxShadow(color: Colors.black.withOpacity(0.05), offset: const Offset(4, 4), blurRadius: 8),
          ],
        ),
        child: Icon(icon, color: Colors.black54, size: iconSize),
      ),
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFFF0F4FA),
        boxShadow: [
            const BoxShadow(color: Colors.white, offset: Offset(-4, -4), blurRadius: 8),
            BoxShadow(color: Colors.black.withOpacity(0.1), offset: const Offset(4, 4), blurRadius: 8),
        ],
      ),
      padding: const EdgeInsets.all(4),
      child: const CircleAvatar(
        backgroundColor: Color(0xFFE2D4C8),
        backgroundImage: null, // اینجا می‌توانید عکس واقعی بگذارید
        child: Icon(Icons.person, color: Colors.white),
      ),
    );
  }
}

class _GlassItem extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String text;
  final bool hasDot;

  const _GlassItem({required this.icon, required this.iconColor, required this.text, required this.hasDot});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.blue[50]!.withOpacity(0.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.quicksand(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
          if (hasDot)
            Container(width: 6, height: 6, decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle))
        ],
      ),
    );
  }
}

class _CustomBottomNav extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 80,
      decoration: BoxDecoration(
        color: const Color(0xFFEFF4F9),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20, offset: const Offset(0, 10)),
          const BoxShadow(color: Colors.white, blurRadius: 10, offset: Offset(0, -5)),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _navIcon(Icons.calendar_today_rounded),
          _navIcon(Icons.person_outline_rounded),
          // Floating Add Button
          Transform.translate(
            offset: const Offset(0, -25),
            child: Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: const Color(0xFF2C3E50),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: const Color(0xFF2C3E50).withOpacity(0.4), blurRadius: 15, offset: const Offset(0, 10)),
                ],
              ),
              child: const Icon(Icons.add, color: Colors.white, size: 30),
            ),
          ),
          _navIcon(Icons.notifications_none_rounded),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF2C3E50),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.home_rounded, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _navIcon(IconData icon) {
    return Icon(icon, color: Colors.grey[500], size: 28);
  }
}
