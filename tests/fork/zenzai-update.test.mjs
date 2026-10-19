// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 hkrhd
import assert from 'node:assert/strict';
import test from 'node:test';
import { run } from '../../.github/bot/zenzai-update.mjs';

const Current = 'Miwa-Keita/zenz-v3.1-small-gguf';
const New = 'Miwa-Keita/zenz-v3.2-small-gguf';
const OldChecksum = '1'.repeat(64);
const NewChecksum = '2'.repeat(64);

// 公開 API をメモリ上で再現し、通知文書と PR を利用者の視点から確認する。
function service({ id = New, checksum = NewChecksum } = {}) {
  const state = {
    models: [{ id: Current }, { id }],
    metadata: {
      id, sha: 'a'.repeat(40), cardData: { license: 'apache-2.0' },
      siblings: [{ rfilename: 'ggml-model-Q5_K_M.gguf', size: 73871936, lfs: { sha256: checksum, size: 73871936 } }],
    },
    branches: new Map(), pulls: [], writes: [], failMetadata: false, failPull: false,
    modelNextPage: [], pullNextPage: [],
  };
  const json = (data, status = 200, headers) => new Response(JSON.stringify(data), { status, headers });
  state.fetchImpl = async (url, options) => {
    const { pathname, searchParams, origin } = new URL(url);
    const { method, headers } = options;
    const body = options.body === undefined ? undefined : JSON.parse(options.body);
    if (method !== 'GET') state.writes.push({ pathname, body });
    if (origin === 'https://huggingface.co') {
      assert.equal(headers.Authorization, undefined, 'GitHub のトークンを Hugging Face に送らない');
      if (pathname === '/api/models') {
        if (searchParams.has('cursor')) return json(state.modelNextPage);
        return json(state.models, 200, state.modelNextPage.length ? {
          Link: '<https://huggingface.co/api/models?author=Miwa-Keita&search=zenz&cursor=next>; rel="next"',
        } : undefined);
      }
      assert.equal(pathname, `/api/models/${state.metadata.id}`);
      return state.failMetadata ? json({ error: 'unavailable' }, 503) : json(state.metadata);
    }
    assert.equal(origin, 'https://api.github.com');
    const path = pathname.replace('/repos/hkrhd/Meltype', '');
    if (path === '/git/ref/heads/fork_by_hkrhd') return json({ object: { sha: 'b'.repeat(40) } });
    if (path === `/git/commits/${'b'.repeat(40)}`) return json({ sha: 'b'.repeat(40), tree: { sha: 'c'.repeat(40) } });
    if (path === '/contents/mac/fetch-zenzai-model.sh') {
      const source = `checksum=${OldChecksum}\nurl=https://huggingface.co/${Current}/resolve/${'d'.repeat(40)}/ggml-model-Q5_K_M.gguf\n`;
      return json({ encoding: 'base64', content: Buffer.from(source).toString('base64') });
    }
    if (path === '/pulls' && method === 'GET') {
      // 実際の GitHub と同様に base・head・state で絞り込む。
      let pulls = searchParams.has('page') ? state.pullNextPage : state.pulls;
      pulls = pulls.filter(pr => pr.base === searchParams.get('base') && `hkrhd:${pr.head}` === searchParams.get('head')
        && (searchParams.get('state') === 'all' || pr.state === searchParams.get('state')));
      return json(pulls, 200, !searchParams.has('page') && state.pullNextPage.length ? {
        Link: `<${url}&page=2>; rel="next"`,
      } : undefined);
    }
    if (path.startsWith('/git/ref/heads/')) {
      const branch = path.slice('/git/ref/heads/'.length);
      return state.branches.has(branch) ? json({ object: { sha: state.branches.get(branch) } }) : json({}, 404);
    }
    if (path === '/git/trees' && method === 'POST') {
      state.report = body.tree[0];
      return json({ sha: 'e'.repeat(40) });
    }
    if (path === '/git/commits' && method === 'POST') return json({ sha: 'f'.repeat(40) });
    if (path === '/git/refs' && method === 'POST') {
      const branch = body.ref.replace('refs/heads/', '');
      if (state.branches.has(branch)) return json({}, 422);
      state.branches.set(branch, body.sha);
      return json({ ref: body.ref }, 201);
    }
    if (path === '/pulls' && method === 'POST') {
      if (state.failPull) return json({ message: 'unavailable' }, 503);
      const pr = { ...body, state: 'open', html_url: 'https://github.com/hkrhd/Meltype/pull/123' };
      state.pulls.push(pr);
      return json(pr, 201);
    }
    throw new Error(`想定外のリクエスト: ${method} ${url}`);
  };
  state.run = (options = {}) => run({ repo: 'hkrhd/Meltype', token: 'test-token', fetchImpl: state.fetchImpl, ...options });
  return state;
}

test('新系列の small / Q5_K_M を Draft PR で通知し、変更は候補文書だけにする', async () => {
  const api = service();
  const result = await api.run();
  assert.equal(result.status, 'created');
  assert.equal(api.pulls.length, 1);
  const pr = api.pulls[0];
  assert.equal(pr.base, 'fork_by_hkrhd');
  assert.equal(pr.draft, true);
  assert.match(pr.title, /v3\.2/);
  assert.match(pr.body, /v3\.1[\s\S]*→[\s\S]*v3\.2/);
  for (const value of [NewChecksum, api.metadata.sha, 'apache-2.0', 'bash mac/update.sh', '実機へインストールして動作確認']) {
    assert.ok(pr.body.includes(value));
  }
  assert.equal(api.report.path, 'docs/ZENZAI-UPDATE.md');
  assert.ok(api.report.content.includes(NewChecksum));
  assert.ok(!api.writes.some(write => write.pathname.includes('fetch-zenzai-model.sh')));
});

test('同系列の重みの差し替えも通知する', async () => {
  const api = service({ id: Current });
  assert.equal((await api.run()).status, 'created');
  assert.match(api.pulls[0].title, /v3\.1/);
  assert.ok(api.pulls[0].body.includes(NewChecksum));
});

test('版番号を数値比較し、別作者・xsmall・プレリリースは候補にしない', async () => {
  const id = 'Miwa-Keita/zenz-v3.10-small-gguf';
  const api = service({ id });
  api.models = [
    { id: 'Miwa-Keita/zenz-v3.2-small-gguf' }, { id },
    { id: 'someone/zenz-v99-small-gguf' }, { id: 'Miwa-Keita/zenz-v99-xsmall-gguf' },
    { id: 'Miwa-Keita/zenz-v99-small' }, { id: 'Miwa-Keita/zenz-v99-rc1-small-gguf' },
  ];
  assert.equal((await api.run()).status, 'created');
  assert.match(api.pulls[0].title, /v3\.10/);
});

test('モデル一覧の次ページにある新系列も検知する', async () => {
  const api = service();
  api.models = [{ id: Current }];
  api.modelNextPage = [{ id: New }];
  assert.equal((await api.run()).status, 'created');
});

test('重みが同じなら説明文・リビジョン・ライセンスの更新だけでは通知しない', async () => {
  const api = service({ id: Current, checksum: OldChecksum });
  assert.equal((await api.run()).status, 'unchanged');
  assert.equal(api.writes.length, 0);
});

for (const state of ['open', 'closed', 'merged']) {
  test(`${state} の PR があれば重みが同じ候補を再通知しない`, async () => {
    const api = service();
    await api.run();
    api.pulls[0].state = state === 'open' ? 'open' : 'closed';
    api.pulls[0].merged_at = state === 'merged' ? '2026-10-18T00:00:00Z' : null;
    api.metadata.sha = '9'.repeat(40); // モデルカードだけの更新
    api.writes.length = 0;
    assert.equal((await api.run()).status, 'existing');
    assert.equal(api.pulls.length, 1);
    assert.equal(api.writes.length, 0);
  });
}

test('PR 一覧の次ページも重複確認に含める', async () => {
  const api = service();
  await api.run();
  api.pullNextPage = api.pulls.splice(0);
  api.writes.length = 0;
  assert.equal((await api.run()).status, 'existing');
  assert.equal(api.writes.length, 0);
});

test('以前の候補をクローズしていても、その後の重み更新は新たに通知する', async () => {
  const api = service();
  await api.run();
  api.pulls[0].state = 'closed';
  api.metadata.siblings[0].lfs.sha256 = '3'.repeat(64);
  assert.equal((await api.run()).status, 'created');
  assert.equal(api.pulls.length, 2);
  assert.notEqual(api.pulls[0].head, api.pulls[1].head);
});

test('dry-run は候補と文書を確認するだけで書き込まない', async () => {
  const api = service();
  const result = await api.run({ dryRun: true, token: undefined });
  assert.equal(result.status, 'dry-run');
  assert.equal(result.candidate.id, New);
  assert.ok(result.content.includes('`apache-2.0`'));
  assert.equal(api.writes.length, 0);
});

test('API 障害時は失敗し、PR を作成しない', async () => {
  const api = service();
  api.failMetadata = true;
  await assert.rejects(api.run(), /HTTP 503/);
  assert.equal(api.writes.length, 0);
});

test('最新候補の必須情報が不足しても旧版に切り替えず失敗する', async () => {
  for (const remove of [
    api => { api.metadata.siblings = []; },
    api => { delete api.metadata.siblings[0].lfs.sha256; },
    api => { api.metadata.siblings[0].lfs.size = 1; },
    api => { delete api.metadata.cardData.license; },
  ]) {
    const api = service();
    remove(api);
    await assert.rejects(api.run(), /不正または不足/);
    assert.equal(api.writes.length, 0);
  }
});

test('PR 作成直前に失敗しても、再実行で残った候補ブランチから通知できる', async () => {
  const api = service();
  api.failPull = true;
  await assert.rejects(api.run(), /HTTP 503/);
  assert.equal(api.pulls.length, 0);
  api.failPull = false;
  assert.equal((await api.run()).status, 'created');
  assert.equal(api.pulls.length, 1);
  assert.equal(api.branches.size, 1);
});
