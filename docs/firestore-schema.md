# Firestore schema

Quyết định chủ sản phẩm 2026-10-19: bỏ backend, dùng Firebase Auth + Cloud Firestore. Đây là **hợp đồng dữ liệu**; sửa schema thì sửa luôn
`firestore.rules` và `firestore.indexes.json`. Backend cũ (Next.js/Prisma) đã bỏ và xóa khỏi repo; mã cũ xem lịch sử git.

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
`clubs/{clubId}` → `{name, nameLower, description, region, visibility ('public'|'private'), memberCount, ownerId, createdAt, rulesText?, groupGoal?, archivedAt?, pinnedPostId?, isDevFixture?}` — owner/admin sửa được name/nameLower/description/region/visibility/rulesText (TM04; `rulesText` ≤ 1000)
`pinnedPostId` (TM04): owner/admin ghim một bài lên đầu feed (null = bỏ ghim).
`archivedAt` (TM04): owner giải tán = lưu trữ một chiều; sau đó rules chặn thành viên mới, bài đăng, sự kiện, mã mời (`clubOpen`); tìm kiếm
bỏ club đã lưu trữ; thành viên vẫn đọc và rời được. Xóa hẳn dữ liệu cần Cloud Functions (ADR 0003).
`groupGoal` (TM22, owner/admin đặt/gỡ) → `{period ('week'|'month'), metric ('distance'|'count'|'time'), target (m / buổi / ms), weekStart (1–7)}`.
`clubs/{clubId}/memberStats/{uid}` (TM21/TM22) → `{userId, displayName, days: {YYYY-MM-DD: {a: đạt mục tiêu ngày, d: m, n: số buổi, t: ms}}, updatedAt}`
— mỗi thành viên active TỰ bật chia sẻ rồi tự ghi (≤ 62 ngày; chỉ hoạt động hợp lệ cho nhóm, không riêng tư/tọa độ/số bước thô); tắt = xóa
document. Thành viên active đọc; app ghi lại mỗi lần mở (Home). Chuỗi nhóm = ngày mọi người đang chia sẻ đều đạt.
— tạo từ app (TM01) trong một transaction cùng `members/{uid}` (role `owner`) và `clubQuota/{uid}`; tên 3–40, mô tả ≤ 300, vùng ≤ 60.
`clubs/{clubId}/members/{uid}` → `{userId, clubId, role ('owner'|'admin'|'member'), status ('active'|'pending'), displayName, joinedAt, inviteCode?}`
— tự vào: club công khai `active`, riêng `pending`; có mã mời → `active` (TM03). Owner/admin duyệt, xóa; owner đổi vai trò và chuyển quyền chủ (TM02).
`clubs/{clubId}/bans/{uid}` → `{bannedBy, createdAt}` (owner/admin ghi; người bị cấm không vào lại được)
`clubQuota/{uid}` → `{count, lastCreatedAt (Timestamp)}` — hạn mức tạo club: tối đa 5, cách nhau ≥ 1 giờ; không xóa được.
`clubInvites/{code}` (8 ký tự `A–Z 2–9` bỏ I/L/O/0/1) → `{clubId, createdBy, createdAt, expiresAt (ms), maxUses (≤ 100), uses}` — hạn ≤ 30 ngày;
`uses` chỉ tăng 1 trong cùng transaction người dùng vào club bằng mã đó.
`posts/{postId}` → `{clubId, authorId, authorName, text, createdAt, cheerCount, commentCount, deletedAt|null, activity?}` — `activity` (TM06) chỉ gồm `{id, type, title, startedAt, distanceM?, distanceEstimated, movingMs, avgPaceSecPerKm?, steps?}`: không tọa độ, không bản đồ, không ghi chú (rules chặn khóa khác)
`posts/{postId}/cheers/{uid}` → `{createdAt}`
`posts/{postId}/comments/{commentId}` → `{authorId, authorName, text, createdAt, deletedAt|null}`
`events/{eventId}` → `{clubId, title, description, location, startsAt, endsAt|null, tzId, maxGoing|null, createdBy, goingCount, cancelledAt|null, createdAt, updatedAt}`
— TM05: owner/admin tạo (giờ trong tương lai, `goingCount` = 0); người tạo hoặc owner/admin sửa trước giờ bắt đầu (không hạ `maxGoing` dưới
số đã đăng ký) và hủy; `goingCount` không vượt `maxGoing`. Bản sao `users/{uid}/eventRsvps/{eventId}` `{clubId, createdAt}` để lên lịch nhắc
cục bộ 1 ngày / 1 giờ trước (giờ đọc lại từ `events/{id}` nên sửa giờ vẫn đúng).
`events/{eventId}/rsvps/{uid}` → `{createdAt, displayName}` (danh sách người tham gia)
`challenges/{id}` → `{title, description, metric ('distance'|'count'|'time'), target (m / lần / ms), startsAt, endsAt, participantCount, isDevFixture?}`
Thử thách của club (TM31) thêm `{clubId, createdBy, startDate, endDate, tzId, activityTypes: ['run','walk'], createdAt, cancelledAt?}`: owner/admin
club tạo (kỳ ≤ 93 ngày, chưa kết thúc, `participantCount` = 0); chỉ thành viên active tham gia; hủy (`cancelledAt`) trước `startsAt`.
Danh sách: `where clubId == X orderBy endsAt desc` (index `challenges(clubId, endsAt desc)`); danh sách chung bỏ thử thách có `clubId`.
Đội (TM32): `challenges/{id}/teams/{teamId}` → `{name (1–30), color (0–7), createdBy, createdAt}` — owner/admin club tạo trước hạn khóa.
Participant thêm `teamId?`, `teamChanges?`: chọn đội lần đầu tự do, đổi tối đa 1 lần, khóa 48 giờ trước `endsAt` (rules `teamsOpen`); không
gửi `teamId` khi tham gia. Vào đội = thành viên club đọc được tiến độ của mình (query `participants where teamId == X`). Điểm đội = trung bình
mỗi người, tính ở client.
Vòng đời (TM33): sắp diễn ra (< `startsAt`) → đang diễn ra (≤ `endsAt`) → chờ đồng bộ 48 giờ → khóa. Participant chỉ sửa tiến độ
hoặc rời tới hết thời gian chờ (rules `challengeOpen`); `leaderboardOptIn`/`displayName` đổi lúc nào cũng được. Kỳ là mốc tuyệt đối
(UTC ms) nên mọi múi giờ cùng một cửa sổ; hoạt động tính theo `startedAt`, không theo lúc đồng bộ.
+ tùy chọn `activityTypes[]` (mặc định run/walk/indoorRun), `tzId`, `startDate`/`endDate` (YYYY-MM-DD), `badgeKey`.
Tiến độ tính ở client từ hoạt động cục bộ trong `[startsAt, endsAt]` rồi ghi `progressValue`/`completedAt` vào participant.
Quan hệ tham gia của tôi đọc từ `users/{uid}/challengeJoins/{id}`. Các trường tùy chọn khác: `clubs.nameLower`, `routes.nameLower`/`attribution`, `events.endsAt`/`tzId`.
Xóa comment cần cả `postId` (đường dẫn `posts/{postId}/comments/{id}`) và giảm `commentCount` của post.
`challenges/{id}/participants/{uid}` → `{userId, joinedAt, leaderboardOptIn, displayName, progressValue, progressUpdatedAt}`
— bảng xếp hạng (TM30) query `leaderboardOptIn == true` sắp `progressValue` giảm dần, đồng điểm theo `progressUpdatedAt` tăng dần.
Tiến độ chỉ cộng hoạt động hợp lệ cho nhóm (`utils/calc/group_eligibility.dart`, ADR 0003).
`routes/{id}` → `{name, description, region, distanceM, surface, polyline, createdAt, isDevFixture?}` (chỉ Admin SDK ghi)
`reports/{id}` → `{reporterId, targetType (post | comment | user | challenge_result — khiếu nại kết quả TM41), targetId, reason, createdAt}` (chỉ tạo)
`feedback/{id}` → `{uid, message, diagnostics, appVersion, createdAt}` (chỉ tạo)

## Live sharing
`liveShares/{shareId}` → `{ownerId, activityId, viewerIds[], startedAt, expiresAt, status ('active'|'paused'|'ended'), endedAt|null,
lastPoint {t, lat, lon, accuracyM?}|null, lastPointAt}` — chỉ lưu **điểm mới nhất** (ghi đè), không lưu lịch sử.

## Việc server từng làm, giờ làm ở client
| Trước (backend cũ, đã bỏ) | Nay |
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
