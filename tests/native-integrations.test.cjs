const test = require('node:test');
const { execFileSync } = require('node:child_process');
const { mkdtempSync, rmSync } = require('node:fs');
const { tmpdir } = require('node:os');
const { join } = require('node:path');

for (const [name, source, frameworks] of [
  ['native launch animation and readiness gates', 'native-launch-darwin.m', ['AppKit', 'QuartzCore']],
  ['EventKit identity and foreground guards without user data', 'eventkit-darwin.m', ['Foundation', 'EventKit']],
]) {
  test(name, { skip: process.platform !== 'darwin' }, () => {
    const dir = mkdtempSync(join(tmpdir(), 'sci-station-native-test-'));
    try {
      const binary = join(dir, 'test');
      execFileSync('xcrun', ['clang', '-fobjc-arc', '-mmacosx-version-min=12.0',
        ...frameworks.flatMap(f => ['-framework', f]), join(__dirname, source), '-o', binary], { stdio: 'pipe' });
      execFileSync(binary, { stdio: 'pipe' });
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });
}
