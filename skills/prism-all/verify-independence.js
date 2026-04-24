#!/usr/bin/env node
// prism-all — Layer 2 self-check. Copy of prism-codex template, SELF_NAME changed.

'use strict';

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const SELF_NAME = 'prism-all';
const REQUIRED_FILES = ['SKILL.md', 'verify-independence.js'];
const PREREQUISITES = [
  { cmd: 'codex --version', label: 'Codex CLI', fatal: true, min: '0.125.0' },
];

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
if (strict) checkPrereqs();
process.stdout.write(`[verify-independence:${SELF_NAME}] PASS — skill is self-contained\n`);
process.exit(0);
