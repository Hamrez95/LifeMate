from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def replace_once(path: str, old: str, new: str) -> None:
    target = ROOT / path
    text = target.read_text(encoding="utf-8")
    if old not in text:
        if new in text:
            return
        raise SystemExit(f"Expected snippet not found in {path}")
    target.write_text(text.replace(old, new, 1), encoding="utf-8")


def write(path: str, content: str) -> None:
    target = ROOT / path
    target.parent.mkdir(parents=True, exist_ok=True)
    normalized = content.rstrip() + "\n"
    if target.exists() and target.read_text(encoding="utf-8") == normalized:
        return
    target.write_text(normalized, encoding="utf-8")


write(
    "packages/lifemate_client/lib/src/profile_avatar.dart",
    r'''import 'package:flutter/material.dart';

import 'lifemate_api_client.dart';

@immutable
class LifeMateProfileAvatarOption {
  const LifeMateProfileAvatarOption({
    required this.key,
    required this.label,
    required this.icon,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  final String key;
  final String label;
  final IconData icon;
  final Color backgroundColor;
  final Color foregroundColor;
}

abstract final class LifeMateProfileAvatars {
  static const String defaultKey = 'person_blue';

  static const List<LifeMateProfileAvatarOption> options = [
    LifeMateProfileAvatarOption(
      key: 'person_blue',
      label: 'آبی',
      icon: Icons.person_rounded,
      backgroundColor: Color(0xFFE4F2FF),
      foregroundColor: Color(0xFF2878B8),
    ),
    LifeMateProfileAvatarOption(
      key: 'person_green',
      label: 'سبز',
      icon: Icons.person_rounded,
      backgroundColor: Color(0xFFE3F7EE),
      foregroundColor: Color(0xFF2D8A67),
    ),
    LifeMateProfileAvatarOption(
      key: 'person_purple',
      label: 'یاسی',
      icon: Icons.person_rounded,
      backgroundColor: Color(0xFFF0E8FF),
      foregroundColor: Color(0xFF7652B5),
    ),
    LifeMateProfileAvatarOption(
      key: 'person_orange',
      label: 'گلبهی',
      icon: Icons.person_rounded,
      backgroundColor: Color(0xFFFFECE4),
      foregroundColor: Color(0xFFB85E3B),
    ),
    LifeMateProfileAvatarOption(
      key: 'heart_coral',
      label: 'قلب',
      icon: Icons.favorite_rounded,
      backgroundColor: Color(0xFFFFE7EA),
      foregroundColor: Color(0xFFC84F65),
    ),
    LifeMateProfileAvatarOption(
      key: 'caregiver_teal',
      label: 'مراقب',
      icon: Icons.volunteer_activism_rounded,
      backgroundColor: Color(0xFFE2F7F6),
      foregroundColor: Color(0xFF277F7C),
    ),
  ];

  static bool isAllowed(String? value) =>
      value != null && options.any((option) => option.key == value);

  static String normalize(String? value) =>
      isAllowed(value) ? value! : defaultKey;

  static LifeMateProfileAvatarOption resolve(String? value) {
    final normalized = normalize(value);
    return options.firstWhere((option) => option.key == normalized);
  }
}

class LifeMateProfileAvatar extends StatelessWidget {
  const LifeMateProfileAvatar({
    super.key,
    this.avatarKey,
    this.radius = 36,
    this.showBorder = true,
  });

  final String? avatarKey;
  final double radius;
  final bool showBorder;

  @override
  Widget build(BuildContext context) {
    final option = LifeMateProfileAvatars.resolve(avatarKey);
    return Semantics(
      image: true,
      label: 'آواتار پروفایل ${option.label}',
      child: Container(
        width: radius * 2,
        height: radius * 2,
        padding: EdgeInsets.all(showBorder ? 3 : 0),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
          border: showBorder
              ? Border.all(
                  color: option.foregroundColor.withValues(alpha: 0.18),
                  width: 1.5,
                )
              : null,
        ),
        child: CircleAvatar(
          backgroundColor: option.backgroundColor,
          child: Icon(
            option.icon,
            size: radius,
            color: option.foregroundColor,
          ),
        ),
      ),
    );
  }
}

class LifeMateAvatarPicker extends StatelessWidget {
  const LifeMateAvatarPicker({
    super.key,
    required this.selectedKey,
    required this.onSelected,
  });

  final String selectedKey;
  final ValueChanged<String>? onSelected;

  @override
  Widget build(BuildContext context) {
    final normalized = LifeMateProfileAvatars.normalize(selectedKey);
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 12,
      runSpacing: 12,
      children: LifeMateProfileAvatars.options.map((option) {
        final selected = option.key == normalized;
        return Semantics(
          button: true,
          selected: selected,
          label: 'انتخاب آواتار ${option.label}',
          child: InkWell(
            key: ValueKey('profile-avatar-${option.key}'),
            onTap: onSelected == null ? null : () => onSelected!(option.key),
            customBorder: const CircleBorder(),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected
                      ? option.foregroundColor
                      : Colors.transparent,
                  width: 3,
                ),
              ),
              child: LifeMateProfileAvatar(
                avatarKey: option.key,
                radius: 30,
                showBorder: false,
              ),
            ),
          ),
        );
      }).toList(growable: false),
    );
  }
}

class LifeMateCurrentUserAvatar extends StatefulWidget {
  const LifeMateCurrentUserAvatar({
    super.key,
    required this.apiClient,
    this.radius = 22,
  });

  final LifeMateApiClient apiClient;
  final double radius;

  @override
  State<LifeMateCurrentUserAvatar> createState() =>
      _LifeMateCurrentUserAvatarState();
}

class _LifeMateCurrentUserAvatarState extends State<LifeMateCurrentUserAvatar> {
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.apiClient.getCurrentUser();
  }

  @override
  void didUpdateWidget(covariant LifeMateCurrentUserAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.apiClient, widget.apiClient)) {
      _future = widget.apiClient.getCurrentUser();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snapshot) {
        final data = snapshot.data ?? const <String, dynamic>{};
        final profile = data['profile'] as Map<String, dynamic>? ?? const {};
        return LifeMateProfileAvatar(
          avatarKey: profile['avatarKey']?.toString(),
          radius: widget.radius,
        );
      },
    );
  }
}
''',
)

replace_once(
    "packages/lifemate_client/lib/lifemate_client.dart",
    "export 'src/lifemate_bootstrap.dart';\n",
    "export 'src/lifemate_bootstrap.dart';\nexport 'src/profile_avatar.dart';\n",
)

replace_once(
    "packages/lifemate_client/lib/src/lifemate_api_client.dart",
    '''  Future<Map<String, dynamic>> updateCurrentProfile({
    required int version,
    required String displayName,
    String? phoneNumber,
    required String locale,
    required String timeZone,
  }) async => _asObject(
    await _send(
      'PATCH',
      '/api/v1/me/profile',
      body: {
        'version': version,
        'displayName': displayName.trim(),
        'phoneNumber': _emptyToNull(phoneNumber),
        'locale': locale.trim(),
        'timeZone': timeZone.trim(),
      },
    ),
  );
''',
    '''  Future<Map<String, dynamic>> updateCurrentProfile({
    required int version,
    required String displayName,
    String? phoneNumber,
    required String locale,
    required String timeZone,
    required String avatarKey,
  }) async => _asObject(
    await _send(
      'PATCH',
      '/api/v1/me/profile',
      body: {
        'version': version,
        'displayName': displayName.trim(),
        'phoneNumber': _emptyToNull(phoneNumber),
        'locale': locale.trim(),
        'timeZone': timeZone.trim(),
        'avatarKey': avatarKey.trim(),
      },
    ),
  );
''',
)

write(
    "packages/lifemate_client/test/profile_avatar_test.dart",
    r'''import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  test('profile avatar catalog is deterministic and rejects unknown keys', () {
    expect(
      LifeMateProfileAvatars.options.map((option) => option.key).toSet().length,
      LifeMateProfileAvatars.options.length,
    );
    expect(
      LifeMateProfileAvatars.normalize('unknown-avatar'),
      LifeMateProfileAvatars.defaultKey,
    );
    expect(LifeMateProfileAvatars.isAllowed('person_green'), isTrue);
  });

  testWidgets('avatar picker reports the selected persisted key', (tester) async {
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LifeMateAvatarPicker(
            selectedKey: LifeMateProfileAvatars.defaultKey,
            onSelected: (value) => selected = value,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('profile-avatar-person_purple')));
    await tester.pumpAndSettle();

    expect(selected, 'person_purple');
  });
}
''',
)

write(
    "packages/lifemate_client/test/profile_api_client_test.dart",
    r'''import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  test('profile update sends the selected avatar key to the owner endpoint', () async {
    late http.Request observed;
    final api = LifeMateApiClient(
      baseUri: Uri.parse('https://api.example.test'),
      accessToken: () => 'access-token',
      httpClient: MockClient((request) async {
        observed = request;
        return http.Response(
          jsonEncode({
            'id': 'profile-1',
            'userId': 'user-1',
            'displayName': 'Owner',
            'phoneNumber': null,
            'email': 'owner@example.test',
            'locale': 'fa',
            'timeZone': 'Asia/Tehran',
            'avatarKey': 'person_purple',
            'version': 2,
            'createdAtUtc': '2026-08-04T00:00:00Z',
            'updatedAtUtc': '2026-08-04T00:01:00Z',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final result = await api.updateCurrentProfile(
      version: 1,
      displayName: ' Owner ',
      phoneNumber: '',
      locale: 'fa',
      timeZone: 'Asia/Tehran',
      avatarKey: 'person_purple',
    );

    expect(observed.method, 'PATCH');
    expect(observed.url.path, '/api/v1/me/profile');
    expect(observed.headers['authorization'], 'Bearer access-token');
    expect(jsonDecode(observed.body), {
      'version': 1,
      'displayName': 'Owner',
      'phoneNumber': null,
      'locale': 'fa',
      'timeZone': 'Asia/Tehran',
      'avatarKey': 'person_purple',
    });
    expect(result['avatarKey'], 'person_purple');
  });
}
''',
)

write(
    "supabase/migrations/20260804213000_add_profile_avatar_key.sql",
    r'''alter table lifemate.user_profiles
    add column if not exists avatar_key character varying(32)
    not null default 'person_blue';

do $migration$
begin
    if not exists (
        select 1
        from pg_constraint
        where conname = 'ck_user_profiles_avatar_key'
          and conrelid = 'lifemate.user_profiles'::regclass
    ) then
        alter table lifemate.user_profiles
            add constraint ck_user_profiles_avatar_key check (
                avatar_key in (
                    'person_blue',
                    'person_green',
                    'person_purple',
                    'person_orange',
                    'heart_coral',
                    'caregiver_teal'
                )
            );
    end if;
end
$migration$;

comment on column lifemate.user_profiles.avatar_key is
'Non-sensitive allow-listed avatar identifier selected by the profile owner.';
''',
)

write(
    "supabase/functions/lifemate-api/profile.ts",
    r'''import postgres from "postgres";
import {
  ApiError,
  normalizeOptional,
  requiredPositiveInt,
  requiredText,
  requiredTimeZone,
} from "./validation.ts";

type ProfileAuthSnapshot = {
  email: string | null;
};

type Row = Record<string, any>;

const allowedAvatarKeys = new Set([
  "person_blue",
  "person_green",
  "person_purple",
  "person_orange",
  "heart_coral",
  "caregiver_teal",
]);

export type ProfilePatch = {
  expectedVersion: number;
  displayName: string;
  phoneNumber: string | null;
  locale: string;
  timeZone: string;
  avatarKey: string;
};

export function normalizeProfilePatch(
  body: Record<string, unknown>,
): ProfilePatch {
  return {
    expectedVersion: requiredPositiveInt(body.version, "version"),
    displayName: requiredText(body.displayName, "displayName", 120),
    phoneNumber: optionalPhone(body.phoneNumber),
    locale: requiredLocale(body.locale),
    timeZone: requiredTimeZone(body.timeZone),
    avatarKey: requiredAvatarKey(body.avatarKey),
  };
}

/// Profile persistence deliberately supports both the current live schema and
/// the reviewed additive `version` migration. This lets the candidate function
/// be smoke-tested without applying DDL to the production database. Once the
/// migration is promoted, the exact same API automatically switches to the
/// integer version column. Before that, the millisecond `updated_at_utc` value
/// acts as a deterministic optimistic-concurrency token.
export function createProfileStore(databaseUrl: string) {
  const sql = postgres(databaseUrl, {
    max: 2,
    idle_timeout: 20,
    connect_timeout: 10,
    prepare: false,
  });
  let versionColumnPromise: Promise<boolean> | null = null;

  function hasVersionColumn(): Promise<boolean> {
    versionColumnPromise ??= sql`
      select exists (
        select 1
        from information_schema.columns
        where table_schema = 'lifemate'
          and table_name = 'user_profiles'
          and column_name = 'version'
      ) as present
    `.then((rows: Row[]) => rows[0]?.present === true);
    return versionColumnPromise;
  }

  async function getProfile(userId: string): Promise<Record<string, unknown>> {
    const rows = await (await hasVersionColumn()
      ? sql`
          select id, user_id, display_name, phone_number, email, locale,
                 time_zone, avatar_key, version, created_at_utc, updated_at_utc
          from lifemate.user_profiles
          where user_id = ${userId}
          limit 1
        `
      : sql`
          select id, user_id, display_name, phone_number, email, locale,
                 time_zone, avatar_key,
                 floor(extract(epoch from updated_at_utc) * 1000)::bigint
                   as version,
                 created_at_utc, updated_at_utc
          from lifemate.user_profiles
          where user_id = ${userId}
          limit 1
        `);
    if (!rows[0]) {
      throw new ApiError(404, "profile_missing", "User profile was not found.");
    }
    return mapProfile(rows[0]);
  }

  async function updateProfile(
    userId: string,
    auth: ProfileAuthSnapshot,
    body: Record<string, unknown>,
  ): Promise<Record<string, unknown>> {
    const patch = normalizeProfilePatch(body);
    const usesVersionColumn = await hasVersionColumn();

    return await sql.begin(async (tx: any) => {
      const rows = await (usesVersionColumn
        ? tx`
            update lifemate.user_profiles
            set display_name = ${patch.displayName},
                phone_number = ${patch.phoneNumber},
                email = ${auth.email},
                locale = ${patch.locale},
                time_zone = ${patch.timeZone},
                avatar_key = ${patch.avatarKey},
                version = version + 1,
                updated_at_utc = now()
            where user_id = ${userId} and version = ${patch.expectedVersion}
            returning id, user_id, display_name, phone_number, email, locale,
                      time_zone, avatar_key, version, created_at_utc,
                      updated_at_utc
          `
        : tx`
            update lifemate.user_profiles
            set display_name = ${patch.displayName},
                phone_number = ${patch.phoneNumber},
                email = ${auth.email},
                locale = ${patch.locale},
                time_zone = ${patch.timeZone},
                avatar_key = ${patch.avatarKey},
                updated_at_utc = greatest(
                  now(),
                  updated_at_utc + interval '1 millisecond'
                )
            where user_id = ${userId}
              and floor(extract(epoch from updated_at_utc) * 1000)::bigint =
                  ${patch.expectedVersion}
            returning id, user_id, display_name, phone_number, email, locale,
                      time_zone, avatar_key,
                      floor(extract(epoch from updated_at_utc) * 1000)::bigint
                        as version,
                      created_at_utc, updated_at_utc
          `);
      if (!rows[0]) {
        const current = await (usesVersionColumn
          ? tx`
              select version
              from lifemate.user_profiles
              where user_id = ${userId}
              limit 1
            `
          : tx`
              select floor(extract(epoch from updated_at_utc) * 1000)::bigint
                       as version
              from lifemate.user_profiles
              where user_id = ${userId}
              limit 1
            `);
        if (!current[0]) {
          throw new ApiError(
            404,
            "profile_missing",
            "User profile was not found.",
          );
        }
        throw new ApiError(
          409,
          "stale_profile",
          "Profile has changed. Refresh and try again.",
        );
      }

      await tx`
        insert into lifemate.audit_logs
          (id, actor_user_id, action, resource_type, resource_id,
           metadata_json, created_at_utc)
        values
          (${crypto.randomUUID()}, ${userId}, 'profile.updated',
           'user_profile', ${rows[0].id}, null, now())
      `;
      return mapProfile(rows[0]);
    });
  }

  return { getProfile, updateProfile };
}

function requiredAvatarKey(value: unknown): string {
  const normalized = normalizeOptional(value);
  if (normalized == null || !allowedAvatarKeys.has(normalized)) {
    throw new ApiError(
      400,
      "invalid_avatar_key",
      "avatarKey is not supported.",
    );
  }
  return normalized;
}

function requiredLocale(value: unknown): string {
  const locale = normalizeOptional(value);
  if (
    locale == null ||
    locale.length > 16 ||
    !/^[a-z]{2,3}(?:-[A-Z]{2})?$/.test(locale)
  ) {
    throw new ApiError(400, "invalid_locale", "locale is invalid.");
  }
  return locale;
}

function optionalPhone(value: unknown): string | null {
  const normalized = normalizeOptional(value);
  if (normalized == null) return null;
  const compact = normalized.replace(/[\s()-]/g, "");
  if (!/^\+?[0-9]{7,15}$/.test(compact)) {
    throw new ApiError(
      400,
      "invalid_phone_number",
      "phoneNumber is invalid.",
    );
  }
  return compact;
}

function mapProfile(row: Row): Record<string, unknown> {
  return {
    id: row.id,
    userId: row.user_id,
    displayName: row.display_name,
    phoneNumber: row.phone_number,
    email: row.email,
    locale: row.locale,
    timeZone: row.time_zone,
    avatarKey: row.avatar_key ?? "person_blue",
    version: Number(row.version),
    createdAtUtc: iso(row.created_at_utc),
    updatedAtUtc: iso(row.updated_at_utc),
  };
}

function iso(value: unknown): string {
  return value instanceof Date
    ? value.toISOString()
    : new Date(String(value)).toISOString();
}
''',
)

replace_once(
    "supabase/functions/lifemate-api/database.ts",
    '''        returning id, user_id, display_name, phone_number, email, locale,
                  time_zone, created_at_utc, updated_at_utc
''',
    '''        returning id, user_id, display_name, phone_number, email, locale,
                  time_zone, avatar_key, created_at_utc, updated_at_utc
''',
)
replace_once(
    "supabase/functions/lifemate-api/database.ts",
    '''        p.id as profile_id, p.display_name, p.phone_number, p.email,
        p.locale, p.time_zone, p.created_at_utc as profile_created_at_utc,
''',
    '''        p.id as profile_id, p.display_name, p.phone_number, p.email,
        p.locale, p.time_zone, p.avatar_key,
        p.created_at_utc as profile_created_at_utc,
''',
)
replace_once(
    "supabase/functions/lifemate-api/database.ts",
    '''      time_zone: row.time_zone,
      created_at_utc: row.profile_created_at_utc,
''',
    '''      time_zone: row.time_zone,
      avatar_key: row.avatar_key,
      created_at_utc: row.profile_created_at_utc,
''',
)
replace_once(
    "supabase/functions/lifemate-api/database.ts",
    '''      locale: profile.locale,
      timeZone: profile.time_zone,
    },
''',
    '''      locale: profile.locale,
      timeZone: profile.time_zone,
      avatarKey: profile.avatar_key ?? "person_blue",
    },
''',
)

write(
    "supabase/functions/lifemate-api/profile_test.ts",
    r'''import { assertEquals, assertThrows } from "jsr:@std/assert@1.0.14";
import { ApiError } from "./validation.ts";
import { normalizeProfilePatch } from "./profile.ts";

Deno.test("profile patch normalizes phone and persists an allow-listed avatar", () => {
  assertEquals(
    normalizeProfilePatch({
      version: 3,
      displayName: " ریحانه شکیبا ",
      phoneNumber: "+98 (912) 123-4567",
      locale: "fa",
      timeZone: "Asia/Tehran",
      avatarKey: "person_purple",
    }),
    {
      expectedVersion: 3,
      displayName: "ریحانه شکیبا",
      phoneNumber: "+989121234567",
      locale: "fa",
      timeZone: "Asia/Tehran",
      avatarKey: "person_purple",
    },
  );
});

Deno.test("profile patch permits clearing the optional phone number", () => {
  assertEquals(
    normalizeProfilePatch({
      version: 1,
      displayName: "Owner",
      phoneNumber: "",
      locale: "en-US",
      timeZone: "Europe/Berlin",
      avatarKey: "caregiver_teal",
    }).phoneNumber,
    null,
  );
});

Deno.test("profile patch rejects stale-shape and invalid identity fields", () => {
  for (
    const body of [
      {
        version: 0,
        displayName: "Owner",
        locale: "fa",
        timeZone: "Asia/Tehran",
        avatarKey: "person_blue",
      },
      {
        version: 1,
        displayName: "",
        locale: "fa",
        timeZone: "Asia/Tehran",
        avatarKey: "person_blue",
      },
      {
        version: 1,
        displayName: "Owner",
        phoneNumber: "not-a-phone",
        locale: "fa",
        timeZone: "Asia/Tehran",
        avatarKey: "person_blue",
      },
      {
        version: 1,
        displayName: "Owner",
        locale: "persian",
        timeZone: "Asia/Tehran",
        avatarKey: "person_blue",
      },
      {
        version: 1,
        displayName: "Owner",
        locale: "fa",
        timeZone: "Invalid/Zone",
        avatarKey: "person_blue",
      },
      {
        version: 1,
        displayName: "Owner",
        locale: "fa",
        timeZone: "Asia/Tehran",
        avatarKey: "../../private-photo",
      },
    ]
  ) {
    assertThrows(() => normalizeProfilePatch(body), ApiError);
  }
});
''',
)

write(
    "supabase/functions/lifemate-api/profile_integration_test.ts",
    r'''import { assertEquals, assertRejects } from "jsr:@std/assert@1.0.14";
import postgres from "postgres";
import { type AuthUser, createLifeMateDatabase } from "./database.ts";
import { createProfileStore } from "./profile.ts";
import { ApiError } from "./validation.ts";

const databaseUrl = Deno.env.get("TEST_DATABASE_URL");
if (!databaseUrl) {
  throw new Error(
    "TEST_DATABASE_URL is required for profile integration tests.",
  );
}

Deno.test({
  name: "profile avatar persists with optimistic concurrency and redacted audit",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const admin = postgres(databaseUrl, { max: 1, prepare: false });
    const db = createLifeMateDatabase(
      databaseUrl,
      "integration-only-profile-contact-secret-32-bytes-minimum",
    );
    const profiles = createProfileStore(databaseUrl);
    const suffix = crypto.randomUUID();
    const auth: AuthUser = {
      id: `profile-${suffix}`,
      email: `profile-${suffix}@example.test`,
      phone: null,
      userMetadata: {},
    };

    try {
      await db.bootstrapUser(auth, {
        displayName: "نام اولیه",
        locale: "fa",
        timeZone: "Asia/Tehran",
      });
      const identity = await db.requireIdentity(auth);

      const initial = await profiles.getProfile(identity.appUserId);
      assertEquals(initial.version, 1);
      assertEquals(initial.displayName, "نام اولیه");
      assertEquals(initial.avatarKey, "person_blue");

      const updated = await profiles.updateProfile(identity.appUserId, auth, {
        version: 1,
        displayName: "نام ویرایش‌شده",
        phoneNumber: "+98 (912) 123-4567",
        locale: "fa",
        timeZone: "Europe/Berlin",
        avatarKey: "person_purple",
      });
      assertEquals(updated.version, 2);
      assertEquals(updated.displayName, "نام ویرایش‌شده");
      assertEquals(updated.phoneNumber, "+989121234567");
      assertEquals(updated.email, auth.email);
      assertEquals(updated.timeZone, "Europe/Berlin");
      assertEquals(updated.avatarKey, "person_purple");

      const stale = await assertRejects(
        () =>
          profiles.updateProfile(identity.appUserId, auth, {
            version: 1,
            displayName: "ویرایش قدیمی",
            phoneNumber: null,
            locale: "fa",
            timeZone: "Asia/Tehran",
            avatarKey: "person_green",
          }),
        ApiError,
      );
      assertEquals(stale.status, 409);
      assertEquals(stale.code, "stale_profile");

      const reconnected = createProfileStore(databaseUrl);
      const persisted = await reconnected.getProfile(identity.appUserId);
      assertEquals(persisted.version, 2);
      assertEquals(persisted.displayName, "نام ویرایش‌شده");
      assertEquals(persisted.avatarKey, "person_purple");

      const current = await db.currentUser(identity);
      const currentProfile = current.profile as Record<string, unknown>;
      assertEquals(currentProfile.avatarKey, "person_purple");

      const audits = await admin`
        select action, resource_type, metadata_json
        from lifemate.audit_logs
        where actor_user_id = ${identity.appUserId}
          and action = 'profile.updated'
      `;
      assertEquals(audits.length, 1);
      assertEquals(audits[0].resource_type, "user_profile");
      assertEquals(audits[0].metadata_json, null);
    } finally {
      const users = await admin`
        select id from lifemate.app_users where auth_subject = ${auth.id}
      `;
      if (users[0]) {
        await admin`
          delete from lifemate.audit_logs
          where actor_user_id = ${users[0].id}
             or resource_id = ${users[0].id}
        `;
        await admin`
          delete from lifemate.user_profiles where user_id = ${users[0].id}
        `;
        await admin`
          delete from lifemate.app_users where id = ${users[0].id}
        `;
      }
      await admin.end({ timeout: 5 });
    }
  },
});
''',
)

for path in [
    "wellmate/lib/screens/profile/editable_profile_screen.dart",
    "caremate/lib/screens/editable_profile_screen.dart",
]:
    replace_once(
        path,
        "  String _locale = 'fa';\n",
        "  String _locale = 'fa';\n  String _avatarKey = LifeMateProfileAvatars.defaultKey;\n",
    )
    replace_once(
        path,
        "    _timeZone.text = profile['timeZone']?.toString() ?? 'Asia/Tehran';\n",
        "    _timeZone.text = profile['timeZone']?.toString() ?? 'Asia/Tehran';\n"
        "    _avatarKey = LifeMateProfileAvatars.normalize(\n"
        "      profile['avatarKey']?.toString(),\n"
        "    );\n",
    )
    replace_once(
        path,
        "            timeZone: _timeZone.text,\n",
        "            timeZone: _timeZone.text,\n            avatarKey: _avatarKey,\n",
    )

replace_once(
    "wellmate/lib/screens/profile/editable_profile_screen.dart",
    '''                    const Center(
                      child: CircleAvatar(
                        radius: 44,
                        backgroundColor: Color(0xFFE8F4FF),
                        child: Icon(
                          Icons.person_rounded,
                          size: 50,
                          color: AppColors.primaryBlue,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'تصویر محلی موقت',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
''',
    '''                    const Text(
                      'آواتار پروفایل',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 12),
                    LifeMateAvatarPicker(
                      key: const ValueKey('profile-avatar-picker'),
                      selectedKey: _avatarKey,
                      onSelected: _saving
                          ? null
                          : (value) => setState(() => _avatarKey = value),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'آواتار انتخابی در حساب ذخیره می‌شود و در هر دو اپ نمایش داده خواهد شد.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
''',
)

replace_once(
    "caremate/lib/screens/editable_profile_screen.dart",
    '''                    const Center(
                      child: CircleAvatar(
                        radius: 44,
                        backgroundColor: AppColors.avatarBackground,
                        child: Icon(
                          Icons.person_rounded,
                          size: 50,
                          color: AppColors.primaryBlue,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'تصویر محلی موقت',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.secondaryText),
                    ),
''',
    '''                    const Text(
                      'آواتار پروفایل',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 12),
                    LifeMateAvatarPicker(
                      key: const ValueKey('care-profile-avatar-picker'),
                      selectedKey: _avatarKey,
                      onSelected: _saving
                          ? null
                          : (value) => setState(() => _avatarKey = value),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'آواتار انتخابی در حساب ذخیره می‌شود و در هر دو اپ نمایش داده خواهد شد.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.secondaryText),
                    ),
''',
)

replace_once(
    "wellmate/lib/screens/profile/profile_screen.dart",
    "  late final Future<Map<String, dynamic>> _currentUser;\n",
    "  late Future<Map<String, dynamic>> _currentUser;\n",
)
replace_once(
    "wellmate/lib/screens/profile/profile_screen.dart",
    '''  @override
  Widget build(BuildContext context) {
''',
    '''  Future<void> _openEditor() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const EditableProfileScreen()),
    );
    if (!mounted) return;
    setState(() {
      _currentUser = context.read<LifeMateApiClient>().getCurrentUser();
    });
  }

  @override
  Widget build(BuildContext context) {
''',
)
replace_once(
    "wellmate/lib/screens/profile/profile_screen.dart",
    '''                  const CircleAvatar(
                    radius: 36,
                    backgroundColor: Colors.transparent,
                    backgroundImage: AssetImage(
                      'assets/images/mother_avatar.png',
                    ),
                  ),
''',
    '''                  InkWell(
                    onTap: _openEditor,
                    customBorder: const CircleBorder(),
                    child: LifeMateProfileAvatar(
                      avatarKey: profile['avatarKey']?.toString(),
                      radius: 36,
                    ),
                  ),
''',
)

replace_once(
    "caremate/lib/screens/profile_screen.dart",
    "  late final Future<Map<String, dynamic>> _future;\n",
    "  late Future<Map<String, dynamic>> _future;\n",
)
replace_once(
    "caremate/lib/screens/profile_screen.dart",
    '''  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
''',
    '''  Future<void> _openEditor() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const CareMateEditableProfileScreen(),
      ),
    );
    if (!mounted) return;
    setState(() {
      _future = context.read<LifeMateApiClient>().getCurrentUser();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
''',
)
replace_once(
    "caremate/lib/screens/profile_screen.dart",
    '''            const CircleAvatar(
              radius: 40,
              backgroundColor: AppColors.avatarBackground,
              backgroundImage: AssetImage('assets/images/Caregiver.png'),
            ),
''',
    '''            InkWell(
              onTap: _openEditor,
              customBorder: const CircleBorder(),
              child: LifeMateProfileAvatar(
                avatarKey: profile['avatarKey']?.toString(),
                radius: 40,
              ),
            ),
''',
)

replace_once(
    "wellmate/lib/core/widgets/wellmate_app_header.dart",
    "import 'package:flutter/material.dart';\n",
    "import 'package:flutter/material.dart';\nimport 'package:lifemate_client/lifemate_client.dart';\n",
)
replace_once(
    "wellmate/lib/core/widgets/wellmate_app_header.dart",
    '''              child: const CircleAvatar(
                radius: 20,
                backgroundColor: Colors.transparent,
                backgroundImage:
                    AssetImage('assets/images/mother_avatar.png'),
              ),
''',
    '''              child: LifeMateCurrentUserAvatar(
                apiClient: context.read<LifeMateApiClient>(),
                radius: 20,
              ),
''',
)

replace_once(
    "caremate/lib/widgets/custom_app_header.dart",
    "import 'package:flutter/material.dart';\n",
    "import 'package:flutter/material.dart';\n"
    "import 'package:lifemate_client/lifemate_client.dart';\n"
    "import 'package:provider/provider.dart';\n",
)
replace_once(
    "caremate/lib/widgets/custom_app_header.dart",
    "              child: const ProfileAvatar(),\n",
    "              child: LifeMateCurrentUserAvatar(\n"
    "                apiClient: context.read<LifeMateApiClient>(),\n"
    "                radius: 22,\n"
    "              ),\n",
)

replace_once(
    "caremate/lib/widgets/custom_ui_components.dart",
    "import 'package:flutter/material.dart';\n",
    "import 'package:flutter/material.dart';\nimport 'package:lifemate_client/lifemate_client.dart';\n",
)
replace_once(
    "caremate/lib/widgets/custom_ui_components.dart",
    '''class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.glassBackground,
        boxShadow: [
          const BoxShadow(
              color: Colors.white, offset: Offset(-4, -4), blurRadius: 8),
          BoxShadow(
              color: Colors.black.withOpacity(0.1),
              offset: const Offset(4, 4),
              blurRadius: 8),
        ],
      ),
      padding: const EdgeInsets.all(4),
      child: const CircleAvatar(
        backgroundColor: Color(0xFFE2D4C8),
        backgroundImage: AssetImage('assets/images/Caregiver.png'),
      ),
    );
  }
}
''',
    '''class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({super.key, this.avatarKey});

  final String? avatarKey;

  @override
  Widget build(BuildContext context) {
    return LifeMateProfileAvatar(avatarKey: avatarKey, radius: 24);
  }
}
''',
)

replace_once(
    "wellmate/pubspec.yaml",
    "version: 0.9.0-internal.4+15\n",
    "version: 0.9.0-internal.5+16\n",
)
replace_once(
    "caremate/pubspec.yaml",
    "version: 0.9.0-internal.4+15\n",
    "version: 0.9.0-internal.5+16\n",
)
replace_once(
    "wellmate/lib/core/constants/app_version.dart",
    "const String wellMateAppVersion = '0.9.0-internal.4+15';\n",
    "const String wellMateAppVersion = '0.9.0-internal.5+16';\n",
)
replace_once(
    "caremate/lib/core/constants/app_version.dart",
    "const String careMateAppVersion = '0.9.0-internal.4+15';\n",
    "const String careMateAppVersion = '0.9.0-internal.5+16';\n",
)
