import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';

class CareAccessSettingsScreen extends StatefulWidget {
  const CareAccessSettingsScreen({super.key, required this.relationship});

  final Map<String, dynamic> relationship;

  @override
  State<CareAccessSettingsScreen> createState() =>
      _CareAccessSettingsScreenState();
}

class _CareAccessSettingsScreenState extends State<CareAccessSettingsScreen> {
  bool _loading = true;
  bool _saving = false;
  bool _womenCalendarEnabled = false;
  bool _canViewWomenCalendar = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _canViewWomenCalendar = widget.relationship['canViewWomenCalendar'] == true;
    _load();
  }

  Future<void> _load() async {
    if (!LifeMateFeatureFlags.womenCalendarPilotEnabled) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final profile = await context
          .read<LifeMateApiClient>()
          .getWomenCalendarProfile();
      if (!mounted) return;
      setState(() => _womenCalendarEnabled = profile['enabled'] == true);
    } catch (error) {
      debugPrint('Care permission profile load failed.');
      if (mounted) setState(() => _error = 'وضعیت تقویم بانوان دریافت نشد.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setWomenCalendarAccess(bool value) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final updated = await context
          .read<LifeMateApiClient>()
          .updateCareRelationshipPermissions(
            relationshipId: widget.relationship['id'].toString(),
            canViewWomenCalendar: value,
          );
      if (!mounted) return;
      setState(() {
        _canViewWomenCalendar = updated['canViewWomenCalendar'] == true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            value
                ? 'دسترسی تقویم بانوان برای این مراقب فعال شد.'
                : 'دسترسی تقویم بانوان برای این مراقب غیرفعال شد.',
          ),
        ),
      );
    } catch (error) {
      debugPrint('Care permission update failed.');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تغییر دسترسی انجام نشد.')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name =
        widget.relationship['caregiverDisplayName']?.toString() ?? 'مراقب';
    return Scaffold(
      appBar: AppBar(title: Text('تنظیمات دسترسی $name')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              'هر دسترسی مستقل است و فقط با تصمیم شما فعال می‌شود. قطع رابطه، همه دسترسی‌ها را فوراً متوقف می‌کند.',
              style: TextStyle(height: 1.7),
            ),
          ),
          const SizedBox(height: 18),
          Card(
            elevation: 0,
            child: Column(
              children: [
                const SwitchListTile(
                  value: true,
                  onChanged: null,
                  secondary: Icon(Icons.medication_rounded),
                  title: Text('برنامه و مصرف دارو'),
                  subtitle: Text('دسترسی پایه رابطه مراقبتی'),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  value: _canViewWomenCalendar,
                  onChanged:
                      _loading ||
                          _saving ||
                          !_womenCalendarEnabled ||
                          !LifeMateFeatureFlags.womenCalendarPilotEnabled
                      ? null
                      : _setWomenCalendarAccess,
                  secondary: _saving
                      ? const SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.calendar_month_rounded),
                  title: const Text('تقویم بانوان'),
                  subtitle: Text(
                    !LifeMateFeatureFlags.womenCalendarPilotEnabled
                        ? 'در این Build فعال نیست'
                        : !_womenCalendarEnabled
                        ? 'ابتدا تقویم بانوان را برای خودتان فعال کنید'
                        : 'نمایش خلاصه چرخه؛ یادداشت خصوصی اشتراک‌گذاری نمی‌شود',
                  ),
                ),
                const Divider(height: 1),
                const SwitchListTile(
                  value: false,
                  onChanged: null,
                  secondary: Icon(Icons.folder_shared_outlined),
                  title: Text('مشاهده پرونده سلامت'),
                  subtitle: Text('در نسخه بعدی و پس از قرارداد حریم خصوصی'),
                ),
              ],
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }
}
