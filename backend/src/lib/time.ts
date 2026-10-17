// Tiện ích thời gian: API dùng UTC epoch ms; ngày địa phương dạng YYYY-MM-DD theo tzId IANA.
export const toMs = (d: Date | null | undefined): number | null => (d ? d.getTime() : null);
export const fromMs = (ms: number): Date => new Date(ms);

export function isValidTimeZone(tz: string): boolean {
  try {
    new Intl.DateTimeFormat("en-US", { timeZone: tz });
    return true;
  } catch {
    return false;
  }
}

/** Ngày địa phương (YYYY-MM-DD) của một thời điểm UTC trong múi giờ tz. */
export function localDate(at: Date, tz: string): string {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: tz,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(at);
  const get = (t: string) => parts.find((p) => p.type === t)?.value ?? "";
  return `${get("year")}-${get("month")}-${get("day")}`;
}
