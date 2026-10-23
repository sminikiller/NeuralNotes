import http from 'node:http';
import { requirePublicKey } from './auth.mjs';
import { createHash, randomBytes } from 'node:crypto';
import { RequestFailure } from './server.mjs';
const uuid = /^[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}$/i;
const validID = value => { if (!uuid.test(value ?? '')) throw new RequestFailure(400, 'invalid_id'); return value; };
const digest = value => createHash('sha256').update(value).digest('hex');
const text = (value, max) => { if (typeof value !== 'string' || !value.trim() || value.length > max) throw new RequestFailure(400, 'invalid_text'); return value.trim(); };
async function readJSON(stream, limit = 65536) {
  const chunks = []; let size = 0;
  for await (const chunk of stream) { size += chunk.length; if (size > limit) throw new RequestFailure(413, 'request_too_large'); chunks.push(chunk); }
  try { return JSON.parse(Buffer.concat(chunks).toString('utf8')); } catch { throw new RequestFailure(400, 'invalid_json'); }
}
export class SupabaseStore {
  constructor({ url, publicKey }, transport = fetch) {
    requirePublicKey(publicKey);
    const base = new URL(url); if (base.protocol !== 'https:' || base.pathname !== '/' || base.username || base.password || !publicKey) throw new Error('Invalid project configuration');
    Object.assign(this, { base, publicKey, transport });
  }
  async call(token, path, method = 'GET', body) {
    const response = await this.transport(new URL(path, this.base), { method, redirect: 'error', signal: AbortSignal.timeout(12000),
      headers: { apikey: this.publicKey, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json', Prefer: 'return=representation,resolution=merge-duplicates' }, ...(body === undefined ? {} : { body: JSON.stringify(body) }) });
    if (!response.body) { if (response.ok) return null; throw new RequestFailure(502, 'storage_unavailable'); }
    const data = await readJSON(response.body, 2 * 1024 * 1024);
    if (!response.ok) {
      if (data?.code === 'PT401') throw new RequestFailure(401, 'reauthentication_required');
      if (data?.code === 'PT409') throw new RequestFailure(409, data.message === 'transfer_shared_hubs_first' ? 'transfer_shared_hubs_first' : data.message === 'revision_conflict' ? 'revision_or_identity_conflict' : 'cleanup_incomplete');
      const status = data?.code === '40001' || data?.code === '23505' ? 409 : data?.code === '42501' || response.status === 403 ? 403 : data?.code === 'P0001' ? 429 : response.status === 401 ? 401 : 400;
      throw new RequestFailure(status, status === 409 ? 'revision_or_identity_conflict' : status === 429 ? 'storage_quota' : status === 403 ? 'forbidden' : 'platform_request_failed');
    }
    return data;
  }
  async platformVersion() {
    const response = await this.transport(new URL('/rest/v1/rpc/nn_platform_version', this.base), { method: 'POST',
      headers: { apikey: this.publicKey, 'Content-Type': 'application/json' }, body: '{}', redirect: 'error', signal: AbortSignal.timeout(5000) });
    if (!response.ok || !response.body) throw new RequestFailure(503, 'platform_not_ready');
    const version = await readJSON(response.body, 1024);
    if (version !== 2) throw new RequestFailure(503, 'platform_not_ready');
    return version;
  }
  rpc(token, name, body = {}) { return this.call(token, '/rest/v1/rpc/' + name, 'POST', body); }
  list(token, table, parameters) { return this.call(token, '/rest/v1/' + table + '?' + new URLSearchParams(parameters)); }
  async take(_subject, _now, token, credits = 1) { return await this.rpc(token, 'nn_consume_ai', { credits }) === true; }
}
export function createPlatformApp({ authenticate, store }) {
  if (typeof authenticate !== 'function') throw new Error('Hosted authentication required');
  return http.createServer(async (req, res) => {
    const reply = (status, data) => { res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff' }); res.end(JSON.stringify(data)); };
    try {
      const token = /^Bearer (.+)$/.exec(String(req.headers.authorization ?? ''))?.[1] ?? '';
      const subject = await authenticate(token); if (!subject) throw new RequestFailure(401, 'unauthorized');
      const url = new URL(req.url, 'http://loopback'), path = url.pathname.replace(/^\/v1\/platform/, '');
      const offset = Number(url.searchParams.get('offset') ?? 0);
      if (!Number.isSafeInteger(offset) || offset < 0 || offset > 10000) throw new RequestFailure(400, 'invalid_offset');
      let body;
      if (req.method === 'POST') {
        if (req.headers['content-type']?.split(';')[0] !== 'application/json') throw new RequestFailure(400, 'invalid_content_type');
        req.setTimeout(10000, () => req.destroy()); body = await readJSON(req); req.setTimeout(0);
        if (!body || typeof body !== 'object' || Array.isArray(body)) throw new RequestFailure(400, 'invalid_json');
      }
      const insert = (table, value) => store.call(token, '/rest/v1/' + table, 'POST', value);
      if (req.method === 'GET' && path === '/account') {
        // Credits used today and this month (UTC), the same days the quota function counts.
        const now = new Date(), today = now.toISOString().slice(0, 10), month = today.slice(0, 8) + '01';
        const rows = await store.list(token, 'nn_ai_usage', { user_id: 'eq.' + subject, day: 'gte.' + month, select: 'day,used' });
        const used = (Array.isArray(rows) ? rows : []).filter(row => typeof row?.day === 'string' && Number.isSafeInteger(row.used) && row.used >= 0);
        const usage = { day: today, today: used.filter(row => row.day === today).reduce((sum, row) => sum + row.used, 0), month: used.reduce((sum, row) => sum + row.used, 0) };
        reply(200, { userID: subject, profile: await store.list(token, 'nn_profiles', { user_id: 'eq.' + subject, select: '*' }), entitlements: await store.list(token, 'nn_entitlements', { user_id: 'eq.' + subject, select: 'plan,daily_ai_limit,monthly_ai_limit,storage_limit' }), usage }); return;
      }
      if (req.method === 'POST' && path === '/profile') {
        const response = await store.call(token, '/rest/v1/nn_profiles?on_conflict=user_id', 'POST', { user_id: subject, display_name: text(body.displayName, 80) }); reply(200, response); return;
      }
      if (req.method === 'GET' && path === '/account/export') {
        const tables = { profile: ['nn_profiles', 'user_id'], entitlements: ['nn_entitlements', 'user_id'], usage: ['nn_ai_usage', 'user_id'],
          documents: ['nn_documents', 'owner_id'], snapshots: ['nn_snapshots', 'owner_id'],
          resources: ['nn_resources', 'owner_id'], hubs: ['nn_hubs', 'owner_id'],
          memberships: ['nn_hub_members', 'user_id'], reports: ['nn_reports', 'reporter_id'], blocks: ['nn_blocks', 'user_id'] };
        const section = url.searchParams.get('section'), table = Object.hasOwn(tables, section) ? tables[section] : null;
        if (!table) throw new RequestFailure(400, 'invalid_export_section');
        const orders = { usage: 'day.asc', snapshots: 'document_id.asc,revision.asc', memberships: 'hub_id.asc', blocks: 'blocked_user_id.asc' };
        const rows = await store.list(token, table[0], { [table[1]]: 'eq.' + subject, select: '*', limit: '10', offset: String(offset), order: orders[section] ?? (['profile', 'entitlements'].includes(section) ? 'user_id.asc' : 'id.asc') });
        if (!Array.isArray(rows) || rows.length > 10) throw new RequestFailure(502, 'invalid_export');
        reply(200, { version: 1, userID: subject, section, rows, nextOffset: rows.length === 10 ? offset + 10 : null }); return;
      }
      if (req.method === 'POST' && path === '/account/delete') {
        if (body.confirmation !== 'ELIMINA') throw new RequestFailure(400, 'confirmation_required');
        await store.rpc(token, 'nn_begin_account_deletion');
        const objects = await store.rpc(token, 'nn_account_deletion_objects');
        if (!Array.isArray(objects) || objects.length > 100 || objects.some(p => typeof p !== 'string' || !p.startsWith(subject + '/') || p.includes('..') || p.includes('\\') || p.length > 511)) throw new RequestFailure(502, 'invalid_object');
        if (objects.length) await store.call(token, '/storage/v1/object/neuralnotes-private', 'DELETE', { prefixes: objects });
        const remaining = await store.rpc(token, 'nn_account_deletion_objects');
        if (!Array.isArray(remaining)) throw new RequestFailure(502, 'invalid_object');
        if (remaining.length) { reply(202, { pending: true, removed: objects.length }); return; }
        await store.rpc(token, 'nn_finish_account_deletion');
        reply(200, { deleted: true }); return;
      }
      if (req.method === 'POST' && path === '/hubs/transfer') {
        await store.rpc(token, 'nn_transfer_hub', { target: validID(body.hubID), next_owner: validID(body.userID) }); reply(200, { transferred: true }); return;
      }
      if (req.method === 'GET' && path === '/hubs') { reply(200, await store.list(token, 'nn_hubs', { select: '*', order: 'created_at.desc', limit: '50', offset: String(offset) })); return; }
      if (req.method === 'POST' && path === '/hubs') {
        if (!/^[a-z0-9][a-z0-9-]{2,79}$/.test(body.slug ?? '') || !['public', 'private'].includes(body.visibility)) throw new RequestFailure(400, 'invalid_hub');
        reply(201, await insert('nn_hubs', { owner_id: subject, title: text(body.title, 120), slug: body.slug, visibility: body.visibility })); return;
      }
      if (req.method === 'GET' && path === '/resources') {
        const filters = { select: '*', order: 'created_at.desc', limit: '50', offset: String(offset) };
        if (url.searchParams.get('mine') === '1') filters.owner_id = 'eq.' + subject;
        else { filters.hub_id = 'eq.' + validID(url.searchParams.get('hub')); filters.status = 'eq.published'; }
        if (url.searchParams.has('tag')) { const tag = url.searchParams.get('tag'); if (!/^[\p{L}\p{N} _-]{1,40}$/u.test(tag)) throw new RequestFailure(400, 'invalid_tag'); filters.tags = 'cs.{' + tag + '}'; }
        reply(200, await store.list(token, 'nn_resources', filters)); return;
      }
      if (req.method === 'POST' && path === '/resources') {
        const hub = validID(body.hubID), object = text(body.objectPath, 511);
        if (!object.startsWith(`${subject}/community/${hub}/`) || object.includes('..') || !Array.isArray(body.tags ?? []) || (body.tags ?? []).length > 12 || !(body.tags ?? []).every(v => typeof v === 'string' && v.length <= 40)) throw new RequestFailure(400, 'invalid_resource');
        const uploaded = await store.list(token, 'nn_uploads', { object_path: 'eq.' + object, owner_id: 'eq.' + subject, select: 'object_path', limit: '1' });
        if (!uploaded.length) throw new RequestFailure(400, 'upload_not_reserved');
        reply(201, await insert('nn_resources', { owner_id: subject, hub_id: hub, title: text(body.title, 160), description: typeof body.description === 'string' ? body.description.slice(0, 4000) : '', tags: body.tags ?? [], object_path: object, status: 'pending' })); return;
      }
      if (req.method === 'POST' && path === '/moderate') { if (!['published', 'hidden'].includes(body.status)) throw new RequestFailure(400, 'invalid_status'); reply(200, await store.rpc(token, 'nn_moderate_resource', { target: validID(body.resourceID), next_status: body.status })); return; }
      if (req.method === 'POST' && path === '/reports') { reply(201, await insert('nn_reports', { reporter_id: subject, resource_id: validID(body.resourceID), reason: text(body.reason, 1000) })); return; }
      if (req.method === 'POST' && path === '/blocks') { reply(201, await insert('nn_blocks', { user_id: subject, blocked_user_id: validID(body.userID) })); return; }
      if (req.method === 'POST' && path === '/invites') {
        const raw = randomBytes(32).toString('hex'), expires = new Date(Date.now() + 86400000).toISOString();
        if (!Number.isInteger(body.uses ?? 10) || (body.uses ?? 10) < 1 || (body.uses ?? 10) > 100) throw new RequestFailure(400, 'invalid_uses');
        await store.rpc(token, 'nn_create_invite', { target: validID(body.hubID), token_digest: digest(raw), expires, uses: body.uses ?? 10 });
        reply(201, { token: raw, expiresAt: expires }); return;
      }
      if (req.method === 'POST' && path === '/join') { if (!/^[a-f0-9]{64}$/.test(body.token ?? '')) throw new RequestFailure(400, 'invalid_invite'); reply(200, { hubID: await store.rpc(token, 'nn_join_invite', { token_digest: digest(body.token) }) }); return; }
      if (req.method === 'POST' && path === '/uploads') {
        if (!['cloud', 'community'].includes(body.kind) || !['nnbackup','pdf','png','jpeg'].includes(body.extension) || !Number.isSafeInteger(body.bytes) || body.bytes < 1 || body.bytes > 104857600) throw new RequestFailure(400, 'invalid_upload');
        const objectPath = await store.rpc(token, 'nn_reserve_upload', { kind: body.kind, entity: validID(body.entityID), extension: body.extension, expected_bytes: body.bytes });
        // Authenticated upload: no bearer-less upload token that could bypass RLS size checks.
        reply(201, { objectPath, method: 'POST', uploadURL: new URL('/storage/v1/object/neuralnotes-private/' + objectPath.split('/').map(encodeURIComponent).join('/'), store.base).href, publicKey: store.publicKey, expectedBytes: body.bytes, requiresUserBearer: true, upsert: false }); return;
      }
      if (req.method === 'GET' && path === '/documents') { reply(200, await store.list(token, 'nn_documents', { select: '*', order: 'updated_at.desc', limit: '50', offset: String(offset) })); return; }
      if (req.method === 'POST' && path === '/commit') {
        if (!Number.isInteger(body.expectedRevision) || body.expectedRevision < 0 || !/^[a-f0-9]{64}$/.test(body.checksum ?? '') || !Number.isSafeInteger(body.bytes) || body.bytes < 1 || body.bytes > 104857600 || typeof body.deleted !== 'boolean') throw new RequestFailure(400, 'invalid_snapshot');
        reply(200, await store.rpc(token, 'nn_commit_document', { target: validID(body.documentID), expected_revision: body.expectedRevision, next_title: text(body.title, 160), next_object: text(body.objectPath, 511), next_checksum: body.checksum, next_bytes: body.bytes, tombstone: body.deleted })); return;
      }
      if (req.method === 'GET' && path === '/download') {
        const resource = url.searchParams.get('resource'), document = url.searchParams.get('document');
        if (!!resource === !!document) throw new RequestFailure(400, 'invalid_download');
        const rows = await store.list(token, resource ? 'nn_resources' : 'nn_documents', { id: 'eq.' + validID(resource ?? document), select: 'object_path', limit: '1' });
        if (!rows.length) throw new RequestFailure(404, 'not_found');
        const object = rows[0].object_path;
        if (typeof object !== 'string' || object.includes('..') || !/^[a-f0-9-]{36}\/(cloud|community)\/[a-f0-9-]{36}\/[a-f0-9-]{36}\.(nnbackup|pdf|png|jpeg)$/.test(object)) throw new RequestFailure(502, 'invalid_object');
        const data = await store.call(token, '/storage/v1/object/sign/neuralnotes-private/' + object, 'POST', { expiresIn: 60 });
        if (typeof data?.signedURL !== 'string' || !data.signedURL.startsWith('/object/sign/')) throw new RequestFailure(502, 'invalid_download_url');
        reply(200, { url: new URL('/storage/v1' + data.signedURL, store.base).href, expiresIn: 60 }); return;
      }
      throw new RequestFailure(404, 'not_found');
    } catch (error) { if (!res.destroyed) reply(error instanceof RequestFailure ? error.status : 502, { error: error instanceof RequestFailure ? error.code : 'platform_unavailable' }); }
  });
}
