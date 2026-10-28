// Execute the production footer delegates with Foundation-only test doubles.
// This catches hidden-section text regressions; it is not a UIKit layout test.
import { readFileSync, mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { execFileSync } from 'node:child_process';

const source = readFileSync(new URL('../Natives/LauncherPrefContCfgViewController.m', import.meta.url), 'utf8');
const methods = [...source.matchAll(/^- \([^\n]+\)[^\n]+\{[\s\S]*?(?=\n- \(|\n@end)/gm)]
  .map(match => match[0]);
const delegates = ['titleForFooterInSection', 'heightForFooterInSection', 'estimatedHeightForFooterInSection']
  .map(name => {
    const method = methods.find(text => text.split('\n')[0].includes(`${name}:`));
    if (!method) throw new Error(`Missing production delegate: ${name}`);
    return method;
  }).join('\n');

const harness = `
#import <Foundation/Foundation.h>
@class UITableView;
static const CGFloat UITableViewAutomaticDimension = -1;
static NSString *localize(NSString *key, id unused) {
    if ([key isEqualToString:@"controller_configurator.section.footer.game_mappings"])
        return @"A translated gamepad footer";
    return key;
}
@interface FooterFixture : NSObject
@property NSInteger selectedControlMode;
@property NSArray<NSString *> *prefSections;
@end
@implementation FooterFixture
${delegates}
@end
int main(void) { @autoreleasepool {
    FooterFixture *fixture = [FooterFixture new];
    fixture.prefSections = @[@"key_layout_editor", @"game_mappings", @"menu_mappings", @"controller_style"];
    // Repeated switching catches a footer left behind from the other mode.
    for (int pass = 0; pass < 8; pass++) {
        fixture.selectedControlMode = pass % 2;
        for (NSInteger section = 0; section < 4; section++) {
            NSString *text = [fixture tableView:nil titleForFooterInSection:section];
            BOOL visible = fixture.selectedControlMode == 0 ? section == 0 : section > 0;
            if (!visible && text != nil) {
                NSLog(@"FAIL: hidden section %ld still supplies text", (long)section);
                return 1;
            }
            CGFloat expected = text.length ? UITableViewAutomaticDimension : 0.01;
            if ([fixture tableView:nil heightForFooterInSection:section] != expected ||
                [fixture tableView:nil estimatedHeightForFooterInSection:section] != expected) {
                NSLog(@"FAIL: footer title and sizing disagree");
                return 1;
            }
            if (visible && section < 2 && !text.length) return 1;
            if (section >= 2 && text != nil) return 1; // untranslated keys stay hidden
        }
    }
    NSLog(@"PASS: production footer delegates keep hidden text nil and estimates consistent across mode switches.");
    return 0;
} }
`;
const directory = mkdtempSync(join(tmpdir(), 'pocketj-control-footers-'));
try {
  const executable = join(directory, 'footer-tests');
  execFileSync('xcrun', ['--sdk', 'macosx', 'clang', '-x', 'objective-c', '-fobjc-arc',
    '-framework', 'Foundation', '-', '-o', executable], { input: harness, stdio: ['pipe', 'inherit', 'inherit'] });
  execFileSync(executable, [], { stdio: 'inherit' });
} finally {
  rmSync(directory, { recursive: true, force: true });
}
