-- Keep the legacy daily-log symptoms column compatible while the canonical
-- structured symptom observations are rolled out. Historical PascalCase values
-- remain valid; new writes may persist canonical lower_snake_case identifiers.

alter table lifemate.women_calendar_daily_logs
  drop constraint if exists ck_women_calendar_daily_log_symptoms;

alter table lifemate.women_calendar_daily_logs
  add constraint ck_women_calendar_daily_log_symptoms check (
    cardinality(symptoms) <= 8
    and symptoms <@ array[
      -- Historical stored values.
      'Cramps', 'Headache', 'Bloating', 'Fatigue', 'BreastTenderness',
      'BackPain', 'SleepChange', 'AppetiteChange', 'NoSymptom',
      -- Canonical symptom-catalog identifiers.
      'cramps', 'headache', 'migraine', 'lower_back_pain', 'bloating',
      'fatigue', 'nausea', 'breast_tenderness', 'mood_changes',
      'sleep_changes', 'appetite_changes', 'no_symptom', 'other'
    ]::character varying[]
  );

comment on column lifemate.women_calendar_daily_logs.symptoms is
  'Compatibility projection for historical and canonical symptom identifiers. Canonical structured symptom_observations remains the forward schema.';
