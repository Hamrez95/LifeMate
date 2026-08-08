import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  test('reminder lead normalization is bounded and deterministic', () {
    expect(LifeMateReminderLeadTimes.normalize('30', fallback: 60), 30);
    expect(LifeMateReminderLeadTimes.normalize(-1, fallback: 60), 60);
    expect(LifeMateReminderLeadTimes.label(60), '۱ ساعت قبل');
    expect(LifeMateReminderLeadTimes.label(1440), '۱ روز قبل');
  });
}
