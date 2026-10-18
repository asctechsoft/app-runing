import { describe, expect, it } from "vitest";
import { prisma } from "@/lib/prisma";
import { activityBody, api, createActivity, randomUUID, registerUser, type TestUser } from "./helpers";
import { buildTrackChunks, sha256 } from "./track-helpers";

async function seedChallenge(overrides: Partial<{ targetType: string; targetValue: number; activityTypes: string[] }> = {}) {
  // Dữ liệu challenge chỉ tạo trong test (không có endpoint tạo challenge cho người dùng).
  return prisma.challenge.create({
    data: {
      id: randomUUID(),
      title: "October 10K",
      activityTypesJson: JSON.stringify(overrides.activityTypes ?? ["run"]),
      startDate: "2026-10-01",
      endDate: "2099-10-31",
      tzId: "Asia/Ho_Chi_Minh",
      targetType: overrides.targetType ?? "distance",
      targetValue: overrides.targetValue ?? 10_000,
      badgeKey: "oct10k",
    },
  });
}

async function makeClub(owner: TestUser) {
  const r = await api("POST", "/api/v1/clubs", { token: owner.token, body: { name: "Saigon Runners", regionText: "Ho Chi Minh City", lat: 10.77, lon: 106.7 } });
  expect(r.status).toBe(201);
  return r.body.id as string;
}

async function joinApproved(club: string, owner: TestUser, member: TestUser) {
  await api("POST", `/api/v1/clubs/${club}/join`, { token: member.token });
  const ok = await api("POST", `/api/v1/clubs/${club}/requests/${member.userId}/approve`, { token: owner.token });
  expect(ok.status).toBe(200);
}

describe("M04 challenges", () => {
  it("computes progress server-side, no double counting on retry, recalculates after delete", async () => {
    const u = await registerUser();
    const c = await seedChallenge();
    const join = await api("POST", `/api/v1/challenges/${c.id}/join`, { token: u.token, body: { leaderboardOptIn: true } });
    expect(join.status).toBe(200);
    expect(join.body.participation.progressValue).toBe(0);

    // 2026-09-30 23:30 giờ VN = trước ngày bắt đầu theo tz challenge => không tính.
    await createActivity(u, { startedAt: Date.UTC(2026, 8, 30, 16, 30), endedAt: Date.UTC(2026, 8, 30, 17, 0), distanceM: 3000 });
    // 2026-10-01 00:30 giờ VN (vẫn là 30/9 theo UTC) => tính.
    const a1 = await createActivity(u, { startedAt: Date.UTC(2026, 8, 30, 17, 30), endedAt: Date.UTC(2026, 8, 30, 18, 0), distanceM: 6000 });
    await createActivity(u, { type: "walk", distanceM: 9000 }); // sai loại
    await createActivity(u, { status: "awaitingSave", distanceM: 9000 }); // chưa lưu
    const idem = randomUUID();
    await createActivity(u, { distanceM: 5000 }, idem);
    // Retry upsert cùng nội dung không cộng trùng.
    await api("PUT", `/api/v1/activities/${idem}`, { token: u.token, body: { activity: activityBody({ distanceM: 5000 }) } });

    let p = await api("GET", `/api/v1/challenges/${c.id}/progress`, { token: u.token });
    expect(p.body.progressValue).toBe(11_000);
    expect(p.body.completedAt).toEqual(expect.any(Number));
    let badges = await api("GET", "/api/v1/me/badges", { token: u.token });
    expect(badges.body.items).toHaveLength(1);

    // Xóa hoạt động => tính lại, thu hồi hoàn thành + huy hiệu.
    await api("DELETE", `/api/v1/activities/${a1.id}`, { token: u.token });
    p = await api("GET", `/api/v1/challenges/${c.id}/progress`, { token: u.token });
    expect(p.body.progressValue).toBe(5000);
    expect(p.body.completedAt).toBeNull();
    badges = await api("GET", "/api/v1/me/badges", { token: u.token });
    expect(badges.body.items).toHaveLength(0);

    const board = await api("GET", `/api/v1/challenges/${c.id}/leaderboard`, { token: u.token });
    expect(board.body.items.map((i: { userId: string }) => i.userId)).toEqual([u.userId]);
    await api("PUT", `/api/v1/challenges/${c.id}/leaderboard-opt-in`, { token: u.token, body: { leaderboardOptIn: false } });
    expect((await api("GET", `/api/v1/challenges/${c.id}/leaderboard`, { token: u.token })).body.items).toEqual([]);

    await api("POST", `/api/v1/challenges/${c.id}/leave`, { token: u.token });
    expect((await api("GET", `/api/v1/challenges/${c.id}/progress`, { token: u.token })).status).toBe(404);
  });
});

describe("M06/M07 live sharing", () => {
  it("only listed viewers can read; expires at TTL, on stop, and when activity finishes", async () => {
    const owner = await registerUser("Owner");
    const viewer = await registerUser("Viewer");
    const stranger = await registerUser("Stranger");
    const act = await createActivity(owner, { status: "recording", endedAt: null });

    expect((await api("POST", "/api/v1/live-shares", { token: owner.token, body: { activityId: act.id, viewerIds: [randomUUID()] } })).status).toBe(422);
    const start = await api("POST", "/api/v1/live-shares", { token: owner.token, body: { activityId: act.id, viewerIds: [viewer.userId], ttlMinutes: 60 } });
    expect(start.status).toBe(201);
    const shareId = start.body.id as string;

    await api("POST", `/api/v1/live-shares/${shareId}/points`, { token: owner.token, body: { t: Date.now(), lat: 10.77, lon: 106.7 } });
    const seen = await api("GET", `/api/v1/live-shares/${shareId}`, { token: viewer.token });
    expect(seen.status).toBe(200);
    expect(seen.body.lastPoint).toMatchObject({ lat: 10.77, lon: 106.7 });
    expect(seen.body).not.toHaveProperty("viewerIds");
    expect((await api("GET", `/api/v1/live-shares/${shareId}`, { token: stranger.token })).status).toBe(404);
    expect((await api("POST", `/api/v1/live-shares/${shareId}/points`, { token: viewer.token, body: { t: Date.now(), lat: 1, lon: 1 } })).status).toBe(404);
    expect((await api("GET", "/api/v1/me/live-shares/viewing", { token: viewer.token })).body.items).toHaveLength(1);
    const inbox = await api("GET", "/api/v1/me/notifications", { token: viewer.token });
    expect(inbox.body.items[0].kind).toBe("liveShareStarted");

    // Hết TTL => 404.
    await prisma.liveShare.update({ where: { id: shareId }, data: { expiresAt: new Date(Date.now() - 1000) } });
    expect((await api("GET", `/api/v1/live-shares/${shareId}`, { token: viewer.token })).status).toBe(404);
    expect((await api("POST", `/api/v1/live-shares/${shareId}/points`, { token: owner.token, body: { t: Date.now(), lat: 1, lon: 1 } })).status).toBe(409);

    // Hoạt động kết thúc => tự dừng.
    const s2 = await api("POST", "/api/v1/live-shares", { token: owner.token, body: { activityId: act.id, viewerIds: [viewer.userId] } });
    expect((await api("GET", `/api/v1/live-shares/${s2.body.id}`, { token: viewer.token })).status).toBe(200);
    await api("PATCH", `/api/v1/activities/${act.id}`, { token: owner.token, body: { expectedRevision: 1, status: "saved", endedAt: Date.UTC(2026, 9, 10, 7) } });
    expect((await api("GET", `/api/v1/live-shares/${s2.body.id}`, { token: viewer.token })).status).toBe(404);
    expect((await api("POST", "/api/v1/live-shares", { token: owner.token, body: { activityId: act.id, viewerIds: [viewer.userId] } })).status).toBe(409);

    // Dừng chủ động.
    const act2 = await createActivity(owner, { status: "recording", endedAt: null });
    const s3 = await api("POST", "/api/v1/live-shares", { token: owner.token, body: { activityId: act2.id, viewerIds: [viewer.userId] } });
    await api("POST", `/api/v1/live-shares/${s3.body.id}/stop`, { token: owner.token });
    expect((await api("GET", `/api/v1/live-shares/${s3.body.id}`, { token: viewer.token })).status).toBe(404);
  });
});

describe("M01-M03 clubs, feed, events, J04 privacy, blocking", () => {
  it("join requests do not duplicate; approve/reject by owner/mod; roles", async () => {
    const owner = await registerUser("Owner");
    const m = await registerUser("Member");
    const club = await makeClub(owner);
    const j1 = await api("POST", `/api/v1/clubs/${club}/join`, { token: m.token });
    const j2 = await api("POST", `/api/v1/clubs/${club}/join`, { token: m.token });
    expect(j1.body.membership.status).toBe("pending");
    expect(j2.body.membership.status).toBe("pending");
    expect(await prisma.membership.count({ where: { clubId: club, userId: m.userId } })).toBe(1);
    expect((await api("GET", `/api/v1/clubs/${club}/requests`, { token: m.token })).status).toBe(403);
    const reqs = await api("GET", `/api/v1/clubs/${club}/requests`, { token: owner.token });
    expect(reqs.body.items.map((r: { userId: string }) => r.userId)).toEqual([m.userId]);
    await api("POST", `/api/v1/clubs/${club}/requests/${m.userId}/approve`, { token: owner.token });
    const detail = await api("GET", `/api/v1/clubs/${club}`, { token: m.token });
    expect(detail.body).toMatchObject({ memberCount: 2, myMembership: { role: "member", status: "approved" } });
    expect((await api("PUT", `/api/v1/clubs/${club}/members/${m.userId}/role`, { token: owner.token, body: { role: "mod" } })).body.membership.role).toBe("mod");
    expect((await api("POST", `/api/v1/clubs/${club}/leave`, { token: owner.token })).status).toBe(409);

    const search = await api("GET", "/api/v1/clubs?region=chi minh&minLat=10&maxLat=11&minLon=106&maxLon=107", { token: m.token });
    expect(search.body.items.map((c: { id: string }) => c.id)).toContain(club);
    expect((await api("GET", "/api/v1/clubs?region=hanoi", { token: m.token })).body.items.map((c: { id: string }) => c.id)).not.toContain(club);
    expect((await api("GET", "/api/v1/me/clubs", { token: m.token })).body.items).toHaveLength(1);

    // Sự kiện: chỉ owner/mod tạo; RSVP.
    const ev = await api("POST", `/api/v1/clubs/${club}/events`, {
      token: m.token,
      body: { title: "Sunday long run", startAt: Date.now() + 86_400_000, tzId: "Asia/Ho_Chi_Minh", meetingPlace: "Tao Dan park gate" },
    });
    expect(ev.status).toBe(201);
    const outsider = await registerUser();
    expect((await api("POST", `/api/v1/clubs/${club}/events`, { token: outsider.token, body: { title: "x", startAt: Date.now(), tzId: "UTC", meetingPlace: "x" } })).status).toBe(403);
    const rsvp = await api("POST", `/api/v1/events/${ev.body.id}/rsvp`, { token: owner.token });
    expect(rsvp.body).toMatchObject({ goingCount: 1, myRsvp: "going" });
    expect((await api("DELETE", `/api/v1/events/${ev.body.id}/rsvp`, { token: owner.token })).body.goingCount).toBe(0);
    expect((await api("GET", `/api/v1/events/${ev.body.id}`, { token: outsider.token })).status).toBe(404);
  });

  it("feed respects privacy, hides coordinates unless shared, and blocking cuts access both ways", async () => {
    const owner = await registerUser("Owner");
    const b = await registerUser("B");
    const outsider = await registerUser("Outsider");
    const club = await makeClub(owner);
    await joinApproved(club, owner, b);

    const priv = await createActivity(b);
    expect((await api("POST", `/api/v1/clubs/${club}/posts`, { token: b.token, body: { activityId: priv.id } })).status).toBe(422);
    const shared = await createActivity(b, { privacy: "followers" });
    const chunk = buildTrackChunks(Date.UTC(2026, 9, 10, 6))[0]!;
    await api("PUT", `/api/v1/activities/${shared.id}/track/chunks/0`, { token: b.token, raw: chunk, headers: { "x-checksum-sha256": sha256(chunk) } });
    await api("POST", `/api/v1/activities/${shared.id}/track/finalize`, { token: b.token, body: { totalChunks: 1 } });
    const post = await api("POST", `/api/v1/clubs/${club}/posts`, { token: b.token, body: { text: "Nice run", activityId: shared.id } });
    expect(post.status).toBe(201);

    // J04: thành viên thấy hoạt động nhưng không có tọa độ.
    const feed = await api("GET", `/api/v1/clubs/${club}/posts`, { token: owner.token });
    expect(feed.body.items[0].activity).toMatchObject({ id: shared.id, distanceM: 5000, route: null });
    expect(JSON.stringify(feed.body)).not.toContain("10.7769");
    expect((await api("GET", `/api/v1/shared/activities/${shared.id}`, { token: owner.token })).body.route).toBeNull();
    expect((await api("GET", `/api/v1/shared/activities/${shared.id}`, { token: outsider.token })).status).toBe(404);
    expect((await api("GET", `/api/v1/shared/activities/${priv.id}`, { token: owner.token })).status).toBe(404);
    expect((await api("GET", `/api/v1/clubs/${club}/posts`, { token: outsider.token })).status).toBe(403);

    // Chủ bật shareRoute => có điểm đầu/cuối.
    await api("PATCH", `/api/v1/activities/${shared.id}`, { token: b.token, body: { expectedRevision: 1, shareRoute: true } });
    const withRoute = await api("GET", `/api/v1/shared/activities/${shared.id}`, { token: owner.token });
    expect(withRoute.body.route.start).toEqual({ lat: 10.7769, lon: 106.7009 });
    // Chuyển về onlyMe => feed ẩn hoạt động.
    await api("PATCH", `/api/v1/activities/${shared.id}`, { token: b.token, body: { expectedRevision: 2, privacy: "onlyMe" } });
    const hidden = await api("GET", `/api/v1/clubs/${club}/posts`, { token: owner.token });
    expect(hidden.body.items[0]).toMatchObject({ activity: null, activityHidden: true });

    // Bình luận + cheer + report.
    const postId = post.body.id as string;
    expect((await api("POST", `/api/v1/posts/${postId}/comments`, { token: owner.token, body: { text: "Great!" } })).status).toBe(201);
    expect((await api("POST", `/api/v1/posts/${postId}/cheers`, { token: owner.token })).body).toMatchObject({ cheerCount: 1, cheeredByMe: true });
    expect((await api("POST", `/api/v1/posts/${postId}/cheers`, { token: owner.token })).body.cheerCount).toBe(1);
    const rep = await api("POST", "/api/v1/reports", { token: owner.token, body: { targetType: "post", targetId: postId, reason: "test" } });
    const rep2 = await api("POST", "/api/v1/reports", { token: owner.token, body: { targetType: "post", targetId: postId, reason: "test" } });
    expect(rep2.body.id).toBe(rep.body.id);

    // B chặn owner => owner không thấy/tương tác bài của B, và ngược lại.
    expect((await api("POST", "/api/v1/me/blocks", { token: b.token, body: { userId: owner.userId } })).status).toBe(201);
    const blockedFeed = await api("GET", `/api/v1/clubs/${club}/posts`, { token: owner.token });
    expect(blockedFeed.body.items.map((p: { id: string }) => p.id)).not.toContain(postId);
    expect((await api("GET", `/api/v1/posts/${postId}`, { token: owner.token })).status).toBe(404);
    expect((await api("POST", `/api/v1/posts/${postId}/comments`, { token: owner.token, body: { text: "hi" } })).status).toBe(404);
    expect((await api("POST", `/api/v1/posts/${postId}/cheers`, { token: owner.token })).status).toBe(404);
    const ownerPost = await api("POST", `/api/v1/clubs/${club}/posts`, { token: owner.token, body: { text: "Owner post" } });
    expect((await api("GET", `/api/v1/posts/${ownerPost.body.id}`, { token: b.token })).status).toBe(404);
    const comments = await api("GET", `/api/v1/posts/${ownerPost.body.id}/comments`, { token: b.token });
    expect(comments.status).toBe(404);
    // Live share tới người bị chặn bị từ chối.
    const act = await createActivity(b, { status: "recording", endedAt: null });
    expect((await api("POST", "/api/v1/live-shares", { token: b.token, body: { activityId: act.id, viewerIds: [owner.userId] } })).status).toBe(422);

    // Bỏ chặn => truy cập lại được; xóa bài của chính mình.
    expect((await api("DELETE", `/api/v1/me/blocks/${owner.userId}`, { token: b.token })).status).toBe(200);
    expect((await api("GET", `/api/v1/posts/${postId}`, { token: owner.token })).status).toBe(200);
    expect((await api("DELETE", `/api/v1/posts/${postId}`, { token: owner.token })).status).toBe(404);
    expect((await api("DELETE", `/api/v1/posts/${postId}`, { token: b.token })).status).toBe(200);
  });

  it("rate limits social actions per user", async () => {
    const owner = await registerUser();
    const club = await makeClub(owner);
    process.env.RATE_LIMIT_SOCIAL_PER_MIN = "2";
    try {
      const s = [];
      for (let i = 0; i < 3; i++) s.push((await api("POST", `/api/v1/clubs/${club}/posts`, { token: owner.token, body: { text: `p${i}` } })).status);
      expect(s).toEqual([201, 201, 429]);
    } finally {
      process.env.RATE_LIMIT_SOCIAL_PER_MIN = "10000";
    }
  });
});

describe("M05 routes", () => {
  it("searches, shows detail with polyline + attribution, saves idempotently", async () => {
    const u = await registerUser();
    const route = await prisma.route.create({
      data: {
        id: randomUUID(),
        name: "River loop",
        region: "District 1",
        regionLower: "district 1",
        distanceM: 5200,
        surface: "road",
        polyline: "_p~iF~ps|U_ulLnnqC_mqNvxq`@",
        attribution: "Test data",
      },
    });
    const s = await api("GET", "/api/v1/routes?region=district&minDistanceM=5000&maxDistanceM=6000&surface=road", { token: u.token });
    expect(s.body.items.map((r: { id: string }) => r.id)).toContain(route.id);
    expect(s.body.items[0]).not.toHaveProperty("polyline");
    expect((await api("GET", "/api/v1/routes?surface=trail", { token: u.token })).body.items).toHaveLength(0);
    const d = await api("GET", `/api/v1/routes/${route.id}`, { token: u.token });
    expect(d.body).toMatchObject({ polyline: route.polyline, attribution: "Test data", saved: false });
    await api("POST", `/api/v1/routes/${route.id}/save`, { token: u.token });
    await api("POST", `/api/v1/routes/${route.id}/save`, { token: u.token });
    expect((await api("GET", "/api/v1/me/saved-routes", { token: u.token })).body.items).toHaveLength(1);
    await api("DELETE", `/api/v1/routes/${route.id}/save`, { token: u.token });
    expect((await api("GET", "/api/v1/me/saved-routes", { token: u.token })).body.items).toHaveLength(0);
  });
});
