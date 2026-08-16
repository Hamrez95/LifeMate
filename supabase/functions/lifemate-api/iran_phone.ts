export function normalizeIranianMobileE164(value: string): string | null {
  let normalized = toAsciiDigits(value.trim()).replace(/[\s()\-]/g, "");

  if (normalized.startsWith("0098")) {
    normalized = `+98${normalized.slice(4)}`;
  } else if (normalized.startsWith("98")) {
    normalized = `+${normalized}`;
  } else if (normalized.startsWith("09")) {
    normalized = `+98${normalized.slice(1)}`;
  } else if (/^9\d{9}$/.test(normalized)) {
    normalized = `+98${normalized}`;
  }

  return /^\+989\d{9}$/.test(normalized) ? normalized : null;
}

export function maskIranianMobileE164(value: string): string {
  const normalized = normalizeIranianMobileE164(value);
  if (normalized == null) return "+98••••••••••";
  return `+98 ••• •• ${normalized.slice(-4)}`;
}

function toAsciiDigits(value: string): string {
  let result = "";
  for (const char of value) {
    const codePoint = char.codePointAt(0) ?? -1;
    if (codePoint >= 0x06f0 && codePoint <= 0x06f9) {
      result += String(codePoint - 0x06f0);
    } else if (codePoint >= 0x0660 && codePoint <= 0x0669) {
      result += String(codePoint - 0x0660);
    } else {
      result += char;
    }
  }
  return result;
}
