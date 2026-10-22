import { readFileSync } from 'node:fs';
import http from 'node:http';
import https from 'node:https';
import { createHmac, randomUUID } from 'node:crypto';
import assert from 'node:assert/strict';
import path from 'node:path';
import { createApp } from '../server.mjs';
import { DeepSeekAdapter } from '../deepseek.mjs';
import { SupabaseStore, createPlatformApp } from '../platform.mjs';
import { supabaseAuthenticator } from '../auth.mjs';

const config = JSON.parse(readFileSync(process.argv[2], 'utf8')), origin = `https://localhost:${config.port}`;
const encode = value => Buffer.from(JSON.stringify(value)).toString('base64url');
const jwt = encode({ alg: 'HS256', typ: 'JWT' }) + '.' + encode({ role: 'anon', exp: Math.floor(Date.now() / 1000) + 3600 });
const publicKey = jwt + '.' + createHmac('sha256', config.jwtSecret).update(jwt).digest('base64url');
let providerCalls = 0;
// The Auth/SMTP/database/gateway are real. ONLY this last provider hop is a
// declared fixture: no AI key, outbound request, semantic quality or cost claim.
const adapter = new DeepSeekAdapter({ key: 'fixture-only-no-provider-key' }, async (_url, options) => {
  providerCalls++;
  const payload = JSON.parse(options.body), content = JSON.stringify({ text: 'Spiegazione di controllo basata sulla fonte.', citations: [1] });
  if (payload.stream) {
    const events = [{ choices: [{ delta: { content }, finish_reason: null }] }, { choices: [{ delta: {}, finish_reason: 'stop' }] }];
    return new Response(events.map(x => 'data: ' + JSON.stringify(x) + '\n\n').join('') + 'data: [DONE]\n\n', { headers: { 'Content-Type': 'text/event-stream' } });
  }
  return new Response(JSON.stringify({ choices: [{ message: { content }, finish_reason: 'stop' }] }), { headers: { 'Content-Type': 'application/json' } });
});
const authenticate = supabaseAuthenticator({ url: origin, publicKey });
const store = new SupabaseStore({ url: origin, publicKey });
const ai = createApp({ authenticate, adapter, limiter: store }), platform = createPlatformApp({ authenticate, store });
function proxy(req, res, port, prefix) {
  const upstream = http.request({ hostname: '127.0.0.1', port, method: req.method, path: req.url.slice(prefix.length) || '/', headers: req.headers }, response => {
    res.writeHead(response.statusCode, response.headers); response.pipe(res);
  });
  upstream.on('error', () => { if (!res.headersSent) res.writeHead(502); res.end(); }); req.pipe(upstream);
}
const server = https.createServer({ key: readFileSync(path.join(config.directory, 'key.pem')), cert: readFileSync(path.join(config.directory, 'cert.pem')) }, (req, res) => {
  if (req.url.startsWith('/auth/v1/')) return proxy(req, res, config.authPort, '/auth/v1');
  if (req.url.startsWith('/rest/v1/')) return proxy(req, res, config.restPort, '/rest/v1');
  if (req.url === '/v1/config') { res.setHeader('Content-Type', 'application/json'); res.end(JSON.stringify({ version: 1, managed: true, auth: { url: origin, publicKey }, subscriptionsActive: false })); return; }
  if (req.url.startsWith('/v1/platform/')) platform.emit('request', req, res); else ai.emit('request', req, res);
});
await new Promise(resolve => server.listen(config.port, '127.0.0.1', resolve));
async function call(route, body, token, headers = {}) {
  const response = await fetch(origin + route, { method: body === undefined ? 'GET' : 'POST', headers: { apikey: publicKey, ...(token ? { Authorization: 'Bearer ' + token } : {}), ...(body === undefined ? {} : { 'Content-Type': 'application/json' }), ...headers }, ...(body === undefined ? {} : { body: JSON.stringify(body) }) });
  const text = await response.text(); return { status: response.status, text, json: () => JSON.parse(text) };
}
async function signIn(email) {
  const sent = await call('/auth/v1/otp', { email, create_user: true }); assert.equal(sent.status, 200, 'Real Auth OTP request');
  let code;
  for (let attempt = 0; attempt < 100 && !code; attempt++) {
    const list = await (await fetch(`http://127.0.0.1:${config.mailPort}/api/v1/messages`)).json();
    for (const item of list.messages ?? []) {
      if (!(item.To ?? []).some(x => x.Address === email)) continue;
      const mail = await (await fetch(`http://127.0.0.1:${config.mailPort}/api/v1/message/${item.ID}`)).json();
      code = /\b\d{6,10}\b/.exec(mail.Text || mail.HTML)?.[0]; if (code) break;
    }
    if (!code) await new Promise(resolve => setTimeout(resolve, 100));
  }
  assert.ok(code, 'OTP captured by local SMTP; nothing delivered externally');
  const invalid = await call('/auth/v1/verify', { email, token: '000000', type: 'email' }); assert.notEqual(invalid.status, 200);
  const verified = await call('/auth/v1/verify', { email, token: code, type: 'email' }); assert.equal(verified.status, 200, 'Email code verification');
  const session = verified.json(); assert.ok(session.access_token && session.refresh_token && session.user.id); return session;
}
try {
  const publicConfig = await call('/v1/config'); assert.equal(publicConfig.json().managed, true); assert.ok(!publicConfig.text.includes(config.jwtSecret));
  const a = await signIn('student-a@example.invalid'), b = await signIn('student-b@example.invalid');
  assert.notEqual(a.user.id, b.user.id);
  assert.equal((await call('/v1/platform/profile', { displayName: 'Studente A' }, a.access_token)).status, 200);
  const own = await call('/v1/platform/account', undefined, a.access_token); assert.equal(own.json().profile[0].display_name, 'Studente A');
  const other = await call('/v1/platform/account', undefined, b.access_token); assert.equal(other.json().profile.length, 0);
  const stolen = await call('/rest/v1/nn_profiles?user_id=eq.' + a.user.id, undefined, b.access_token); assert.deepEqual(stolen.json(), []);
  console.log('PASS real email OTP, two identities, profiles and PostgreSQL RLS isolation');
  const input = { task: 'chat', question: 'Spiega la fonte', sources: [{ text: 'Una fonte sintetica per il test.', reference: { documentID: randomUUID(), pageID: randomUUID(), pageRevision: 1 } }] };
  const denied = await call('/v1/study', input); assert.equal(denied.status, 401); assert.equal(providerCalls, 0);
  const streamed = await call('/v1/study', input, a.access_token, { Accept: 'application/x-ndjson' });
  assert.equal(streamed.status, 200);
  const events = streamed.text.trim().split('\n').map(JSON.parse); const result = events.find(x => x.type === 'result');
  assert.ok(events.some(x => x.type === 'delta')); assert.deepEqual(result.artifact.references[0], input.sources[0].reference);
  for (let i = 0; i < 9; i++) assert.equal((await call('/v1/study', input, a.access_token)).status, 200, 'Remaining daily quota');
  const callsBefore = providerCalls; assert.equal((await call('/v1/study', input, a.access_token)).status, 429); assert.equal(providerCalls, callsBefore);
  assert.equal((await call('/v1/study', input, b.access_token)).status, 200);
  console.log('PASS verified Auth → gateway → atomic SQL quota → provider fixture → cited NDJSON; quotas isolated per account');
  const refreshed = await call('/auth/v1/token?grant_type=refresh_token', { refresh_token: a.refresh_token }); assert.equal(refreshed.status, 200);
  const rotated = refreshed.json(); assert.ok(rotated.refresh_token); assert.equal(rotated.user.id, a.user.id);
  assert.equal((await call('/v1/platform/account', undefined, rotated.access_token)).status, 200);
  assert.ok([200, 204].includes((await call('/auth/v1/logout?scope=local', {}, rotated.access_token)).status));
  const revoked = await call('/auth/v1/token?grant_type=refresh_token', { refresh_token: rotated.refresh_token }); assert.notEqual(revoked.status, 200);
  console.log('PASS refresh rotation and logout revocation on real Auth');
  console.log('MANAGED_E2E_PASS: real local services, verified TLS, captured local email; AI transport explicitly simulated, no live provider calls.');
} finally {
  server.closeAllConnections(); await new Promise(resolve => server.close(resolve));
}
