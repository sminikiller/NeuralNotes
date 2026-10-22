import test from 'node:test';
import assert from 'node:assert/strict';
import { once } from 'node:events';
import { SupabaseStore, createPlatformApp } from './platform.mjs';
const user = '11111111-1111-4111-8111-111111111111', other = '22222222-2222-4222-8222-222222222222', hub = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
async function withAPI(store, run) {
  const server = createPlatformApp({ authenticate: async token => token === 'fixture-user' ? user : null, store });
  server.listen(0, '127.0.0.1'); await once(server, 'listening');
  const request = async (path, body, token = 'fixture-user') => {
    const response = await fetch(`http://127.0.0.1:${server.address().port}/v1/platform` + path, { method: body === undefined ? 'GET' : 'POST', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, ...(body === undefined ? {} : { body: JSON.stringify(body) }) });
    return { status: response.status, body: await response.json() };
  };
  try { await run(request); } finally { server.close(); await once(server, 'close'); }
}
test('Platform requires verified account before any database request', async () => {
  await withAPI({ list() { throw Error('must not execute'); } }, async request => assert.equal((await request('/hubs', undefined, 'forged')).status, 401));
});
test('Hub and resource creation cannot choose another owner or publish directly', async () => {
  let inserted;
  const store = { async list() { return [{ object_path: 'reserved' }]; }, async call(_token, path, method, body) { inserted = body; return [body]; } };
  await withAPI(store, async request => {
    assert.equal((await request('/hubs', { owner_id: other, slug: 'infermieristica', title: 'Infermieristica', visibility: 'public' })).status, 201); assert.equal(inserted.owner_id, user);
    const path = `${user}/community/${hub}/bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb.pdf`;
    assert.equal((await request('/resources', { hubID: hub, objectPath: path, title: 'Appunti', status: 'published', owner_id: other })).status, 201);
    assert.equal(inserted.owner_id, user); assert.equal(inserted.status, 'pending');
    assert.equal((await request('/resources', { hubID: hub, objectPath: `${other}/community/${hub}/file.pdf`, title: 'Altrui' })).status, 400);
  });
});
test('Upload reservation returns only authenticated fixed-project upload, never an open upload token', async () => {
  const store = { base: new URL('https://fixture.supabase.co'), publicKey: 'sb_publishable_fixture', async rpc(token, method, body) { assert.equal(token, 'fixture-user'); assert.equal(method, 'nn_reserve_upload'); assert.equal(body.expected_bytes, 200); return `${user}/cloud/${hub}/bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb.nnbackup`; } };
  await withAPI(store, async request => {
    const result = await request('/uploads', { kind: 'cloud', entityID: hub, extension: 'nnbackup', bytes: 200 });
    assert.equal(result.status, 201); assert.equal(result.body.requiresUserBearer, true); assert.equal(result.body.token, undefined);
    assert.equal(new URL(result.body.uploadURL).origin, 'https://fixture.supabase.co');
    assert.equal((await request('/uploads', { kind: 'cloud', entityID: hub, extension: 'nnbackup', bytes: 0 })).status, 400);
  });
});
test('Invites expose a random token once and persist only its digest', async () => {
  let stored;
  await withAPI({ async rpc(_token, name, body) { stored = body; } }, async request => {
    const result = await request('/invites', { hubID: hub, uses: 1 }); assert.equal(result.status, 201);
    assert.match(result.body.token, /^[a-f0-9]{64}$/); assert.notEqual(stored.token_digest, result.body.token); assert.equal(stored.uses, 1);
  });
});
test('Supabase requests forward user token with public key and map revision conflict without leaking database details', async () => {
  const store = new SupabaseStore({ url: 'https://fixture.supabase.co', publicKey: 'sb_publishable_fixture' }, async (url, options) => {
    assert.equal(url.origin, 'https://fixture.supabase.co'); assert.equal(options.headers.Authorization, 'Bearer fixture-user'); assert.equal(options.headers.apikey, 'sb_publishable_fixture');
    return Response.json({ code: '40001', message: 'private internal error' }, { status: 409 });
  });
  await assert.rejects(store.rpc('fixture-user', 'nn_commit_document'), { status: 409, code: 'revision_or_identity_conflict' });
});
test('Persistent quotas send bounded credit units to atomic RPC', async () => {
  const store = new SupabaseStore({ url: 'https://fixture.supabase.co', publicKey: 'sb_publishable_fixture' }, async (_url, options) => {
    assert.deepEqual(JSON.parse(options.body), { credits: 8 }); return Response.json(false);
  });
  assert.equal(await store.take(user, Date.now(), 'fixture-user', 8), false);
});
