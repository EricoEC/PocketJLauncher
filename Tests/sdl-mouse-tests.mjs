import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, mkdtempSync, rmSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { execFileSync } from 'node:child_process';

const root = fileURLToPath(new URL('../', import.meta.url));
const source = readFileSync(join(root, 'Natives/input_bridge_v3.m'), 'utf8');
const typeEnd = source.indexOf('} PJSDLMouseMotionEvent;') + '} PJSDLMouseMotionEvent;'.length;
const motionType = source.slice(source.lastIndexOf('typedef struct {', typeEnd), typeEnd);
const start = source.indexOf('void CallbackBridge_nativeSendCursorPos(');
const end = source.indexOf('    if (!isInputReady) return;', start);
assert(start >= 0 && end > start);
const production = source.slice(start, end) + '\n}\n';
const actions = readFileSync(join(root, 'Natives/utils.h'), 'utf8')
    .match(/^#define ACTION_(?:DOWN|UP|MOVE|MOVE_MOTION)\s+\d+$/gm).join('\n');
const harness = `
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
typedef double CGFloat;
${actions}
${motionType}
typedef union { uint32_t type; uint8_t bytes[128]; } PJSDLEvent;
static void *GLFW_invoke_CursorPos;
static float pjSDLLastX, pjSDLLastY;
static double cursorX, cursorY;
static bool isGrabbing;
static unsigned count;
static float totalX, totalY;
static PJSDLMouseMotionEvent last;
static uint32_t pjSDLWindowID(void) { return 42; }
static bool pjSDLPushEvent(void *event) {
    memcpy(&last, event, sizeof(last));
    assert(last.type == 0x400 && last.windowID == 42);
    totalX += last.xrel; totalY += last.yrel; count++;
    return true;
}
${production}
int main(void) {
    isGrabbing = true;
    CallbackBridge_nativeSendCursorPos(ACTION_DOWN, 900, 500);
    assert(count == 0);
    for (int i = 0; i < 1000; i++)
        CallbackBridge_nativeSendCursorPos(ACTION_MOVE_MOTION, 10, -4);
    assert(totalX == 10000 && totalY == -4000);
    assert(cursorX == 10000 && cursorY == -4000);
    assert(last.x == 10000 && last.xrel == 10);
    CallbackBridge_nativeSendCursorPos(ACTION_MOVE_MOTION, 3, 2);
    CallbackBridge_nativeSendCursorPos(ACTION_MOVE_MOTION, -7, 1);
    assert(totalX == 9996 && totalY == -3997);
    unsigned previous = count;
    CallbackBridge_nativeSendCursorPos(ACTION_UP, 1200, 700);
    CallbackBridge_nativeSendCursorPos(ACTION_DOWN, 40, 60);
    assert(count == previous && totalX == 9996 && totalY == -3997);
    CallbackBridge_nativeSendCursorPos(ACTION_MOVE, 45, 57);
    assert(last.xrel == 5 && last.yrel == -3);
    isGrabbing = false;
    CallbackBridge_nativeSendCursorPos(ACTION_DOWN, 100, 200);
    assert(last.x == 100 && last.y == 200 && last.xrel == 0);
    CallbackBridge_nativeSendCursorPos(ACTION_MOVE, 130, 210);
    assert(last.x == 130 && last.y == 210 && last.xrel == 30 && last.yrel == 10);
    CallbackBridge_nativeSendCursorPos(ACTION_MOVE_MOTION, 5, -2);
    assert(last.x == 135 && last.y == 208 && last.xrel == 5 && last.yrel == -2);
    puts("PASS: production SDL mouse branch: 1000 rapid deltas accumulate, reversal, finger reanchor and absolute menu cursor.");
}
`;
const directory = mkdtempSync(join(tmpdir(), 'pocketj-sdl-mouse-'));
try {
    const input = join(directory, 'mouse.c');
    const output = join(directory, 'mouse-tests');
    writeFileSync(input, harness);
    execFileSync('xcrun', ['clang', '-Wall', '-Wextra', '-Werror', input, '-o', output], { stdio: 'inherit' });
    execFileSync(output, [], { stdio: 'inherit' });
} finally { rmSync(directory, { recursive: true, force: true }); }
