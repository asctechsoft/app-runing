# Domain model và quy ước dữ liệu (C02, C04)

Dùng cho mobile (sqflite) và dữ liệu đám mây trên Firestore (xem `docs/firestore-schema.md`). Tên field camelCase trong JSON/Dart, snake_case trong cột SQLite mobile.

## Quy ước chung
- ID: UUID v4 do **client** sinh (`clientId` = `id`) để idempotent.
- Khoảng cách: **mét** (double). Thời lượng: **mili giây** (int). Timestamp: **UTC epoch ms** (int) + `tzId` (IANA) + `tzOffsetMin` tại thời điểm ghi.
- Mọi bản ghi người dùng có `ownerId` (userId hoặc `guest:<uuid>`), `createdAt`, `updatedAt`, `revision` (int, tăng khi sửa), `deletedAt` (tombstone, nullable).
- Thiếu dữ liệu = `null`, **không** dùng 0. Có trường `source` và `quality` khi liên quan.
- Đơn vị hiển thị (km/mi, kg/lb, cm/ft-in) chỉ là setting hiển thị.

## Thực thể

| Thực thể | Trường chính |
|---|---|
| User | id, email, emailVerifiedAt, displayName, avatarKey, createdAt |
| GuestProfile (mobile) | id (`guest:<uuid>`), displayName, createdAt |
| Profile/Settings | ownerId, displayName, heightCm?, weightKg?, activityLevel?(`new`/`occasional`/`regular`/`active`), runningExperience?, distanceUnit(`km`/`mi`), weightUnit(`kg`/`lb`), heightUnit(`cm`/`ftin`), weekStart(1=Mon), locale, audioCues{enabled, everyKm, voice}, autoPause(bool), revision |
| GoalVersion | id, ownerId, type(`dailySteps`/`weeklyRuns`/`weeklyDistanceM`), value, effectiveFrom (local date `YYYY-MM-DD`), createdAt. Ngày D dùng version có effectiveFrom ≤ D mới nhất. |
| StepSample | id, ownerId, source(`phoneSensor`/`healthConnect`/`healthKit`/`device:<id>`), startAt, endAt, steps, tzId |
| StepDay | ownerId, date (local), steps?, status(`noPermission`/`noData`/`verifiedZero`/`populated`), sourceUsed, lastSampleAt, hourly[24]? |
| Activity | id, ownerId, type(`run`/`walk`/`indoorRun`), status(`recording`/`paused`/`awaitingSave`/`saved`/`discarded`/`recoveryNeeded`), startedAt, endedAt, tzId, tzOffsetMin, distanceM?, movingMs, elapsedMs, avgPaceSecPerKm?, steps?, caloriesKcal?, calorieModel?, weightKgUsed?, title, feeling(`easy`/`steady`/`hard`)?, notes?, privacy(`onlyMe`/`followers`/`public`, mặc định onlyMe), goal{type: free/distance/time, value?}, hasGps, distanceSource(`gps`/`steps`/`manual`), workoutExecutionId?, syncState(`local`/`pending`/`synced`/`error`), revision, deletedAt |
| TrackSegment | id, activityId, seq, startedAt, endedAt?, reason(`start`/`resume`/`gpsGap`/`recovery`) |
| TrackPoint | activityId, segmentId, seq, t (UTC ms), lat, lon, accuracyM?, altitudeM?, speedMps?, accepted(bool), rejectReason? |
| SessionEvent | id, activityId, seq, type(`start`/`pause`/`resume`/`autoPause`/`autoResume`/`gpsLost`/`gpsRecovered`/`lock`/`unlock`/`finish`/`recovered`/`phaseStart`), t (UTC ms), monoMs (đồng hồ đơn điệu từ lúc start) |
| Split | activityId, index, distanceM (1000 hoặc lẻ ở cuối), movingMs, paceSecPerKm |
| Attachment | id, activityId, ownerId, localPath?, remoteKey?, mime, bytes, uploadState(`pending`/`uploaded`/`error`) |
| SyncOperation (outbox) | id, ownerId, entity, entityId, op(`upsert`/`delete`), payload JSON, idempotencyKey, state(`pending`/`sending`/`acked`/`error`), attempts, nextAttemptAt, lastError |
| WorkoutPlan / IntervalStep | id, ownerId, name, steps[{kind: warmup/run/walk/rest/cooldown/repeat, durationMs?, distanceM?, repeat?, children?}] |
| WorkoutExecution / PhaseResult | id, activityId, planSnapshot, phases[{index, kind, plannedMs, actualMs, distanceM, completed}], incomplete(bool) |
| Device | id, ownerId, kind(`bleHeartRate`), name, remoteId, connectedAt, revokedAt |
| HeartRateSample | activityId, t, bpm, deviceId |
| Club / Membership / ClubPost / Comment / Cheer / Report / Block / ClubEvent / Rsvp | xem `docs/firestore-schema.md` |
| Challenge / ChallengeParticipant | ruleVersion, activityTypes[], startDate, endDate, tzId, targetType(distance/count/time), targetValue |
| Route / SavedRoute | polyline (encoded), distanceM, surface, region, attribution |
| LiveShare | id, activityId, ownerId, viewerIds[], startedAt, expiresAt, stoppedAt, lastPoint?, lastUpdateAt |
| NotificationItem | id, ownerId, kind, title, body, deepLink, createdAt, readAt |

## Quy tắc tính (Full_luong §11)
- Distance GPS = tổng khoảng cách Haversine giữa các point **accepted** liên tiếp **trong cùng segment**. Point bị loại khi accuracy > 30 m, hoặc tốc độ suy ra > 12 m/s (run) / 4 m/s (walk), hoặc nhảy > 100 m trong < 3 s.
- Moving time = tổng khoảng `recording` (start/resume → pause/autoPause/finish), đo bằng monotonic.
- Elapsed = endedAt − startedAt.
- Avg pace = movingMs / distanceM (giây/km); `null` nếu distance < 10 m.
- Split: nội suy tại mốc mỗi 1000 m theo thời gian moving; split cuối có distance lẻ thật.
- Calo (met-v1): chỉ khi có weightKg; kcal = MET(speed) × weightKg × movingHours. Lưu `calorieModel` và `weightKgUsed`.
- Steps-derived distance = steps × strideM (heightCm × 0.415 / 100 nếu có height, nếu không thì **không tính**); luôn gắn estimated.
- Bước ngày không cộng bước của run (run steps lấy từ cùng sensor, chỉ là view).
- Tuần bắt đầu thứ Hai (cấu hình được). Run qua nửa đêm thuộc ngày bắt đầu.
