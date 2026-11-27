import test from 'node:test';
import assert from 'node:assert/strict';
import { once } from 'node:events';
import { DeepSeekAdapter } from './deepseek.mjs';
import { createApp } from './server.mjs';
import { supabaseAuthenticator, requirePublicKey } from './auth.mjs';
const signal = () => new AbortController().signal;
const ref = { documentID: '11111111-1111-4111-8111-111111111111' };
const request = () => ({ task: 'chat', question: 'Spiega', sources: [{ text: 'Entropia: esempio', reference: ref }] });
const completed = value => Response.json({ choices: [{ finish_reason: 'stop', message: { content: JSON.stringify(value) } }] });

test('DeepSeek uses fast JSON mode, server model and source text without UUIDs', async () => {
  const adapter = new DeepSeekAdapter({ key: 'fixture-key' }, async (url, options) => {
    assert.equal(url, 'https://api.deepseek.com/chat/completions'); assert.equal(options.redirect, 'error');
    const body = JSON.parse(options.body); assert.equal(body.model, 'deepseek-flash'); assert.deepEqual(body.thinking, { type: 'disabled' });
    assert.deepEqual(body.response_format, { type: 'json_object' }); assert.match(body.messages[0].content, /JSON/);
    assert.equal(options.body.includes(ref.documentID), false); assert.equal(body.max_tokens, 2048);
    return completed({ text: 'Spiegazione [1]', citations: [1] });
  });
  const value = await adapter.generate(request(), signal()); assert.deepEqual(value.references, [ref]);
});

test('DeepSeek refuses truncation, empty JSON and fabricated references', async () => {
  for (const response of [() => Response.json({ choices: [{ finish_reason: 'length', message: { content: '{}' } }] }),
    () => completed({ text: 'Falso [2]', citations: [2] }), () => Response.json({ choices: [{ finish_reason: 'stop', message: { content: '' } }] })]) {
    const adapter = new DeepSeekAdapter({ key: 'fixture' }, async () => response());
    await assert.rejects(adapter.generate(request(), signal()));
  }
});

test('DeepSeek streams Unicode text, then validates final citations', async () => {
  const raw = JSON.stringify({ text: 'È così 🧠 [1]', citations: [1] });
  let wire = '';
  for (const char of raw) wire += `data: ${JSON.stringify({ choices: [{ delta: { content: char }, finish_reason: null }] })}

`;
  wire += 'data: {"choices":[{"delta":{},"finish_reason":"stop"}]}\n\ndata: [DONE]\n\n';
  const bytes = new TextEncoder().encode(wire);
  const adapter = new DeepSeekAdapter({ key: 'fixture' }, async () => new Response(new ReadableStream({ start(controller) { for (let i = 0; i < bytes.length; i += 3) controller.enqueue(bytes.slice(i, i + 3)); controller.close(); } })));
  const events = []; for await (const event of adapter.generateStream(request(), signal())) events.push(event);
  assert.equal(events.filter(v => v.type === 'delta').map(v => v.text).join(''), 'È così 🧠 [1]');
  assert.deepEqual(events.at(-1).artifact.references, [ref]);
});

test('DeepSeek incomplete stream never emits a final artifact', async () => {
  const adapter = new DeepSeekAdapter({ key: 'fixture' }, async () => new Response('data: {"choices":[{"delta":{"content":"{\"text\":\"Parziale"}}]}\n\n'));
  const events = [];
  await assert.rejects(async () => { for await (const event of adapter.generateStream(request(), signal())) events.push(event); });
  assert.equal(events.some(v => v.type === 'result'), false);
});

test('DeepSeek lookup and quiz preserve validated app contracts', async () => {
  const adapter = new DeepSeekAdapter({ key: 'fixture' }, async (_url, options) => {
    const body = JSON.parse(options.body), data = JSON.parse(body.messages[1].content);
    return completed(data.term ? { term: data.term, definition: 'Definizione [1]', explanation: '', examples: [], relatedTerms: [], citations: [1] }
      : { title: 'Quiz', questions: [{ prompt: 'Domanda [1]', options: ['A', 'B', 'C', 'D'], correctIndex: 1, explanation: 'Motivo [1]', citations: [1] }] });
  });
  assert.equal((await adapter.lookup({ term: 'Entropia', sources: request().sources }, signal())).term, 'Entropia');
  assert.equal((await adapter.quiz({ count: 2, sources: request().sources }, signal())).questions.length, 1);
});

test('DeepSeek explain answers from general knowledge in JSON mode with thinking off', async () => {
  const adapter = new DeepSeekAdapter({ key: 'fixture' }, async (_url, options) => {
    const body = JSON.parse(options.body), data = JSON.parse(body.messages[1].content);
    assert.equal(body.response_format.type, 'json_object'); assert.deepEqual(body.thinking, { type: 'disabled' }); assert.ok(body.max_tokens <= 2048);
    assert.match(body.messages[0].content, /conoscenza generale/); assert.doesNotMatch(body.messages[0].content, /Usa soltanto le fonti/);
    assert.match(body.messages[0].content, /\*\*grassetto\*\*/);
    assert.match(body.messages[0].content, /"- "/);
    assert.match(body.messages[0].content, /"1\. "/);
    assert.deepEqual(data, { term: 'Napoleone', selection: '', question: '', context: 'campagna di Russia', subject: 'Storia' });
    return completed({ term: 'Napoleone', kind: 'persona', explanation: 'Imperatore dei francesi.', certain: true });
  });
  const value = await adapter.explain({ term: 'Napoleone', context: 'campagna di Russia', subject: 'Storia' }, signal());
  assert.equal(value.kind, 'persona'); assert.equal(value.provider, 'DeepSeek / deepseek-flash');
  const photo = new DeepSeekAdapter({ key: 'fixture' }, async (_url, options) => {
    const user = JSON.parse(options.body).messages[1].content;
    assert.deepEqual(user.map(part => part.type), ['text', 'image_url']); assert.equal(user[1].image_url.url, 'data:image/jpeg;base64,aGVsbG8=');
    assert.equal(JSON.parse(user[0].text).question, 'Chi è?');
    return completed({ term: '', kind: 'persona', explanation: 'Una persona.', certain: false });
  });
  assert.equal((await photo.explain({ term: '', selection: '', question: 'Chi è?', context: '', subject: '', image: 'aGVsbG8=' }, signal())).term, 'Chi è?');
  const truncated = new DeepSeekAdapter({ key: 'fixture' }, async () => Response.json({ choices: [{ finish_reason: 'length', message: { content: '{' } }] }));
  await assert.rejects(truncated.explain({ term: 'x', context: '', subject: '' }, signal()));
});

test('DeepSeek cards ask for JSON drafts with focus and keep validated citations', async () => {
  const adapter = new DeepSeekAdapter({ key: 'fixture' }, async (_url, options) => {
    const body = JSON.parse(options.body), data = JSON.parse(body.messages[1].content);
    assert.equal(body.response_format.type, 'json_object'); assert.match(body.messages[0].content, /flashcard/);
    assert.equal(data.focus, 'calore'); assert.equal(data.sources[0].reference, undefined);
    return completed({ cards: [{ question: 'Domanda [1]', answer: 'Risposta [1]', citations: [1] }] });
  });
  const value = await adapter.cards({ count: 2, focus: 'calore', sources: request().sources }, signal());
  assert.equal(value.cards.length, 1); assert.deepEqual(value.cards[0].references, [ref]);
  const invented = new DeepSeekAdapter({ key: 'fixture' }, async () => completed({ cards: [{ question: 'Domanda [2]', answer: 'Risposta', citations: [2] }] }));
  await assert.rejects(invented.cards({ count: 2, focus: '', sources: request().sources }, signal()));
});

test('DeepSeek web lookup searches isolated term and only cites search URLs', async () => {
  let calls = 0;
  const transport = async (url, options) => {
    calls++; const body = JSON.parse(options.body);
    if (url.endsWith('/tools/search')) { assert.deepEqual(body, { query: 'Entropia', count: 5, need_content: true }); return Response.json({ results: [{ title: 'Fonte', url: 'https://example.com/term', summary: 'Concetto documentato.' }] }); }
    assert.equal(options.body.includes('private notebook text'), false);
    return completed({ text: 'Sintesi [1]', citations: [1], ignoredURL: 'https://invented.invalid' });
  };
  const disabled = new DeepSeekAdapter({ key: 'fixture' }, transport);
  await assert.rejects(disabled.research({ term: 'Entropia' }, signal()), { code: 'web_search_disabled' }); assert.equal(calls, 0);
  const enabled = new DeepSeekAdapter({ key: 'fixture', enableWebSearch: true }, transport);
  const result = await enabled.research({ term: 'Entropia', sources: 'private notebook text' }, signal());
  assert.equal(result.webSources[0].url, 'https://example.com/term'); assert.deepEqual(result.references, []); assert.equal(calls, 2);
});

test('DeepSeek web rejects unsafe URLs, empty search and missing citations', async () => {
  for (const found of [{ results: [] }, { results: [{ title: 'Unsafe', url: 'javascript:alert(1)', summary: 'text' }] }]) {
    const adapter = new DeepSeekAdapter({ key: 'fixture', enableWebSearch: true }, async () => Response.json(found));
    await assert.rejects(adapter.research({ term: 'Termine' }, signal()));
  }
});

test('Hosted Auth validates with fixed trusted origin and rejects malformed user IDs', async () => {
  const authenticate = supabaseAuthenticator({ url: 'https://project.supabase.co', publicKey: 'sb_publishable_fixture' }, async (url, options) => {
    assert.equal(url.href, 'https://project.supabase.co/auth/v1/user'); assert.equal(options.headers.Authorization, 'Bearer fixture-token');
    return Response.json({ id: ref.documentID });
  });
  assert.equal(await authenticate('fixture-token'), ref.documentID); assert.equal(await authenticate(''), null);
  const bad = supabaseAuthenticator({ url: 'https://project.supabase.co', publicKey: 'sb_publishable_fixture' }, async () => Response.json({ id: 'forged' }));
  assert.equal(await bad('token'), null);
});

test('Managed gateway authenticates before forwarding AI requests', async () => {
  let calls = 0;
  const server = createApp({ authenticate: async token => token === 'verified-fixture' ? ref.documentID : null,
    adapter: { async generate() { calls++; return { text: 'OK' }; } } });
  server.listen(0, '127.0.0.1'); await once(server, 'listening');
  try {
    const url = `http://127.0.0.1:${server.address().port}/v1/study`;
    for (const [token, status] of [['forged', 401], ['verified-fixture', 200]]) {
      const response = await fetch(url, { method: 'POST', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body: JSON.stringify(request()) });
      assert.equal(response.status, status); await response.body.cancel();
    }
    assert.equal(calls, 1);
  } finally { server.close(); await once(server, 'close'); }
});

test('Managed configuration rejects service-role keys before they can reach a client', () => {
  assert.throws(() => requirePublicKey('sb_secret_do_not_publish'));
  const token = 'header.' + Buffer.from(JSON.stringify({ role: 'service_role' })).toString('base64url') + '.signature';
  assert.throws(() => requirePublicKey(token));
  assert.equal(requirePublicKey('sb_publishable_fixture'), 'sb_publishable_fixture');
});
