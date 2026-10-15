'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const {execFileSync} = require('node:child_process');

// Run the production Elm update function with deterministic API replies.
// Commands are deliberately not executed: these checks never modify a workspace.
test('Elm frontend preserves drafts, isolates accounts and protects reports and record queries', async () => {
  const root = path.resolve(__dirname, '..');
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'ecc-administration-elm-'));
  const config = JSON.parse(fs.readFileSync(path.join(root, 'elm.json'), 'utf8'));
  config['source-directories'] = [path.join(root, 'src'), path.join(root, 'tests/elm')];
  fs.writeFileSync(path.join(directory, 'elm.json'), JSON.stringify(config));
  const output = path.join(directory, 'checks.js');
  const localCompiler = path.join(root, 'node_modules/.bin/elm');
  const compiler = fs.existsSync(localCompiler) ? localCompiler : 'elm';
  try {
    execFileSync(compiler, ['make', path.join(root, 'tests/elm/AdministrationChecks.elm'), '--output=' + output], {cwd:directory,timeout:120000,stdio:'pipe'});
  } catch (error) {
    throw new Error('Elm checks failed to compile:\n' + String(error.stderr || error.stdout || error.message));
  }
  const {Elm} = require(output);
  const app = Elm.AdministrationChecks.init({flags:null});
  const checks = await new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('Elm checks timed out')), 5000);
    app.ports.results.subscribe(value => {clearTimeout(timer);resolve(value)});
  });
  assert.ok(checks.length >= 2081);
  for (const check of checks) assert.equal(check.passed, true, check.name);
});
