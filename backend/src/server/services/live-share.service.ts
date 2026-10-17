import type { LiveShare, LiveShareViewer } from "@prisma/client";
import { newId } from "@/lib/crypto";
import { conflict, notFound, unprocessable } from "@/lib/errors";
import { activityRepository } from "@/server/repositories/activity.repository";
import { userRepository } from "@/server/repositories/auth.repository";
import { liveShareRepository } from "@/server/repositories/explore.repository";
import { notificationRepository } from "@/server/repositories/notification.repository";
import { blockRepository, publicUserRepository } from "@/server/repositories/social.repository";
import { livePointSchema, startLiveShareSchema } from "@/server/validators/misc";

// M06/M07: chia sẻ vị trí trực tiếp chỉ cho danh sách người xem được chỉ định; hết hạn theo TTL hoặc khi hoạt động kết thúc.

const ACTIVE_STATUSES = new Set(["recording", "paused", "recoveryNeeded"]);
const isActive = (s: LiveShare, now = new Date()) => !s.stoppedAt && s.expiresAt > now;

function toDto(s: LiveShare & { viewers?: LiveShareViewer[] }, opts: { owner: boolean; ownerDisplayName?: string | null }) {
  return {
    id: s.id,
    activityId: s.activityId,
    ownerId: s.ownerId,
    ownerDisplayName: opts.ownerDisplayName ?? null,
    startedAt: s.startedAt.getTime(),
    expiresAt: s.expiresAt.getTime(),
    stoppedAt: s.stoppedAt?.getTime() ?? null,
    active: isActive(s),
    lastPoint: s.lastPointJson ? (JSON.parse(s.lastPointJson) as unknown) : null,
    lastUpdateAt: s.lastUpdateAt?.getTime() ?? null,
    ...(opts.owner && { viewerIds: (s.viewers ?? []).map((v) => v.userId) }),
  };
}

export const liveShareService = {
  async start(userId: string, raw: unknown) {
    const input = startLiveShareSchema.parse(raw);
    const activity = await activityRepository.findOwned(userId, input.activityId);
    if (!activity) throw notFound("Activity");
    if (!ACTIVE_STATUSES.has(activity.status)) throw conflict("activity_not_active", "Live sharing requires an in-progress activity");
    if (input.viewerIds.includes(userId)) throw unprocessable("invalid_viewers", "Cannot add yourself as a viewer");
    const valid = await userRepository.findManyActiveByIds(input.viewerIds);
    const blocked = new Set(await blockRepository.relatedIds(userId));
    if (valid.length !== input.viewerIds.length || input.viewerIds.some((v) => blocked.has(v))) {
      throw unprocessable("invalid_viewers", "One or more viewers are not available");
    }
    const now = new Date();
    if (await liveShareRepository.findActiveForActivity(userId, activity.id, now)) {
      throw conflict("live_share_active", "A live share is already active for this activity");
    }
    const share = await liveShareRepository.create({
      id: newId(),
      activityId: activity.id,
      ownerId: userId,
      expiresAt: new Date(now.getTime() + input.ttlMinutes * 60_000),
      viewerIds: input.viewerIds,
    });
    await notificationRepository.createMany(
      input.viewerIds.map((v) => ({
        ownerId: v,
        kind: "liveShareStarted",
        title: "Live activity shared with you",
        body: "Someone started sharing their live activity with you.",
        deepLink: `stride://live/${share.id}`,
      })),
    );
    return toDto(share, { owner: true });
  },

  async publishPoint(userId: string, id: string, raw: unknown) {
    const point = livePointSchema.parse(raw);
    const share = await liveShareRepository.findOwned(userId, id);
    if (!share) throw notFound("Live share");
    if (!isActive(share)) throw conflict("live_share_ended", "Live share has ended");
    const updated = await liveShareRepository.update(id, { lastPointJson: JSON.stringify(point), lastUpdateAt: new Date() });
    return toDto(updated, { owner: true });
  },

  /** Người xem chỉ đọc được khi có tên trong danh sách, chưa hết hạn/dừng, không bị chặn. Ngược lại 404. */
  async get(viewerId: string, id: string) {
    const own = await liveShareRepository.findOwned(viewerId, id);
    if (own) return toDto(own, { owner: true });
    const share = await liveShareRepository.findForViewer(viewerId, id);
    if (!share || !isActive(share)) throw notFound("Live share");
    if (await blockRepository.isBlockedEitherWay(viewerId, share.ownerId)) throw notFound("Live share");
    const names = await publicUserRepository.displayNames([share.ownerId]);
    return toDto(share, { owner: false, ownerDisplayName: names.get(share.ownerId) });
  },

  async stop(userId: string, id: string) {
    const share = await liveShareRepository.findOwned(userId, id);
    if (!share) throw notFound("Live share");
    if (share.stoppedAt) return toDto(share, { owner: true });
    return toDto(await liveShareRepository.update(id, { stoppedAt: new Date(), stopReason: "stopped" }), { owner: true });
  },

  async listViewing(viewerId: string) {
    const rows = await liveShareRepository.listActiveForViewer(viewerId, new Date());
    const blocked = new Set(await blockRepository.relatedIds(viewerId));
    const visible = rows.filter((r) => !blocked.has(r.ownerId));
    const names = await publicUserRepository.displayNames(visible.map((r) => r.ownerId));
    return { items: visible.map((r) => toDto(r, { owner: false, ownerDisplayName: names.get(r.ownerId) })), nextCursor: null };
  },

  stopForActivity(activityId: string, reason: string) {
    return liveShareRepository.stopAllForActivity(activityId, reason);
  },
};
