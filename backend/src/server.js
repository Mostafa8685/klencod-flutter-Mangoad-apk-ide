import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import express from 'express';
import helmet from 'helmet';
import multer from 'multer';
import rateLimit from 'express-rate-limit';
import { loadConfig } from './config.js';
import { Store } from './store.js';
import { GitHub, RateLimitError } from './github.js';
import { BuildQueue } from './queue.js';
import { checkZip } from './zipcheck.js';
import { decrypt, encrypt, randomToken, sha256, sign, verify } from './security.js';

class HttpError extends Error {
  constructor(status, code, message) { super(message ?? code); this.status = status; this.code = code; }
}

const PKG = /^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$/;
const RESERVED = new Set(['abstract','assert','boolean','break','byte','case','catch','char','class','const','continue','default','do','double','else','enum','extends','final','finally','float','for','goto','if','implements','import','instanceof','int','interface','long','native','new','package','private','protected','public','return','short','static','strictfp','super','switch','synchronized','this','throw','throws','transient','try','void','volatile','while','true','false','null']);

export function validateMeta(m) {
  const bad = (f) => new HttpError(400, 'invalid_request', `Invalid field: ${f}`);
  if (typeof m !== 'object' || !m) throw bad('meta');
  const s = (v) => (typeof v === 'string' ? v.trim() : '');
  const out = {
    projectName: s(m.projectName), appName: s(m.appName), packageName: s(m.packageName),
    versionName: s(m.versionName), versionCode: Number(m.versionCode), buildType: s(m.buildType), outputName: s(m.outputName),
  };
  if (!out.projectName || out.projectName.length > 60 || /[\x00-\x1f]/.test(out.projectName)) throw bad('projectName');
  if (!out.appName || out.appName.length > 60 || /[<>"\x00-\x1f]/.test(out.appName)) throw bad('appName');
  if (!PKG.test(out.packageName) || out.packageName.length > 100 || out.packageName.split('.').some((p) => RESERVED.has(p))) throw bad('packageName');
  if (!/^[0-9A-Za-z][0-9A-Za-z._-]{0,31}$/.test(out.versionName)) throw bad('versionName');
  if (!Number.isInteger(out.versionCode) || out.versionCode < 1 || out.versionCode > 2100000000) throw bad('versionCode');
  if (!['debug', 'release'].includes(out.buildType)) throw bad('buildType');
  if (!/^[A-Za-z0-9._-]{1,64}\.apk$/.test(out.outputName)) throw bad('outputName');
  return out;
}

export function createApp(cfg) {
  const store = new Store(cfg.dataDir);
  const gh = new GitHub(cfg);
  const queue = new BuildQueue(cfg, store, gh);
  const app = express();
  app.set('trust proxy', 1);
  app.disable('x-powered-by');
  app.use(helmet());
  app.use(express.json({ limit: '10kb' }));
  app.use(rateLimit({ windowMs: 60000, limit: 120, standardHeaders: true, legacyHeaders: false, message: { error: { code: 'rate_limited', message: 'Too many requests' } } }));

  const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: cfg.maxZipMb * 1024 * 1024, files: 2, fields: 2, fieldSize: 4096 } });
  const buildLimiter = rateLimit({ windowMs: 3600000, limit: 10, keyGenerator: (r) => r.user?.id ?? r.ip, message: { error: { code: 'rate_limited', message: 'Build limit reached' } } });
  const sessionLimiter = rateLimit({ windowMs: 3600000, limit: 20, message: { error: { code: 'rate_limited', message: 'Too many sessions' } } });
  const wrap = (fn) => (req, res, next) => Promise.resolve(fn(req, res, next)).catch(next);

  // ---- Authentication: opaque bearer session per app install ----
  const auth = (req, _res, next) => {
    const h = req.headers.authorization ?? '';
    const user = h.startsWith('Bearer ') ? store.findUserByTokenHash(sha256(h.slice(7))) : null;
    if (!user) return next(new HttpError(401, 'unauthorized'));
    req.user = user; next();
  };
  const ownJob = (req) => {
    const job = store.getJob(req.params.jobId);
    if (!job || job.userId !== req.user.id) throw new HttpError(404, 'not_found'); // same reply: no existence leak
    return job;
  };
  const publicJob = (j) => ({
    id: j.id, projectName: j.projectName, projectType: j.projectType, packageName: j.packageName,
    versionName: j.versionName, buildType: j.buildType, stage: j.stage, createdAt: j.createdAt,
    startedAt: j.startedAt ?? null, finishedAt: j.finishedAt ?? null, apkName: j.apkName ?? null, apkSize: j.apkSize ?? null, error: j.error ?? null,
  });

  app.get('/health', (_q, r) => r.json({ ok: true }));

  app.post('/api/session', sessionLimiter, wrap((req, res) => {
    const deviceId = String(req.body?.deviceId ?? '');
    if (!/^[0-9a-f]{32}$/.test(deviceId)) throw new HttpError(400, 'invalid_request');
    const id = sha256(deviceId).slice(0, 24);
    const token = randomToken();
    const prev = store.getUser(id);
    store.putUser({ ...(prev ?? {}), id, tokenHash: sha256(token), createdAt: prev?.createdAt ?? new Date().toISOString() });
    store.audit('session', { user: id });
    res.json({ token });
  }));

  // ---- GitHub Device Flow ----
  app.post('/api/auth/github/device/start', auth, wrap(async (req, res) => {
    const d = await gh.deviceStart();
    req.user.device = { code: encrypt(cfg.encryptionKey, d.device_code), expiresAt: Date.now() + d.expires_in * 1000, interval: d.interval, nextPollAt: 0 };
    store.putUser(req.user);
    store.audit('device_start', { user: req.user.id });
    res.json({ user_code: d.user_code, verification_uri: d.verification_uri, expires_in: d.expires_in, interval: d.interval });
  }));

  app.get('/api/auth/github/device/status', auth, wrap(async (req, res) => {
    const u = req.user;
    if (u.ghToken && !u.device) return res.json({ status: 'connected', login: u.ghLogin });
    if (!u.device) return res.json({ status: 'none' });
    if (Date.now() > u.device.expiresAt) { delete u.device; store.putUser(u); return res.json({ status: 'expired' }); }
    if (Date.now() < u.device.nextPollAt) return res.json({ status: 'pending', interval: u.device.interval });
    u.device.nextPollAt = Date.now() + u.device.interval * 1000;
    const r = await gh.devicePoll(decrypt(cfg.encryptionKey, u.device.code));
    if (r.access_token) {
      const login = await gh.userLogin(r.access_token);
      if (!login) throw new HttpError(502, 'github_error');
      u.ghToken = encrypt(cfg.encryptionKey, r.access_token); u.ghLogin = login; delete u.device;
      store.putUser(u); store.audit('github_connected', { user: u.id });
      return res.json({ status: 'connected', login });
    }
    switch (r.error) {
      case 'authorization_pending': store.putUser(u); return res.json({ status: 'pending', interval: u.device.interval });
      case 'slow_down': u.device.interval = r.interval ?? u.device.interval + 5; store.putUser(u); return res.json({ status: 'slow_down', interval: u.device.interval });
      case 'expired_token': delete u.device; store.putUser(u); return res.json({ status: 'expired' });
      case 'access_denied': delete u.device; store.putUser(u); return res.json({ status: 'denied' });
      default: throw new HttpError(502, 'github_error');
    }
  }));

  app.post('/api/auth/github/disconnect', auth, wrap((req, res) => {
    delete req.user.ghToken; delete req.user.ghLogin; delete req.user.device;
    store.putUser(req.user); store.audit('github_disconnected', { user: req.user.id });
    res.json({ ok: true });
  }));

  const requireGithub = async (user) => {
    if (!user.ghToken) throw new HttpError(403, 'github_not_connected');
    const login = await gh.userLogin(decrypt(cfg.encryptionKey, user.ghToken));
    if (!login) { delete user.ghToken; store.putUser(user); throw new HttpError(403, 'token_expired'); }
  };

  // ---- Builds ----
  const newJob = (user, meta, projectType, hasIcon) => ({
    id: crypto.randomUUID(), userId: user.id, ...meta, projectType, hasIcon,
    stage: 'waiting', createdAt: new Date().toISOString(), logs: [`${new Date().toISOString()} queued`],
  });

  app.post('/api/builds', auth, buildLimiter, upload.fields([{ name: 'source', maxCount: 1 }, { name: 'icon', maxCount: 1 }]), wrap(async (req, res) => {
    await requireGithub(req.user);
    let meta;
    try { meta = validateMeta(JSON.parse(req.body.meta)); } catch (e) { throw e instanceof HttpError ? e : new HttpError(400, 'invalid_request'); }
    const zip = req.files?.source?.[0]?.buffer;
    if (!zip) throw new HttpError(400, 'invalid_request', 'Missing source');
    const check = checkZip(zip);
    if (!check.ok) throw new HttpError(400, check.code, check.message);
    if (!['flutter', 'native'].includes(check.type)) throw new HttpError(400, 'unsupported_project', `Project type "${check.type}" has no build path yet`);
    if (meta.buildType === 'release' && check.type !== 'flutter') throw new HttpError(400, 'release_unsupported', 'Release builds are only supported for Flutter projects');
    const icon = req.files?.icon?.[0]?.buffer;
    if (icon && !(icon[0] === 0x89 && icon[1] === 0x50) && !(icon[0] === 0xff && icon[1] === 0xd8)) throw new HttpError(400, 'invalid_request', 'Icon must be PNG or JPEG');
    if (icon && icon.length > 5 * 1024 * 1024) throw new HttpError(400, 'invalid_request', 'Icon too large');
    const job = newJob(req.user, meta, check.type, Boolean(icon));
    const dir = store.jobDir(job.id);
    fs.mkdirSync(dir, { recursive: true, mode: 0o700 });
    fs.writeFileSync(path.join(dir, 'source.zip'), zip);
    if (icon) fs.writeFileSync(path.join(dir, 'icon.img'), icon);
    store.putJob(job); store.audit('build_created', { user: req.user.id, job: job.id, type: check.type });
    queue.enqueue(job.id);
    res.status(201).json({ job: publicJob(job) });
  }));

  app.get('/api/builds', auth, (req, res) => res.json({ jobs: store.jobsOf(req.user.id).map(publicJob) }));
  app.get('/api/builds/:jobId', auth, (req, res) => res.json({ job: publicJob(ownJob(req)) }));
  app.get('/api/builds/:jobId/logs', auth, (req, res) => res.json({ logs: ownJob(req).logs }));

  app.post('/api/builds/:jobId/retry', auth, buildLimiter, wrap(async (req, res) => {
    const old = ownJob(req);
    await requireGithub(req.user);
    if (old.stage !== 'failed') throw new HttpError(409, 'invalid_state');
    const src = path.join(store.jobDir(old.id), 'source.zip');
    if (!fs.existsSync(src)) throw new HttpError(410, 'source_expired');
    const { id, userId, stage, logs, createdAt, runId, startedAt, finishedAt, error, apkName, apkSize, ...rest } = old;
    const job = newJob(req.user, {}, rest.projectType, rest.hasIcon);
    Object.assign(job, rest, { id: job.id });
    fs.mkdirSync(store.jobDir(job.id), { recursive: true, mode: 0o700 });
    for (const f of ['source.zip', 'icon.img']) if (fs.existsSync(path.join(store.jobDir(old.id), f))) fs.copyFileSync(path.join(store.jobDir(old.id), f), path.join(store.jobDir(job.id), f));
    store.putJob(job); queue.enqueue(job.id);
    res.status(201).json({ job: publicJob(job) });
  }));

  // ---- Download: signed, short-lived, bound to this job and user ----
  const sendApk = (job, res) => {
    const file = path.join(store.jobDir(job.id), 'output.apk');
    if (job.stage !== 'completed' || !fs.existsSync(file)) throw new HttpError(404, 'artifact_missing');
    store.audit('download', { job: job.id });
    res.download(file, job.apkName, { headers: { 'content-type': 'application/vnd.android.package-archive' } });
  };
  app.post('/api/builds/:jobId/download-link', auth, wrap((req, res) => {
    const job = ownJob(req);
    if (job.stage !== 'completed') throw new HttpError(409, 'artifact_missing');
    const exp = Math.floor(Date.now() / 1000) + cfg.downloadLinkTtlSec;
    const sig = sign(cfg.signingSecret, `dl:${job.userId}`, job.id, exp);
    res.json({ url: `${cfg.publicUrl}/api/builds/${job.id}/download?exp=${exp}&sig=${sig}`, expiresAt: new Date(exp * 1000).toISOString() });
  }));
  app.get('/api/builds/:jobId/download', wrap((req, res) => {
    const job = store.getJob(req.params.jobId);
    if (!job) throw new HttpError(404, 'not_found');
    const viaSig = verify(cfg.signingSecret, `dl:${job.userId}`, job.id, req.query.exp, req.query.sig);
    if (!viaSig) { // fall back to bearer auth + ownership
      return auth(req, res, (err) => { if (err) throw err; ownJob(req); sendApk(job, res); });
    }
    sendApk(job, res);
  }));

  // ---- Internal: runner fetches source/icon with a 15-minute signed URL ----
  for (const [kind, file] of [['source', 'source.zip'], ['icon', 'icon.img']]) {
    app.get(`/internal/${kind}/:jobId`, wrap((req, res) => {
      const { jobId } = req.params;
      if (!verify(cfg.signingSecret, kind, jobId, req.query.exp, req.query.sig)) throw new HttpError(403, 'forbidden');
      const p = path.join(store.jobDir(jobId), file);
      if (!/^[0-9a-f-]{36}$/.test(jobId) || !fs.existsSync(p)) throw new HttpError(404, 'not_found');
      res.sendFile(p);
    }));
  }

  // ---- Error handling: never leak stack traces ----
  app.use((err, _req, res, _next) => {
    if (err instanceof multer.MulterError) return res.status(413).json({ error: { code: 'zip_invalid', message: 'Upload too large or malformed' } });
    if (err instanceof RateLimitError) return res.status(429).json({ error: { code: 'rate_limited', message: 'GitHub rate limit' } });
    if (err instanceof HttpError) return res.status(err.status).json({ error: { code: err.code, message: err.message } });
    console.error('internal error:', err?.message);
    res.status(500).json({ error: { code: 'internal_error', message: 'Internal error' } });
  });

  return { app, store, queue };
}

if (process.argv[1] === new URL(import.meta.url).pathname) {
  const cfg = loadConfig();
  const { app, queue } = createApp(cfg);
  queue.resume();
  setInterval(() => queue.sweep(), 3600 * 1000).unref();
  queue.sweep();
  app.listen(cfg.port, () => console.log(`Mango backend listening on ${cfg.port}`));
}
