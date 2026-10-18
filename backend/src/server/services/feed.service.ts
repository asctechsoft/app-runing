import type { ClubPost, Comment } from "@prisma/client";
import { newId } from "@/lib/crypto";
import { notFound, unprocessable } from "@/lib/errors";
import { limitSocial } from "@/lib/rate-limit";
import { decodeCursor, pageQuery, toPage } from "@/server/http/pagination";
import { activityRepository } from "@/server/repositories/activity.repository";
import {
  blockRepository,
  cheerRepository,
  commentRepository,
  membershipRepository,
  postRepository,
  publicUserRepository,
  reportRepository,
} from "@/server/repositories/social.repository";
import { blockSchema, commentSchema, createPostSchema, reportSchema } from "@/server/validators/misc";
import { requireMember } from "./club.service";
import { privacyService } from "./privacy.service";

// M02: feed club. Người bị chặn (hai chiều) không thấy/tương tác nội dung của nhau => 404.

async function accessiblePost(userId: string, postId: string) {
  const post = await postRepository.find(postId);
  if (!post) throw notFound("Post");
  const m = await membershipRepository.find(post.clubId, userId);
  if (!m || m.status !== "approved") throw notFound("Post");
  if (post.authorId !== userId && (await blockRepository.isBlockedEitherWay(userId, post.authorId))) throw notFound("Post");
  return post;
}

function toCommentDto(c: Comment, names: Map<string, string | null>) {
  return { id: c.id, postId: c.postId, authorId: c.authorId, authorDisplayName: names.get(c.authorId) ?? null, text: c.text, createdAt: c.createdAt.getTime() };
}

export const feedService = {
  async decoratePosts(viewerId: string, posts: ClubPost[]) {
    const ids = posts.map((p) => p.id);
    const [comments, cheers, mine, names, activities] = await Promise.all([
      postRepository.commentCounts(ids),
      postRepository.cheerCounts(ids),
      postRepository.cheeredBy(viewerId, ids),
      publicUserRepository.displayNames([...new Set(posts.map((p) => p.authorId))]),
      privacyService.visibleActivities(viewerId, posts.flatMap((p) => (p.activityId ? [p.activityId] : []))),
    ]);
    const cc = new Map(comments.map((r) => [r.postId, r._count._all]));
    const ch = new Map(cheers.map((r) => [r.postId, r._count._all]));
    const my = new Set(mine.map((r) => r.postId));
    return posts.map((p) => ({
      id: p.id,
      clubId: p.clubId,
      authorId: p.authorId,
      authorDisplayName: names.get(p.authorId) ?? null,
      text: p.text,
      // Hoạt động chỉ hiện khi quyền riêng tư hiện tại vẫn cho phép; không có tọa độ trừ khi chủ bật shareRoute.
      activity: p.activityId ? (activities.get(p.activityId) ?? null) : null,
      activityHidden: p.activityId !== null && !activities.has(p.activityId),
      commentCount: cc.get(p.id) ?? 0,
      cheerCount: ch.get(p.id) ?? 0,
      cheeredByMe: my.has(p.id),
      createdAt: p.createdAt.getTime(),
    }));
  },

  async list(userId: string, clubId: string, rawQuery: unknown) {
    await requireMember(userId, clubId);
    const q = pageQuery.parse(rawQuery);
    const blocked = await blockRepository.relatedIds(userId);
    const rows = await postRepository.list(clubId, blocked, decodeCursor(q.cursor), q.limit);
    const page = toPage(rows, q.limit, (p) => p.createdAt);
    return { items: await this.decoratePosts(userId, page.items), nextCursor: page.nextCursor };
  },

  async create(userId: string, clubId: string, raw: unknown) {
    const input = createPostSchema.parse(raw);
    await limitSocial("post", userId);
    await requireMember(userId, clubId);
    if (input.id) {
      const existing = await postRepository.findAny(input.id);
      if (existing) {
        if (existing.authorId !== userId || existing.clubId !== clubId) throw notFound("Post");
        return (await this.decoratePosts(userId, [existing]))[0]!;
      }
    }
    if (input.activityId) {
      const a = await activityRepository.findOwned(userId, input.activityId);
      if (!a) throw notFound("Activity");
      if (a.privacy === "onlyMe") throw unprocessable("activity_private", "Change the activity privacy before posting it");
      if (a.status !== "saved") throw unprocessable("activity_not_saved", "Only saved activities can be posted");
    }
    const post = await postRepository.create({
      id: input.id ?? newId(),
      clubId,
      authorId: userId,
      activityId: input.activityId ?? null,
      text: input.text,
    });
    return (await this.decoratePosts(userId, [post]))[0]!;
  },

  async get(userId: string, postId: string) {
    const post = await accessiblePost(userId, postId);
    return (await this.decoratePosts(userId, [post]))[0]!;
  },

  async remove(userId: string, postId: string) {
    const post = await postRepository.find(postId);
    if (!post || post.authorId !== userId) throw notFound("Post");
    await postRepository.softDelete(postId);
    return { id: postId, deleted: true };
  },

  async listComments(userId: string, postId: string, rawQuery: unknown) {
    await accessiblePost(userId, postId);
    const q = pageQuery.parse(rawQuery);
    const blocked = await blockRepository.relatedIds(userId);
    const rows = await commentRepository.list(postId, blocked, decodeCursor(q.cursor), q.limit);
    const page = toPage(rows, q.limit, (c) => c.createdAt);
    const names = await publicUserRepository.displayNames([...new Set(page.items.map((c) => c.authorId))]);
    return { items: page.items.map((c) => toCommentDto(c, names)), nextCursor: page.nextCursor };
  },

  async addComment(userId: string, postId: string, raw: unknown) {
    const input = commentSchema.parse(raw);
    await limitSocial("comment", userId);
    await accessiblePost(userId, postId);
    const c = await commentRepository.create({ postId, authorId: userId, text: input.text });
    const names = await publicUserRepository.displayNames([userId]);
    return toCommentDto(c, names);
  },

  async removeComment(userId: string, commentId: string) {
    const c = await commentRepository.find(commentId);
    if (!c || c.authorId !== userId) throw notFound("Comment");
    await commentRepository.softDelete(commentId);
    return { id: commentId, deleted: true };
  },

  async cheer(userId: string, postId: string, on: boolean) {
    await limitSocial("cheer", userId);
    await accessiblePost(userId, postId);
    if (on) await cheerRepository.add(postId, userId);
    else await cheerRepository.remove(postId, userId);
    return this.get(userId, postId);
  },

  async report(userId: string, raw: unknown) {
    const input = reportSchema.parse(raw);
    await limitSocial("report", userId);
    if (input.targetType === "post") await accessiblePost(userId, input.targetId);
    else if (input.targetType === "comment") {
      const c = await commentRepository.find(input.targetId);
      if (!c) throw notFound("Comment");
      await accessiblePost(userId, c.postId);
    } else if (input.targetId === userId) {
      throw unprocessable("invalid_target", "Cannot report yourself");
    }
    const existing = await reportRepository.find(userId, input.targetType, input.targetId);
    const r = existing ?? (await reportRepository.create({ reporterId: userId, ...input }));
    return { id: r.id, targetType: r.targetType, targetId: r.targetId, createdAt: r.createdAt.getTime() };
  },

  async block(userId: string, raw: unknown) {
    const { userId: target } = blockSchema.parse(raw);
    if (target === userId) throw unprocessable("invalid_target", "Cannot block yourself");
    await limitSocial("block", userId);
    const b = await blockRepository.add(userId, target);
    return { userId: b.blockedId, createdAt: b.createdAt.getTime() };
  },

  async unblock(userId: string, target: string) {
    const r = await blockRepository.remove(userId, target);
    if (r.count === 0) throw notFound("Block");
    return { userId: target, blocked: false };
  },

  async listBlocks(userId: string) {
    const rows = await blockRepository.listByBlocker(userId);
    return { items: rows.map((b) => ({ userId: b.blockedId, createdAt: b.createdAt.getTime() })), nextCursor: null };
  },
};
