import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate/navigation/shell_navigation.dart';

void main() {
  test('primary destination IDs and paths stay stable', () {
    expect(
      shellDestinationOrder.map((item) => item.id),
      ['home', 'today', 'journey', 'circle', 'you'],
    );
    expect(
      shellDestinationOrder.map((item) => item.path),
      ['/home', '/today', '/journey', '/circle', '/you'],
    );
  });

  test('normalizes known shell and product routes', () {
    expect(
      normalizeShellUri(Uri.parse('lifemate://app/today'))?.destination,
      ShellDestination.today,
    );

    final module = normalizeShellUri(
      Uri.parse('lifemate://app/apps/cocoonmate?resourceId=episode:123&v=1'),
    );
    expect(module?.moduleId, 'cocoonmate');
    expect(module?.resourceId, 'episode:123');
  });

  test('rejects sensitive or unknown deep-link parameters', () {
    expect(
      normalizeShellUri(Uri.parse('/apps/wellmate?diagnosis=private')),
      isNull,
    );
    expect(
      normalizeShellUri(Uri.parse('/today?unexpected=value')),
      isNull,
    );
  });

  test('root and trailing slash normalize safely', () {
    expect(
      normalizeShellUri(Uri.parse('/'))?.destination,
      ShellDestination.home,
    );
    expect(
      normalizeShellUri(Uri.parse('/circle/'))?.destination,
      ShellDestination.circle,
    );
  });
}
