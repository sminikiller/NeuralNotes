// Checks names/status only. No provider key, token, email, or response is logged.
import { pathToFileURL } from 'node:url';
import { DeepSeekAdapter } from './deepseek.mjs';
import { requirePublicKey } from './auth.mjs';
export function configurationChecks(env) {
  const required = ['NN_SUPABASE_URL', 'NN_SUPABASE_PUBLIC_KEY', 'NN_PROVIDER_KEY'];
  const missing = required.filter(key => !env[key]);
  const problems = [];
  if (env.NN_SUPABASE_URL) {
    try { const url = new URL(env.NN_SUPABASE_URL); if (url.protocol !== 'https:' || url.username || url.password || url.search || url.hash || url.pathname !== '/') problems.push('invalid NN_SUPABASE_URL'); }
    catch { problems.push('invalid NN_SUPABASE_URL'); }
  }
  if (env.NN_SUPABASE_PUBLIC_KEY) { try { requirePublicKey(env.NN_SUPABASE_PUBLIC_KEY); } catch { problems.push('NN_SUPABASE_PUBLIC_KEY must be publishable/anon'); } }
  return { configured: missing.length === 0 && problems.length === 0, missing, problems };
}
async function main() {
  const checks = configurationChecks(process.env); console.log(JSON.stringify(checks));
  if (!checks.configured) { process.exitCode = 2; return; }
  const auth = await fetch(new URL('/auth/v1/settings', process.env.NN_SUPABASE_URL), {
    headers: { apikey: process.env.NN_SUPABASE_PUBLIC_KEY }, redirect: 'error', signal: AbortSignal.timeout(15000)
  });
  if (!auth.ok) throw new Error('Hosted Auth settings check failed');
  const settings = await auth.json(); console.log(JSON.stringify({ authReachable: true, emailEnabled: settings.external?.email === true }));
  if (process.argv.includes('--live-model')) {
    if ((process.env.NN_PROVIDER ?? 'deepseek') !== 'deepseek') throw new Error('This bounded probe only supports a DeepSeek-configured key');
    // Explicit bounded live probe with synthetic text, never notebook content.
    const adapter = new DeepSeekAdapter({ key: process.env.NN_PROVIDER_KEY, model: process.env.NN_MODEL ?? 'deepseek-flash', maxOutputTokens: 256 });
    const result = await adapter.generate({ task: 'chat', question: 'Riassumi in una frase la fonte.', sources: [{ text: 'Questo è un controllo tecnico del collegamento AI.', reference: { documentID: '00000000-0000-4000-8000-000000000001' } }] }, AbortSignal.timeout(30000));
    if (!result?.text || !result.references?.length) throw new Error('Live model response failed validation');
    console.log(JSON.stringify({ liveModel: 'passed', outputStored: false }));
  } else console.log(JSON.stringify({ liveModel: 'not_tested' }));
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) main().catch(() => { console.error('Preflight failed; check hosted service configuration. Secrets and response content omitted.'); process.exitCode = 1; });
