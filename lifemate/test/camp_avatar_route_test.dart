import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate/living_camp/camp_avatar_fallback.dart';
import 'package:lifemate/living_camp/camp_avatar_route.dart';

void main() {
  test(
    'route visits WellMate for wellness and drink before returning home',
    () {
      final outbound = CampAvatarRoute.sample(.18);
      final wellness = CampAvatarRoute.sample(.39);
      final drink = CampAvatarRoute.sample(.46);
      final returning = CampAvatarRoute.sample(.72);
      final home = CampAvatarRoute.sample(.96);

      expect(outbound.action, CampAvatarAction.walk);
      expect(outbound.position.x, greaterThan(CampAvatarRoute.wellmateDoor.x));
      expect(wellness.action, CampAvatarAction.wellness);
      expect(wellness.position.x, CampAvatarRoute.wellmateDoor.x);
      expect(drink.action, CampAvatarAction.drink);
      expect(returning.action, CampAvatarAction.walk);
      expect(returning.position.x, greaterThan(CampAvatarRoute.wellmateDoor.x));
      expect(home.action, CampAvatarAction.idle);
      expect(home.position.x, CampAvatarRoute.home.x);
      expect(home.position.y, CampAvatarRoute.home.y);
    },
  );

  test('route clamps progress and remains deterministic', () {
    expect(CampAvatarRoute.sample(-1).position.x, CampAvatarRoute.home.x);
    expect(CampAvatarRoute.sample(2).position.y, CampAvatarRoute.home.y);
    expect(CampAvatarRoute.sample(.39).commandId, 'wellmate-wellness');
  });
}
