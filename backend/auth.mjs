export function requirePublicKey(key) {
  if (typeof key !== 'string') throw new Error('Publishable/anon key required');
  if (key.startsWith('sb_publishable_')) return key;
  try { if (JSON.parse(Buffer.from(key.split('.')[1], 'base64url').toString('utf8')).role === 'anon') return key; } catch { }
  throw new Error('Use a publishable/anon key, never a service-role secret');
}
// Hosted Auth owns passwords, recovery and token refresh. No service key here.
export function supabaseAuthenticator({ url, publicKey }, transport = fetch) {
  requirePublicKey(publicKey);
  const origin = new URL(url);
  if (origin.protocol !== 'https:' || origin.username || origin.password || origin.pathname !== '/' || !publicKey) throw new Error('Invalid Supabase Auth configuration');
  return async token => {
    if (!token || token.length > 8192) return null;
    const response = await transport(new URL('/auth/v1/user', origin), { redirect: 'error', headers: { apikey: publicKey, Authorization: `Bearer ${token}` }, signal: AbortSignal.timeout(8000) });
    if (!response.ok) { await response.body?.cancel(); return null; }
    if (!response.body) return null;
    const chunks = []; let size = 0;
    for await (const chunk of response.body) { size += chunk.length; if (size > 65536) return null; chunks.push(chunk); }
    const text = Buffer.concat(chunks).toString('utf8');
    let user; try { user = JSON.parse(text); } catch { return null; }
    if (user.is_anonymous === true) return null;
    return typeof user.id === 'string' && /^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i.test(user.id) ? user.id : null;
  };
}
