import type { Activity, Track } from "@prisma/client";
import { notFound } from "@/lib/errors";
import { activityRepository } from "@/server/repositories/activity.repository";
import { trackRepository } from "@/server/repositories/media.repository";
import { blockRepository, membershipRepository } from "@/server/repositories/social.repository";

// J04: mặc định onlyMe. Người khác chỉ thấy khi privacy cho phép VÀ có quan hệ (cùng club đã duyệt) VÀ không chặn nhau.
// Bản xem công khai không bao giờ chứa tọa độ đầu/cuối trừ khi chủ sở hữu bật shareRoute.

export async function canView(viewerId: string, a: Pick<Activity, "ownerId" | "privacy" | "deletedAt" | "status">): Promise<boolean> {
  if (a.deletedAt) return false;
  if (a.ownerId === viewerId) return true;
  if (a.status !== "saved") return false;
  if (a.privacy !== "followers" && a.privacy !== "public") return false;
  if (await blockRepository.isBlockedEitherWay(viewerId, a.ownerId)) return false;
  return membershipRepository.shareApprovedClub(viewerId, a.ownerId);
}

export function toPublicActivity(a: Activity, track: Track | null) {
  const route =
    a.shareRoute && track && track.startLat != null && track.startLon != null
      ? { start: { lat: track.startLat, lon: track.startLon }, end: track.endLat != null && track.endLon != null ? { lat: track.endLat, lon: track.endLon } : null }
      : null;
  return {
    id: a.id,
    ownerId: a.ownerId,
    type: a.type,
    title: a.title,
    startedAt: a.startedAt.getTime(),
    endedAt: a.endedAt?.getTime() ?? null,
    tzId: a.tzId,
    distanceM: a.distanceM,
    distanceSource: a.distanceSource,
    distanceEstimated: a.distanceSource === "steps",
    movingMs: a.movingMs,
    elapsedMs: a.elapsedMs,
    avgPaceSecPerKm: a.avgPaceSecPerKm,
    steps: a.steps,
    feeling: a.feeling,
    privacy: a.privacy,
    route,
  };
}

export const privacyService = {
  /** Lọc danh sách hoạt động theo quyền xem của viewer; trả map id -> bản công khai. */
  async visibleActivities(viewerId: string, ids: string[]) {
    const out = new Map<string, ReturnType<typeof toPublicActivity>>();
    if (ids.length === 0) return out;
    const rows = await activityRepository.findLiveForPrivacyCheck([...new Set(ids)]);
    for (const a of rows) {
      if (!(await canView(viewerId, a))) continue;
      const track = a.shareRoute ? await trackRepository.findOwned(a.ownerId, a.id) : null;
      out.set(a.id, toPublicActivity(a, track));
    }
    return out;
  },

  async getShared(viewerId: string, activityId: string) {
    const map = await this.visibleActivities(viewerId, [activityId]);
    const a = map.get(activityId);
    if (!a) throw notFound("Activity");
    return a;
  },
};
