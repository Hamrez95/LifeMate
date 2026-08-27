import { zipSync } from "npm:fflate@0.8.2";

export type ResearchExportFormat = "CSV" | "XLSX";

export type FormattedResearchExport = {
  bytes: Uint8Array;
  contentType: string;
  extension: "csv" | "xlsx";
};

export function formatResearchPreview(
  preview: Record<string, unknown>,
  format: ResearchExportFormat,
): FormattedResearchExport {
  if (preview.eligible !== true || !Array.isArray(preview.cells)) {
    throw new Error("research_preview_not_exportable");
  }
  if (preview.cells.length > 20_000) {
    throw new Error("research_preview_cell_limit_exceeded");
  }
  const rows = preview.cells.map((cell) => primitiveRow(cell));
  const columns = Array.from(
    new Set(rows.flatMap((row) => Object.keys(row))),
  ).sort();
  if (columns.length === 0) {
    throw new Error("research_preview_has_no_cells");
  }
  if (columns.length > 100) {
    throw new Error("research_preview_column_limit_exceeded");
  }

  if (format === "CSV") {
    const text = [
      columns.map(csvCell).join(","),
      ...rows.map((row) =>
        columns.map((column) => csvCell(row[column] ?? null)).join(",")
      ),
    ].join("\r\n") + "\r\n";
    return {
      bytes: new TextEncoder().encode(text),
      contentType: "text/csv; charset=utf-8",
      extension: "csv",
    };
  }
  if (format !== "XLSX") throw new Error("research_export_format_invalid");
  return {
    bytes: createXlsx(columns, rows),
    contentType:
      "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    extension: "xlsx",
  };
}

type Primitive = string | number | boolean | null;
type PrimitiveRow = Record<string, Primitive>;

function primitiveRow(value: unknown): PrimitiveRow {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("research_preview_cell_invalid");
  }
  const result: PrimitiveRow = {};
  for (const [key, item] of Object.entries(value as Record<string, unknown>)) {
    if (!/^[A-Za-z][A-Za-z0-9_]{0,79}$/.test(key)) {
      throw new Error("research_preview_column_invalid");
    }
    if (
      item !== null && typeof item !== "string" &&
      typeof item !== "number" && typeof item !== "boolean"
    ) {
      throw new Error("research_preview_value_invalid");
    }
    if (typeof item === "number" && !Number.isFinite(item)) {
      throw new Error("research_preview_value_invalid");
    }
    if (typeof item === "string" && item.length > 500) {
      throw new Error("research_preview_value_invalid");
    }
    result[key] = item as Primitive;
  }
  return result;
}

function csvCell(value: Primitive | string): string {
  if (value === null) return "";
  const text = typeof value === "boolean" ? (value ? "true" : "false") : String(value);
  const safe = /^[=+\-@]/.test(text) ? `'${text}` : text;
  return /[",\r\n]/.test(safe) ? `"${safe.replaceAll('"', '""')}"` : safe;
}

function createXlsx(columns: string[], rows: PrimitiveRow[]): Uint8Array {
  const encoder = new TextEncoder();
  const sheetRows = [
    columns.map((column) => xlsxCell(column)),
    ...rows.map((row) => columns.map((column) => xlsxCell(row[column] ?? null))),
  ];
  const sheetXml = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>${
    sheetRows.map((cells, rowIndex) =>
      `<row r="${rowIndex + 1}">${
        cells.map((cell, columnIndex) =>
          cellXml(cell, cellReference(columnIndex + 1, rowIndex + 1))
        ).join("")
      }</row>`
    ).join("")
  }</sheetData></worksheet>`;

  const files: Record<string, Uint8Array> = {
    "[Content_Types].xml": encoder.encode(
      `<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>`,
    ),
    "_rels/.rels": encoder.encode(
      `<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>`,
    ),
    "xl/workbook.xml": encoder.encode(
      `<?xml version="1.0" encoding="UTF-8" standalone="yes"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Research Export" sheetId="1" r:id="rId1"/></sheets></workbook>`,
    ),
    "xl/_rels/workbook.xml.rels": encoder.encode(
      `<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>`,
    ),
    "xl/styles.xml": encoder.encode(
      `<?xml version="1.0" encoding="UTF-8" standalone="yes"?><styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><fonts count="1"><font><sz val="11"/><name val="Calibri"/></font></fonts><fills count="1"><fill><patternFill patternType="none"/></fill></fills><borders count="1"><border/></borders><cellStyleXfs count="1"><xf/></cellStyleXfs><cellXfs count="1"><xf xfId="0"/></cellXfs></styleSheet>`,
    ),
    "xl/worksheets/sheet1.xml": encoder.encode(sheetXml),
  };
  return zipSync(files, { level: 6 });
}

function xlsxCell(value: Primitive): Primitive {
  if (typeof value === "string" && /^[=+\-@]/.test(value)) return `'${value}`;
  return value;
}

function cellXml(value: Primitive, reference: string): string {
  if (value === null) return `<c r="${reference}"/>`;
  if (typeof value === "number") return `<c r="${reference}"><v>${value}</v></c>`;
  if (typeof value === "boolean") return `<c r="${reference}" t="b"><v>${value ? 1 : 0}</v></c>`;
  return `<c r="${reference}" t="inlineStr"><is><t xml:space="preserve">${xmlEscape(value)}</t></is></c>`;
}

function cellReference(column: number, row: number): string {
  let letters = "";
  let current = column;
  while (current > 0) {
    const remainder = (current - 1) % 26;
    letters = String.fromCharCode(65 + remainder) + letters;
    current = Math.floor((current - 1) / 26);
  }
  return `${letters}${row}`;
}

function xmlEscape(value: string): string {
  return value.replaceAll("&", "&amp;").replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;").replaceAll('"', "&quot;")
    .replaceAll("'", "&apos;");
}
