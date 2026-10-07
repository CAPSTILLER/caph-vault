// Builds flat/ (forge flatten output, full comments) and paste/ (same code, comments stripped).
// Usage: node scripts/make-paste.mjs   (run after `forge flatten`, see README)
import { readFileSync, writeFileSync } from 'node:fs';

function stripComments(src) {
  let out = '';
  let i = 0;
  let quote = null;
  while (i < src.length) {
    const c = src[i];
    const n = src[i + 1];
    if (quote) {
      out += c;
      if (c === '\\') { out += n ?? ''; i += 2; continue; }
      if (c === quote) quote = null;
      i++;
      continue;
    }
    if (c === '"' || c === "'") { quote = c; out += c; i++; continue; }
    if (c === '/' && n === '/') {
      const end = src.indexOf('\n', i);
      const line = src.slice(i, end === -1 ? src.length : end);
      if (line.startsWith('// SPDX-License-Identifier')) out += line;
      i = end === -1 ? src.length : end;
      continue;
    }
    if (c === '/' && n === '*') {
      const end = src.indexOf('*/', i + 2);
      i = end === -1 ? src.length : end + 2;
      continue;
    }
    out += c;
    i++;
  }
  return out
    .split('\n')
    .map((l) => l.replace(/\s+$/, ''))
    .join('\n')
    .replace(/\n{3,}/g, '\n\n')
    .trim() + '\n';
}

for (const name of ['CAPHVault', 'HighScoreRecords']) {
  const flat = readFileSync(`flat/${name}.flat.sol`, 'utf8');
  let paste = stripComments(flat);
  // Keep only the first SPDX line (flattened files repeat it per source).
  let seen = false;
  paste = paste
    .split('\n')
    .filter((l) => {
      if (!l.startsWith('// SPDX-License-Identifier')) return true;
      if (seen) return false;
      seen = true;
      return true;
    })
    .join('\n')
    .replace(/\n{3,}/g, '\n\n');
  // forge flatten merges every pragma into one line; it is equivalent to =0.8.24, so say that plainly.
  paste = paste.replace(/^pragma solidity [^;]+;/m, 'pragma solidity 0.8.24;');
  writeFileSync(`paste/${name}.paste.sol`, paste);
  // Review copy: just the contract (imports OpenZeppelin), comments stripped. Short enough for chat.
  const core = stripComments(readFileSync(`src/${name}.sol`, 'utf8'));
  writeFileSync(`paste/${name}.core.sol`, core);
  console.log(name, 'flat', flat.split('\n').length, 'paste', paste.split('\n').length, 'core', core.split('\n').length);
}
