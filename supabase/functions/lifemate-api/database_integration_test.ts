import { assert, assertEquals, assertRejects } from "jsr:@std/assert@1.0.14";
import postgres from "postgres";
import { createCareEventStore } from "./care_events.ts";
import {
  type AppIdentity,
  type AuthUser,
  createLifeMateDatabase,
} from "./database.ts";
import { ApiError } from "./validation.ts";

const databaseUrl = Deno.env.get("TEST_DATABASE_URL");
if (!databaseUrl) {
  throw new Error(
    "TEST_DATABASE_URL is required for database integration tests.",
  );
}

const contactSecret = "integration-only-contact-secret-with-32-plus-characters";

Deno.test({
  name: "patient caregiver and unrelated-user journey remains isolated",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const admin = postgres(databaseUrl, { max: 1, prepare: false });
    const db = createLifeMateDatabase(databaseUrl, contactSecret);
    const careEvents = createCareEventStore(databaseUrl);
    const suffix = crypto.randomUUID();

    try {
      const patientAuth = auth(
        `patient-${suffix}`,
        `patient-${suffix}@example.test`,
      );
      const caregiverAuth = auth(
        `caregiver-${suffix}`,
        `caregiver-${suffix}@example.test`,
      );
      const unrelatedAuth = auth(
        `unrelated-${suffix}`,
        `unrelated-${suffix}@example.test`,
      );

      const patient = await bootstrap(db, patientAuth, "بیمار آزمایشی");
      const caregiver = await bootstrap(db, caregiverAuth, "مراقب مجاز");
      const unrelated = await bootstrap(db, unrelatedAuth, "کاربر نامرتبط");

      const target = localSchedule(new Date(Date.now() + 3 * 60 * 60 * 1000));
      const patientOccurrence = await createOccurrence(
        db,
        patient.appUserId,
        "داروی بیمار",
        target,
      );
      const unrelatedOccurrence = await createOccurrence(
        db,
        unrelated.appUserId,
        "داروی کاربر نامرتبط",
        target,
      );

      const sharedRequestId = crypto.randomUUID();
      const taken = await db.reportDose(
        patient.appUserId,
        patientOccurrence.id,
        {
          clientRequestId: sharedRequestId,
          version: patientOccurrence.version,
          status: "taken",
          occurredAtUtc: new Date().toISOString(),
        },
      );
      assertEquals(taken.status, "taken");

      const retried = await db.reportDose(
        patient.appUserId,
        patientOccurrence.id,
        {
          clientRequestId: sharedRequestId,
          version: patientOccurrence.version,
          status: "taken",
          occurredAtUtc: new Date().toISOString(),
        },
      );
      assertEquals(retried.id, patientOccurrence.id);
      assertEquals(retried.status, "taken");

      await assertApiError(
        () =>
          db.reportDose(unrelated.appUserId, patientOccurrence.id, {
            clientRequestId: sharedRequestId,
            version: patientOccurrence.version,
            status: "taken",
            occurredAtUtc: new Date().toISOString(),
          }),
        404,
        "dose_occurrence_not_found",
      );

      const unrelatedTaken = await db.reportDose(
        unrelated.appUserId,
        unrelatedOccurrence.id,
        {
          clientRequestId: sharedRequestId,
          version: unrelatedOccurrence.version,
          status: "taken",
          occurredAtUtc: new Date().toISOString(),
        },
      );
      assertEquals(unrelatedTaken.status, "taken");

      const careEventRequestId = crypto.randomUUID();
      const appointmentPayload = {
        clientRequestId: careEventRequestId,
        eventType: "appointment",
        title: "ویزیت متخصص قلب",
        providerName: "دکتر تست",
        specialty: "قلب و عروق",
        medicationName: null,
        doseText: null,
        administrationRoute: null,
        reason: "پیگیری برنامه درمان",
        instructions: "مدارک قبلی همراه بیمار باشد",
        centerName: "مرکز درمانی تست",
        addressLine: "تهران، خیابان نمونه، پلاک ۱",
        phoneNumber: "02100000000",
        scheduledLocalDate: target.date,
        scheduledLocalTime: target.localTime,
        timeZone: "Asia/Tehran",
      };
      const appointment = await careEvents.createCareEvent(
        patient.appUserId,
        appointmentPayload,
      );
      const appointmentRetry = await careEvents.createCareEvent(
        patient.appUserId,
        appointmentPayload,
      );
      assertEquals(appointmentRetry.id, appointment.id);

      const patientEvents = await careEvents.listCareEvents(
        patient.appUserId,
        target.date,
        target.date,
      );
      assert(patientEvents.some((event) => event.id === appointment.id));
      assertEquals(
        patientEvents[0]?.addressLine,
        appointmentPayload.addressLine,
      );

      const injection = await careEvents.createCareEvent(patient.appUserId, {
        clientRequestId: crypto.randomUUID(),
        eventType: "injection",
        title: "B12",
        medicationName: "B12",
        doseText: "1 ampoule",
        administrationRoute: "intramuscular",
        scheduledLocalDate: target.date,
        scheduledLocalTime: target.localTime,
        timeZone: "Asia/Tehran",
        recurrence: { enabled: true, unit: "month", interval: 6, weekdays: [] },
      });
      const eventsAfterInjection = await careEvents.listCareEvents(
        patient.appUserId,
        target.date,
        target.date,
      );
      assert(
        eventsAfterInjection.some((event) => event.seriesId === injection.id),
      );
      assert(
        eventsAfterInjection.some((event) => event.eventType === "injection"),
      );

      await assertApiError(
        () =>
          careEvents.listCareRecipientEvents(
            caregiver.appUserId,
            patient.appUserId,
            target.date,
            target.date,
          ),
        403,
        "care_access_denied",
      );

      const invitation = await db.createInvitation(patient, {
        contact: caregiverAuth.email,
        consentVersion: "care-patient-consent-v1",
        confirmConsent: true,
      });
      assert(typeof invitation.token === "string");

      await assertApiError(
        () =>
          db.acceptInvitation(unrelated, {
            token: invitation.token,
            consentVersion: "care-caregiver-consent-v1",
            confirmConsent: true,
          }),
        403,
        "invitation_contact_mismatch",
      );

      const relationship = await db.acceptInvitation(caregiver, {
        token: invitation.token,
        consentVersion: "care-caregiver-consent-v1",
        confirmConsent: true,
      });
      assertEquals(relationship.status, "active");

      const repeatedAccept = await db.acceptInvitation(caregiver, {
        token: invitation.token,
        consentVersion: "care-caregiver-consent-v1",
        confirmConsent: true,
      });
      assertEquals(repeatedAccept.id, relationship.id);

      const caregiverView = await db.listCareDoseOccurrences(
        caregiver.appUserId,
        patient.appUserId,
        target.date,
        target.date,
      );
      assert(caregiverView.some((dose) => dose.id === patientOccurrence.id));

      const caregiverEventView = await careEvents.listCareRecipientEvents(
        caregiver.appUserId,
        patient.appUserId,
        target.date,
        target.date,
      );
      assert(caregiverEventView.some((event) => event.id === appointment.id));

      await assertApiError(
        () =>
          db.listCareDoseOccurrences(
            unrelated.appUserId,
            patient.appUserId,
            target.date,
            target.date,
          ),
        403,
        "care_access_denied",
      );
      await assertApiError(
        () =>
          careEvents.listCareRecipientEvents(
            unrelated.appUserId,
            patient.appUserId,
            target.date,
            target.date,
          ),
        403,
        "care_access_denied",
      );

      await db.revokeRelationship(patient.appUserId, relationship.id);
      await db.revokeRelationship(patient.appUserId, relationship.id);

      await assertApiError(
        () =>
          db.listCareDoseOccurrences(
            caregiver.appUserId,
            patient.appUserId,
            target.date,
            target.date,
          ),
        403,
        "care_access_denied",
      );
      await assertApiError(
        () =>
          careEvents.listCareRecipientEvents(
            caregiver.appUserId,
            patient.appUserId,
            target.date,
            target.date,
          ),
        403,
        "care_access_denied",
      );

      const eventRows = await admin`
        select actor_user_id, client_request_id
        from lifemate.dose_adherence_events
        where client_request_id = ${sharedRequestId}
        order by actor_user_id
      `;
      assertEquals(eventRows.length, 2);
      assertEquals(
        new Set(eventRows.map((row) => row.actor_user_id)).size,
        2,
      );

      const auditRows = await admin`
        select action, metadata_json
        from lifemate.audit_logs
        where actor_user_id in ${
        admin([
          patient.appUserId,
          caregiver.appUserId,
          unrelated.appUserId,
        ])
      }
      `;
      assert(auditRows.length >= 9);
      const careEventAudit = auditRows.find(
        (row) => row.action === "care_event.created",
      );
      assert(careEventAudit);
      assertEquals(
        careEventAudit.metadata_json,
        JSON.stringify({ eventType: "Appointment" }),
      );
      assert(
        auditRows
          .filter((row) => row.action !== "care_event.created")
          .every((row) => row.metadata_json == null),
      );

      const reconnected = createLifeMateDatabase(databaseUrl, contactSecret);
      const persisted = await reconnected.listMedications(patient.appUserId);
      assert(persisted.some((medication) => medication.name === "داروی بیمار"));
    } finally {
      await admin.end({ timeout: 5 });
    }
  },
});

function auth(subject: string, email: string): AuthUser {
  return {
    id: subject,
    email,
    phone: null,
    userMetadata: {},
  };
}

async function bootstrap(
  db: ReturnType<typeof createLifeMateDatabase>,
  authUser: AuthUser,
  displayName: string,
): Promise<AppIdentity> {
  await db.bootstrapUser(authUser, {
    displayName,
    locale: "fa",
    timeZone: "Asia/Tehran",
  });
  return await db.requireIdentity(authUser);
}

async function createOccurrence(
  db: ReturnType<typeof createLifeMateDatabase>,
  userId: string,
  medicationName: string,
  target: { date: string; dayOfWeek: string; localTime: string },
): Promise<Record<string, any>> {
  const medication = await db.createMedication(userId, {
    name: medicationName,
    strengthText: "10 mg",
    form: "tablet",
    notes: null,
  });
  await db.createTreatmentPlan(userId, {
    medicationId: medication.id,
    doseText: "یک عدد",
    instructions: null,
    startDate: target.date,
    endDate: target.date,
    timeZone: "Asia/Tehran",
    schedules: [{
      dayOfWeek: target.dayOfWeek,
      localTime: target.localTime,
    }],
  });
  const occurrences = await db.listDoseOccurrences(
    userId,
    target.date,
    target.date,
  );
  assertEquals(occurrences.length, 1);
  return occurrences[0] as Record<string, any>;
}

function localSchedule(date: Date): {
  date: string;
  dayOfWeek: string;
  localTime: string;
} {
  const formatter = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Tehran",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    weekday: "long",
    hour: "2-digit",
    minute: "2-digit",
    hourCycle: "h23",
  });
  const parts = Object.fromEntries(
    formatter.formatToParts(date).map((part) => [part.type, part.value]),
  );
  return {
    date: `${parts.year}-${parts.month}-${parts.day}`,
    dayOfWeek: parts.weekday,
    localTime: `${parts.hour}:${parts.minute}`,
  };
}

async function assertApiError(
  action: () => Promise<unknown>,
  status: number,
  code: string,
): Promise<void> {
  const error = await assertRejects(action, ApiError);
  assertEquals(error.status, status);
  assertEquals(error.code, code);
}
