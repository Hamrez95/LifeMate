import 'package:flutter_test/flutter_test.dart';
import 'package:wellmate/models/schedule_item_model.dart';
import 'package:wellmate/screens/home/home_screen_content.dart';

void main() {
  test('past scheduled dose is overdue immediately for home presentation', () {
    final now = DateTime(2026, 8, 10, 9, 49);
    final past = _item(id: 'past', time: '09:30');
    final future = _item(id: 'future', time: '18:30');
    final taken = _item(
      id: 'taken',
      time: '08:00',
      status: 'taken',
      isDone: true,
    );

    expect(isHomeScheduleOverdue(past, now), isTrue);
    expect(isHomeScheduleOverdue(future, now), isFalse);
    expect(isHomeScheduleOverdue(taken, now), isFalse);
  });

  test('home ordering keeps upcoming items before overdue items', () {
    final now = DateTime(2026, 8, 10, 9, 49);
    final items = <ScheduleItemModel>[
      _item(id: 'past', time: '09:30'),
      _item(id: 'future-late', time: '20:00'),
      _item(id: 'future-next', time: '18:30'),
    ]..sort((a, b) => compareHomeScheduleForDisplay(a, b, now));

    expect(items.map((item) => item.id), [
      'future-next',
      'future-late',
      'past',
    ]);
  });
}

ScheduleItemModel _item({
  required String id,
  required String time,
  String status = 'scheduled',
  bool isDone = false,
}) => ScheduleItemModel(
  id: id,
  title: id,
  time: time,
  dosage: '',
  type: 'medicine',
  frequency: 'روزانه',
  status: status,
  isDone: isDone,
  startDate: DateTime(2026, 8, 10),
);
