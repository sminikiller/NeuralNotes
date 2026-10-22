import { createApp, ResponsesAdapter } from './server.mjs';
import { DeepSeekAdapter } from './deepseek.mjs';
import http from 'node:http';
import { proposedPlans } from './plans.mjs';
import { SupabaseStore, createPlatformApp } from './platform.mjs';
import { supabaseAuthenticator } from './auth.mjs';

const type = process.env.NN_PROVIDER ?? 'deepseek';
if (!['deepseek', 'responses'].includes(type)) throw new Error('Unknown NN_PROVIDER');
const adapter = type === 'deepseek'
  ? new DeepSeekAdapter({ key: process.env.NN_PROVIDER_KEY, model: process.env.NN_MODEL ?? 'deepseek-flash', enableWebSearch: process.env.NN_ENABLE_WEB_SEARCH === '1', maxOutputTokens: Number(process.env.NN_MAX_OUTPUT_TOKENS ?? 2048) })
  : new ResponsesAdapter({ key: process.env.NN_PROVIDER_KEY, model: process.env.NN_MODEL, enableWebSearch: process.env.NN_ENABLE_WEB_SEARCH === '1' });
const authenticate = process.env.NN_SUPABASE_URL ? supabaseAuthenticator({ url: process.env.NN_SUPABASE_URL, publicKey: process.env.NN_SUPABASE_PUBLIC_KEY }) : undefined;
const store = authenticate ? new SupabaseStore({ url: process.env.NN_SUPABASE_URL, publicKey: process.env.NN_SUPABASE_PUBLIC_KEY }) : undefined;
const ai = createApp({ secret: process.env.NN_AUTH_SECRET, authenticate, adapter, ...(store ? { limiter: store } : {}) });
const platform = store ? createPlatformApp({ authenticate, store }) : undefined;
const app = http.createServer((req, res) => {
  if (req.method === 'GET' && req.url === '/v1/config') { res.writeHead(200, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' }); res.end(JSON.stringify({ version: 1, managed: !!store, auth: store ? { url: store.base.href, publicKey: store.publicKey } : null, limits: { maximumUploadBytes: 104857600 }, proposedPlans, subscriptionsActive: false })); return; }
  if (platform && req.url.startsWith('/v1/platform/')) platform.emit('request', req, res); else ai.emit('request', req, res); });
app.listen(Number(process.env.PORT ?? 8787), process.env.NN_BIND ?? '127.0.0.1', () => console.log('NeuralNotes managed gateway on loopback; publish behind HTTPS.'));
