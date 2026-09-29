import 'package:caremate/screens/relationship_presentation_screen.dart';
import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';
import 'package:wellmate/screens/profile/care_access_phone_screen.dart';
import 'package:wellmate/screens/profile/health_record_screen.dart';

/// Product-specific profile actions hosted inside LifeMate's single profile.
/// The account identity and editable personal fields stay owned by LifeMate;
/// these entries open the product's distinct health and care workflows.
List<Widget> buildWellMateProfileSections(
  BuildContext context,
  LifeMateApiClient apiClient,
  bool isPersian,
) => [
  _ProductProfileSection(
    title: isPersian ? 'سلامت و مراقبت در WellMate' : 'WellMate health & care',
    actions: [
      _ProductProfileAction(
        icon: Icons.folder_shared_outlined,
        title: isPersian ? 'مدارک پرونده سلامت' : 'Health documents',
        subtitle: isPersian
            ? 'نسخه‌ها، آزمایش‌ها و تصویرهای پزشکی'
            : 'Prescriptions, results and medical images',
        onTap: () =>
            _pushWithApi(context, apiClient, const HealthRecordScreen()),
      ),
      _ProductProfileAction(
        icon: Icons.people_alt_outlined,
        title: isPersian ? 'دسترسی مراقبان' : 'Caregiver access',
        subtitle: isPersian
            ? 'مدیریت دسترسی به اطلاعات سلامت شما'
            : 'Manage access to your health information',
        onTap: () => Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => LifeMateCareAccessInventoryScreen(
              apiClient: apiClient,
              role: LifeMateCareAccessRole.patient,
              accent: const Color(0xFF10B981),
              background: const Color(0xFFF4F9F6),
              ink: const Color(0xFF1F2937),
              onManage: () => _pushWithApi(
                context,
                apiClient,
                const CareAccessPhoneScreen(),
              ),
            ),
          ),
        ),
      ),
    ],
  ),
];

List<Widget> buildCareMateProfileSections(
  BuildContext context,
  LifeMateApiClient apiClient,
  bool isPersian,
) => [
  _ProductProfileSection(
    title: isPersian ? 'مراقبت در CareMate' : 'CareMate caregiving',
    actions: [
      _ProductProfileAction(
        icon: Icons.family_restroom_outlined,
        title: isPersian ? 'افراد تحت مراقبت' : 'People under care',
        subtitle: isPersian
            ? 'مدیریت نام‌ها و رابطه‌های مراقبتی'
            : 'Manage names and caregiving relationships',
        onTap: () => _pushWithApi(
          context,
          apiClient,
          const CareMateRelationshipPresentationScreen(),
        ),
      ),
      _ProductProfileAction(
        icon: Icons.admin_panel_settings_outlined,
        title: isPersian ? 'دسترسی و رضایت‌ها' : 'Access and consent',
        subtitle: isPersian
            ? 'مرور دسترسی‌های مراقبتی شما'
            : 'Review your caregiving access',
        onTap: () => Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => LifeMateCareAccessInventoryScreen(
              apiClient: apiClient,
              role: LifeMateCareAccessRole.caregiver,
              accent: const Color(0xFF4A90E2),
              background: const Color(0xFFF4F9FF),
              ink: const Color(0xFF283054),
            ),
          ),
        ),
      ),
    ],
  ),
];

void _pushWithApi(
  BuildContext context,
  LifeMateApiClient apiClient,
  Widget page,
) {
  Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) =>
          Provider<LifeMateApiClient>.value(value: apiClient, child: page),
    ),
  );
}

class _ProductProfileSection extends StatelessWidget {
  const _ProductProfileSection({required this.title, required this.actions});

  final String title;
  final List<_ProductProfileAction> actions;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsetsDirectional.only(start: 4, bottom: 8),
        child: Text(title, style: Theme.of(context).textTheme.titleMedium),
      ),
      Card(child: Column(children: actions)),
    ],
  );
}

class _ProductProfileAction extends StatelessWidget {
  const _ProductProfileAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon),
    title: Text(title),
    subtitle: Text(subtitle),
    trailing: const Icon(Icons.chevron_right_rounded),
    onTap: onTap,
  );
}
