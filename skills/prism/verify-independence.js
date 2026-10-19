#!/usr/bin/env node
// prism — Layer 2 self-check.
// Same pattern as sibling skills; only SELF_NAME / REQUIRED_FILES / PREREQUISITES differ.
//
// Verifies the skill is self-contained AND that its deterministic scripts exist and
// actually run. v0.2 made parse-findings.js + verify-evidence.js load-bearing (the
// Evidence pass calls them), so a missing or broken script must fail this check —
// not silently PASS as "self-contained". --strict also runs each script's --selftest.

'use strict';

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const SELF_NAME = 'prism';
// Required at rest: the contract + the deterministic scripts it invokes.
const REQUIRED_FILES = ['SKILL.md', 'verify-independence.js', 'parse-findings.js', 'verify-evidence.js', 'verify-ideas.js', 'references/record-v2.md', 'references/redteam-lens.md', 'references/design-lenses.md', 'references/ideas.md', 'templates/ideas-contract.md', 'templates/idea-check-contract.md', 'templates/ideas-prompt.md', 'templates/idea-check-prompt.md'];
// Scripts that must pass their own --selftest under --strict (integrity, not just presence).
const SELFTEST_SCRIPTS = ['parse-findings.js', 'verify-evidence.js', 'verify-ideas.js'];
const PREREQUISITES = []; // prism is Claude-only — no external CLI prerequisite

const SELF_DIR = __dirname;

function fail(m) { process.stderr.write(`[verify-independence:${SELF_NAME}] FAIL  ${m}\n`); process.exit(2); }
function warn(m) { process.stderr.write(`[verify-independence:${SELF_NAME}] WARN  ${m}\n`); }
function ok(m)   { process.stdout.write(`[verify-independence:${SELF_NAME}] OK    ${m}\n`); }

function walk(dir, acc = []) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, e.name);
    if (e.isDirectory()) walk(full, acc);
    else if (e.isFile()) acc.push(full);
  }
  return acc;
}
function normalize(p) { return p.replace(/\\/g, '/'); }

function scanForCrossRefs(filePath, content) {
  const violations = [];
  if (/\/(plugins\/marketplaces\/[^/]+\/plugins|\.claude\/skills)\/_shared(\/|$)/.test(content)) {
    violations.push('references a `_shared/` directory');
  }
  const absRegex = /(?:~|\/c)?\/[^\s`"')\]]*?\.claude\/(?:plugins\/marketplaces\/[^/]+\/plugins|skills)\/([A-Za-z0-9._-]+)/g;
  let m;
  while ((m = absRegex.exec(content)) !== null) {
    if (m[1] !== SELF_NAME) violations.push(`references another plugin/skill "${m[1]}" at absolute path: ${m[0]}`);
  }
  const relRegex = /\.\.\/[^\s`"')\]]*(?:plugins|skills)\/([A-Za-z0-9._-]+)\//g;
  while ((m = relRegex.exec(content)) !== null) {
    if (m[1] !== SELF_NAME) violations.push(`relative path crosses into sibling plugin/skill "${m[1]}": ${m[0]}`);
  }
  return violations;
}

function compareSemver(a, b) {
  const pa = a.split('.').map(Number), pb = b.split('.').map(Number);
  for (let i = 0; i < 3; i++) {
    if ((pa[i] || 0) > (pb[i] || 0)) return 1;
    if ((pa[i] || 0) < (pb[i] || 0)) return -1;
  }
  return 0;
}

function checkRequired() {
  for (const rel of REQUIRED_FILES) {
    if (!fs.existsSync(path.join(SELF_DIR, rel))) fail(`missing required file: ${rel}`);
  }
  ok(`required files present (${REQUIRED_FILES.length})`);
}

function checkNoCrossRefs() {
  const exts = new Set(['.md', '.js', '.sh', '.json', '.yml', '.yaml', '.txt', '.py']);
  const files = walk(SELF_DIR).filter(f => exts.has(path.extname(f)));
  const off = {};
  for (const f of files) {
    const v = scanForCrossRefs(f, fs.readFileSync(f, 'utf8'));
    if (v.length) off[normalize(path.relative(SELF_DIR, f))] = v;
  }
  const keys = Object.keys(off);
  if (keys.length) {
    for (const f of keys) for (const msg of off[f]) process.stderr.write(`[verify-independence:${SELF_NAME}] FAIL  ${f} — ${msg}\n`);
    process.exit(2);
  }
  ok(`no cross-plugin references in ${files.length} scanned files`);
}

// SKILL.md's command lines are the contract between the orchestrator and the scripts, and nothing
// else reads them. Lint the rules a CLI change broke before: --root on every idea-prompt build and
// no retired discovery angle. Only command forms (`.js" prompt`, `.sh" ideas`) are checked; prose
// that names a subcommand is not a command line.
function checkSkillCommands() {
  const lines = fs.readFileSync(path.join(SELF_DIR, 'SKILL.md'), 'utf8').split('\n');
  const bad = [];
  lines.forEach((l, i) => {
    if (/verify-ideas\.js"\s+prompt\s+propose\b/.test(l) && !/\s--root\s/.test(l)) bad.push(`line ${i + 1}: prompt propose without --root`);
    if (/codex-run\.sh"\s+ideas\s/.test(l) && !/\s--root\s/.test(l)) bad.push(`line ${i + 1}: codex-run.sh ideas without --root`);
    if (/`<angle>`/.test(l) && /\bimprovement\b/.test(l)) bad.push(`line ${i + 1}: the retired improvement angle is listed`);
  });
  if (bad.length) fail(`SKILL.md command lines no longer match the scripts:\n  ${bad.join('\n  ')}`);
  ok('SKILL.md command lines match the script CLIs (--root, angles)');
}

// Windows: from PowerShell/cmd the first `bash` on PATH is often System32\bash.exe (the WSL
// launcher), which cannot open C:\ paths. Prefer Git Bash; CODEX_RUN_BASH overrides.
function resolveBash() {
  if (process.env.CODEX_RUN_BASH) return process.env.CODEX_RUN_BASH;
  if (process.platform !== 'win32') return 'bash';
  const cands = [];
  try {
    const gitExec = execSync('git --exec-path', { stdio: ['ignore', 'pipe', 'ignore'] }).toString().trim();
    cands.push(path.join(gitExec, '..', '..', '..', 'bin', 'bash.exe'));
  } catch (e) { /* git not on PATH */ }
  cands.push('C:\\Program Files\\Git\\bin\\bash.exe');
  for (const c of cands) if (fs.existsSync(c)) return c;
  return 'bash';
}

// --strict: the scripts must not just exist, they must pass their own selftest. A failure prints
// the failing cases (or the tail) so the reason is visible.
function checkScripts() {
  const bash = resolveBash();
  for (const rel of SELFTEST_SCRIPTS) {
    const script = path.join(SELF_DIR, rel);
    const runner = rel.endsWith('.sh') ? bash : 'node';
    try {
      execSync(`"${runner}" "${script}" --selftest`, { stdio: ['ignore', 'pipe', 'pipe'], timeout: 600000 });
      ok(`selftest passed: ${rel}`);
    } catch (e) {
      const text = `${e.stdout || ''}${e.stderr || ''}`;
      const lines = text.split('\n').filter((l) => /FAIL|ERROR|WSL|not found/.test(l)).slice(0, 10).join('\n') || text.slice(-600);
      fail(`selftest FAILED: ${rel} (runner: ${runner}${e.signal ? `, killed by ${e.signal}` : ''})\n${lines}`);
    }
  }
}

// --strict, Codex-backed skills: the installed CLI must accept every flag codex-run.sh passes
// (the selftest only exercises a fake codex).
function checkCodexFlags() {
  const codex = PREREQUISITES.find((p) => p.label === 'Codex CLI');
  if (!codex) return;
  // Optional Codex (a skill that can run Claude-only): problems are warnings, not failures.
  const bad = (m) => (codex.fatal ? fail(m) : warn(m));
  let help = '';
  try {
    help = execSync('codex exec --help', { stdio: ['ignore', 'pipe', 'ignore'], timeout: 60000 }).toString();
  } catch (e) {
    return bad('`codex exec --help` failed: cannot confirm the flags codex-run.sh needs');
  }
  const need = ['--config', '--sandbox', '--model', '--output-last-message', '--skip-git-repo-check', '--dangerously-bypass-approvals-and-sandbox'];
  const missing = need.filter((f) => !help.includes(f));
  if (missing.length) return bad(`installed Codex CLI lacks ${missing.join(', ')} (codex-run.sh passes them)`);
  ok(`Codex CLI accepts ${need.length} flags codex-run.sh passes`);
}
function checkPrereqs() {
  for (const p of PREREQUISITES) {
    try {
      const out = execSync(p.cmd, { stdio: ['ignore', 'pipe', 'ignore'] }).toString().trim();
      if (p.min) {
        const m = out.match(/(\d+\.\d+\.\d+)/);
        if (m && compareSemver(m[1], p.min) < 0) {
          const msg = `prerequisite version too old: ${p.label} ${m[1]} < required ${p.min}`;
          if (p.fatal) fail(msg); else warn(msg);
          continue;
        }
      }
      ok(`prerequisite present: ${p.label} (${out.split('\n')[0]})`);
    } catch (e) {
      const msg = `prerequisite missing: ${p.label} (\`${p.cmd}\` failed)`;
      if (p.fatal) fail(msg); else warn(msg);
    }
  }
}

const strict = process.argv.includes('--strict');
checkRequired();
checkNoCrossRefs();
checkSkillCommands();
if (strict) { checkScripts(); checkPrereqs(); checkCodexFlags(); }
process.stdout.write(`[verify-independence:${SELF_NAME}] PASS — skill is self-contained\n`);
process.exit(0);
