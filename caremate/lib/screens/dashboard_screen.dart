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
        Timer.periodic(const Duration(seconds: 20), (_) => _onRefresh());
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

    final TextStyle mainFont = TextStyle(
        fontFamily: isPersian ? 'Vazir' : 'Poppins',
        color: AppColors.primaryText);
    final TextStyle titleFont = TextStyle(
        fontFamily: isPersian ? 'Vazir' : 'Poppins',
        fontSize: 24,
        fontWeight: FontWeight.bold,
        color: AppColors.titleDarkBlue);

    final String patientName =
        "${loc['dashboard_patient']}: ${MockData.patientNameEn}";

    return Scaffold(
      backgroundColor: AppColors.background,
      // اینجا با extendBody: true به محتوا اجازه می‌دهیم تا زیر نویگیشن بار برود
      extendBody: true,

      // حذف Stack و قرار دادن مستقیم بدنه
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            children: [
              // --- Header ---
              const CustomAppHeader(),

              Align(
                alignment:
                    isPersian ? Alignment.centerLeft : Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 20),
                  child: GlassIconButton(
                      icon: Icons.tune_rounded,
                      size: 38,
                      iconSize: 20,
                      onTap: _onRefresh),
                ),
              ),

              Align(
                alignment:
                    isPersian ? Alignment.centerRight : Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(patientName,
                      style: mainFont.copyWith(
                          fontSize: 12, color: AppColors.secondaryText)),
                ),
              ),

              // --- Current Status Section ---
              SectionHeader(
                  title: loc['dashboard_current_status'],
                  font: mainFont,
                  textDirection:
                      isPersian ? TextDirection.rtl : TextDirection.ltr),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                decoration: AppColors.softDecoration(),
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
                                  fontSize: 15, fontWeight: FontWeight.bold)),
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
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                          Color(0xFFE598D8))),
                                ),
                                Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(loc['dashboard_week'],
                                        style: mainFont.copyWith(
                                            fontSize: 12,
                                            color: AppColors.secondaryText)),
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
                                  fontSize: 15, fontWeight: FontWeight.bold)),
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
                    Text(MockData.medicationProgress.toPersianDigit(isPersian),
                        style: mainFont.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: LinearProgressIndicator(
                          value: MockData.medicationProgressValue,
                          minHeight: 12,
                          backgroundColor: Colors.grey[200],
                          valueColor: const AlwaysStoppedAnimation<Color>(
                              Color(0xFF6FCF97))),
                    ),
                    const SizedBox(height: 12),
                    Text(loc['dashboard_total_meds'],
                        style: mainFont.copyWith(
                            color: AppColors.secondaryText, fontSize: 13)),
                  ],
                ),
              ),
              // این فضای خالی باعث می‌شود وقتی به پایین اسکرول می‌کنید، کارت آخر پشت نویگیشن مخفی نشود
              const SizedBox(height: 120),
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

  Widget _buildStatusContent(dynamic loc, bool isPersian, TextStyle mainFont) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
            backendStatus!['item']?['type'] == 'med'
                ? loc['dashboard_current_medicine']
                : loc['dashboard_current_appointment'],
            style:
                mainFont.copyWith(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 8),
        Text(
            (backendStatus!['item']?['name'] ?? '-')
                .toString()
                .toPersianDigit(isPersian),
            style:
                mainFont.copyWith(fontSize: 18, color: Colors.blueGrey[800])),
        const SizedBox(height: 8),
        if (backendStatus!['status'] == 'done' ||
            backendStatus!['status'] == 'attended')
          _statusBadge(
              backendStatus!['status'] == 'done'
                  ? loc['dashboard_status_taken']
                  : loc['dashboard_status_attended'],
              Colors.green,
              mainFont),
        if (backendStatus!['status'] == 'pending')
          _statusBadge(
              loc['dashboard_status_pending'], Colors.orange, mainFont),
        const SizedBox(height: 16),
        Text(loc['dashboard_next'],
            style:
                mainFont.copyWith(fontWeight: FontWeight.bold, fontSize: 15)),
        const SizedBox(height: 6),
        _nextMedication(isPersian, mainFont),
      ],
    );
  }

  Widget _statusBadge(String text, MaterialColor color, TextStyle font) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(10)),
      child: Text(text,
          style: font.copyWith(
              fontSize: 14, color: color[800], fontWeight: FontWeight.bold)),
    );
  }

  Widget _nextMedication(bool isPersian, TextStyle mainFont) {
    final nextList = backendStatus!['nextMedications'] as List?;
    if (nextList != null && nextList.isNotEmpty) {
      return Text(
          (nextList.first['name'] ?? '-').toString().toPersianDigit(isPersian),
          style: mainFont.copyWith(fontSize: 16, color: Colors.blueGrey[600]));
    }
    return Text('-',
        style: mainFont.copyWith(fontSize: 16, color: Colors.blueGrey[600]));
  }
}
