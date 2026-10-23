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
test('Account overview reports plan limits and credits used today and this month', async () => {
  const today = new Date().toISOString().slice(0, 10), queries = [];
  const store = { async list(token, table, parameters) {
    assert.equal(token, 'fixture-user'); queries.push([table, parameters]);
    if (table === 'nn_ai_usage') return [{ day: today, used: 3 }, { day: today.slice(0, 8) + '01', used: 5 }, { day: today, used: -2 }, { day: 7, used: 1 }];
    if (table === 'nn_entitlements') return [{ plan: 'free', daily_ai_limit: 10, monthly_ai_limit: 100, storage_limit: 268435456 }];
    return [{ user_id: user, display_name: 'Studente' }];
  } };
  await withAPI(store, async request => {
    const response = await request('/account');
    assert.equal(response.status, 200); assert.equal(response.body.userID, user);
    assert.deepEqual(response.body.usage, { day: today, today: today.endsWith('-01') ? 8 : 3, month: 8 });
    assert.equal(response.body.entitlements[0].daily_ai_limit, 10);
    const usage = queries.find(([table]) => table === 'nn_ai_usage')[1];
    assert.equal(usage.user_id, 'eq.' + user); assert.equal(usage.day, 'gte.' + today.slice(0, 8) + '01');
  });
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


test('Account export uses a fixed self-scoped table and bounded stable pages', async () => {
  const queries = [];
  await withAPI({ async list(token, table, params) { queries.push({token,table,params}); return Array.from({length:10},(_,i)=>({id:i})); } }, async request => {
    const result = await request('/account/export?section=resources&offset=20&owner_id=' + other);
    assert.equal(result.status,200); assert.equal(result.body.nextOffset,30);
    assert.equal(queries[0].params.owner_id,'eq.'+user); assert.equal(queries[0].params.limit,'10'); assert.equal(queries[0].params.order,'id.asc');
    assert.equal((await request('/account/export?section=auth.users')).status,400);
    assert.equal((await request('/account/export?section=__proto__')).status,400);
  });
});
test('Account deletion removes physical own objects before finalizing, never just database metadata', async () => {
  const calls = []; let reads=0;
  await withAPI({ async rpc(token,name) { calls.push(name); assert.equal(token,'fixture-user'); if(name==='nn_account_deletion_objects') return reads++===0 ? [user+'/cloud/a/file.nnbackup'] : []; },
    async call(token,path,method,body) { calls.push(method); assert.equal(path,'/storage/v1/object/neuralnotes-private'); assert.equal(method,'DELETE'); assert.deepEqual(body.prefixes,[user+'/cloud/a/file.nnbackup']); } }, async request => {
    assert.equal((await request('/account/delete',{confirmation:'no'})).status,400); assert.equal(calls.length,0);
    const result=await request('/account/delete',{confirmation:'ELIMINA',userID:other}); assert.equal(result.status,200); assert.equal(result.body.deleted,true);
    assert.deepEqual(calls,['nn_begin_account_deletion','nn_account_deletion_objects','DELETE','nn_account_deletion_objects','nn_finish_account_deletion']);
  });
});
test('Account deletion is resumable and rejects cross-account storage paths', async () => {
  let finished=false;
  const store={async rpc(_token,name) { if(name==='nn_account_deletion_objects') return [user+'/cloud/a/file.nnbackup']; if(name==='nn_finish_account_deletion') finished=true; }, async call() {} };
  await withAPI(store,async request=>{assert.equal((await request('/account/delete',{confirmation:'ELIMINA'})).status,202); assert.equal(finished,false);});
  store.rpc=async(_token,name)=> name==='nn_account_deletion_objects' ? [other+'/cloud/a/file.nnbackup'] : null;
  store.call=async()=>assert.fail('must not delete another owner object');
  await withAPI(store,async request=>{assert.equal((await request('/account/delete',{confirmation:'ELIMINA'})).status,502); assert.equal(finished,false);});
});
test('Storage cleanup failure leaves identity and pending operation for retry', async()=>{
  let finished=false;
  await withAPI({async rpc(_token,name){if(name==='nn_account_deletion_objects')return [user+'/cloud/a/file.nnbackup']; if(name==='nn_finish_account_deletion')finished=true;}, async call(){throw Error('network');}},async request=>{
    assert.equal((await request('/account/delete',{confirmation:'ELIMINA'})).status,502); assert.equal(finished,false);
  });
});

test('Readiness probes only the public schema version, with no user or service-role credential', async()=>{
  const config={url:'https://fixture.supabase.co',publicKey:'sb_publishable_fixture'};
  const ready=new SupabaseStore(config,async(url,options)=>{assert.equal(url.pathname,'/rest/v1/rpc/nn_platform_version'); assert.equal(options.headers.Authorization,undefined); return Response.json(2);});
  assert.equal(await ready.platformVersion(),2);
  for (const value of [1,{},'2']) await assert.rejects(new SupabaseStore(config,async()=>Response.json(value)).platformVersion(),{code:'platform_not_ready'});
});
