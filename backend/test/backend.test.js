import test from 'node:test';
import assert from 'node:assert/strict';
import AdmZip from 'adm-zip';
import { checkZip, isSafeEntryPath, detectType } from '../src/zipcheck.js';
import { encrypt, decrypt, sign, verify } from '../src/security.js';
import { validateMeta } from '../src/server.js';

const mk = (files) => { const z = new AdmZip(); for (const [n, c] of Object.entries(files)) z.addFile(n, Buffer.from(c)); return z.toBuffer(); };

test('zip safety and type detection', () => {
  assert.equal(isSafeEntryPath('lib/main.dart'), true);
  assert.equal(isSafeEntryPath('../x'), false);
  assert.equal(isSafeEntryPath('/etc/passwd'), false);
  assert.equal(detectType(['pubspec.yaml', 'lib/a.dart']), 'flutter');
  const ok = checkZip(mk({ 'pubspec.yaml': 'name: a', 'lib/main.dart': 'void main(){}' }));
  assert.equal(ok.ok, true); assert.equal(ok.type, 'flutter');
  assert.equal(checkZip(Buffer.from('not a zip')).ok, false);
});

test('encryption round trip and tamper detection', () => {
  const key = Buffer.alloc(32, 7);
  const blob = encrypt(key, 'gho_secret');
  assert.equal(decrypt(key, blob), 'gho_secret');
  assert.throws(() => decrypt(Buffer.alloc(32, 8), blob));
});

test('signed urls expire and are bound to id', () => {
  const exp = Math.floor(Date.now() / 1000) + 60;
  const s = sign('k', 'source', 'job1', exp);
  assert.equal(verify('k', 'source', 'job1', exp, s), true);
  assert.equal(verify('k', 'source', 'job2', exp, s), false);
  assert.equal(verify('k', 'icon', 'job1', exp, s), false);
  const past = Math.floor(Date.now() / 1000) - 5;
  assert.equal(verify('k', 'source', 'job1', past, sign('k', 'source', 'job1', past)), false);
});

test('meta validation rejects injection', () => {
  const good = { projectName: 'Lens', appName: 'Mango Lens', packageName: 'com.mango.lens', versionName: '1.2.0', versionCode: 12, buildType: 'debug', outputName: 'MangoLens.apk' };
  assert.equal(validateMeta(good).packageName, 'com.mango.lens');
  assert.throws(() => validateMeta({ ...good, packageName: 'com.x"; rm -rf /' }));
  assert.throws(() => validateMeta({ ...good, versionName: '1.0;id' }));
  assert.throws(() => validateMeta({ ...good, outputName: '../a.apk' }));
});
