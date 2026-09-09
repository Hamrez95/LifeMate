import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { filterLinkedPregnancyCareEvents } from "./pregnancy_calendar_routes.ts";

Deno.test("pregnancy calendar keeps only linked canonical series", () => {
  const linked = new Set(["11111111-1111-4111-8111-111111111111"]);
  const events = [
    {
      id: "11111111-1111-4111-8111-111111111111:2026-09-10@09:00",
      seriesId: "11111111-1111-4111-8111-111111111111",
      scheduledLocalDate: "2026-09-10",
      timeZone: "Asia/Tehran",
    },
    {
      id: "22222222-2222-4222-8222-222222222222",
      seriesId: "22222222-2222-4222-8222-222222222222",
      scheduledLocalDate: "2026-09-11",
      timeZone: "Asia/Tehran",
    },
  ];

  const visible = filterLinkedPregnancyCareEvents(events, linked);

  assertEquals(visible.length, 1);
  assertEquals(
    visible[0].seriesId,
    "11111111-1111-4111-8111-111111111111",
  );
  assertEquals(visible[0].scheduledLocalDate, "2026-09-10");
  assertEquals(visible[0].timeZone, "Asia/Tehran");
});

Deno.test("pregnancy calendar does not invent unlinked milestone events", () => {
  const visible = filterLinkedPregnancyCareEvents(
    [
      {
        id: "33333333-3333-4333-8333-333333333333",
        seriesId: "33333333-3333-4333-8333-333333333333",
        title: "Unrelated appointment",
      },
    ],
    new Set(),
  );

  assertEquals(visible, []);
});
