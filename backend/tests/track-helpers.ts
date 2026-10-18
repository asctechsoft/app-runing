import { createHash } from "node:crypto";
import { randomUUID } from "node:crypto";

export const sha256 = (b: Uint8Array | string) => createHash("sha256").update(b).digest("hex");

/** Track 2 segment (có khoảng nghỉ giữa) chia thành 3 chunk. */
export function buildTrackChunks(startedAt: number) {
  const seg1 = randomUUID();
  const seg2 = randomUUID();
  const pt = (segmentId: string, seq: number, t: number, lat: number, lon: number, accepted = true) => ({
    segmentId,
    seq,
    t,
    lat,
    lon,
    accuracyM: accepted ? 5 : 80,
    altitudeM: 10,
    speedMps: 3,
    accepted,
    rejectReason: accepted ? null : "accuracy",
  });
  const chunks = [
    {
      segments: [{ id: seg1, seq: 0, startedAt, endedAt: null, reason: "start" }],
      points: [pt(seg1, 0, startedAt, 10.7769, 106.7009), pt(seg1, 1, startedAt + 5000, 10.7772, 106.7012)],
    },
    {
      segments: [{ id: seg1, seq: 0, startedAt, endedAt: startedAt + 60_000, reason: "start" }],
      points: [pt(seg1, 2, startedAt + 10_000, 10.7775, 106.7015), pt(seg1, 3, startedAt + 15_000, 10.79, 106.75, false)],
    },
    {
      segments: [{ id: seg2, seq: 1, startedAt: startedAt + 120_000, endedAt: startedAt + 180_000, reason: "resume" }],
      points: [pt(seg2, 0, startedAt + 120_000, 10.778, 106.702), pt(seg2, 1, startedAt + 125_000, 10.7783, 106.7023)],
    },
  ];
  return chunks.map((c) => new TextEncoder().encode(JSON.stringify(c)));
}
