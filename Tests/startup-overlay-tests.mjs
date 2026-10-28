import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, mkdtempSync, rmSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../', import.meta.url));
const vp = fileURLToPath(new URL('../../../VisionPro-PJL/v0.2/', import.meta.url));
const hasVision = existsSync(join(vp, 'Sources/UI/GameWindow.swift'));
const keys = ['engine.log.title', 'engine.log.export', ...['window', 'jli', 'jvm', 'jni', 'renderer', 'frame', 'exited', 'failed'].map(s => `engine.stage.${s}`)];
const table = text => new Map([...text.matchAll(/^"([^"\n]+)"\s*=\s*("(?:[^"\\]|\\.)*")\s*;/gm)]
    .map(m => [m[1], JSON.parse(m[2])]));
for (const language of ['en', 'zh-Hans']) {
    const ios = table(readFileSync(join(root, `Natives/resources/${language}.lproj/Localizable.strings`), 'utf8'));
    const vision = hasVision ? table(readFileSync(join(vp, `Resources/${language}.lproj/Localizable.strings`), 'utf8')) : null;
    for (const key of keys) {
        assert(ios.get(key)?.length, `iOS key missing: ${key}`);
        if (vision) {
            assert(vision.has(key), `Vision key missing: ${key}`);
            // iOS-only brand migration: the separate Vision checkout is not edited.
            const expected = key === 'engine.stage.jvm'
                ? vision.get(key).replace(/(?:the )?iOS PojavLauncher/, 'PocketJ Launcher')
                : vision.get(key);
            assert.equal(ios.get(key), expected, `${language}: ${key}`);
        }
    }
}
const iosView = readFileSync(join(root, 'Natives/PocketJStartupOverlay.m'), 'utf8');
const visionView = hasVision ? readFileSync(join(vp, 'Sources/UI/GameWindow.swift'), 'utf8') : null;
if (visionView) assert(visionView.includes('VStack(spacing: 12)'));
assert(iosView.includes('stack.spacing = 12;'));
if (visionView) assert(visionView.includes('.padding(24)'));
assert(iosView.includes('constant:-48]'));
for (const symbol of ['doc.text.magnifyingglass', 'square.and.arrow.up']) {
    assert(iosView.includes(symbol));
    if (visionView) assert(visionView.includes(symbol));
}
assert(iosView.includes('@[self.spinner, self.stageLabel, self.timerLabel, logs, self.exportButton]'));
if (visionView) {
    assert(visionView.indexOf('ProgressView()') < visionView.indexOf('Text(model.launchError ?? startupStage)'));
    assert(visionView.indexOf('Text(model.launchError ?? startupStage)') < visionView.indexOf('Text(waitStarted, style: .timer)'));
}
console.log(hasVision
    ? 'PASS: Vision/iOS startup texts, content order, symbols and spacing contract.'
    : 'PASS: iOS startup localization/layout contract. SKIP cross-project parity: optional Vision v0.2 checkout not present.');
const logView = readFileSync(join(root, 'Natives/PLLogOutputView.m'), 'utf8');
const toggle = logView.slice(logView.indexOf('- (void)actionToggleLogOutput {'),
    logView.indexOf('+ (void)_appendToLog:'));
assert(toggle.includes('container.hidden = !show;'));
assert(!toggle.includes('self.frame'));
assert(!toggle.includes('completion: ^'));
console.log('PASS: log visibility is synchronous and independent of controller-owned frame/layout.');
const surface = readFileSync(join(root, 'Natives/GameSurfaceView.m'), 'utf8');
assert(surface.includes('PocketJInstallSDLStartupObservation();'));
assert(surface.includes('hasPrefix:@"SDL_"'));
assert(surface.includes('id<CAMetalDrawable> drawable = [self pocketj_startupNextDrawable];'));
assert(surface.includes('id<CAMetalDrawable> drawable = [super nextDrawable];'));
assert(surface.includes('[drawable addPresentedHandler:'));
assert(surface.includes('PocketJGameStartupPresented(session);'));
assert(!surface.includes('PocketJGameStartupPresented(state.session)'));
console.log('PASS: SDL-owned and GLFW-owned Metal layers share real-presentation observation with session protection.');
const directory = mkdtempSync(join(tmpdir(), 'pocketj-startup-tests-'));
try {
    const output = join(directory, 'startup-tests');
    execFileSync('xcrun', ['--sdk', 'macosx', 'clang', '-I', join(root, 'Natives'),
        join(root, 'Natives/PocketJGameStartup.c'), join(root, 'Tests/GameStartupTests.c'),
        '-o', output, '-pthread'], { stdio: 'inherit' });
    execFileSync(output, [], { stdio: 'inherit' });
    const observation = surface.slice(surface.indexOf('static void PocketJObserveStartupDrawable'),
        surface.indexOf('@interface GameSurfaceView()'));
    const harness = readFileSync(join(root, 'Tests/StartupMetalObservationTests.m'), 'utf8')
        .replace('// POCKETJ_OBSERVATION_IMPLEMENTATION', observation);
    const harnessPath = join(directory, 'metal-observation.m');
    writeFileSync(harnessPath, harness);
    const observationOutput = join(directory, 'metal-observation-tests');
    execFileSync('xcrun', ['--sdk', 'macosx', 'clang', '-fobjc-arc', '-fblocks',
        '-framework', 'Foundation', '-I', join(root, 'Natives'), harnessPath,
        join(root, 'Natives/PocketJGameStartup.c'), '-o', observationOutput, '-pthread'], { stdio: 'inherit' });
    execFileSync(observationOutput, [], { stdio: 'inherit' });
} finally {
    rmSync(directory, { recursive: true, force: true });
}
