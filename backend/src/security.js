import crypto from 'node:crypto';

export const randomToken = (n = 32) => crypto.randomBytes(n).toString('hex');
export const sha256 = (s) => crypto.createHash('sha256').update(s).digest('hex');

export function encrypt(key, plain) {
  const iv = crypto.randomBytes(12);
  const c = crypto.createCipheriv('aes-256-gcm', key, iv);
  const enc = Buffer.concat([c.update(plain, 'utf8'), c.final()]);
  return [iv, c.getAuthTag(), enc].map((b) => b.toString('base64')).join('.');
}

export function decrypt(key, blob) {
  const [iv, tag, enc] = blob.split('.').map((s) => Buffer.from(s, 'base64'));
  const d = crypto.createDecipheriv('aes-256-gcm', key, iv);
  d.setAuthTag(tag);
  return Buffer.concat([d.update(enc), d.final()]).toString('utf8');
}

const hmac = (secret, msg) => crypto.createHmac('sha256', secret).update(msg).digest('hex');

/** Short-lived signature bound to a purpose, job id, and expiry. */
export function sign(secret, purpose, id, expSec) {
  return hmac(secret, `${purpose}:${id}:${expSec}`);
}

export function verify(secret, purpose, id, expSec, sig) {
  if (!sig || !Number.isFinite(Number(expSec)) || Number(expSec) < Math.floor(Date.now() / 1000)) return false;
  const a = Buffer.from(sign(secret, purpose, id, expSec));
  const b = Buffer.from(String(sig));
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}
