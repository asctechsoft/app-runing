import type { Attachment } from "@prisma/client";
import { sha256Hex } from "@/lib/crypto";
import { publicBaseUrl } from "@/lib/env";
import { conflict, notFound, unprocessable } from "@/lib/errors";
import { isUniqueViolation, runInTransaction } from "@/lib/prisma";
import { signPurposeToken, verifyPurposeToken } from "@/lib/signed-token";
import { storage } from "@/lib/storage";
import { activityRepository, changeLogRepository } from "@/server/repositories/activity.repository";
import { attachmentRepository } from "@/server/repositories/media.repository";
import { MAX_ATTACHMENT_BYTES, requestAttachmentSchema } from "@/server/validators/misc";

// H05: ảnh đính kèm riêng tư. Upload/download qua URL ký số ngắn hạn tới chính API này.

const UPLOAD_TTL_SEC = 10 * 60;
const DOWNLOAD_TTL_SEC = 5 * 60;
const MAX_PER_ACTIVITY = 20;

export function toAttachmentDto(a: Attachment) {
  if (a.deletedAt) return { id: a.id, activityId: a.activityId, revision: a.revision, deletedAt: a.deletedAt.getTime() };
  return {
    id: a.id,
    activityId: a.activityId,
    mime: a.mime,
    bytes: a.bytes,
    uploadState: a.uploadState,
    revision: a.revision,
    createdAt: a.createdAt.getTime(),
    updatedAt: a.updatedAt.getTime(),
    deletedAt: null,
  };
}

/** Kiểm tra chữ ký file (magic bytes) khớp mime khai báo. */
function sniffMatches(mime: string, b: Uint8Array): boolean {
  const ascii = (from: number, to: number) => String.fromCharCode(...b.slice(from, to));
  switch (mime) {
    case "image/jpeg":
      return b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff;
    case "image/png":
      return b[0] === 0x89 && ascii(1, 4) === "PNG";
    case "image/webp":
      return ascii(0, 4) === "RIFF" && ascii(8, 12) === "WEBP";
    case "image/heic":
      return ascii(4, 8) === "ftyp" && /^(heic|heix|hevc|hevx|mif1|msf1|heim|heis)$/.test(ascii(8, 12));
    default:
      return false;
  }
}

async function uploadUrl(a: Attachment) {
  const { token, expiresAt } = await signPurposeToken("upload", { aid: a.id, uid: a.ownerId }, UPLOAD_TTL_SEC);
  return { uploadUrl: `${publicBaseUrl()}/api/v1/uploads/${token}`, uploadMethod: "PUT", uploadHeaders: { "Content-Type": a.mime }, expiresAt };
}

export const attachmentService = {
  async requestUpload(userId: string, activityId: string, raw: unknown) {
    const input = requestAttachmentSchema.parse(raw);
    const activity = await activityRepository.findOwned(userId, activityId);
    if (!activity) throw notFound("Activity");

    const owner = await attachmentRepository.ownerOf(input.id);
    if (owner && owner !== userId) throw notFound("Attachment");
    if (owner) {
      const existing = (await attachmentRepository.findOwned(userId, input.id, { includeDeleted: true }))!;
      if (existing.deletedAt) throw conflict("attachment_deleted", "Attachment was deleted");
      if (existing.activityId !== activityId || existing.mime !== input.mime || existing.bytes !== input.bytes) {
        throw conflict("attachment_conflict", "Attachment id already used with different metadata");
      }
      if (existing.uploadState === "uploaded") return { attachment: toAttachmentDto(existing), upload: null };
      return { attachment: toAttachmentDto(existing), upload: await uploadUrl(existing) };
    }
    if ((await attachmentRepository.countLiveForActivity(userId, activityId)) >= MAX_PER_ACTIVITY) {
      throw unprocessable("attachment_limit", `At most ${MAX_PER_ACTIVITY} attachments per activity`);
    }
    try {
      const created = await attachmentRepository.create({
        id: input.id,
        activityId,
        ownerId: userId,
        mime: input.mime,
        bytes: input.bytes,
        sha256: input.sha256 ?? null,
        storageKey: `attachments/${userId}/${activityId}/${input.id}`,
      });
      return { attachment: toAttachmentDto(created), upload: await uploadUrl(created) };
    } catch (err) {
      if (isUniqueViolation(err)) throw conflict("attachment_conflict", "Attachment id already exists");
      throw err;
    }
  },

  /** PUT tới URL ký số: token chứa attachmentId + userId; vẫn truy vấn theo owner. */
  async receiveUpload(token: string, contentType: string | null, bytes: Uint8Array) {
    const claims = await verifyPurposeToken("upload", token);
    if (!claims || typeof claims.aid !== "string" || typeof claims.uid !== "string") throw notFound("Upload");
    const a = await attachmentRepository.findOwned(claims.uid, claims.aid);
    if (!a || a.uploadState !== "pending") throw notFound("Upload");
    if (contentType?.split(";")[0]?.trim() !== a.mime) throw unprocessable("mime_mismatch", "Content-Type does not match declared mime");
    if (bytes.byteLength !== a.bytes || bytes.byteLength > MAX_ATTACHMENT_BYTES) {
      throw unprocessable("size_mismatch", "Uploaded size does not match declared bytes");
    }
    if (!sniffMatches(a.mime, bytes)) throw unprocessable("content_mismatch", "File content does not match declared mime");
    const digest = sha256Hex(bytes);
    if (a.sha256 && a.sha256 !== digest) throw unprocessable("checksum_mismatch", "Checksum does not match");
    await storage().put(a.storageKey, bytes);
    await attachmentRepository.update(a.ownerId, a.id, { sha256: digest });
  },

  async complete(userId: string, id: string) {
    return runInTransaction(async (tx) => {
      const a = await attachmentRepository.findOwned(userId, id, {}, tx);
      if (!a) throw notFound("Attachment");
      if (a.uploadState === "uploaded") return toAttachmentDto(a);
      if (!(await storage().exists(a.storageKey))) throw conflict("upload_missing", "File has not been uploaded yet");
      await attachmentRepository.update(userId, id, { uploadState: "uploaded", revision: a.revision + 1 }, tx);
      await changeLogRepository.record(userId, "attachment", id, "upsert", tx);
      return toAttachmentDto((await attachmentRepository.findOwned(userId, id, {}, tx))!);
    });
  },

  async list(userId: string, activityId: string) {
    const activity = await activityRepository.findOwned(userId, activityId);
    if (!activity) throw notFound("Activity");
    const rows = await attachmentRepository.listForActivity(userId, activityId);
    return { items: rows.map(toAttachmentDto), nextCursor: null };
  },

  async downloadUrl(userId: string, id: string) {
    const a = await attachmentRepository.findOwned(userId, id);
    if (!a || a.uploadState !== "uploaded") throw notFound("Attachment");
    const { token, expiresAt } = await signPurposeToken("download", { aid: a.id, uid: userId }, DOWNLOAD_TTL_SEC);
    return { url: `${publicBaseUrl()}/api/v1/files/${token}`, expiresAt };
  },

  async serve(token: string) {
    const claims = await verifyPurposeToken("download", token);
    if (!claims || typeof claims.aid !== "string" || typeof claims.uid !== "string") throw notFound("File");
    const a = await attachmentRepository.findOwned(claims.uid, claims.aid);
    if (!a || a.uploadState !== "uploaded") throw notFound("File");
    const bytes = await storage().get(a.storageKey);
    if (!bytes) throw notFound("File");
    return { bytes, mime: a.mime };
  },

  async remove(userId: string, id: string) {
    const a = await attachmentRepository.findOwned(userId, id, { includeDeleted: true });
    if (!a) throw notFound("Attachment");
    if (a.deletedAt) return toAttachmentDto(a);
    await runInTransaction(async (tx) => {
      await attachmentRepository.update(userId, id, { deletedAt: new Date(), revision: a.revision + 1 }, tx);
      await changeLogRepository.record(userId, "attachment", id, "delete", tx);
    });
    await storage().delete(a.storageKey);
    return toAttachmentDto((await attachmentRepository.findOwned(userId, id, { includeDeleted: true }))!);
  },
};
