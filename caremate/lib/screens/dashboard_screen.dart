
import 'package:flutter/material.dart';
import '../services/backend_service.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Map<String, dynamic>? backendStatus;
  bool syncing = false;

  List<_ActivityItem> get _activityList {
    final base = [
      _ActivityItem(
        icon: Icons.check_circle_rounded,
        color: Colors.green,
        title: 'Medicine Taken: Acetaminophen',
        time: '10:30 AM',
      ),
      _ActivityItem(
        icon: Icons.favorite_rounded,
        color: Colors.redAccent,
        title: 'Heart Rate Normal',
        time: '',
      ),
    ];
    if (backendStatus != null && backendStatus!['status'] != 'pending') {
      final item = backendStatus!['item'] as Map<String, dynamic>;
      String title;
      if (item['type'] == 'med') {
        title = 'Medicine Taken: ${item['name']}';
      } else {
        title = 'Appointment Attended: ${item['name']}';
      }
      return [
        _ActivityItem(
          icon: Icons.notifications_active_rounded,
          color: Colors.blue,
          title: 'Update: $title',
          time: 'Just Now',
        ),
        ...base
      ];
    }
    return base;
  }

  Future<void> _onRefresh() async {
    setState(() { syncing = true; });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Syncing...'),
        duration: Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
    try {
      final data = await BackendService.getStatus();
      setState(() {
        backendStatus = data;
      });
    } catch (_) {}
    await Future.delayed(const Duration(seconds: 1));
    setState(() { syncing = false; });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'CareMate',
          style: TextStyle(
            color: Color(0xFF4A90E2),
            fontWeight: FontWeight.bold,
            fontSize: 26,
            letterSpacing: 1,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFF4A90E2)),
            onPressed: _onRefresh,
            tooltip: 'Sync',
          ),
        ],
        centerTitle: true,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
          children: [
            // Partner Status Card
            _PartnerStatusCard(),
            const SizedBox(height: 28),
            // Recent Activity
            Text(
              'Recent Activity',
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 12),
            ..._activityList.map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: _ActivityCard(item: item),
                )),
          ],
        ),
      ),
      bottomNavigationBar: const _BottomMenu(selectedIndex: 0),
    );
  }
}

class _PartnerStatusCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      shadowColor: Colors.blueGrey.withOpacity(0.10),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 28.0, horizontal: 24),
        child: Row(
          children: [
            // Circular Progress (Health Status)
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 64,
                  height: 64,
                  child: CircularProgressIndicator(
                    value: 0.85,
                    strokeWidth: 7,
                    backgroundColor: Colors.blue[50],
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF4A90E2)),
                  ),
                ),
                const Text(
                  '85%',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF4A90E2),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 24),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Mom is doing great today',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: const BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 7),
                      const Text(
                        'Online',
                        style: TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActivityItem {
  final IconData icon;
  final Color color;
  final String title;
  final String time;
  _ActivityItem({required this.icon, required this.color, required this.title, required this.time});
}

class _ActivityCard extends StatelessWidget {
  final _ActivityItem item;
  const _ActivityCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      shadowColor: Colors.blueGrey.withOpacity(0.10),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 18),
        child: Row(
          children: [
            Icon(item.icon, color: item.color, size: 28),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                item.title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (item.time.isNotEmpty)
              Text(
                item.time,
                style: TextStyle(
                  color: Colors.grey[500],
                  fontSize: 14,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BottomMenu extends StatelessWidget {
  final int selectedIndex;
  const _BottomMenu({required this.selectedIndex});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.blueGrey.withOpacity(0.08),
            blurRadius: 16,
            offset: const Offset(0, -2),
          ),
        ],
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _MenuIcon(
            icon: Icons.home_rounded,
            label: 'Home',
            selected: selectedIndex == 0,
          ),
          _MenuIcon(
            icon: Icons.notifications_rounded,
            label: 'Alerts',
            selected: selectedIndex == 1,
          ),
          _MenuIcon(
            icon: Icons.settings_rounded,
            label: 'Settings',
            selected: selectedIndex == 2,
          ),
        ],
      ),
    );
  }
}

class _MenuIcon extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  const _MenuIcon({required this.icon, required this.label, required this.selected});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          color: selected ? Theme.of(context).primaryColor : Colors.grey[400],
          size: 30,
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            color: selected ? Theme.of(context).primaryColor : Colors.grey[400],
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}
