#include <CoreGraphics/CoreGraphics.h>
#include <CoreFoundation/CoreFoundation.h>

extern void goHotkeyCallback(void);

static CGEventRef eventCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *userInfo) {
    if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput) {
        CGEventTapEnable((CFMachPortRef)userInfo, true);
        return event;
    }

    if (type != kCGEventKeyDown) {
        return event;
    }

    CGKeyCode keyCode = (CGKeyCode)CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode);
    CGEventFlags flags = CGEventGetFlags(event);

    // Ctrl+Option+K: keycode 40 = 'k'
    bool hasOption = (flags & kCGEventFlagMaskAlternate) != 0;
    bool hasCtrl   = (flags & kCGEventFlagMaskControl) != 0;
    bool noCmd     = (flags & kCGEventFlagMaskCommand) == 0;
    bool noShift   = (flags & kCGEventFlagMaskShift) == 0;

    if (keyCode == 40 && hasOption && hasCtrl && noCmd && noShift) {
        goHotkeyCallback();
        return NULL;
    }

    return event;
}

void simulatePaste(void) {
    CGEventSourceRef source = CGEventSourceCreate(kCGEventSourceStateHIDSystemState);

    // keycode 9 = 'v'
    CGEventRef keyDown = CGEventCreateKeyboardEvent(source, 9, true);
    CGEventRef keyUp   = CGEventCreateKeyboardEvent(source, 9, false);

    // Add Cmd modifier
    CGEventSetFlags(keyDown, kCGEventFlagMaskCommand);
    CGEventSetFlags(keyUp, kCGEventFlagMaskCommand);

    CGEventPost(kCGHIDEventTap, keyDown);
    CGEventPost(kCGHIDEventTap, keyUp);

    CFRelease(keyDown);
    CFRelease(keyUp);
    CFRelease(source);
}

int startEventTap(void) {
    CGEventMask mask = CGEventMaskBit(kCGEventKeyDown);
    CFMachPortRef tap = CGEventTapCreate(
        kCGSessionEventTap,
        kCGHeadInsertEventTap,
        kCGEventTapOptionDefault,
        mask,
        eventCallback,
        NULL
    );

    if (!tap) {
        return -1;
    }

    CFRunLoopSourceRef source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0);
    CFRunLoopAddSource(CFRunLoopGetMain(), source, kCFRunLoopCommonModes);
    CGEventTapEnable(tap, true);
    CFRunLoopRun();
    return 0;
}
