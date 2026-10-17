import { sha256Hex } from "@/lib/crypto";
import { AppError, badRequest, conflict, notFound, unprocessable } from "@/lib/errors";
import { isUniqueViolation } from "@/lib/prisma";
import { storage } from "@/lib/storage";
import { activityRepository } from "@/server/repositories/activity.repository";
import { trackChunkRepository, trackRepository } from "@/server/repositories/media.repository";
import {
  chunkParams,
  finalizeTrackSchema,
  trackChunkSchema,
  type TrackPoint,
  type TrackSegment,
} from "@/server/validators/activity";
import { buildGpx, type MergedTrack } from "./gpx";

// H02: upload track theo chunk, idempotent theo (activityId, seq, sha256); finalize kiểm tra đủ 0..n-1.

const chunkKey = (userId: string, activityId: string, seq: number) => `tracks/${userId}/${activityId}/chunks/${seq}.json`;
const trackKey = (userId: string, activityId: string) => `tracks/${userId}/${activityId}/track.json`;

async function requireGpsActivity(userId: string, activityId: string) {
  const activity = await activityRepository.findOwned(userId, activityId);
  if (!activity) throw notFound("Activity");
  if (!activity.hasGps) throw conflict("no_gps", "Activity has no GPS track");
  return activity;
}

function parseChunk(bytes: Uint8Array) {
  let data: unknown;
  try {
    data = JSON.parse(new TextDecoder().decode(bytes));
  } catch {
    throw badRequest("invalid_json", "Chunk is not valid JSON");
  }
  const parsed = trackChunkSchema.safeParse(data);
  if (!parsed.success) {
    throw unprocessable("invalid_chunk", "Chunk does not match the track schema", parsed.error.issues.slice(0, 10));
  }
  return parsed.data;
}

function summarize(t: { activityId: string; status: string; totalChunks: number | null; pointCount: number | null; segmentCount: number | null; sha256: string | null; finalizedAt: Date | null }) {
  return {
    activityId: t.activityId,
    status: t.status,
    totalChunks: t.totalChunks,
    pointCount: t.pointCount,
    segmentCount: t.segmentCount,
    sha256: t.sha256,
    finalizedAt: t.finalizedAt?.getTime() ?? null,
  };
}

export const trackService = {
  async putChunk(userId: string, rawParams: unknown, bytes: Uint8Array, checksum: string | null) {
    const { id: activityId, seq } = chunkParams.parse(rawParams);
    await requireGpsActivity(userId, activityId);
    if (!checksum || !/^[a-f0-9]{64}$/i.test(checksum)) {
      throw badRequest("checksum_required", "X-Checksum-Sha256 header (hex) is required");
    }
    const actual = sha256Hex(bytes);
    if (actual !== checksum.toLowerCase()) {
      throw unprocessable("checksum_mismatch", "Chunk checksum does not match content");
    }

    const existing = await trackChunkRepository.find(userId, activityId, seq);
    if (existing) {
      if (existing.sha256 === actual) return { status: 200, chunk: { seq, sha256: actual, duplicate: true } };
      throw conflict("chunk_conflict", "A different chunk was already uploaded for this seq");
    }
    const track = await trackRepository.ensure(userId, activityId);
    if (track.status === "finalized") throw conflict("track_finalized", "Track is already finalized");

    parseChunk(bytes);
    const key = chunkKey(userId, activityId, seq);
    await storage().put(key, bytes);
    try {
      await trackChunkRepository.create({ activityId, ownerId: userId, seq, sha256: actual, bytes: bytes.byteLength, storageKey: key });
    } catch (err) {
      if (!isUniqueViolation(err)) throw err;
      const again = await trackChunkRepository.find(userId, activityId, seq);
      if (again?.sha256 === actual) return { status: 200, chunk: { seq, sha256: actual, duplicate: true } };
      throw conflict("chunk_conflict", "A different chunk was already uploaded for this seq");
    }
    return { status: 201, chunk: { seq, sha256: actual, duplicate: false } };
  },

  async finalize(userId: string, activityId: string, raw: unknown) {
    const { totalChunks } = finalizeTrackSchema.parse(raw);
    await requireGpsActivity(userId, activityId);
    const track = await trackRepository.findOwned(userId, activityId);
    if (track?.status === "finalized") {
      if (track.totalChunks === totalChunks) return summarize(track);
      throw conflict("track_finalized", "Track already finalized with a different chunk count");
    }
    const chunks = track ? await trackChunkRepository.list(userId, activityId) : [];
    const present = new Set(chunks.map((c) => c.seq));
    const missing: number[] = [];
    for (let i = 0; i < totalChunks; i++) if (!present.has(i)) missing.push(i);
    if (missing.length > 0) {
      throw conflict("track_incomplete", "Track chunks are missing", { missing: missing.slice(0, 200), missingCount: missing.length });
    }
    if (chunks.some((c) => c.seq >= totalChunks)) {
      throw conflict("track_chunk_out_of_range", "Chunks exist beyond totalChunks");
    }

    // Gộp chunk: segment theo id, point khử trùng theo (segmentId, seq).
    const segments = new Map<string, TrackSegment>();
    const points = new Map<string, TrackPoint>();
    for (const c of chunks) {
      const bytes = await storage().get(c.storageKey);
      if (!bytes || sha256Hex(bytes) !== c.sha256) {
        throw new AppError(500, "storage_corrupt", "Stored chunk is missing or corrupt");
      }
      const data = parseChunk(bytes);
      for (const s of data.segments) {
        const prev = segments.get(s.id);
        segments.set(s.id, prev ? { ...prev, endedAt: s.endedAt ?? prev.endedAt ?? null } : s);
      }
      for (const p of data.points) points.set(`${p.segmentId}:${p.seq}`, p);
    }
    const unknownSeg = [...points.values()].find((p) => !segments.has(p.segmentId));
    if (unknownSeg) throw unprocessable("track_invalid", "Point references an undeclared segment");

    const merged: MergedTrack = {
      activityId,
      segments: [...segments.values()]
        .sort((a, b) => a.seq - b.seq)
        .map((s) => ({
          ...s,
          points: [...points.values()].filter((p) => p.segmentId === s.id).sort((a, b) => a.seq - b.seq || a.t - b.t),
        })),
    };
    const accepted = merged.segments.flatMap((s) => s.points.filter((p) => p.accepted));
    const bytes = new TextEncoder().encode(JSON.stringify(merged));
    const key = trackKey(userId, activityId);
    await storage().put(key, bytes);
    const first = accepted[0];
    const last = accepted[accepted.length - 1];
    const n = await trackRepository.finalize(userId, activityId, {
      status: "finalized",
      totalChunks,
      storageKey: key,
      sha256: sha256Hex(bytes),
      pointCount: points.size,
      segmentCount: merged.segments.length,
      startLat: first?.lat ?? null,
      startLon: first?.lon ?? null,
      endLat: last?.lat ?? null,
      endLon: last?.lon ?? null,
      finalizedAt: new Date(),
    });
    const final = await trackRepository.findOwned(userId, activityId);
    if (n === 0 && final?.totalChunks !== totalChunks) throw conflict("track_finalized", "Track already finalized");
    // Xóa file chunk (giữ metadata để re-upload trùng vẫn idempotent).
    await storage().deletePrefix(`tracks/${userId}/${activityId}/chunks`);
    return summarize(final!);
  },

  async loadMerged(userId: string, activityId: string): Promise<MergedTrack | null> {
    const track = await trackRepository.findOwned(userId, activityId);
    if (!track || track.status !== "finalized" || !track.storageKey) return null;
    const bytes = await storage().get(track.storageKey);
    if (!bytes) return null;
    return JSON.parse(new TextDecoder().decode(bytes)) as MergedTrack;
  },

  async download(userId: string, activityId: string) {
    const activity = await activityRepository.findOwned(userId, activityId);
    if (!activity) throw notFound("Activity");
    const merged = await this.loadMerged(userId, activityId);
    if (!merged) throw notFound("Track");
    return merged;
  },

  async gpx(userId: string, activityId: string) {
    const activity = await activityRepository.findOwned(userId, activityId);
    if (!activity) throw notFound("Activity");
    const merged = await this.loadMerged(userId, activityId);
    if (!merged) throw notFound("Track");
    const gpx = buildGpx(merged, { name: activity.title, type: activity.type, startedAt: activity.startedAt.getTime() });
    if (!gpx) throw notFound("GPS points");
    return gpx;
  },
};
