import { appTasks } from '@ohos/hvigor-ohos-plugin';

/*
 * Make sure the third_party/ git submodules are checked out before any module
 * is compiled.
 *
 * The eudi_lib_* libraries are git submodules pinned under
 * third_party/<name> (see .gitmodules); each module's cjpm.toml references
 * them via path = "../../third_party/<name>/<inner>". hvigor evaluates this
 * file synchronously in node during its configuration phase, before any
 * module is compiled, so initialising them here guarantees they are in place.
 *
 * Policy:
 *   - submodule not checked out (cloned without --recursive)
 *               -> git submodule update --init
 *   - already checked out -> used as is: no fetch, no reset, so local edits
 *               made while debugging a library are never discarded
 *   - upgrading a library: check out the new commit inside third_party/<name>
 *               and commit the updated gitlink in this repository
 *   - SKIP_FETCH_THIRD_PARTY=1 skips the check entirely (offline builds, or
 *               a source tree that is not a git checkout)
 */
(function syncThirdPartyDeps() {
  if (process.env.SKIP_FETCH_THIRD_PARTY === '1') return;
  const fs = require('fs');
  const path = require('path');
  const { execSync } = require('child_process');

  const root = path.join(__dirname, 'third_party');
  const gitmodules = fs.readFileSync(path.join(__dirname, '.gitmodules'), 'utf8');
  const deps: string[] = [];
  const pathRe = /^\s*path\s*=\s*third_party\/(\S+)\s*$/gm;
  for (let m = pathRe.exec(gitmodules); m !== null; m = pathRe.exec(gitmodules)) deps.push(m[1]);
  // A checked-out submodule has a `.git` file; an uninitialised one is an
  // empty directory (or missing when the tree came from a partial copy).
  const missing = () => deps.filter((name) => !fs.existsSync(path.join(root, name, '.git')));
  if (missing().length === 0) return;

  // hvigor evaluates this file more than once per build, and those evaluations
  // overlap in time. Serialise the checkout on an atomically created lock
  // directory so a second evaluation never reads a half-written library
  // ("Can not find .../eudi_lib_x509/eudi_cjx509").
  fs.mkdirSync(root, { recursive: true });
  const lock = path.join(root, '.deps-sync.lock');
  const sleepMs = (ms: number) => Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);
  let locked = false;
  for (let i = 0; i < 900 && !locked; i++) {   // up to ~15 minutes
    try {
      fs.mkdirSync(lock);
      locked = true;
    } catch (e) {
      try {
        // A build killed mid-sync leaves the lock behind; reclaim a stale one.
        if (Date.now() - fs.statSync(lock).mtimeMs > 15 * 60 * 1000) {
          fs.rmSync(lock, { recursive: true, force: true });
          continue;
        }
      } catch (_) { continue; }
      sleepMs(1000);
    }
  }
  if (!locked) throw new Error('[deps] timed out waiting for the third_party sync lock; build aborted.');

  try {
    const todo = missing();   // another evaluation may have finished meanwhile
    if (todo.length === 0) return;
    console.log(`[deps] initialising submodules: ${todo.join(', ')}`);
    try {
      execSync(`git submodule update --init -- ${todo.map((n) => `"third_party/${n}"`).join(' ')}`,
        { cwd: __dirname, stdio: 'inherit' });
    } catch (e) {
      console.error(`[deps] git submodule update failed: ${e}`);
      throw new Error('[deps] could not check out the third_party submodules; build aborted. ' +
        'Clone with `git clone --recursive`, or run `git submodule update --init` in the project root.');
    }
  } finally {
    fs.rmSync(lock, { recursive: true, force: true });
  }
})();

/**
 * 首次克隆后 oh_modules/ 不存在（gitignore 产物），ArkTS 编译会直接报
 * "Cannot find module '@cangjie/cjhybridcomponent'"。这里在缺失时 best-effort
 * 自动跑一次 `ohpm install --all`（等价于 DevEco 打开工程时的自动 Sync）。
 * 找不到 ohpm 时只告警不中止——DevEco 内构建自身会处理依赖安装。
 */
(function ensureOhpmInstall() {
  const fs = require('fs');
  const path = require('path');
  const { execSync } = require('child_process');
  const root = __dirname;
  if (fs.existsSync(path.join(root, 'entry', 'oh_modules'))) return;

  const isWin = process.platform === 'win32';
  const candidates = [
    'ohpm', // PATH 上有就直接用
    path.join(process.env.DEVECO_TOOL_HOME || '', 'ohpm', 'bin', isWin ? 'ohpm.bat' : 'ohpm'),
    '/Applications/DevEco-Studio.app/Contents/tools/ohpm/bin/ohpm', // macOS 默认
  ].filter(Boolean);

  for (const ohpm of candidates) {
    try {
      // ohpm 需要 node；DevEco 自带的 node 兜底进 PATH / NODE_HOME
      const devecoNode = '/Applications/DevEco-Studio.app/Contents/tools/node';
      const env = { ...process.env };
      if (!env.NODE_HOME && fs.existsSync(devecoNode)) {
        env.NODE_HOME = devecoNode;
        env.PATH = path.join(devecoNode, 'bin') + path.delimiter + env.PATH;
      }
      console.log('[deps] oh_modules missing -> ohpm install --all');
      execSync(`"${ohpm}" install --all`, { cwd: root, stdio: 'inherit', env });
      return;
    } catch (e) { /* 试下一个候选 */ }
  }
  console.warn('[deps] WARN: oh_modules missing and no usable ohpm found. ' +
    'Run `ohpm install --all` in the project root (or open the project once in DevEco Studio) before building.');
})();

export default {
  system: appTasks, /* Built-in plugin of Hvigor. It cannot be modified. */
  plugins: []       /* Custom plugin to extend the functionality of Hvigor. */
}
