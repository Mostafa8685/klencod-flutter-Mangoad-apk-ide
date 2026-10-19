import path from 'node:path';

function req(name) {
  const v = process.env[name];
  if (!v) throw new Error(`Missing required env var ${name}`);
  return v;
}

export function loadConfig(env = process.env) {
  const get = (n, d) => env[n] ?? d;
  const key = Buffer.from(env.ENCRYPTION_KEY ?? '', 'hex');
  if (key.length !== 32) throw new Error('ENCRYPTION_KEY must be 64 hex chars (32 bytes)');
  return {
    port: Number(get('PORT', 8080)),
    publicUrl: req('PUBLIC_URL').replace(/\/+$/, ''),
    githubClientId: req('GITHUB_CLIENT_ID'),
    // Minimal scope: only identifies the user. Builds never use the user's token.
    githubScope: get('GITHUB_OAUTH_SCOPE', 'read:user'),
    buildRepo: req('BUILD_REPO'), // owner/repo (private, dedicated)
    buildRepoToken: req('BUILD_REPO_TOKEN'), // fine-grained PAT: Actions RW + Contents R on that repo only
    workflowFile: get('WORKFLOW_FILE', 'build-android.yml'),
    workflowRef: get('WORKFLOW_REF', 'main'),
    encryptionKey: key,
    signingSecret: req('SIGNING_SECRET'),
    dataDir: path.resolve(get('DATA_DIR', './data')),
    maxZipMb: Number(get('MAX_ZIP_MB', 200)),
    retentionHours: Number(get('RETENTION_HOURS', 24)),
    buildTimeoutMin: Number(get('BUILD_TIMEOUT_MIN', 40)),
    maxParallel: Number(get('MAX_PARALLEL_BUILDS', 1)),
    downloadLinkTtlSec: Number(get('DOWNLOAD_LINK_TTL_SEC', 300)),
  };
}
