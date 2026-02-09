
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class HomeScreen extends StatefulWidget {
	const HomeScreen({super.key});

	@override
	State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
	static const int initialSeconds = 90;
	int secondsLeft = initialSeconds;
	Timer? _timer;
	bool isDone = false;
	bool isLoading = false;
	FlutterLocalNotificationsPlugin? flutterLocalNotificationsPlugin;

	final List<Map<String, String>> scheduleList = [
		{'type': 'med', 'name': 'Acetaminophen'},
		{'type': 'med', 'name': 'Vitamin D'},
		{'type': 'med', 'name': 'Aspirin'},
		{'type': 'med', 'name': 'Metformin'},
		{'type': 'med', 'name': 'Atorvastatin'},
		{'type': 'med', 'name': 'Lisinopril'},
		{'type': 'med', 'name': 'Omeprazole'},
		{'type': 'med', 'name': 'Levothyroxine'},
		{'type': 'appt', 'name': 'Dr. Smith - Cardiology'},
		{'type': 'appt', 'name': 'Dr. Lee - Endocrinology'},
	];
	int currentIndex = 0;

	@override
	void initState() {
		super.initState();
		_startTimer();
		_initNotifications();
	}

	void _startTimer() {
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

	void _initNotifications() async {
		flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
		const AndroidInitializationSettings initializationSettingsAndroid =
				AndroidInitializationSettings('@mipmap/ic_launcher');
		const InitializationSettings initializationSettings = InitializationSettings(
			android: initializationSettingsAndroid,
		);
		await flutterLocalNotificationsPlugin!.initialize(initializationSettings);
	}

	Future<void> _showNotification() async {
		const AndroidNotificationDetails androidPlatformChannelSpecifics =
				AndroidNotificationDetails(
			'wellmate_channel',
			'WellMate Notifications',
			channelDescription: 'Notification channel for WellMate',
			importance: Importance.max,
			priority: Priority.high,
			ticker: 'ticker',
		);
		const NotificationDetails platformChannelSpecifics =
				NotificationDetails(android: androidPlatformChannelSpecifics);
		await flutterLocalNotificationsPlugin?.show(
			0,
			'Great Job!',
			'Caregiver has been notified.',
			platformChannelSpecifics,
		);
	}

	Future<void> _onMarkAsDone() async {
		setState(() {
			isLoading = true;
		});
		await MockApiService.markAsDone();
		setState(() {
			isLoading = false;
			isDone = true;
		});
		await _showNotification();
	}

	@override
	void dispose() {
		_timer?.cancel();
		super.dispose();
	}

	String get timerText {
		final minutes = (secondsLeft ~/ 60).toString().padLeft(2, '0');
		final seconds = (secondsLeft % 60).toString().padLeft(2, '0');
		return '$minutes:$seconds';
	}

	@override
	Widget build(BuildContext context) {
		final theme = Theme.of(context);
		final currentItem = scheduleList[currentIndex];
		// Show next 3 items in schedule for context
		final nextItems = List.generate(3, (i) {
			int idx = (currentIndex + i) % scheduleList.length;
			return scheduleList[idx];
		});
		return Scaffold(
			body: SafeArea(
				child: Column(
					children: [
						const SizedBox(height: 32),
						// Large neumorphic timer
						Center(
							child: Container(
								width: 220,
								height: 220,
								decoration: BoxDecoration(
									color: const Color(0xFFF5F8FF),
									shape: BoxShape.circle,
									boxShadow: [
										BoxShadow(
											color: Colors.white.withOpacity(0.8),
											offset: const Offset(-12, -12),
											blurRadius: 24,
										),
										BoxShadow(
											color: Colors.blueGrey.withOpacity(0.08),
											offset: const Offset(12, 12),
											blurRadius: 24,
										),
									],
								),
								child: Center(
									child: Text(
										timerText,
										style: const TextStyle(
											fontSize: 56,
											fontWeight: FontWeight.bold,
											color: Color(0xFF4A90E2),
											letterSpacing: 2,
										),
									),
								),
							),
						),
						const SizedBox(height: 32),
						// Mark as Done button
						SizedBox(
							width: 220,
							height: 60,
							child: ElevatedButton(
								onPressed: (isDone || isLoading) ? null : _onMarkAsDone,
								style: ElevatedButton.styleFrom(
									backgroundColor: isDone
											? Colors.green
											: theme.primaryColor,
									shape: RoundedRectangleBorder(
										borderRadius: BorderRadius.circular(32),
									),
									elevation: 8,
									shadowColor: Colors.blueGrey.withOpacity(0.15),
								),
								child: isLoading
										? const SizedBox(
												width: 28,
												height: 28,
												child: CircularProgressIndicator(
													valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
													strokeWidth: 3,
												),
											)
										: Text(
												isDone ? (currentItem['type'] == 'med' ? 'Taken!' : 'Done!') : (currentItem['type'] == 'med' ? 'Mark as Done' : 'Mark as Attended'),
												style: const TextStyle(
													fontSize: 22,
													fontWeight: FontWeight.w600,
													color: Colors.white,
												),
											),
							),
						),
						const SizedBox(height: 16),
						// Reset/Next button for testing
						SizedBox(
							width: 120,
							height: 40,
							child: OutlinedButton(
								onPressed: () {
									setState(() {
										currentIndex = (currentIndex + 1) % scheduleList.length;
										secondsLeft = initialSeconds;
										isDone = false;
										isLoading = false;
									});
									_timer?.cancel();
									_startTimer();
								},
								style: OutlinedButton.styleFrom(
									shape: RoundedRectangleBorder(
										borderRadius: BorderRadius.circular(24),
									),
									side: BorderSide(color: theme.primaryColor),
								),
								child: const Text(
									'Next',
									style: TextStyle(
										fontSize: 16,
										color: Color(0xFF4A90E2),
									),
								),
							),
						),
						const SizedBox(height: 20),
						// Today's Schedule
						Padding(
							padding: const EdgeInsets.symmetric(horizontal: 24.0),
							child: Align(
								alignment: Alignment.centerLeft,
								child: Text(
									"Today's Schedule",
									style: theme.textTheme.bodyLarge?.copyWith(
										fontWeight: FontWeight.bold,
										color: Colors.black87,
									),
								),
							),
						),
						const SizedBox(height: 12),
						Expanded(
							child: ListView.separated(
								padding: const EdgeInsets.symmetric(horizontal: 24),
								itemCount: nextItems.length,
								separatorBuilder: (_, __) => const SizedBox(height: 12),
								itemBuilder: (context, i) {
									final item = nextItems[i];
									if (item['type'] == 'med') {
										return _MedicineCard(name: item['name']!);
									} else {
										return _AppointmentCard(name: item['name']!);
									}
								},
							),
						),
					],
				),
			),
			bottomNavigationBar: _BottomMenu(selectedIndex: 0),
		);
	}
}

// Appointment Card Widget
class _AppointmentCard extends StatelessWidget {
  final String name;
  const _AppointmentCard({required this.name});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      shadowColor: Colors.blueGrey.withOpacity(0.10),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18.0, horizontal: 20),
        child: Row(
          children: [
            Icon(Icons.calendar_today_rounded, color: Theme.of(context).primaryColor, size: 28),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                name,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
	}
// End of _AppointmentCard
}

class _MedicineCard extends StatelessWidget {
	final String name;
	const _MedicineCard({required this.name});

	@override
	Widget build(BuildContext context) {
		return Card(
			elevation: 6,
			shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
			shadowColor: Colors.blueGrey.withOpacity(0.10),
			color: Colors.white,
			child: Padding(
				padding: const EdgeInsets.symmetric(vertical: 18.0, horizontal: 20),
				child: Row(
					children: [
						Icon(Icons.medication, color: Theme.of(context).primaryColor, size: 28),
						const SizedBox(width: 16),
						Text(
							name,
							style: const TextStyle(
								fontSize: 18,
								fontWeight: FontWeight.w500,
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

/// Mock API Service for demo
class MockApiService {
	static Future<void> markAsDone() async {
		await Future.delayed(const Duration(milliseconds: 1500));
	}
}
