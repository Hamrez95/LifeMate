import { assertEquals } from "jsr:@std/assert@1.0.14";
import { unzipSync } from "npm:fflate@0.8.2";
import { formatResearchPreview } from "./research_export_format.ts";

const preview = {
  eligible: true,
  cells: [
    {
      observationType: "weight",
      unit: "kg",
      ageBucket: "20–22",
      homeRegion: "IR-07",
      subjectCount: 25,
      observationCount: 40,
      averageValue: 68.4,
    },
  ],
};

Deno.test("research CSV export is deterministic and formula-safe", () => {
  const result = formatResearchPreview({
    eligible: true,
    cells: [{ label: "=CMD()", count: 20 }],
  }, "CSV");
  const text = new TextDecoder().decode(result.bytes);
  assertEquals(result.extension, "csv");
  assertEquals(text.includes("'=CMD()"), true);
  assertEquals(text.endsWith("\r\n"), true);
});

Deno.test("research XLSX export contains a worksheet and no raw JSON", () => {
  const result = formatResearchPreview(preview, "XLSX");
  const files = unzipSync(result.bytes);
  assertEquals(result.extension, "xlsx");
  assertEquals(Boolean(files["xl/worksheets/sheet1.xml"]), true);
  const sheet = new TextDecoder().decode(files["xl/worksheets/sheet1.xml"]);
  assertEquals(sheet.includes("20–22"), true);
  assertEquals(sheet.includes("person_id"), false);
});
