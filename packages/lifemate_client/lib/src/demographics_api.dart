import 'package:supabase_flutter/supabase_flutter.dart';

enum LifeMateGenderIdentity {
  notCollected('NotCollected'),
  woman('Woman'),
  man('Man'),
  nonBinary('NonBinary'),
  selfDescribe('SelfDescribe'),
  preferNotToSay('PreferNotToSay');

  const LifeMateGenderIdentity(this.wireValue);
  final String wireValue;

  static LifeMateGenderIdentity parse(Object? value) => values.firstWhere(
        (item) => item.wireValue == value?.toString(),
        orElse: () => LifeMateGenderIdentity.notCollected,
      );
}

enum LifeMateSexAssignedAtBirth {
  notCollected('NotCollected'),
  female('Female'),
  male('Male'),
  intersex('Intersex'),
  preferNotToSay('PreferNotToSay');

  const LifeMateSexAssignedAtBirth(this.wireValue);
  final String wireValue;

  static LifeMateSexAssignedAtBirth parse(Object? value) => values.firstWhere(
        (item) => item.wireValue == value?.toString(),
        orElse: () => LifeMateSexAssignedAtBirth.notCollected,
      );
}

class LifeMateDemographics {
  const LifeMateDemographics({
    required this.genderIdentity,
    required this.genderSelfDescription,
    required this.sexAssignedAtBirth,
    required this.updatedAtUtc,
  });

  factory LifeMateDemographics.fromJson(Map<String, dynamic> json) {
    return LifeMateDemographics(
      genderIdentity: LifeMateGenderIdentity.parse(json['gender_identity']),
      genderSelfDescription: _nullable(json['gender_self_description']),
      sexAssignedAtBirth:
          LifeMateSexAssignedAtBirth.parse(json['sex_assigned_at_birth']),
      updatedAtUtc: _date(json['demographics_updated_at_utc']),
    );
  }

  final LifeMateGenderIdentity genderIdentity;
  final String? genderSelfDescription;
  final LifeMateSexAssignedAtBirth sexAssignedAtBirth;
  final DateTime? updatedAtUtc;

  bool get hasExplicitAnswer =>
      genderIdentity != LifeMateGenderIdentity.notCollected &&
      sexAssignedAtBirth != LifeMateSexAssignedAtBirth.notCollected;

  static String? _nullable(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static DateTime? _date(Object? value) {
    final text = value?.toString();
    return text == null ? null : DateTime.tryParse(text)?.toUtc();
  }
}

class LifeMateDemographicsApi {
  LifeMateDemographicsApi({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<LifeMateDemographics> getMine() async {
    final value = await _client.rpc('get_my_demographics');
    return _decode(value);
  }

  Future<LifeMateDemographics> saveMine({
    required LifeMateGenderIdentity genderIdentity,
    String? genderSelfDescription,
    required LifeMateSexAssignedAtBirth sexAssignedAtBirth,
  }) async {
    if (genderIdentity == LifeMateGenderIdentity.notCollected ||
        sexAssignedAtBirth == LifeMateSexAssignedAtBirth.notCollected) {
      throw ArgumentError('Demographic answers must be explicit.');
    }
    final description = genderSelfDescription?.trim();
    if (genderIdentity == LifeMateGenderIdentity.selfDescribe &&
        (description == null || description.isEmpty || description.length > 120)) {
      throw ArgumentError.value(
        genderSelfDescription,
        'genderSelfDescription',
        'A self-description between 1 and 120 characters is required.',
      );
    }
    final value = await _client.rpc(
      'set_my_demographics',
      params: <String, dynamic>{
        'p_gender_identity': genderIdentity.wireValue,
        'p_gender_self_description':
            genderIdentity == LifeMateGenderIdentity.selfDescribe
                ? description
                : null,
        'p_sex_assigned_at_birth': sexAssignedAtBirth.wireValue,
      },
    );
    return _decode(value);
  }

  static LifeMateDemographics _decode(dynamic value) {
    final row = switch (value) {
      List<dynamic> values when values.isNotEmpty => values.first,
      Map<dynamic, dynamic> object => object,
      _ => null,
    };
    if (row is! Map) {
      throw const FormatException('Demographic response is missing.');
    }
    return LifeMateDemographics.fromJson(Map<String, dynamic>.from(row));
  }
}
