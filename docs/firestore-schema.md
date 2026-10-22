# Firestore schema (thay backend Next.js/Prisma)

Quyết định chủ sản phẩm 2026-10-19: bỏ backend, dùng Firebase Auth + Cloud Firestore. Đây là **hợp đồng dữ liệu**; sửa schema thì sửa luôn
`firestore.rules` và `firestore.indexes.json`. Backend cũ ở `backend/` không còn được app gọi.

Quy ước chung:
- Thời gian lưu **epoch ms (int)**, giống API cũ. Trường đồng bộ dùng thêm `serverUpdatedAt` (Firestore `Timestamp`, `FieldValue.serverTimestamp()`).
- `uid` = Firebase Auth uid. ID bản ghi do client sinh (UUID v4) → ghi lại cùng ID là idempotent.
- Mọi lỗi Firebase đi qua `guardFirebase` / `mapFirebaseError` (`lib/services/application/api_client.dart`) thành `ApiException`.
- Không bao giờ ghi token/mật khẩu vào Firestore.

## Người dùng
`users/{uid}`
- `displayName`, `email`, `emailLower`, `createdAt` (ms)
- `profile` (map, đúng như `profilePayloadForServer`), `profileRevision` (int), `profileUpdatedAt` (ms)
- `deletionRequestedAt` (ms, tùy chọn)

`userLookup/{emailLower}` → `{uid, displayName}` (để chia sẻ live theo email; chỉ chủ sở hữu ghi, người đăng nhập đọc được).

`users/{uid}/goals/{goalId}` → `{type, value, effectiveFrom, createdAt}` (append-only)

`users/{uid}/activities/{activityId}` → các khóa của `activityBodyForServer` + `revision` (int, tăng 1 mỗi lần ghi),
`updatedAt` (ms), `serverUpdatedAt` (Timestamp), `deletedAt` (ms | null — tombstone, không xóa document).

`users/{uid}/activities/{activityId}/trackChunks/{seq}` (`seq` đệm 5 chữ số, vd `00000`) → `{seq, count, sha256, json}`;
`json` là chuỗi JSON của một chunk như `buildTrackChunks` (tối đa 500 điểm/chunk để document < 1 MiB).

`users/{uid}/blocks/{blockedUid}` → `{createdAt}`
`users/{uid}/savedRoutes/{routeId}` → `{savedAt}`
`users/{uid}/challengeJoins/{challengeId}` → `{joinedAt, leaderboardOptIn, status}`

## Explore
`clubs/{clubId}` → `{name, description, region, visibility ('public'|'private'), memberCount, ownerId, createdAt, isDevFixture?}`
`clubs/{clubId}/members/{uid}` → `{userId, clubId, role ('owner'|'admin'|'member'), status ('active'|'pending'), displayName, joinedAt}`
`posts/{postId}` → `{clubId, authorId, authorName, text, createdAt, cheerCount, commentCount, deletedAt|null}`
`posts/{postId}/cheers/{uid}` → `{createdAt}`
`posts/{postId}/comments/{commentId}` → `{authorId, authorName, text, createdAt, deletedAt|null}`
`events/{eventId}` → `{clubId, title, description, startsAt, location, createdBy, goingCount, cancelledAt|null}`
`events/{eventId}/rsvps/{uid}` → `{createdAt}`
`challenges/{id}` → `{title, description, metric ('distance'|'count'|'time'), target (m / lần / ms), startsAt, endsAt, participantCount, isDevFixture?}`
+ tùy chọn `activityTypes[]` (mặc định run/walk/indoorRun), `tzId`, `startDate`/`endDate` (YYYY-MM-DD), `badgeKey`.
Tiến độ tính ở client từ hoạt động cục bộ trong `[startsAt, endsAt]` rồi ghi `progressValue`/`completedAt` vào participant.
Quan hệ tham gia của tôi đọc từ `users/{uid}/challengeJoins/{id}`. Các trường tùy chọn khác: `clubs.nameLower`, `routes.nameLower`/`attribution`, `events.endsAt`/`tzId`.
Xóa comment cần cả `postId` (đường dẫn `posts/{postId}/comments/{id}`) và giảm `commentCount` của post.
`challenges/{id}/participants/{uid}` → `{userId, joinedAt, leaderboardOptIn, displayName, progressValue, progressUpdatedAt}`
`routes/{id}` → `{name, description, region, distanceM, surface, polyline, createdAt, isDevFixture?}` (chỉ Admin SDK ghi)
`reports/{id}` → `{reporterId, targetType, targetId, reason, createdAt}` (chỉ tạo)
`feedback/{id}` → `{uid, message, diagnostics, appVersion, createdAt}` (chỉ tạo)

## Live sharing
`liveShares/{shareId}` → `{ownerId, activityId, viewerIds[], startedAt, expiresAt, status ('active'|'paused'|'ended'), endedAt|null,
lastPoint {t, lat, lon, accuracyM?}|null, lastPointAt}` — chỉ lưu **điểm mới nhất** (ghi đè), không lưu lịch sử.

## Việc server từng làm, giờ làm ở client
| Trước (backend) | Nay |
|---|---|
| JWT/refresh/bcrypt | Firebase Auth (Google + Email/Password) |
| Verify/reset email | Firebase gửi mail (`sendEmailVerification`, `sendPasswordResetEmail`) |
| `sync/push` + revision | Transaction Firestore kiểm `revision` |
| `sync/pull` cursor | Query `serverUpdatedAt > cursor` |
| Track chunk upload | Subcollection `trackChunks` |
| Export zip / xóa tài khoản (job) | Client gom dữ liệu thành JSON / xóa từng subcollection rồi `user.delete()` |
| Rate limit | Không có (rủi ro: dùng Firebase App Check + hạn mức Firestore) |
| Leaderboard / seed | Seed bằng `scripts/seed-firestore.mjs` (Admin SDK) |

## Triển khai
```bash
firebase deploy --only firestore:rules,firestore:indexes --project app-runing-667b3
```
Cần bật **Cloud Firestore** (Native mode) trong Firebase Console trước.
