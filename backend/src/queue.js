import fs from 'node:fs';
import path from 'node:path';
import AdmZip from 'adm-zip';
import { sign } from './security.js';
import { RateLimitError } from './github.js';

const STEP_STAGE = {
  'Download source': 'preparing',
  'Validate and prepare': 'validating',
  'Install dependencies': 'installing',
  'Build APK': 'building',
  'Upload artifact': 'uploading',
};
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

export class BuildQueue {
  constructor(cfg, store, gh) {
    this.cfg = cfg; this.store = store; this.gh = gh;
    this.pending = []; this.running = 0;
  }

  enqueue(jobId) { this.pending.push(jobId); this.#pump(); }

  resume() {
    for (const j of Object.values(this.store.data.jobs)) if (!['completed', 'failed'].includes(j.stage)) this.enqueue(j.id);
  }

  #pump() {
    while (this.running < this.cfg.maxParallel && this.pending.length) {
      const id = this.pending.shift();
      this.running++;
      this.#run(id).catch((e) => this.#fail(id, 'internal_error', e)).finally(() => { this.running--; this.#pump(); });
    }
  }

  #log(job, line) { job.logs.push(`${new Date().toISOString()} ${line}`); if (job.logs.length > 500) job.logs.shift(); }

  #fail(id, code, err) {
    const job = this.store.getJob(id);
    if (!job) return;
    job.stage = 'failed'; job.error = code; job.finishedAt = new Date().toISOString();
    this.#log(job, `FAILED: ${code}${err ? ` (${String(err.message ?? err).slice(0, 200)})` : ''}`);
    this.store.putJob(job);
    this.store.audit('build_failed', { job: id, code });
  }

  async #run(id) {
    const { cfg, store, gh } = this;
    const job = store.getJob(id);
    if (!job) return;
    const setStage = (s) => { if (job.stage !== s) { job.stage = s; this.#log(job, `stage: ${s}`); store.putJob(job); } };
    const deadline = Date.now() + cfg.buildTimeoutMin * 60000;

    const withBackoff = async (fn) => {
      for (;;) {
        try { return await fn(); } catch (e) {
          if (!(e instanceof RateLimitError)) throw e;
          this.#log(job, 'GitHub rate limit reached, waiting');
          await sleep(Math.min(Math.max(e.resetAtMs - Date.now(), 5000), 120000));
          if (Date.now() > deadline) throw new Error('timeout');
        }
      }
    };

    try {
      job.startedAt ??= new Date().toISOString();
      if (!job.runId) {
        const exp = Math.floor(Date.now() / 1000) + 900;
        const url = (kind) => `${cfg.publicUrl}/internal/${kind}/${id}?exp=${exp}&sig=${sign(cfg.signingSecret, kind, id, exp)}`;
        await withBackoff(() => gh.dispatch({
          job_id: id,
          source_url: url('source'),
          icon_url: job.hasIcon ? url('icon') : '',
          app_name: job.appName, package_name: job.packageName,
          version_name: job.versionName, version_code: String(job.versionCode),
          build_type: job.buildType, output_name: job.outputName,
        }));
        this.#log(job, 'workflow dispatched');
        store.putJob(job);
        for (let i = 0; i < 24 && !job.runId; i++) {
          await sleep(5000);
          const run = await withBackoff(() => gh.findRun(id));
          if (run) { job.runId = run.id; store.putJob(job); }
        }
        if (!job.runId) return this.#fail(id, 'run_not_found');
      }

      for (;;) {
        if (Date.now() > deadline) return this.#fail(id, 'timeout');
        const run = await withBackoff(() => gh.getRun(job.runId));
        const steps = await withBackoff(() => gh.runSteps(job.runId));
        const active = steps.find((s) => s.status === 'in_progress') ?? [...steps].reverse().find((s) => s.status === 'completed' && STEP_STAGE[s.name]);
        if (active && STEP_STAGE[active.name]) setStage(STEP_STAGE[active.name]);
        else if (run.status === 'queued') setStage('waiting');
        if (run.status === 'completed') {
          if (run.conclusion !== 'success') {
            const bad = steps.find((s) => s.conclusion === 'failure');
            return this.#fail(id, bad?.name === 'Validate and prepare' ? 'unsupported_project' : 'build_failed', new Error(bad ? `step "${bad.name}" failed` : run.conclusion));
          }
          break;
        }
        await sleep(15000);
      }

      const zipBuf = await withBackoff(() => gh.downloadArtifact(job.runId, id));
      const apk = zipBuf && new AdmZip(zipBuf).getEntries().find((e) => e.entryName.endsWith('.apk') && !e.isDirectory);
      const data = apk?.getData();
      if (!data || data.length < 1000 || data[0] !== 0x50 || data[1] !== 0x4b) return this.#fail(id, 'artifact_missing');
      const dir = store.jobDir(id);
      fs.writeFileSync(path.join(dir, 'output.apk'), data);
      job.apkName = job.outputName; job.apkSize = data.length;
      job.stage = 'completed'; job.finishedAt = new Date().toISOString();
      this.#log(job, `completed, apk ${data.length} bytes`);
      store.putJob(job);
      store.audit('build_completed', { job: id });
    } catch (e) {
      this.#fail(id, e.message === 'timeout' ? 'timeout' : 'build_failed', e);
    }
  }

  /** Deletes expired jobs and their files (retention policy). */
  sweep() {
    const cutoff = Date.now() - this.cfg.retentionHours * 3600 * 1000;
    for (const j of Object.values(this.store.data.jobs)) {
      if (new Date(j.createdAt).getTime() < cutoff && ['completed', 'failed'].includes(j.stage)) {
        fs.rmSync(this.store.jobDir(j.id), { recursive: true, force: true });
        this.store.deleteJob(j.id);
        this.store.audit('job_expired', { job: j.id });
      }
    }
  }
}
