import { spawnSync, spawn } from 'node:child_process';
import { randomBytes, createHmac } from 'node:crypto';
import { mkdirSync, readdirSync, writeFileSync, readFileSync, rmSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import net from 'node:net';

const root = fileURLToPath(new URL('../../', import.meta.url));
const id = randomBytes(5).toString('hex'), project = `neuralnotes-integration-${id}`;
const directory = path.join(root, '.verification', project); mkdirSync(directory, { recursive: true });
async function freePort() {
  const server = net.createServer(); await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const port = server.address().port; await new Promise(resolve => server.close(resolve)); return port;
}
const ports = await Promise.all([freePort(), freePort(), freePort(), freePort(), freePort()]);
const config = { authPort: ports[0], restPort: ports[1], mailPort: ports[2], port: ports[3], storagePort: ports[4], jwtSecret: randomBytes(32).toString('hex'), directory };
const origin = `https://localhost:${config.port}`;
const encode = value => Buffer.from(JSON.stringify(value)).toString('base64url');
const makeJWT = role => { const data = encode({alg:'HS256',typ:'JWT'})+'.'+encode({role,exp:Math.floor(Date.now()/1000)+3600}); return data+'.'+createHmac('sha256',config.jwtSecret).update(data).digest('base64url'); };
const environment = path.join(directory, 'test.env');
writeFileSync(environment, `NN_TEST_DB_PASSWORD=${randomBytes(24).toString('hex')}\nNN_TEST_JWT_SECRET=${config.jwtSecret}\nNN_TEST_AUTH_PORT=${config.authPort}\nNN_TEST_REST_PORT=${config.restPort}\nNN_TEST_MAIL_PORT=${config.mailPort}\nNN_TEST_ORIGIN=${origin}\nNN_TEST_STORAGE_PORT=${config.storagePort}\nNN_TEST_ANON_KEY=${makeJWT("anon")}\nNN_TEST_SERVICE_KEY=${makeJWT("service_role")}\n`, { mode: 0o600 });
const prefix = ['compose', '-p', project, '--env-file', environment, '-f', path.join(root, 'backend/integration/compose.yaml')];
function docker(args, input) {
  const result = spawnSync('docker', [...prefix, ...args], { input, encoding: 'utf8', maxBuffer: 8 * 1024 * 1024 });
  if (result.status !== 0) throw new Error(`Docker ${args[0]} failed\n${result.stderr || result.stdout}`);
  return result.stdout;
}
let started = false;
try {
  const openssl = process.env.NN_TEST_OPENSSL ?? (process.platform === 'win32' && existsSync('C:/Program Files/Git/usr/bin/openssl.exe') ? 'C:/Program Files/Git/usr/bin/openssl.exe' : 'openssl');
  const certificate = spawnSync(openssl, ['req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '2', '-subj', '/CN=localhost', '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1', '-keyout', path.join(directory, 'key.pem'), '-out', path.join(directory, 'cert.pem')], { encoding: 'utf8' });
  if (certificate.status !== 0) throw new Error('Local TLS certificate generation failed. Set NN_TEST_OPENSSL to the OpenSSL executable.');
  started = true; docker(['up', '-d', '--wait', '--wait-timeout', '90']);
  docker(['exec', '-T', 'db', 'psql', '-U', 'postgres', '-v', 'ON_ERROR_STOP=1'], readFileSync(path.join(root, 'backend/platform/schema.sql')));
  for (const migration of readdirSync(path.join(root, 'backend/platform/migrations')).filter(f => f.endsWith('.sql')).sort()) {
    docker(['exec', '-T', 'db', 'psql', '-U', 'postgres', '-v', 'ON_ERROR_STOP=1'], readFileSync(path.join(root, 'backend/platform/migrations', migration)));
  }
  docker(['exec', '-T', 'db', 'psql', '-U', 'postgres', '-c', "NOTIFY pgrst, 'reload schema';"]);
  writeFileSync(path.join(directory, 'config.json'), JSON.stringify(config), { mode: 0o600 });
  const child = spawn(process.execPath, [path.join(root, 'backend/integration/verify.mjs'), path.join(directory, 'config.json')], {
    cwd: root, env: { ...process.env, NODE_EXTRA_CA_CERTS: path.join(directory, 'cert.pem') }, stdio: 'inherit'
  });
  const status = await new Promise(resolve => child.on('exit', resolve));
  if (status !== 0) throw new Error('Managed integration verification failed');
} catch (error) {
  console.error(error.message); process.exitCode = 1;
  // Auth logs can include email/OTP details: retain locally, never print them.
  if (started) { try { writeFileSync(path.join(directory, 'services.log'), docker(['logs', '--no-color'])); } catch { } }
} finally {
  if (started) { try { docker(['down', '--volumes', '--remove-orphans']); } catch { console.error('Test containers need cleanup: ' + project); process.exitCode = 1; } }
  for (const file of ['test.env', 'config.json', 'key.pem']) { try { rmSync(path.join(directory, file)); } catch { } }
}
