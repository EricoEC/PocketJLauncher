import assert from 'node:assert/strict';
import { readFileSync, mkdtempSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';
const root = fileURLToPath(new URL('../', import.meta.url));
const dir = mkdtempSync(join(tmpdir(), 'pocketj-update-tests-'));
try {
    const binary = join(dir, 'test');
    execFileSync('xcrun', ['clang', '-fobjc-arc', '-fblocks', '-framework', 'Foundation',
        '-I', join(root, 'Natives'), join(root, 'Natives/PocketJUpdateChecker.m'),
        join(root, 'Tests/UpdateCheckerTests.m'), '-o', binary], { stdio: 'inherit' });
    execFileSync(binary, process.argv.includes('--live') ? ['--live'] : [], { stdio: 'inherit' });
    const ui = readFileSync(join(root, 'Natives/PocketJUpdatePrompt.m'), 'utf8');
    for (const text of ['立即更新', '下次再说', '跳过此版本', 'GitHub Releases', '123 云盘',
        'https://github.com/EricoEC/PocketJLauncher/releases',
        'https://1842976282.share.123pan.cn/123pan/5B6UTd-KLi1A']) assert(ui.includes(text));
    assert(ui.includes('popoverPresentationController.sourceRect'));
    const settings = readFileSync(join(root, 'Natives/ModernSettingsViewController.m'), 'utf8');
    assert(settings.includes('showRelease:release from:self manual:YES'));
    const controller = readFileSync(join(root, 'Natives/ModernRootTabBarController.m'), 'utf8');
    assert(controller.includes('UIApplicationDidBecomeActiveNotification'));
    assert(controller.includes('showRelease:release from:self manual:NO'));
    assert(controller.includes('notification.userInfo[@"manual"]'));
    for (const lang of ['en', 'zh-Hans']) {
        const strings = readFileSync(join(root, `Natives/resources/${lang}.lproj/Localizable.strings`), 'utf8');
        for (const key of ['立即更新', '下次再说', '跳过此版本', '选择下载来源', '123 云盘'])
            assert(strings.includes(`"${key}" = "`));
    }
    console.log('PASS: automatic/manual UI routing, three actions, fixed download links, iPad anchor and bilingual copy.');
} finally { rmSync(dir, { recursive: true, force: true }); }
