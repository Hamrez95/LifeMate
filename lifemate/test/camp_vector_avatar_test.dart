import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate/living_camp/camp_avatar_fallback.dart';
import 'package:lifemate/living_camp/camp_vector_avatar.dart';

void main() {
  Widget host({
    required CampAvatarFamily family,
    required CampAvatarAction action,
    bool motionEnabled = true,
    bool reduceMotion = false,
    String? commandId,
    void Function(CampAvatarAction, String?)? onComplete,
  }) => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: Center(
        child: SizedBox(
          width: 132,
          height: 198,
          child: CampVectorAvatar(
            family: family,
            action: action,
            motionEnabled: motionEnabled,
            commandId: commandId,
            onActionComplete: onComplete,
          ),
        ),
      ),
    ),
  );

  testWidgets('both adult families render editable vector paths', (
    tester,
  ) async {
    for (final family in CampAvatarFamily.values) {
      await tester.pumpWidget(
        host(
          family: family,
          action: CampAvatarAction.idle,
          motionEnabled: false,
        ),
      );
      expect(
        find.byKey(const ValueKey('camp-vector-avatar-paint')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('walk loops without emitting a completion', (tester) async {
    var completions = 0;
    await tester.pumpWidget(
      host(
        family: CampAvatarFamily.adultMasculine,
        action: CampAvatarAction.walk,
        onComplete: (_, _) => completions++,
      ),
    );
    await tester.pump(const Duration(seconds: 3));
    expect(completions, 0);
    expect(tester.takeException(), isNull);
  });

  for (final action in [CampAvatarAction.drink, CampAvatarAction.wellness]) {
    testWidgets('$action completes once and returns to idle', (tester) async {
      final results = <(CampAvatarAction, String?)>[];
      await tester.pumpWidget(
        host(
          family: CampAvatarFamily.adultFeminine,
          action: action,
          commandId: 'first',
          onComplete: (a, id) => results.add((a, id)),
        ),
      );
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 4));
      expect(results, [(action, 'first')]);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('reduced motion keeps a stable pose and completes action', (
    tester,
  ) async {
    var completions = 0;
    await tester.pumpWidget(
      host(
        family: CampAvatarFamily.adultMasculine,
        action: CampAvatarAction.drink,
        reduceMotion: true,
        onComplete: (_, _) => completions++,
      ),
    );
    await tester.pump(const Duration(seconds: 3));
    expect(completions, 1);
    expect(
      find.byKey(const ValueKey('camp-vector-avatar-paint')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
