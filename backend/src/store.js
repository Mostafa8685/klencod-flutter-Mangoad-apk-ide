import fs from 'node:fs';
import path from 'node:path';

/** Tiny JSON store with atomic writes. Secrets inside are always encrypted by callers. */
export class Store {
  constructor(dir) {
    this.dir = dir;
    this.file = path.join(dir, 'db.json');
    fs.mkdirSync(path.join(dir, 'jobs'), { recursive: true });
    this.data = fs.existsSync(this.file) ? JSON.parse(fs.readFileSync(this.file, 'utf8')) : { users: {}, jobs: {} };
  }
  save() {
    const tmp = `${this.file}.tmp`;
    fs.writeFileSync(tmp, JSON.stringify(this.data), { mode: 0o600 });
    fs.renameSync(tmp, this.file);
  }
  getUser = (id) => this.data.users[id];
  findUserByTokenHash(h) {
    return Object.values(this.data.users).find((u) => u.tokenHash === h);
  }
  putUser(u) { this.data.users[u.id] = u; this.save(); }
  getJob = (id) => this.data.jobs[id];
  putJob(j) { this.data.jobs[j.id] = j; this.save(); }
  deleteJob(id) { delete this.data.jobs[id]; this.save(); }
  jobsOf = (userId) => Object.values(this.data.jobs).filter((j) => j.userId === userId);
  jobDir(id) { return path.join(this.dir, 'jobs', id); }
  audit(event, fields = {}) {
    // Never pass tokens or codes here.
    fs.appendFile(path.join(this.dir, 'audit.log'), JSON.stringify({ t: new Date().toISOString(), event, ...fields }) + '\n', () => {});
  }
}
