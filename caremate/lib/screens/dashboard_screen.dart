// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../services/backend_service.dart';
import '../localization/app_localizations.dart';
import '../localization/locale_provider.dart';
import 'profile_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({Key? key}) : super(key: key);

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Map<String, dynamic>? backendStatus;
  bool syncing = false;

  final Color bgColor = const Color(0xFFDFE9F5);
  final Color cardColor = Colors.white.withOpacity(0.9);
  final Color primaryText = const Color(0xFF2B3A60);
  final Color secondaryText = const Color(0xFF6B7280);

  Timer? _autoRefreshTimer;

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
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 20), (timer) {
      _onRefresh();
    });
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

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

    // نام بیمار (می‌تواند از دیتابیس بیاید، اینجا ترکیب ترجمه و نام است)
    final String patientName = "${loc['dashboard_patient']}: John Doe";

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
                        loc['main_dashboard_title'], // CareMate or Localized Name
                        style: titleFont,
                      ),
                      GestureDetector(
                        onTap: () {
                          Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfileScreen()));
                        },
                        child: _ProfileAvatar(),
                      ),
                    ],
                  ),
                  Align(
                    alignment: isPersian ? Alignment.centerLeft : Alignment.centerRight,
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
                    alignment: isPersian ? Alignment.centerRight : Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        patientName,
                        style: mainFont.copyWith(fontSize: 12, color: secondaryText),
                      ),
                    ),
                  ),

                  // --- Synced Med/Appointments Section ---
                  _SectionHeader(
                    title: loc['dashboard_current_status'],
                    font: mainFont,
                    textDirection: isPersian ? TextDirection.rtl : TextDirection.ltr,
                  ),
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
                                    ? loc['dashboard_current_medicine']
                                    : loc['dashboard_current_appointment'],
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
                                        ? loc['dashboard_status_taken']
                                        : loc['dashboard_status_attended'],
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
                                    loc['dashboard_status_pending'],
                                    style: mainFont.copyWith(fontSize: 14, color: Colors.orange[800], fontWeight: FontWeight.bold),
                                  ),
                                ),
                              const SizedBox(height: 16),
                              Text(
                                loc['dashboard_next'],
                                style: mainFont.copyWith(fontWeight: FontWeight.bold, fontSize: 15),
                              ),
                              const SizedBox(height: 6),
                              (() {
                                final nextList = backendStatus!['nextMedications'] as List?;
                                if (nextList != null && nextList.isNotEmpty) {
                                  final med = nextList.first;
                                  return Text(
                                    med['name'] ?? '-',
                                    style: mainFont.copyWith(fontSize: 16, color: Colors.blueGrey[600]),
                                  );
                                }
                                return Text('-', style: mainFont.copyWith(fontSize: 16, color: Colors.blueGrey[600]));
                              })(),
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
                          decoration: _softDecoration(color: const Color(0xFFF0F2F5)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(loc['dashboard_partner_status'], style: mainFont.copyWith(fontSize: 15, fontWeight: FontWeight.bold)),
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
                                        valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFE598D8)),
                                      ),
                                    ),
                                    Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(loc['dashboard_week'], style: mainFont.copyWith(fontSize: 12, color: secondaryText)),
                                        Text("12", style: mainFont.copyWith(fontSize: 22, fontWeight: FontWeight.bold)),
                                      ],
                                    ),
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
                              Text("${loc['dashboard_mood']} ${loc['dashboard_mood_happy']}", style: mainFont.copyWith(fontSize: 12)),
                              Text("${loc['dashboard_craving']} ${loc['dashboard_craving_sweets']}", style: mainFont.copyWith(fontSize: 12)),
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
                              Text(loc['dashboard_baby_tracker'], style: mainFont.copyWith(fontSize: 15, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 15),
                              _GlassItem(
                                icon: Icons.baby_changing_station,
                                iconColor: Colors.blueAccent,
                                text: loc['dashboard_supply_low'],
                                hasDot: true,
                                font: mainFont,
                              ),
                              const SizedBox(height: 12),
                              _GlassItem(
                                icon: Icons.vaccines,
                                iconColor: Colors.orangeAccent,
                                text: loc['dashboard_vaccine_tomo'],
                                hasDot: false,
                                font: mainFont,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // --- Quick Summary ---
                  _SectionHeader(
                    title: loc['dashboard_quick_summary'], 
                    font: mainFont,
                    textDirection: isPersian ? TextDirection.rtl : TextDirection.ltr
                    ),
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
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: LinearProgressIndicator(
                            value: 0.8,
                            minHeight: 12,
                            backgroundColor: Colors.grey[200],
                            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF6FCF97)),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(loc['dashboard_total_meds'], style: mainFont.copyWith(color: secondaryText, fontSize: 13)),
                      ],
                    ),
                  ),

                  const SizedBox(height: 120),
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
// Widgets
// -----------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  final String title;
  final TextStyle font;
  final TextDirection? textDirection;
  
  const _SectionHeader({
    required this.title, 
    required this.font, 
    this.textDirection
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      // --- تغییر اصلی اینجاست ---
      // اگر جهت متن RTL (راست به چپ) بود، المنت را به سمت راست هل بده
      // در غیر این صورت به سمت چپ
      alignment: textDirection == TextDirection.rtl 
          ? Alignment.centerRight 
          : Alignment.centerLeft,
          
      child: Text(
        title,
        style: font.copyWith(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: const Color(0xFF2B3A60),
        ),
        // این خط جهت نوشتار حروف را تنظیم می‌کند (مثلاً پرانتزها درست نمایش داده شوند)
        textDirection: textDirection,
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
        backgroundImage: null,
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
  final TextStyle font;

  const _GlassItem({
    required this.icon, 
    required this.iconColor, 
    required this.text, 
    required this.hasDot,
    required this.font,
  });

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
              style: font.copyWith(fontSize: 12, fontWeight: FontWeight.w600),
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
