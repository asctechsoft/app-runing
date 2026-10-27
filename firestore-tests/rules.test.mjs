// FB03: test firestore.rules bằng Firestore Emulator. Mỗi collection trong docs/firestore-schema.md có ca "được phép" và "bị chặn".
// Chạy: cd firestore-tests && npm install && npm run test:emulator   (Java 11+; firebase-tools 13 ghim trong devDependencies)
//
// Gọi REST API của emulator (HTTP/1.1) thay vì SDK web: SDK dùng gRPC/HTTP2 và bị treo trên máy có phần mềm bảo mật chặn
// luồng HTTP/2 tới localhost. Xác thực bằng token giả không ký — cách emulator chấp nhận (giống @firebase/rules-unit-testing).
import { after, before, beforeEach, describe, test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const PROJECT = 'demo-stride';
const HOST = process.env.FIRESTORE_EMULATOR_HOST ?? '127.0.0.1:8080';
const BASE = `http://${HOST}/v1/projects/${PROJECT}/databases/(default)/documents`;

// ---------- token giả ----------
const b64 = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
function token(uid) {
  const now = Math.floor(Date.now() / 1000);
  return `${b64({ alg: 'none', typ: 'JWT' })}.${b64({
    iss: `https://securetoken.google.com/${PROJECT}`,
    aud: PROJECT,
    iat: now,
    exp: now + 3600,
    auth_time: now,
    sub: uid,
    user_id: uid,
    firebase: { sign_in_provider: 'custom', identities: {} },
  })}.`;
}

// ---------- mã hóa giá trị Firestore ----------
function enc(v) {
  if (v === null) return { nullValue: null };
  if (typeof v === 'boolean') return { booleanValue: v };
  if (typeof v === 'number') return Number.isInteger(v) ? { integerValue: String(v) } : { doubleValue: v };
  if (typeof v === 'string') return { stringValue: v };
  if (Array.isArray(v)) return { arrayValue: { values: v.map(enc) } };
  return { mapValue: { fields: Object.fromEntries(Object.entries(v).map(([k, x]) => [k, enc(x)])) } };
}
const fields = (data) => Object.fromEntries(Object.entries(data).map(([k, v]) => [k, enc(v)]));

async function call(uid, method, path, body) {
  const headers = { 'Content-Type': 'application/json' };
  if (uid === 'owner') headers.Authorization = 'Bearer owner'; // bỏ qua rules (vai trò Admin SDK)
  else if (uid) headers.Authorization = `Bearer ${token(uid)}`;
  const res = await fetch(`${BASE}/${path}`, { method, headers, body: body ? JSON.stringify(body) : undefined });
  await res.text();
  return res.status;
}

/** Client của một người dùng (uid null = chưa đăng nhập). Trả HTTP status. */
const as = (uid) => ({
  get: (path) => call(uid, 'GET', path),
  list: (path) => call(uid, 'GET', path),
  set: (path, data) => call(uid, 'PATCH', path, { fields: fields(data) }),
  update: (path, data) =>
    call(uid, 'PATCH', `${path}?${Object.keys(data).map((k) => `updateMask.fieldPaths=${k}`).join('&')}&currentDocument.exists=true`, {
      fields: fields(data),
    }),
  delete: (path) => call(uid, 'DELETE', path),
});

/** Ghi nhiều document nguyên tử (như transaction/batch của SDK). `serverTime` = các trường đặt bằng giờ server. */
async function commit(uid, writes) {
  const root = `projects/${PROJECT}/databases/(default)/documents`;
  const headers = { 'Content-Type': 'application/json', Authorization: `Bearer ${token(uid)}` };
  const body = {
    writes: writes.map(({ path, data, serverTime = [] }) => ({
      update: { name: `${root}/${path}`, fields: fields(data) },
      ...(serverTime.length ? { updateTransforms: serverTime.map((f) => ({ fieldPath: f, setToServerValue: 'REQUEST_TIME' })) } : {}),
    })),
  };
  const res = await fetch(`http://${HOST}/v1/${root}:commit`, { method: 'POST', headers, body: JSON.stringify(body) });
  await res.text();
  return res.status;
}

/** Query một collection con với điều kiện bằng (runQuery) — như `.where(field, isEqualTo: v)` của SDK. */
async function query(uid, parent, collectionId, where = {}) {
  const root = `projects/${PROJECT}/databases/(default)/documents`;
  const filters = Object.entries(where).map(([k, v]) => ({ fieldFilter: { field: { fieldPath: k }, op: 'EQUAL', value: enc(v) } }));
  const structuredQuery = {
    from: [{ collectionId }],
    ...(filters.length ? { where: filters.length === 1 ? filters[0] : { compositeFilter: { op: 'AND', filters } } } : {}),
  };
  const headers = { 'Content-Type': 'application/json', Authorization: `Bearer ${token(uid)}` };
  const res = await fetch(`http://${HOST}/v1/${root}/${parent}:runQuery`, { method: 'POST', headers, body: JSON.stringify({ structuredQuery }) });
  await res.text();
  return res.status;
}

const ok = async (p) => assert.ok((await p) < 300, 'mong đợi được phép');
const denied = async (p) => assert.equal(await p, 403, 'mong đợi bị chặn (PERMISSION_DENIED)');
const seed = (path, data) => ok(as('owner').set(path, data));

// ---------- vòng đời ----------
before(async () => {
  const rules = readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8');
  const res = await fetch(`http://${HOST}/emulator/v1/projects/${PROJECT}:securityRules`, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ rules: { files: [{ name: 'firestore.rules', content: rules }] } }),
  });
  assert.equal(res.status, 200, await res.text());
});
beforeEach(async () => {
  const res = await fetch(`http://${HOST}/emulator/v1/projects/${PROJECT}/databases/(default)/documents`, { method: 'DELETE' });
  assert.equal(res.status, 200);
});
after(() => {});

// ---------- test ----------
describe('users/{uid} — chỉ chủ sở hữu', () => {
  test('chủ đọc/ghi hồ sơ và subcollection', async () => {
    await ok(as('alice').set('users/alice', { displayName: 'A' }));
    await ok(as('alice').set('users/alice/activities/a1', { distanceM: 5000 }));
    await ok(as('alice').get('users/alice/activities/a1'));
  });
  test('người lạ không đọc/ghi hoạt động của người khác; chưa đăng nhập bị chặn', async () => {
    await seed('users/alice', { displayName: 'A' });
    await seed('users/alice/activities/a1', { distanceM: 5000 });
    await denied(as('bob').get('users/alice'));
    await denied(as('bob').set('users/alice', { displayName: 'hacked' }));
    await denied(as('bob').get('users/alice/activities/a1'));
    await denied(as('bob').set('users/alice/activities/a2', { distanceM: 1 }));
    await denied(as(null).get('users/alice'));
  });
});

describe('userLookup/{emailLower}', () => {
  test('tự ghi bản ghi của mình; người đăng nhập get được', async () => {
    await ok(as('alice').set('userLookup/a@x.com', { uid: 'alice' }));
    await ok(as('bob').get('userLookup/a@x.com'));
  });
  test('không ghi thay người khác, không liệt kê, không xóa của người khác', async () => {
    await denied(as('bob').set('userLookup/a@x.com', { uid: 'alice' }));
    await seed('userLookup/a@x.com', { uid: 'alice' });
    await denied(as('bob').list('userLookup'));
    await denied(as('bob').delete('userLookup/a@x.com'));
    await denied(as(null).get('userLookup/a@x.com'));
  });
});

describe('clubs + members', () => {
  beforeEach(() => seed('clubs/c1', { name: 'Club', visibility: 'public', memberCount: 1 }));
  test('đọc club; tăng memberCount đúng 1; tự vào với vai trò member rồi rời', async () => {
    await ok(as('bob').get('clubs/c1'));
    await ok(as('bob').update('clubs/c1', { memberCount: 2 }));
    await ok(as('bob').set('clubs/c1/members/bob', { userId: 'bob', role: 'member', status: 'active' }));
    await ok(as('bob').delete('clubs/c1/members/bob'));
  });
  test('không tạo club ngoài luồng, không nhảy memberCount, không đổi tên; không tự nâng quyền, không thêm người khác', async () => {
    await denied(as('bob').set('clubs/c2', { name: 'Mine', memberCount: 0 }));
    await denied(as('bob').update('clubs/c1', { memberCount: 50 }));
    await denied(as('bob').update('clubs/c1', { name: 'Hacked' }));
    await denied(as('bob').set('clubs/c1/members/bob', { userId: 'bob', role: 'owner', status: 'active' }));
    await denied(as('bob').set('clubs/c1/members/carol', { userId: 'carol', role: 'member' }));
    await seed('clubs/c1/members/bob', { userId: 'bob', role: 'member', status: 'active' });
    await denied(as('bob').update('clubs/c1/members/bob', { role: 'admin' }));
    await denied(as(null).get('clubs/c1'));
  });
  test('club riêng: tự vào chỉ được pending; người bị cấm không vào lại', async () => {
    await seed('clubs/p1', { name: 'Private', visibility: 'private', memberCount: 1 });
    await denied(as('bob').set('clubs/p1/members/bob', { userId: 'bob', role: 'member', status: 'active' }));
    await ok(as('bob').set('clubs/p1/members/bob', { userId: 'bob', role: 'member', status: 'pending' }));
    await seed('clubs/c1/bans/eve', { bannedBy: 'alice' });
    await denied(as('eve').set('clubs/c1/members/eve', { userId: 'eve', role: 'member', status: 'active' }));
  });
});

describe('TM01: tạo club', () => {
  const club = (owner, extra = {}) => ({
    name: 'Morning Crew',
    nameLower: 'morning crew',
    description: 'Easy runs',
    region: 'Hanoi',
    visibility: 'public',
    memberCount: 1,
    ownerId: owner,
    createdAt: 1,
    ...extra,
  });
  const create = (uid, id, { data = club(uid), member = { userId: uid, role: 'owner', status: 'active' }, quota = { count: 1 } } = {}) =>
    commit(uid, [
      { path: `clubQuota/${uid}`, data: quota, serverTime: ['lastCreatedAt'] },
      { path: `clubs/${id}`, data },
      { path: `clubs/${id}/members/${uid}`, data: member },
    ]);

  test('tạo club + owner + hạn mức trong một transaction; hiện trong club của tôi', async () => {
    await ok(create('alice', 'n1'));
    await ok(as('alice').get('clubs/n1/members/alice'));
    await ok(as('alice').get('clubQuota/alice'));
  });
  test('chặn: tạo thay người khác, thiếu bước, dữ liệu sai, vượt hạn mức, tạo quá nhanh, reset hạn mức', async () => {
    await denied(create('bob', 'x1', { data: club('alice') }));
    await denied(commit('bob', [{ path: 'clubs/x2', data: club('bob') }])); // không có member owner + hạn mức
    await denied(create('bob', 'x3', { data: club('bob', { name: 'ab', nameLower: 'ab' }) }));
    await denied(create('bob', 'x4', { data: club('bob', { name: 'A'.repeat(41), nameLower: 'a'.repeat(41) }) }));
    await denied(create('bob', 'x5', { data: club('bob', { memberCount: 99 }) }));
    await denied(create('bob', 'x6', { data: club('bob', { visibility: 'secret' }) }));
    await denied(create('bob', 'x7', { data: club('bob', { verified: true }) }));
    await denied(create('bob', 'x8', { member: { userId: 'bob', role: 'admin', status: 'active' } }));
    await denied(create('bob', 'x9', { quota: { count: 6 } }));
    await ok(create('bob', 'b1'));
    await denied(create('bob', 'b2', { quota: { count: 2 } })); // chưa đủ 1 giờ
    await denied(as('bob').delete('clubQuota/bob'));
    await denied(as('carol').get('clubQuota/bob'));
    // Đã có club → không thể "tạo lại" để chiếm quyền owner.
    await denied(as('carol').set('clubs/b1/members/carol', { userId: 'carol', role: 'owner', status: 'active' }));
  });
});

describe('TM02: quản lý thành viên', () => {
  beforeEach(async () => {
    await seed('clubs/c1', { name: 'Club', visibility: 'private', memberCount: 3, ownerId: 'olly' });
    await seed('clubs/c1/members/olly', { userId: 'olly', role: 'owner', status: 'active' });
    await seed('clubs/c1/members/adam', { userId: 'adam', role: 'admin', status: 'active' });
    await seed('clubs/c1/members/mia', { userId: 'mia', role: 'member', status: 'active' });
    await seed('clubs/c1/members/pete', { userId: 'pete', role: 'member', status: 'pending' });
  });
  test('owner/admin duyệt yêu cầu; owner đổi vai trò; admin từ chối/đuổi member; cấm', async () => {
    await ok(as('adam').update('clubs/c1/members/pete', { status: 'active' }));
    await ok(as('olly').update('clubs/c1/members/mia', { role: 'admin' }));
    await ok(as('olly').update('clubs/c1/members/mia', { role: 'member' }));
    await ok(as('adam').delete('clubs/c1/members/mia'));
    await ok(as('adam').set('clubs/c1/bans/mia', { bannedBy: 'adam' }));
    await ok(as('adam').get('clubs/c1/bans/mia'));
  });
  test('chặn: member duyệt/đuổi, tự nâng quyền, admin đổi vai trò/đuổi owner, owner tự rời', async () => {
    await denied(as('mia').update('clubs/c1/members/pete', { status: 'active' }));
    await denied(as('mia').delete('clubs/c1/members/pete'));
    await denied(as('mia').update('clubs/c1/members/mia', { role: 'admin' }));
    await denied(as('adam').update('clubs/c1/members/mia', { role: 'admin' }));
    await denied(as('adam').update('clubs/c1/members/adam', { role: 'owner' }));
    await denied(as('adam').delete('clubs/c1/members/olly'));
    await denied(as('olly').delete('clubs/c1/members/olly'));
    await denied(as('olly').update('clubs/c1/members/mia', { role: 'owner' })); // phải hạ chính mình cùng lúc
    await denied(as('mia').set('clubs/c1/bans/pete', { bannedBy: 'mia' }));
    await denied(as('mia').get('clubs/c1/bans/pete'));
    await denied(as('adam').update('clubs/c1/members/pete', { status: 'active', role: 'admin' }));
  });
  test('chuyển quyền chủ trong một transaction; owner cũ thành admin rồi mới rời được', async () => {
    await ok(
      commit('olly', [
        { path: 'clubs/c1/members/mia', data: { userId: 'mia', role: 'owner', status: 'active' } },
        { path: 'clubs/c1/members/olly', data: { userId: 'olly', role: 'admin', status: 'active' } },
        { path: 'clubs/c1', data: { name: 'Club', visibility: 'private', memberCount: 3, ownerId: 'mia' } },
      ]),
    );
    await ok(as('olly').delete('clubs/c1/members/olly'));
    await denied(as('adam').update('clubs/c1', { ownerId: 'adam' }));
  });
});

describe('TM04: sửa thông tin club', () => {
  const club = { name: 'Morning Crew', nameLower: 'morning crew', description: '', region: '', visibility: 'public', memberCount: 3, ownerId: 'olly', createdAt: 1 };
  const edit = (extra = {}) => ({ name: 'Evening Crew', nameLower: 'evening crew', description: 'Hi', region: 'HCM', visibility: 'private', rulesText: 'Be kind', ...extra });
  beforeEach(async () => {
    await seed('clubs/c1', club);
    await seed('clubs/c1/members/olly', { userId: 'olly', role: 'owner', status: 'active' });
    await seed('clubs/c1/members/adam', { userId: 'adam', role: 'admin', status: 'active' });
    await seed('clubs/c1/members/mia', { userId: 'mia', role: 'member', status: 'active' });
  });

  test('owner và admin sửa tên, mô tả, vùng, chế độ, nội quy', async () => {
    await ok(as('olly').update('clubs/c1', edit()));
    await ok(as('adam').update('clubs/c1', edit({ rulesText: '' })));
  });

  test('chặn: member/người lạ sửa, sửa owner/bộ đếm kèm theo, nội quy quá dài, nameLower lệch, trường lạ', async () => {
    await denied(as('mia').update('clubs/c1', edit()));
    await denied(as('bob').update('clubs/c1', edit()));
    await denied(as('adam').update('clubs/c1', edit({ ownerId: 'adam' })));
    await denied(as('olly').update('clubs/c1', edit({ memberCount: 99 })));
    await denied(as('olly').update('clubs/c1', edit({ rulesText: 'x'.repeat(1001) })));
    await denied(as('olly').update('clubs/c1', edit({ nameLower: 'other' })));
    await denied(as('olly').update('clubs/c1', edit({ name: 'ab', nameLower: 'ab' })));
    await denied(as('olly').update('clubs/c1', edit({ pinned: true })));
  });
});

describe('TM04: giải tán (lưu trữ) club', () => {
  const club = { name: 'Morning Crew', nameLower: 'morning crew', description: '', region: '', visibility: 'public', memberCount: 2, ownerId: 'olly', createdAt: 1 };
  const H = 3600 * 1000;
  beforeEach(async () => {
    await seed('clubs/c1', club);
    await seed('clubs/c1/members/olly', { userId: 'olly', role: 'owner', status: 'active' });
    await seed('clubs/c1/members/adam', { userId: 'adam', role: 'admin', status: 'active' });
  });
  test('chỉ owner giải tán, một lần; sau đó không ai vào, đăng bài, tạo sự kiện hay mã mời; thành viên vẫn đọc và rời được', async () => {
    await denied(as('adam').update('clubs/c1', { archivedAt: 5 }));
    await ok(as('olly').update('clubs/c1', { archivedAt: 5 }));
    await denied(as('olly').update('clubs/c1', { archivedAt: 6 }));
    await denied(as('bob').set('clubs/c1/members/bob', { userId: 'bob', role: 'member', status: 'active' }));
    await denied(as('adam').set('posts/p9', { clubId: 'c1', authorId: 'adam', text: 'x' }));
    await denied(as('adam').set('events/e9', {
      clubId: 'c1', title: 'Run', description: '', location: '', startsAt: Date.now() + 48 * H, endsAt: null, tzId: 'UTC', maxGoing: null,
      createdBy: 'adam', goingCount: 0, cancelledAt: null, createdAt: 1, updatedAt: 1,
    }));
    await denied(as('olly').set('clubInvites/ARCHIVE2', { clubId: 'c1', createdBy: 'olly', createdAt: 1, expiresAt: Date.now() + H, maxUses: 5, uses: 0 }));
    await ok(as('adam').get('clubs/c1'));
    await ok(as('adam').delete('clubs/c1/members/adam'));
  });
  test('ghim bài: owner/admin ghim và bỏ ghim; thành viên thường không', async () => {
    await seed('clubs/c1/members/mia', { userId: 'mia', role: 'member', status: 'active' });
    await ok(as('adam').update('clubs/c1', { pinnedPostId: 'p1' }));
    await ok(as('olly').update('clubs/c1', { pinnedPostId: null }));
    await denied(as('mia').update('clubs/c1', { pinnedPostId: 'p2' }));
    await denied(as('adam').update('clubs/c1', { pinnedPostId: 5 }));
  });
});

describe('TM21/TM22: số liệu và mục tiêu nhóm', () => {
  const club = { name: 'Morning Crew', nameLower: 'morning crew', description: '', region: '', visibility: 'public', memberCount: 3, ownerId: 'olly', createdAt: 1 };
  const stats = (uid, n = 2) => ({
    userId: uid, displayName: uid, updatedAt: 1,
    days: Object.fromEntries(Array.from({ length: n }, (_, i) => [`2026-10-${String(i + 1).padStart(2, '0')}`, { a: true, d: 5000, n: 1, t: 1 }])),
  });
  const goal = (extra = {}) => ({ period: 'week', metric: 'distance', target: 50000, weekStart: 1, ...extra });
  beforeEach(async () => {
    await seed('clubs/c1', club);
    await seed('clubs/c1/members/olly', { userId: 'olly', role: 'owner', status: 'active' });
    await seed('clubs/c1/members/adam', { userId: 'adam', role: 'admin', status: 'active' });
    await seed('clubs/c1/members/mia', { userId: 'mia', role: 'member', status: 'active' });
    await seed('clubs/c1/members/pete', { userId: 'pete', role: 'member', status: 'pending' });
  });

  test('thành viên tự chia sẻ / tắt; thành viên đọc; owner/admin đặt và gỡ mục tiêu; vẫn sửa club được khi có mục tiêu', async () => {
    await ok(as('mia').set('clubs/c1/memberStats/mia', stats('mia', 62)));
    await ok(as('olly').get('clubs/c1/memberStats/mia'));
    await ok(as('mia').delete('clubs/c1/memberStats/mia'));
    await ok(as('adam').update('clubs/c1', { groupGoal: goal() }));
    await ok(as('olly').update('clubs/c1', { groupGoal: goal({ period: 'month', metric: 'time', target: 3600000 }) }));
    await ok(as('olly').update('clubs/c1', { name: 'Evening Crew', nameLower: 'evening crew', description: '', region: '', visibility: 'public', rulesText: '' }));
  });

  test('chặn: ghi thay người khác, người ngoài/chờ duyệt, quá 62 ngày, trường lạ; người ngoài đọc; member đặt mục tiêu; mục tiêu sai', async () => {
    await denied(as('mia').set('clubs/c1/memberStats/adam', stats('adam')));
    await denied(as('bob').set('clubs/c1/memberStats/bob', stats('bob')));
    await denied(as('pete').set('clubs/c1/memberStats/pete', stats('pete')));
    await denied(as('mia').set('clubs/c1/memberStats/mia', stats('mia', 63)));
    await denied(as('mia').set('clubs/c1/memberStats/mia', { ...stats('mia'), steps: 12000 }));
    await seed('clubs/c1/memberStats/mia', stats('mia'));
    await denied(as('bob').get('clubs/c1/memberStats/mia'));
    await denied(as('mia').update('clubs/c1', { groupGoal: goal() }));
    await denied(as('adam').update('clubs/c1', { groupGoal: goal({ target: 0 }) }));
    await denied(as('adam').update('clubs/c1', { groupGoal: goal({ period: 'day' }) }));
    await denied(as('adam').update('clubs/c1', { groupGoal: goal({ weekStart: 9 }) }));
  });
});

describe('TM03: mã mời club', () => {
  const FAR = Date.now() + 7 * 24 * 3600 * 1000;
  const invite = (extra = {}) => ({ clubId: 'p1', createdBy: 'olly', createdAt: 1, expiresAt: FAR, maxUses: 50, uses: 0, ...extra });
  // `inv` = dữ liệu mã đúng như đã seed (chỉ `uses` đổi), để lần bị chặn là do điều kiện đang kiểm, không do sửa trường khác.
  const join = (uid, code, { inv = invite(), uses = inv.uses + 1, status = 'active', member = null } = {}) =>
    commit(uid, [
      { path: `clubs/p1/members/${uid}`, data: member ?? { userId: uid, role: 'member', status, inviteCode: code } },
      { path: `clubInvites/${code}`, data: { ...inv, uses } },
    ]);
  beforeEach(async () => {
    await seed('clubs/p1', { name: 'Private', visibility: 'private', memberCount: 2, ownerId: 'olly' });
    await seed('clubs/pub', { name: 'Public', visibility: 'public', memberCount: 2, ownerId: 'olly' });
    await seed('clubs/p1/members/olly', { userId: 'olly', role: 'owner', status: 'active' });
    await seed('clubs/p1/members/mia', { userId: 'mia', role: 'member', status: 'active' });
    await seed('clubs/pub/members/mia', { userId: 'mia', role: 'member', status: 'active' });
  });

  test('owner tạo mã; thành viên club công khai tạo mã; người khác dùng mã vào club riêng (active ngay)', async () => {
    await ok(as('olly').set('clubInvites/ABCDEFGH', invite()));
    await ok(as('mia').set('clubInvites/PUBCODE2', invite({ clubId: 'pub', createdBy: 'mia' })));
    await ok(as('bob').get('clubInvites/ABCDEFGH'));
    await ok(join('bob', 'ABCDEFGH'));
    await ok(as('bob').get('clubs/p1/members/bob'));
  });

  test('đang chờ duyệt → dùng mã để thành active', async () => {
    await seed('clubInvites/ABCDEFGH', invite());
    await seed('clubs/p1/members/pete', { userId: 'pete', role: 'member', status: 'pending' });
    await ok(
      commit('pete', [
        { path: 'clubs/p1/members/pete', data: { userId: 'pete', role: 'member', status: 'active', inviteCode: 'ABCDEFGH' } },
        { path: 'clubInvites/ABCDEFGH', data: { ...invite(), uses: 1 } },
      ]),
    );
  });

  test('chặn: thành viên thường tạo mã club riêng, mã quá hạn/quá lượt, dùng mã mà không tăng lượt, mã club khác, liệt kê', async () => {
    await denied(as('mia').set('clubInvites/MIACODE2', invite({ createdBy: 'mia' })));
    await denied(as('bob').set('clubInvites/BOBCODE2', invite({ clubId: 'pub', createdBy: 'bob' })));
    await denied(as('olly').set('clubInvites/LONGLIFE', invite({ expiresAt: Date.now() + 60 * 24 * 3600 * 1000 })));
    await denied(as('olly').set('clubInvites/MANYUSES', invite({ maxUses: 1000 })));
    await denied(as('olly').set('clubInvites/USEDXXXX', invite({ uses: 5 })));

    await seed('clubInvites/EXPIRED2', invite({ expiresAt: 1 }));
    await denied(join('bob', 'EXPIRED2', { inv: invite({ expiresAt: 1 }) }));
    await seed('clubInvites/USEDUP22', invite({ uses: 50 }));
    await denied(join('bob', 'USEDUP22', { inv: invite({ uses: 50 }) }));
    await seed('clubInvites/ABCDEFGH', invite());
    await denied(as('bob').set('clubs/p1/members/bob', { userId: 'bob', role: 'member', status: 'active', inviteCode: 'ABCDEFGH' }));
    await denied(join('bob', 'ABCDEFGH', { uses: 5 }));
    await denied(join('bob', 'ABCDEFGH', { member: { userId: 'bob', role: 'admin', status: 'active', inviteCode: 'ABCDEFGH' } }));
    await seed('clubInvites/PUBCODE3', invite({ clubId: 'pub' }));
    await denied(
      commit('bob', [
        { path: 'clubs/p1/members/bob', data: { userId: 'bob', role: 'member', status: 'active', inviteCode: 'PUBCODE3' } },
        { path: 'clubInvites/PUBCODE3', data: { ...invite({ clubId: 'pub' }), uses: 1 } },
      ]),
    );
    await denied(as('bob').update('clubInvites/ABCDEFGH', { uses: 1 }));
    await denied(as('bob').list('clubInvites'));
    await seed('clubs/p1/bans/eve', { bannedBy: 'olly' });
    await denied(join('eve', 'ABCDEFGH'));
    await denied(as('bob').delete('clubInvites/ABCDEFGH'));
    await ok(as('olly').delete('clubInvites/ABCDEFGH'));
  });
});

describe('posts (+ cheers, comments)', () => {
  beforeEach(async () => {
    await seed('clubs/c1/members/alice', { userId: 'alice', role: 'member', status: 'active' });
    await seed('clubs/c1/members/pending', { userId: 'pending', role: 'member', status: 'pending' });
    await seed('posts/p1', { clubId: 'c1', authorId: 'alice', text: 'hi', cheerCount: 0, commentCount: 0 });
  });
  test('thành viên active đọc, đăng, cheer; tác giả xóa mềm', async () => {
    await ok(as('alice').get('posts/p1'));
    await ok(as('alice').set('posts/p2', { clubId: 'c1', authorId: 'alice', text: 'x' }));
    await ok(as('alice').update('posts/p1', { cheerCount: 1 }));
    await ok(as('alice').update('posts/p1', { deletedAt: 1 }));
    await ok(as('alice').set('posts/p1/cheers/alice', { at: 1 }));
    await ok(as('alice').set('posts/p1/comments/k1', { authorId: 'alice', text: 'ok' }));
  });
  test('người ngoài / chờ duyệt không đọc, không đăng; không sửa nội dung, không đăng thay', async () => {
    await denied(as('stranger').get('posts/p1'));
    await denied(as('pending').get('posts/p1'));
    await denied(as('stranger').set('posts/p3', { clubId: 'c1', authorId: 'stranger', text: 'x' }));
    await denied(as('alice').set('posts/p3', { clubId: 'c1', authorId: 'bob', text: 'x' }));
    await denied(as('alice').update('posts/p1', { text: 'edited' }));
    await denied(as('alice').delete('posts/p1'));
    await denied(as('alice').set('posts/p1/cheers/bob', { at: 1 }));
    await denied(as('alice').set('posts/p1/comments/k2', { authorId: 'bob', text: 'x' }));
  });
  test('TM06: bài có tóm tắt hoạt động; chặn tọa độ/ghi chú/kiểu sai trong activity', async () => {
    const act = { id: 'a1', type: 'run', title: 'Run', startedAt: 1, distanceM: 5000, distanceEstimated: false, movingMs: 1, avgPaceSecPerKm: 330 };
    await ok(as('alice').set('posts/p4', { clubId: 'c1', authorId: 'alice', text: '', activity: act }));
    await denied(as('alice').set('posts/p5', { clubId: 'c1', authorId: 'alice', text: '', activity: { ...act, startLat: 21.0 } }));
    await denied(as('alice').set('posts/p6', { clubId: 'c1', authorId: 'alice', text: '', activity: { ...act, notes: 'private' } }));
    await denied(as('alice').set('posts/p7', { clubId: 'c1', authorId: 'alice', text: '', activity: 'a1' }));
  });
});

describe('events (+ rsvps)', () => {
  const H = 3600 * 1000;
  const ev = (extra = {}) => ({
    clubId: 'c1', title: 'Sunday long run', description: '', location: 'Hoan Kiem', startsAt: Date.now() + 48 * H, endsAt: null,
    tzId: 'Asia/Ho_Chi_Minh', maxGoing: 2, createdBy: 'adam', goingCount: 0, cancelledAt: null, createdAt: 1, updatedAt: 1, ...extra,
  });
  beforeEach(async () => {
    await seed('clubs/c1', { name: 'Club', visibility: 'public', memberCount: 3, ownerId: 'olly' });
    await seed('clubs/c1/members/olly', { userId: 'olly', role: 'owner', status: 'active' });
    await seed('clubs/c1/members/adam', { userId: 'adam', role: 'admin', status: 'active' });
    await seed('clubs/c1/members/alice', { userId: 'alice', role: 'member', status: 'active' });
    await seed('events/e1', ev());
  });
  test('admin tạo; người tạo/owner sửa trước giờ bắt đầu và hủy; thành viên RSVP, tăng goingCount', async () => {
    await ok(as('adam').set('events/e2', ev()));
    await ok(as('adam').update('events/e1', { title: 'Sunday 15K', startsAt: Date.now() + 72 * H, updatedAt: 2 }));
    await ok(as('olly').update('events/e1', { maxGoing: null, updatedAt: 3 }));
    await ok(as('alice').update('events/e1', { goingCount: 1 }));
    await ok(as('alice').set('events/e1/rsvps/alice', { createdAt: 1, displayName: 'Alice' }));
    await ok(as('adam').update('events/e1', { cancelledAt: 5 }));
  });
  test('chặn: thành viên thường/người ngoài tạo, sự kiện trong quá khứ, sửa sau giờ bắt đầu, thành viên sửa, vượt sức chứa, RSVP thay người khác', async () => {
    await denied(as('alice').set('events/e3', ev({ createdBy: 'alice' })));
    await denied(as('stranger').set('events/e3', ev({ createdBy: 'stranger' })));
    await denied(as('stranger').get('events/e1'));
    await denied(as('adam').set('events/e4', ev({ startsAt: Date.now() - H })));
    await denied(as('adam').set('events/e5', ev({ goingCount: 5 })));
    await denied(as('adam').set('events/e6', ev({ endsAt: 1 })));
    await denied(as('alice').update('events/e1', { title: 'Hijacked', updatedAt: 2 }));
    await denied(as('alice').update('events/e1', { cancelledAt: 5 }));
    await seed('events/full', ev({ goingCount: 2 }));
    await denied(as('alice').update('events/full', { goingCount: 3 }));
    await denied(as('adam').update('events/full', { maxGoing: 1, updatedAt: 2 }));
    await seed('events/started', ev({ startsAt: Date.now() - H }));
    await denied(as('adam').update('events/started', { title: 'Late edit', updatedAt: 2 }));
    await denied(as('alice').set('events/e1/rsvps/bob', { createdAt: 1 }));
    await denied(as('alice').set('events/e1/rsvps/alice', { createdAt: 1, lat: 21 }));
    await denied(as('alice').delete('events/e1'));
  });
});

describe('TM31: thử thách của club', () => {
  const DAY = 24 * 3600 * 1000;
  const start = Date.now() + 2 * DAY;
  const ch = (extra = {}) => ({
    clubId: 'c1', createdBy: 'adam', title: 'Crew km', description: '', metric: 'distance', target: 50000,
    startsAt: start, endsAt: start + 30 * DAY, startDate: '2026-11-01', endDate: '2026-11-30', tzId: 'ICT',
    activityTypes: ['run', 'walk'], participantCount: 0, createdAt: 1, ...extra,
  });
  beforeEach(async () => {
    await seed('clubs/c1', { name: 'Club', visibility: 'private', memberCount: 3, ownerId: 'olly' });
    await seed('clubs/c1/members/olly', { userId: 'olly', role: 'owner', status: 'active' });
    await seed('clubs/c1/members/adam', { userId: 'adam', role: 'admin', status: 'active' });
    await seed('clubs/c1/members/mia', { userId: 'mia', role: 'member', status: 'active' });
    await seed('clubs/c1/members/pete', { userId: 'pete', role: 'member', status: 'pending' });
  });

  test('owner/admin tạo; thành viên active tham gia; hủy được trước khi bắt đầu', async () => {
    await ok(as('adam').set('challenges/k1', ch()));
    await ok(as('olly').set('challenges/k2', ch({ createdBy: 'olly', metric: 'count', target: 30 })));
    await ok(as('mia').set('challenges/k1/participants/mia', { userId: 'mia', leaderboardOptIn: false }));
    await ok(as('olly').update('challenges/k1', { cancelledAt: 5 }));
  });

  test('chặn: member/người lạ tạo, tạo thay người khác, quá 93 ngày, indoor, đã kết thúc, đếm sẵn; người ngoài/chờ duyệt tham gia; hủy sau khi bắt đầu', async () => {
    await denied(as('mia').set('challenges/x1', ch({ createdBy: 'mia' })));
    await denied(as('bob').set('challenges/x2', ch({ createdBy: 'bob' })));
    await denied(as('adam').set('challenges/x3', ch({ createdBy: 'olly' })));
    await denied(as('adam').set('challenges/x4', ch({ endsAt: start + 100 * DAY })));
    await denied(as('adam').set('challenges/x5', ch({ activityTypes: ['run', 'walk', 'indoorRun'] })));
    await denied(as('adam').set('challenges/x6', ch({ startsAt: 1, endsAt: 2 })));
    await denied(as('adam').set('challenges/x7', ch({ participantCount: 99 })));
    await denied(as('adam').set('challenges/x8', ch({ metric: 'streak' })));
    await denied(as('adam').set('challenges/x9', ch({ badgeKey: 'gold' })));

    await seed('challenges/k1', ch());
    await denied(as('bob').set('challenges/k1/participants/bob', { userId: 'bob', leaderboardOptIn: false }));
    await denied(as('pete').set('challenges/k1/participants/pete', { userId: 'pete', leaderboardOptIn: false }));
    await denied(as('mia').update('challenges/k1', { cancelledAt: 5 }));
    await denied(as('adam').update('challenges/k1', { title: 'Renamed' }));
    await seed('challenges/started', ch({ startsAt: Date.now() - DAY }));
    await denied(as('olly').update('challenges/started', { cancelledAt: 5 }));
  });
});

describe('TM33: vòng đời thử thách', () => {
  const H = 3600 * 1000;
  const p = (uid) => ({ userId: uid, leaderboardOptIn: false, progressValue: 1000, progressUpdatedAt: 1 });
  beforeEach(async () => {
    await seed('challenges/active', { title: 'a', participantCount: 1, startsAt: 0, endsAt: Date.now() + 24 * H });
    await seed('challenges/grace', { title: 'g', participantCount: 1, startsAt: 0, endsAt: Date.now() - 24 * H });
    await seed('challenges/locked', { title: 'l', participantCount: 1, startsAt: 0, endsAt: Date.now() - 49 * H });
    for (const c of ['active', 'grace', 'locked']) await seed(`challenges/${c}/participants/mia`, p('mia'));
    await seed('clubs/c1', { name: 'Club', visibility: 'public', memberCount: 1, ownerId: 'olly' });
    await seed('challenges/club', { title: 'c', participantCount: 1, startsAt: 0, endsAt: Date.now() + 24 * H, clubId: 'c1' });
    await seed('challenges/club/participants/eve', p('eve'));
  });

  test('cập nhật tiến độ khi đang diễn ra và trong 48 giờ chờ đồng bộ; đổi hiện tên lúc nào cũng được', async () => {
    await ok(as('mia').update('challenges/active/participants/mia', { progressValue: 2000 }));
    await ok(as('mia').update('challenges/grace/participants/mia', { progressValue: 3000 }));
    await ok(as('mia').update('challenges/locked/participants/mia', { leaderboardOptIn: true }));
  });

  test('chặn: sửa tiến độ / rời sau khi khóa; người không còn trong club cập nhật tiếp', async () => {
    await denied(as('mia').update('challenges/locked/participants/mia', { progressValue: 9999 }));
    await denied(as('mia').delete('challenges/locked/participants/mia'));
    await denied(as('eve').update('challenges/club/participants/eve', { progressValue: 9999 }));
    await ok(as('eve').update('challenges/club/participants/eve', { leaderboardOptIn: true }));
  });
});

describe('TM32: đội trong thử thách của club', () => {
  const H = 3600 * 1000;
  const team = (by) => ({ name: 'Red', color: 1, createdBy: by, createdAt: 1 });
  beforeEach(async () => {
    await seed('clubs/c1', { name: 'Club', visibility: 'public', memberCount: 3, ownerId: 'olly' });
    await seed('clubs/c1/members/olly', { userId: 'olly', role: 'owner', status: 'active' });
    await seed('clubs/c1/members/mia', { userId: 'mia', role: 'member', status: 'active' });
    await seed('clubs/c1/members/bo', { userId: 'bo', role: 'member', status: 'active' });
    await seed('challenges/k', { title: 'k', participantCount: 2, startsAt: 0, endsAt: Date.now() + 10 * 24 * H, clubId: 'c1' });
    await seed('challenges/k/teams/red', team('olly'));
    await seed('challenges/k/teams/blue', { ...team('olly'), name: 'Blue', color: 2 });
    await seed('challenges/k/participants/mia', { userId: 'mia', leaderboardOptIn: false, progressValue: 5 });
    await seed('challenges/k/participants/bo', { userId: 'bo', leaderboardOptIn: false, progressValue: 9, teamId: 'blue' });
  });

  test('owner tạo đội; chọn đội, đổi một lần; thành viên club đọc/query người trong đội', async () => {
    await ok(as('olly').set('challenges/k/teams/green', { ...team('olly'), name: 'Green', color: 3 }));
    await ok(as('mia').update('challenges/k/participants/mia', { teamId: 'red' }));
    await ok(as('mia').update('challenges/k/participants/mia', { teamId: 'blue', teamChanges: 1 }));
    await ok(as('mia').get('challenges/k/participants/bo'));
    await ok(query('mia', 'challenges/k', 'participants', { teamId: 'blue' }));
  });

  test('chặn: member tạo đội, đổi lần hai, đội không tồn tại, gửi teamId khi tham gia, khóa trước hạn, sửa đội qua đường tiến độ, người ngoài đọc', async () => {
    await denied(as('mia').set('challenges/k/teams/x', team('mia')));
    await denied(as('mia').update('challenges/k/participants/mia', { teamId: 'ghost' }));
    await denied(as('mia').update('challenges/k/participants/mia', { teamId: 'red', progressValue: 999 }));
    await seed('challenges/k/participants/mia', { userId: 'mia', leaderboardOptIn: false, teamId: 'red', teamChanges: 1 });
    await denied(as('mia').update('challenges/k/participants/mia', { teamId: 'blue', teamChanges: 2 }));
    await denied(as('mia').update('challenges/k/participants/mia', { teamId: 'blue', teamChanges: 1 }));
    await denied(as('stranger').get('challenges/k/participants/bo'));
    await denied(as('olly').set('challenges/k/participants/olly', { userId: 'olly', leaderboardOptIn: false, teamId: 'red' }));
    await seed('challenges/late', { title: 'l', participantCount: 1, startsAt: 0, endsAt: Date.now() + 24 * H, clubId: 'c1' });
    await seed('challenges/late/teams/red', team('olly'));
    await seed('challenges/late/participants/mia', { userId: 'mia', leaderboardOptIn: false });
    await denied(as('mia').update('challenges/late/participants/mia', { teamId: 'red' }));
    await denied(as('olly').set('challenges/late/teams/blue', team('olly')));
  });
});

describe('challenges + participants (bảng xếp hạng)', () => {
  beforeEach(async () => {
    await seed('challenges/ch1', { title: 'x', participantCount: 0, endsAt: Date.now() + 24 * 3600 * 1000 });
    await seed('challenges/ch1/participants/alice', { userId: 'alice', leaderboardOptIn: false, progressValue: 10 });
    await seed('challenges/ch1/participants/carol', { userId: 'carol', leaderboardOptIn: true, progressValue: 20 });
  });
  test('tham gia, đọc tiến độ của mình và người bật leaderboardOptIn', async () => {
    await ok(as('bob').set('challenges/ch1/participants/bob', { userId: 'bob', leaderboardOptIn: false }));
    await ok(as('bob').update('challenges/ch1', { participantCount: 1 }));
    await ok(as('bob').get('challenges/ch1/participants/carol'));
    await ok(as('alice').get('challenges/ch1/participants/alice'));
    await ok(query('bob', 'challenges/ch1', 'participants', { leaderboardOptIn: true }));
    // Bật/tắt hiện tên của chính mình.
    await ok(as('alice').update('challenges/ch1/participants/alice', { leaderboardOptIn: true }));
  });
  test('không đọc người tắt leaderboardOptIn; không ghi tiến độ người khác; không tạo thử thách', async () => {
    await denied(as('bob').get('challenges/ch1/participants/alice'));
    // TM30: bảng xếp hạng chỉ query được khi lọc leaderboardOptIn == true.
    await denied(query('bob', 'challenges/ch1', 'participants'));
    await denied(query('bob', 'challenges/ch1', 'participants', { leaderboardOptIn: false }));
    await denied(as('bob').update('challenges/ch1/participants/carol', { progressValue: 0 }));
    await denied(as('bob').set('challenges/ch2', { title: 'mine' }));
    await denied(as('bob').update('challenges/ch1', { participantCount: 9 }));
  });
});

describe('routes — chỉ Admin SDK ghi', () => {
  test('người đăng nhập đọc; không ai ghi từ client', async () => {
    await seed('routes/r1', { name: 'Lake loop' });
    await ok(as('bob').get('routes/r1'));
    await denied(as('bob').set('routes/r2', { name: 'x' }));
    await denied(as('bob').update('routes/r1', { name: 'y' }));
    await denied(as(null).get('routes/r1'));
  });
});

describe('liveShares — chủ ghi, người được mời đọc', () => {
  beforeEach(() => seed('liveShares/s1', { ownerId: 'alice', viewerIds: ['bob'] }));
  test('chủ tạo/cập nhật; người được mời đọc', async () => {
    await ok(as('alice').set('liveShares/s2', { ownerId: 'alice', viewerIds: ['bob'] }));
    await ok(as('alice').update('liveShares/s1', { lastPoint: { lat: 1.5, lon: 2.5 } }));
    await ok(as('bob').get('liveShares/s1'));
  });
  test('người không được mời không đọc; không ghi thay chủ; tối đa 20 người xem; không xóa', async () => {
    await denied(as('carol').get('liveShares/s1'));
    await denied(as('bob').update('liveShares/s1', { viewerIds: ['bob', 'carol'] }));
    await denied(as('bob').set('liveShares/s3', { ownerId: 'alice', viewerIds: [] }));
    await denied(as('alice').set('liveShares/s4', { ownerId: 'alice', viewerIds: Array.from({ length: 21 }, (_, i) => `v${i}`) }));
    await denied(as('alice').delete('liveShares/s1'));
  });
});

describe('reports / feedback — chỉ tạo', () => {
  test('tạo đúng người gửi', async () => {
    await ok(as('bob').set('reports/r1', { reporterId: 'bob', targetId: 'p1' }));
    await ok(as('bob').set('feedback/f1', { uid: 'bob', text: 'hi' }));
  });
  test('không đọc, không sửa, không giả người gửi', async () => {
    await seed('reports/r1', { reporterId: 'bob' });
    await denied(as('bob').get('reports/r1'));
    await denied(as('bob').update('reports/r1', { x: 1 }));
    await denied(as('bob').set('reports/r2', { reporterId: 'alice' }));
    await denied(as('bob').set('feedback/f2', { uid: 'alice' }));
    await denied(as(null).set('feedback/f3', { uid: 'x' }));
  });
});
