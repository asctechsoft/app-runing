import type { Club, ClubEvent, Membership } from "@prisma/client";
import { newId } from "@/lib/crypto";
import { conflict, forbidden, notFound } from "@/lib/errors";
import { runInTransaction } from "@/lib/prisma";
import { decodeCursor, pageQuery, toPage } from "@/server/http/pagination";
import { notificationRepository } from "@/server/repositories/notification.repository";
import {
  blockRepository,
  clubRepository,
  eventRepository,
  membershipRepository,
  publicUserRepository,
} from "@/server/repositories/social.repository";
import { clubSearchQuery, createClubSchema, createEventSchema, roleSchema } from "@/server/validators/misc";

// M01 (clubs, membership, vai trò owner/mod/member) và M03 (sự kiện club, RSVP).

function toMembershipDto(m: Membership | null | undefined) {
  if (!m) return null;
  return { role: m.role, status: m.status, updatedAt: m.updatedAt.getTime() };
}

function toClubDto(c: Club, memberCount: number, m?: Membership | null) {
  return {
    id: c.id,
    name: c.name,
    description: c.description,
    regionText: c.regionText,
    lat: c.lat,
    lon: c.lon,
    ownerId: c.ownerId,
    memberCount,
    isDevFixture: c.isDevFixture,
    createdAt: c.createdAt.getTime(),
    myMembership: toMembershipDto(m),
  };
}

async function decorate(userId: string, clubs: Club[]) {
  const ids = clubs.map((c) => c.id);
  const [counts, mine] = await Promise.all([clubRepository.memberCounts(ids), membershipRepository.findManyForUser(userId, ids)]);
  const countMap = new Map(counts.map((c) => [c.clubId, c._count._all]));
  const mineMap = new Map(mine.map((m) => [m.clubId, m]));
  return clubs.map((c) => toClubDto(c, countMap.get(c.id) ?? 0, mineMap.get(c.id)));
}

export async function requireClub(clubId: string) {
  const club = await clubRepository.find(clubId);
  if (!club) throw notFound("Club");
  return club;
}

/** Thành viên đã duyệt; nếu không => 403 not_member (club là thông tin công khai nên không cần giấu). */
export async function requireMember(userId: string, clubId: string) {
  const club = await requireClub(clubId);
  const m = await membershipRepository.find(clubId, userId);
  if (!m || m.status !== "approved") throw forbidden("not_member", "Club membership required");
  return { club, membership: m };
}

async function requireModerator(userId: string, clubId: string) {
  const r = await requireMember(userId, clubId);
  if (r.membership.role !== "owner" && r.membership.role !== "mod") throw forbidden("not_moderator", "Owner or moderator role required");
  return r;
}

function toEventDto(e: ClubEvent, going: number, myStatus: string | null) {
  return {
    id: e.id,
    clubId: e.clubId,
    creatorId: e.creatorId,
    title: e.title,
    description: e.description,
    startAt: e.startAt.getTime(),
    endAt: e.endAt?.getTime() ?? null,
    tzId: e.tzId,
    meetingPlace: e.meetingPlace,
    cancelledAt: e.cancelledAt?.getTime() ?? null,
    goingCount: going,
    myRsvp: myStatus,
  };
}

export const clubService = {
  async search(userId: string, rawQuery: unknown) {
    const q = clubSearchQuery.parse(rawQuery);
    const box =
      q.minLat !== undefined && q.maxLat !== undefined && q.minLon !== undefined && q.maxLon !== undefined
        ? { minLat: q.minLat, maxLat: q.maxLat, minLon: q.minLon, maxLon: q.maxLon }
        : undefined;
    const rows = await clubRepository.search({ text: q.q, region: q.region, box }, decodeCursor(q.cursor), q.limit);
    const page = toPage(rows, q.limit, (c) => c.createdAt);
    return { items: await decorate(userId, page.items), nextCursor: page.nextCursor };
  },

  async create(userId: string, raw: unknown) {
    const input = createClubSchema.parse(raw);
    const club = await runInTransaction(async (tx) => {
      const c = await clubRepository.create(
        {
          id: newId(),
          name: input.name,
          description: input.description,
          regionText: input.regionText,
          searchText: `${input.name} ${input.regionText}`.toLowerCase(),
          lat: input.lat ?? null,
          lon: input.lon ?? null,
          ownerId: userId,
        },
        tx,
      );
      await membershipRepository.create({ clubId: c.id, userId, role: "owner", status: "approved" }, tx);
      return c;
    });
    return (await decorate(userId, [club]))[0]!;
  },

  async detail(userId: string, clubId: string) {
    return (await decorate(userId, [await requireClub(clubId)]))[0]!;
  },

  /** Gửi lại yêu cầu tham gia không tạo bản ghi trùng (unique clubId+userId). */
  async requestJoin(userId: string, clubId: string) {
    const club = await requireClub(clubId);
    if (await blockRepository.isBlockedEitherWay(userId, club.ownerId)) throw notFound("Club");
    const existing = await membershipRepository.find(clubId, userId);
    if (existing && (existing.status === "pending" || existing.status === "approved")) {
      return { membership: toMembershipDto(existing) };
    }
    const m = existing
      ? await membershipRepository.update(clubId, userId, { status: "pending", role: "member" })
      : await membershipRepository.create({ clubId, userId, role: "member", status: "pending" });
    const mods = await membershipRepository.listModerators(clubId);
    await notificationRepository.createMany(
      mods.map((mod) => ({
        ownerId: mod.userId,
        kind: "clubJoinRequest",
        title: "New join request",
        body: club.name,
        deepLink: `stride://clubs/${clubId}/requests`,
      })),
    );
    return { membership: toMembershipDto(m) };
  },

  async listRequests(actorId: string, clubId: string) {
    await requireModerator(actorId, clubId);
    const rows = await membershipRepository.listPending(clubId);
    const names = await publicUserRepository.displayNames(rows.map((r) => r.userId));
    return {
      items: rows.map((r) => ({ userId: r.userId, displayName: names.get(r.userId) ?? null, requestedAt: r.updatedAt.getTime() })),
      nextCursor: null,
    };
  },

  async decide(actorId: string, clubId: string, userId: string, approve: boolean) {
    const { club } = await requireModerator(actorId, clubId);
    const m = await membershipRepository.find(clubId, userId);
    if (!m || m.status !== "pending") throw notFound("Join request");
    const updated = await membershipRepository.update(clubId, userId, { status: approve ? "approved" : "rejected" });
    await notificationRepository.create({
      ownerId: userId,
      kind: approve ? "clubJoinApproved" : "clubJoinRejected",
      title: approve ? "Join request approved" : "Join request declined",
      body: club.name,
      deepLink: `stride://clubs/${clubId}`,
    });
    return { userId, membership: toMembershipDto(updated) };
  },

  async leave(userId: string, clubId: string) {
    await requireClub(clubId);
    const m = await membershipRepository.find(clubId, userId);
    if (!m || (m.status !== "approved" && m.status !== "pending")) throw notFound("Membership");
    if (m.role === "owner") throw conflict("owner_cannot_leave", "Transfer ownership before leaving");
    const updated = await membershipRepository.update(clubId, userId, { status: "left", role: "member" });
    return { membership: toMembershipDto(updated) };
  },

  async setRole(actorId: string, clubId: string, userId: string, raw: unknown) {
    const { role } = roleSchema.parse(raw);
    const { membership } = await requireMember(actorId, clubId);
    if (membership.role !== "owner") throw forbidden("not_owner", "Only the owner can change roles");
    const target = await membershipRepository.find(clubId, userId);
    if (!target || target.status !== "approved") throw notFound("Member");
    if (target.role === "owner") throw conflict("cannot_change_owner", "Owner role cannot be changed");
    const updated = await membershipRepository.update(clubId, userId, { role });
    return { userId, membership: toMembershipDto(updated) };
  },

  async myClubs(userId: string) {
    const ms = await membershipRepository.listApprovedForUser(userId);
    const clubs = await clubRepository.findMany(ms.map((m) => m.clubId));
    return { items: await decorate(userId, clubs), nextCursor: null };
  },

  // ---- Sự kiện (M03)
  async listEvents(userId: string, clubId: string, rawQuery: unknown) {
    await requireMember(userId, clubId);
    const q = pageQuery.parse(rawQuery);
    const rows = await eventRepository.list(clubId, decodeCursor(q.cursor), q.limit);
    const page = toPage(rows, q.limit, (e) => e.startAt);
    return { items: await this.decorateEvents(userId, page.items), nextCursor: page.nextCursor };
  },

  async decorateEvents(userId: string, events: ClubEvent[]) {
    const ids = events.map((e) => e.id);
    const [counts, mine] = await Promise.all([eventRepository.goingCounts(ids), eventRepository.myRsvps(userId, ids)]);
    const c = new Map(counts.map((r) => [r.eventId, r._count._all]));
    const m = new Map(mine.map((r) => [r.eventId, r.status]));
    return events.map((e) => toEventDto(e, c.get(e.id) ?? 0, m.get(e.id) ?? null));
  },

  async createEvent(actorId: string, clubId: string, raw: unknown) {
    await requireModerator(actorId, clubId);
    const input = createEventSchema.parse(raw);
    const e = await eventRepository.create({
      id: newId(),
      clubId,
      creatorId: actorId,
      title: input.title,
      description: input.description,
      startAt: new Date(input.startAt),
      endAt: input.endAt != null ? new Date(input.endAt) : null,
      tzId: input.tzId,
      meetingPlace: input.meetingPlace,
    });
    return (await this.decorateEvents(actorId, [e]))[0]!;
  },

  async requireEventMember(userId: string, eventId: string) {
    const e = await eventRepository.find(eventId);
    if (!e) throw notFound("Event");
    const m = await membershipRepository.find(e.clubId, userId);
    if (!m || m.status !== "approved") throw notFound("Event");
    return { event: e, membership: m };
  },

  async getEvent(userId: string, eventId: string) {
    const { event } = await this.requireEventMember(userId, eventId);
    return (await this.decorateEvents(userId, [event]))[0]!;
  },

  async rsvp(userId: string, eventId: string, going: boolean) {
    const { event } = await this.requireEventMember(userId, eventId);
    if (going) {
      if (event.cancelledAt) throw conflict("event_cancelled", "Event was cancelled");
      if ((event.endAt ?? event.startAt) < new Date()) throw conflict("event_past", "Event has already happened");
    }
    await eventRepository.setRsvp(eventId, userId, going ? "going" : "cancelled");
    return (await this.decorateEvents(userId, [event]))[0]!;
  },

  async cancelEvent(actorId: string, eventId: string) {
    const e = await eventRepository.find(eventId);
    if (!e) throw notFound("Event");
    await requireModerator(actorId, e.clubId);
    const updated = e.cancelledAt ? e : await eventRepository.cancel(eventId);
    return (await this.decorateEvents(actorId, [updated]))[0]!;
  },
};
