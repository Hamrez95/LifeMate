export interface PhoneOtpProvider {
  sendOtp(phoneE164: string, otp: string): Promise<void>;
}

export class KavenegarOtpProvider implements PhoneOtpProvider {
  constructor(
    private readonly apiKey: string,
    private readonly template: string,
  ) {}

  async sendOtp(phoneE164: string, otp: string): Promise<void> {
    const receptor = iranianReceptor(phoneE164);
    if (!/^\d{6,10}$/.test(otp)) throw new Error("invalid_otp_shape");
    if (!/^[A-Za-z0-9_-]{1,64}$/.test(this.template)) {
      throw new Error("invalid_kavenegar_template");
    }

    const url = new URL(
      `https://api.kavenegar.com/v1/${
        encodeURIComponent(this.apiKey)
      }/verify/lookup.json`,
    );
    url.searchParams.set("receptor", receptor);
    url.searchParams.set("token", otp);
    url.searchParams.set("template", this.template);

    const response = await fetch(url, {
      method: "GET",
      signal: AbortSignal.timeout(3_500),
      headers: { accept: "application/json" },
    });
    if (!response.ok) throw new Error(`kavenegar_http_${response.status}`);

    const body = await response.json().catch(() => null) as
      | { return?: { status?: number } }
      | null;
    if (body?.return?.status !== 200) {
      throw new Error("kavenegar_rejected");
    }
  }
}

function iranianReceptor(phoneE164: string): string {
  const normalized = phoneE164.replace(/[\s()-]/g, "");
  if (!/^\+989\d{9}$/.test(normalized)) {
    throw new Error("iran_phone_required");
  }
  return `0${normalized.slice(3)}`;
}
