// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 hkrhd
// Zenzai small の重み更新を通知する。--dry-run は外部への書き込みを行わない。
import { pathToFileURL } from 'node:url';

const Base = 'fork_by_hkrhd';
const ModelFile = 'ggml-model-Q5_K_M.gguf';
const ModelPattern = /^Miwa-Keita\/zenz-v([0-9]+(?:\.[0-9]+)*)-small-gguf$/;
const ReportPath = 'docs/ZENZAI-UPDATE.md';

function compareVersions(a, b) {
  const left = a.split('.').map(BigInt);
  const right = b.split('.').map(BigInt);
  for (let i = 0; i < Math.max(left.length, right.length); i++) {
    const difference = (left[i] ?? 0n) - (right[i] ?? 0n);
    if (difference !== 0n) return difference > 0n ? 1 : -1;
  }
  return 0;
}

function report(current, candidate) {
  const source = `https://huggingface.co/${candidate.id}`;
  return `# Zenzai small / Q5_K_M の更新

[v${current.version}](https://huggingface.co/${current.id}/tree/${current.revision}) → [v${candidate.version}](${source}/tree/${candidate.revision})

- [モデル取得先](${source}/resolve/${candidate.revision}/${ModelFile})
- SHA-256: \`${candidate.checksum}\`
- [ライセンス・モデルカード](${source}/blob/${candidate.revision}/README.md): \`${candidate.license}\`

ライセンスとエンジン・Metal との互換性を確認して更新してください。
フォークの変換挙動と評価上限2回を保ち、\`bash mac/update.sh\` で実機へインストールして動作確認し、変換品質・性能の結果を報告してください。
`;
}

/** ワークフロー全体。テストでは公開 API の応答を置き換えて通知結果を検証する。 */
export async function run({
  repo = process.env.GITHUB_REPOSITORY,
  token = process.env.GITHUB_TOKEN,
  dryRun = false,
  fetchImpl = fetch,
} = {}) {
  if (repo !== 'hkrhd/Meltype') throw new Error('実行対象は hkrhd/Meltype のみです。');
  if (!dryRun && !token) throw new Error('GITHUB_TOKEN が必要です。');
  const github = `https://api.github.com/repos/${repo}`;

  async function request(url, { method = 'GET', body, allowMissing = false } = {}) {
    const origin = new URL(url).origin;
    if (!['https://api.github.com', 'https://huggingface.co'].includes(origin)) {
      throw new Error(`想定外の API URL: ${url}`);
    }
    if (dryRun && method !== 'GET') throw new Error('dry-run での書き込みは禁止です。');
    const headers = { 'User-Agent': 'meltype-zenzai-update' };
    if (origin === 'https://api.github.com') {
      headers.Accept = 'application/vnd.github+json';
      headers['X-GitHub-Api-Version'] = '2022-11-28';
      if (token) headers.Authorization = `Bearer ${token}`;
    }
    if (body !== undefined) headers['Content-Type'] = 'application/json';
    const response = await fetchImpl(url, {
      method, headers,
      body: body === undefined ? undefined : JSON.stringify(body),
      signal: AbortSignal.timeout(30_000),
    });
    if (allowMissing && response.status === 404) return null;
    if (!response.ok) throw new Error(`${method} ${url}: HTTP ${response.status}`);
    return response;
  }

  async function list(url) {
    const entries = [];
    while (url) {
      const response = await request(url);
      const page = await response.json();
      if (!Array.isArray(page)) throw new Error(`一覧の形式が不正です: ${url}`);
      entries.push(...page);
      url = response.headers.get('link')?.match(/<([^>]+)>;\s*rel="next"/)?.[1];
    }
    return entries;
  }

  // 通知の比較元と PR の親は、同じ fork_by_hkrhd のコミットに固定する。
  const baseRef = await (await request(`${github}/git/ref/heads/${Base}`)).json();
  const base = await (await request(`${github}/git/commits/${baseRef.object.sha}`)).json();
  const source = await (await request(`${github}/contents/mac/fetch-zenzai-model.sh?ref=${base.sha}`)).json();
  if (source.encoding !== 'base64') throw new Error('モデル取得スクリプトを読めませんでした。');
  const script = Buffer.from(source.content, 'base64').toString('utf8');
  const pinned = script.match(/^url=https:\/\/huggingface\.co\/(Miwa-Keita\/zenz-v([0-9]+(?:\.[0-9]+)*)-small-gguf)\/resolve\/([0-9a-f]{40})\/ggml-model-Q5_K_M\.gguf$/m);
  const checksum = script.match(/^checksum=([0-9a-f]{64})$/m)?.[1];
  if (!pinned || !checksum) throw new Error('固定中のモデル情報の形式が想定と異なります。');
  const current = { id: pinned[1], version: pinned[2], revision: pinned[3], checksum };

  const models = await list('https://huggingface.co/api/models?author=Miwa-Keita&search=zenz&limit=100');
  const candidates = models.flatMap(model => {
    const match = ModelPattern.exec(model.id);
    return match ? [{ id: model.id, version: match[1] }] : [];
  }).sort((a, b) => compareVersions(b.version, a.version));
  const latest = candidates[0];
  if (!latest) throw new Error('公開されている Zenzai small GGUF が見つかりません。');
  if (compareVersions(latest.version, current.version) < 0) {
    throw new Error('配布元の最新版が使用中のモデルより古くなっています。');
  }

  const metadata = await (await request(`https://huggingface.co/api/models/${latest.id}?blobs=true`)).json();
  const file = metadata.siblings?.find(sibling => sibling.rfilename === ModelFile);
  const candidate = {
    ...latest, revision: metadata.sha, checksum: file?.lfs?.sha256,
    size: file?.size, license: metadata.cardData?.license,
  };
  if (metadata.id !== latest.id || !/^[0-9a-f]{40}$/.test(candidate.revision ?? '')
      || !/^[0-9a-f]{64}$/.test(candidate.checksum ?? '')
      || !Number.isSafeInteger(candidate.size) || candidate.size <= 0 || file.lfs.size !== candidate.size
      || typeof candidate.license !== 'string' || !/^[a-zA-Z0-9][a-zA-Z0-9.+-]*$/.test(candidate.license)) {
    throw new Error(`モデルのリビジョン・重み・ライセンス情報が不正または不足しています: ${latest.id}`);
  }
  if (candidate.id === current.id && candidate.checksum === current.checksum) {
    console.log('Zenzai small の重み更新はありません。');
    return { status: 'unchanged' };
  }

  // 重みが同じなら README 等の編集で repo のリビジョンが変わっても同じ候補と扱う。
  const branch = `automation/zenzai-v${candidate.version}-${candidate.checksum}`;
  const query = new URLSearchParams({ state: 'all', base: Base, head: `hkrhd:${branch}`, per_page: '100' });
  const existing = await list(`${github}/pulls?${query}`);
  if (existing.length) {
    console.log(`このモデルの更新依頼 PR は作成済みです: ${existing[0].html_url}`);
    return { status: 'existing', url: existing[0].html_url };
  }

  const title = `Zenzai small v${candidate.version} のモデル更新を確認する`;
  const content = report(current, candidate);
  if (dryRun) {
    console.log(`DRY RUN: ${title}\n${content}`);
    return { status: 'dry-run', candidate, content };
  }

  // PR 作成前に失敗した実行が残した同名ブランチは、そのまま使って再試行する。
  const previous = await request(`${github}/git/ref/heads/${branch}`, { allowMissing: true });
  if (!previous) {
    const tree = await (await request(`${github}/git/trees`, {
      method: 'POST', body: {
        base_tree: base.tree.sha,
        tree: [{ path: ReportPath, mode: '100644', type: 'blob', content }],
      },
    })).json();
    const commit = await (await request(`${github}/git/commits`, {
      method: 'POST', body: { message: title, tree: tree.sha, parents: [base.sha] },
    })).json();
    await request(`${github}/git/refs`, {
      method: 'POST', body: { ref: `refs/heads/${branch}`, sha: commit.sha },
    });
  }
  const pr = await (await request(`${github}/pulls`, {
    method: 'POST', body: {
      title, base: Base, head: branch, draft: true,
      body: content,
    },
  })).json();
  console.log(`更新依頼の Draft PR を作成しました: ${pr.html_url}`);
  return { status: 'created', url: pr.html_url };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const args = process.argv.slice(2);
  if (args.some(arg => arg !== '--dry-run')) throw new Error('使用方法: node .github/bot/zenzai-update.mjs [--dry-run]');
  await run({ dryRun: args.includes('--dry-run') });
}
