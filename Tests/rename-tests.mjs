import assert from 'node:assert/strict';
import { readFileSync, mkdtempSync, rmSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { execFileSync, spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
const root = fileURLToPath(new URL('../', import.meta.url));
const read = path => readFileSync(join(root, path), 'utf8');
const run = (command, args, options = {}) => execFileSync(command, args, { cwd: root, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024, ...options });
const symbols = ['Init', 'InitOpenGL', 'CreateContext', 'GetCurrentContext', 'MakeCurrent', 'Terminate', 'SetWindowHint', 'SwapBuffers', 'SwapInterval', 'PumpEvents', 'RewindEvents'];
const aliasNames = [...read('Natives/PocketJLegacyRenderAliases.m').matchAll(/^(?:int|void\s*\*?)\s*pojav(\w+)\(/gm)].map(m => m[1]).sort();
assert.deepEqual(aliasNames, [...symbols].sort());

// Every remaining application-source spelling must have a concrete reason.
const audit = spawnSync('rg', ['--json', '-i', 'pojav', 'Natives', 'JavaApp/src',
    '--glob', '!external/**', '--glob', '!build/**', '--glob', '!*.dylib', '--glob', '!*.a'], { cwd: root, encoding: 'utf8' });
assert([0, 1].includes(audit.status), audit.stderr);
const exceptions = {
    'Natives/PocketJEnvironment.c': /^\s*\{"POCKETJ_[A-Z_]+", "POJAV_[A-Z_]+"\},$/,
    'Natives/PocketJLegacyRenderAliases.m': /^(?:int|void\s*\*?)\s*pojav\w+\([^\n]+\{[^\n]+pocketj\w+\(/,
    'Natives/ios_uikit_bridge.m': /^JNIEXPORT void JNICALL Java_net_kdt_pojavlaunch_uikit_UIKit_showError\(/,
    'Natives/authenticator/MinecraftAccountJNI.m': /^JNIEXPORT jstring JNICALL Java_net_kdt_pojavlaunch_value_MinecraftAccount_getAccessTokenFromKeychain\(/,
    'JavaApp/src/launcher/com/erico/pocketj/PocketJLauncher.java': /^\s*System.getProperty\("pojav.internal.keepForgeSplash"\)\);$/,
    'Natives/input_bridge_v3.m': /^\s*\/\/ From Java_net_kdt_pojavlaunch_AWTInputBridge_nativeClipboardReceived$/,
    'Natives/customcontrols/ControlButton.m': /^\s*\/\/ net\/kdt\/pojavlaunch\/customcontrols\/ControlData.update\(\)$/,
    'Natives/customcontrols/ControlJoystick.m': /^\s*\/\/ net\/kdt\/pojavlaunch\/customcontrols\/ControlData.update\(\)$/,
};
for (const row of audit.stdout.trim().split('\n').filter(Boolean).map(JSON.parse)) {
    if (row.type !== 'match') continue;
    const path = row.data.path.text, text = row.data.lines.text.trimEnd();
    assert(exceptions[path]?.test(text), `Unapproved legacy reference: ${path}:${row.data.line_number}: ${text}`);
}
const launcher = read('Natives/JavaLauncher.m');
assert(launcher.includes('"com.erico.pocketj.PocketJLauncher"'));
assert(launcher.includes('-Djava.system.class.loader=com.erico.pocketj.PocketJClassLoader'));
assert(read('JavaApp/src/launcher/com/erico/pocketj/Tools.java').includes('(PocketJClassLoader) ClassLoader.getSystemClassLoader()'));
assert(read('JavaApp/Makefile').includes('$(SOURCEDIR)/%.java $(NAMESPACE_STAMP)'));
assert(!read('JavaApp/Makefile').includes('$(CLASSES) $(LWJGL341_PATCH_CLASSES): $(NAMESPACE_STAMP)'));
const glfw = read('JavaApp/src/lwjgl/org/lwjgl/glfw/GLFW.java');
for (const name of symbols.filter(s => s !== 'InitOpenGL')) assert(glfw.includes(`"pocketj${name}"`), name);
for (const [file, symbol] of [
    ['Natives/ios_uikit_bridge.m', 'Java_com_erico_pocketj_uikit_UIKit_showError'],
    ['Natives/authenticator/MinecraftAccountJNI.m', 'Java_com_erico_pocketj_value_MinecraftAccount_getAccessTokenFromKeychain'],
]) assert(read(file).includes(symbol));

const directory = mkdtempSync(join(tmpdir(), 'pocketj-rename-tests-'));
try {
    const environment = join(directory, 'environment');
    run('xcrun', ['--sdk', 'macosx', 'clang', '-I', 'Natives', 'Natives/PocketJEnvironment.c', 'Tests/PocketJEnvironmentTests.c', '-o', environment]);
    run(environment, [], { stdio: 'inherit' });
    const renderer = join(directory, 'renderer');
    run('xcrun', ['--sdk', 'macosx', 'clang', '-fcommon', '-I', 'Natives', '-I', 'Natives/external/mesa',
        '-framework', 'Foundation', '-framework', 'QuartzCore', 'Natives/PocketJLegacyRenderAliases.m', 'Tests/PocketJRenderAliasTests.m', '-o', renderer]);
    run(renderer, [], { stdio: 'inherit' });
    for (const suffix of ['BUNDLE', 'JRE8', 'JRE17', 'JRE21', 'JRE25']) {
        const name = `POCKETJ_${suffix}_DIR`, old = `POJAV_${suffix}_DIR`;
        // Evaluate the real declarations without the unrelated tool/JDK checks
        // performed while parsing the complete packaging Makefile.
        const declarations = read('Makefile').split('\n').filter(line => /^POCKETJ_(BUNDLE|JRE8|JRE17|JRE21|JRE25)_DIR\s*\?=/.test(line)).join('\n');
        assert.equal(declarations.split('\n').length, 5);
        const input = `OUTPUTDIR := artifacts\nSOURCEDIR := source\n${declarations}\n.PHONY: __rename_test\n__rename_test:\n\t@printf '%s\\n' '$(${name})'\n`;
        const evaluate = args => run('/opt/homebrew/bin/gmake', ['--no-print-directory', '-s', '-f', '-', '__rename_test', ...args], { input, stdio: ['pipe', 'pipe', 'pipe'] }).trim();
        assert.equal(evaluate([`${old}=legacy-path`]), 'legacy-path');
        assert.equal(evaluate([`${name}=new-path`, `${old}=legacy-path`]), 'new-path');
    }
    console.log('PASS: application legacy allowlist, Java/JNI/GLFW references and five Makefile variable precedence rules.');
} finally { rmSync(directory, { recursive: true, force: true }); }

const at = process.argv.indexOf('--app');
if (at !== -1) {
    const app = process.argv[at + 1];
    assert(app);
    const entries = jar => run('unzip', ['-Z1', join(app, 'libs', jar)]).trim().split('\n');
    const mainEntries = entries('launcher.jar');
    assert(mainEntries.includes('com/erico/pocketj/PocketJLauncher.class'));
    assert(mainEntries.includes('com/erico/pocketj/PocketJClassLoader.class'));
    for (const jar of ['launcher.jar', 'lwjgl.jar', 'lwjgl341.jar']) {
        assert(!entries(jar).some(p => p.startsWith('net/kdt/pojavlaunch/')), `Old classes in ${jar}`);
        const bytes = execFileSync('unzip', ['-p', join(app, 'libs', jar)], { maxBuffer: 128 * 1024 * 1024 });
        assert(!bytes.includes(Buffer.from('net/kdt/pojavlaunch')), `Old Java descriptor in ${jar}`);
    }
    const exports = run('xcrun', ['dyld_info', '-exports', join(app, 'PocketJLauncher')]);
    const exported = new Set([...exports.matchAll(/\s_([A-Za-z0-9_]+)\s*$/gm)].map(m => m[1]));
    assert(exported.has('main'));
    for (const name of symbols) for (const prefix of ['pocketj', 'pojav']) assert(exported.has(prefix + name), `${prefix}${name} missing`);
    for (const symbol of ['Java_com_erico_pocketj_uikit_UIKit_showError', 'Java_net_kdt_pojavlaunch_uikit_UIKit_showError']) assert(exported.has(symbol));
    const account = run('xcrun', ['dyld_info', '-exports', join(app, 'Frameworks/libPocketJAccountJNI.dylib')]);
    for (const prefix of ['com_erico_pocketj', 'net_kdt_pojavlaunch']) assert(account.includes(`_Java_${prefix}_value_MinecraftAccount_getAccessTokenFromKeychain`));
    console.log('PASS: final JAR namespace, both LWJGL bindings, main export, 22 render exports and four JNI exports.');
}
