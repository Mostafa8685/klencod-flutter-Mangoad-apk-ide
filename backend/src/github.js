export class RateLimitError extends Error {
  constructor(resetAtMs) { super('github_rate_limited'); this.resetAtMs = resetAtMs; }
}

const API = 'https://api.github.com';
const UA = 'mango-apk-studio-backend';

async function guard(res) {
  if (res.status === 429 || (res.status === 403 && res.headers.get('x-ratelimit-remaining') === '0')) {
    const reset = Number(res.headers.get('x-ratelimit-reset')) * 1000;
    const retry = Number(res.headers.get('retry-after')) * 1000;
    throw new RateLimitError(reset || Date.now() + (retry || 60000));
  }
  return res;
}

export class GitHub {
  constructor(cfg) { this.cfg = cfg; }

  // ---- OAuth Device Flow (official endpoints) ----
  async deviceStart() {
    const r = await fetch('https://github.com/login/device/code', {
      method: 'POST',
      headers: { accept: 'application/json', 'content-type': 'application/json', 'user-agent': UA },
      body: JSON.stringify({ client_id: this.cfg.githubClientId, scope: this.cfg.githubScope }),
    });
    const j = await r.json();
    if (!r.ok || !j.device_code) throw new Error(`device_start_failed:${j.error ?? r.status}`);
    return j; // device_code, user_code, verification_uri, expires_in, interval
  }

  async devicePoll(deviceCode) {
    const r = await fetch('https://github.com/login/oauth/access_token', {
      method: 'POST',
      headers: { accept: 'application/json', 'content-type': 'application/json', 'user-agent': UA },
      body: JSON.stringify({
        client_id: this.cfg.githubClientId,
        device_code: deviceCode,
        grant_type: 'urn:ietf:params:oauth:grant-type:device_code',
      }),
    });
    return r.json(); // access_token | error: authorization_pending|slow_down|expired_token|access_denied
  }

  async userLogin(token) {
    const r = await guard(await fetch(`${API}/user`, { headers: this.#h(token) }));
    if (r.status === 401) return null;
    if (!r.ok) throw new Error(`github_user_failed:${r.status}`);
    return (await r.json()).login;
  }

  // ---- Build repo operations (operator token, never the user's token) ----
  #h(token = this.cfg.buildRepoToken) {
    return { authorization: `Bearer ${token}`, accept: 'application/vnd.github+json', 'x-github-api-version': '2022-11-28', 'user-agent': UA };
  }

  async dispatch(inputs) {
    const r = await guard(await fetch(`${API}/repos/${this.cfg.buildRepo}/actions/workflows/${this.cfg.workflowFile}/dispatches`, {
      method: 'POST', headers: { ...this.#h(), 'content-type': 'application/json' },
      body: JSON.stringify({ ref: this.cfg.workflowRef, inputs }),
    }));
    if (r.status !== 204) throw new Error(`dispatch_failed:${r.status}`);
  }

  async findRun(jobId) {
    const r = await guard(await fetch(`${API}/repos/${this.cfg.buildRepo}/actions/workflows/${this.cfg.workflowFile}/runs?event=workflow_dispatch&per_page=30`, { headers: this.#h() }));
    if (!r.ok) throw new Error(`runs_failed:${r.status}`);
    return (await r.json()).workflow_runs.find((x) => x.display_title === `build ${jobId}`) ?? null;
  }

  async getRun(id) {
    const r = await guard(await fetch(`${API}/repos/${this.cfg.buildRepo}/actions/runs/${id}`, { headers: this.#h() }));
    if (!r.ok) throw new Error(`run_failed:${r.status}`);
    return r.json();
  }

  async runSteps(id) {
    const r = await guard(await fetch(`${API}/repos/${this.cfg.buildRepo}/actions/runs/${id}/jobs`, { headers: this.#h() }));
    if (!r.ok) return [];
    const j = await r.json();
    return j.jobs?.[0]?.steps ?? [];
  }

  async downloadArtifact(runId, jobId) {
    const r = await guard(await fetch(`${API}/repos/${this.cfg.buildRepo}/actions/runs/${runId}/artifacts`, { headers: this.#h() }));
    if (!r.ok) throw new Error(`artifacts_failed:${r.status}`);
    const art = (await r.json()).artifacts.find((a) => a.name === `apk-${jobId}` && !a.expired);
    if (!art) return null;
    const z = await guard(await fetch(art.archive_download_url, { headers: this.#h(), redirect: 'follow' }));
    if (!z.ok) throw new Error(`artifact_download_failed:${z.status}`);
    return Buffer.from(await z.arrayBuffer());
  }
}
