// Short-lived helper for one BTT-compatible action:
// activate the Dock item currently under the pointer, then send Command-H.
// It is launched only by Trickpad's 3-finger double-tap binding.

#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import <unistd.h>

static BOOL ensureAccessibility(BOOL prompt) {
    NSDictionary *options = @{
        (__bridge NSString *)kAXTrustedCheckOptionPrompt: @(prompt)
    };
    return AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options);
}

static AXUIElementRef copyDockItemAtPointer(void) {
    NSPoint mouse = [NSEvent mouseLocation];
    AXUIElementRef systemWide = AXUIElementCreateSystemWide();
    AXUIElementRef element = NULL;
    AXError err = AXUIElementCopyElementAtPosition(
        systemWide, (float)mouse.x, (float)mouse.y, &element);
    CFRelease(systemWide);
    if (err != kAXErrorSuccess || element == NULL) return NULL;

    AXUIElementRef current = element;
    for (int depth = 0; depth < 8 && current != NULL; depth++) {
        CFTypeRef roleValue = NULL;
        CFTypeRef titleValue = NULL;
        AXUIElementCopyAttributeValue(current, kAXRoleAttribute, &roleValue);
        AXUIElementCopyAttributeValue(current, kAXTitleAttribute, &titleValue);

        NSString *role = [(__bridge id)roleValue isKindOfClass:[NSString class]]
            ? (__bridge NSString *)roleValue : @"";
        NSString *title = [(__bridge id)titleValue isKindOfClass:[NSString class]]
            ? (__bridge NSString *)titleValue : @"";

        BOOL isDockItem =
            [role isEqualToString:(__bridge NSString *)kAXDockItemRole] ||
            [role isEqualToString:(__bridge NSString *)kAXButtonRole];

        if (roleValue) CFRelease(roleValue);
        if (titleValue) CFRelease(titleValue);

        if (isDockItem && title.length > 0) {
            if (current != element) CFRelease(element);
            return current;
        }

        CFTypeRef parentValue = NULL;
        AXError parentErr = AXUIElementCopyAttributeValue(
            current, kAXParentAttribute, &parentValue);
        if (current != element) CFRelease(current);
        if (parentErr != kAXErrorSuccess || parentValue == NULL) {
            CFRelease(element);
            return NULL;
        }
        current = (AXUIElementRef)parentValue;
    }

    if (current && current != element) CFRelease(current);
    CFRelease(element);
    return NULL;
}

static void sendCommandH(void) {
    CGEventSourceRef source = CGEventSourceCreate(kCGEventSourceStateHIDSystemState);
    if (!source) return;

    const CGKeyCode commandKey = 55;
    const CGKeyCode hKey = 4;
    CGEventRef cmdDown = CGEventCreateKeyboardEvent(source, commandKey, true);
    CGEventRef hDown = CGEventCreateKeyboardEvent(source, hKey, true);
    CGEventRef hUp = CGEventCreateKeyboardEvent(source, hKey, false);
    CGEventRef cmdUp = CGEventCreateKeyboardEvent(source, commandKey, false);

    if (cmdDown && hDown && hUp && cmdUp) {
        CGEventSetFlags(hDown, kCGEventFlagMaskCommand);
        CGEventSetFlags(hUp, kCGEventFlagMaskCommand);
        CGEventPost(kCGHIDEventTap, cmdDown);
        CGEventPost(kCGHIDEventTap, hDown);
        CGEventPost(kCGHIDEventTap, hUp);
        CGEventPost(kCGHIDEventTap, cmdUp);
    }

    if (cmdDown) CFRelease(cmdDown);
    if (hDown) CFRelease(hDown);
    if (hUp) CFRelease(hUp);
    if (cmdUp) CFRelease(cmdUp);
    CFRelease(source);
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        BOOL request = argc > 1 && strcmp(argv[1], "--request-accessibility") == 0;
        BOOL checkOnly = argc > 1 && strcmp(argv[1], "--check") == 0;

        if (!ensureAccessibility(request)) {
            if (checkOnly || request)
                fprintf(stderr, "Accessibility permission is not granted.\n");
            return 77;
        }
        if (checkOnly) {
            printf("trusted\n");
            return 0;
        }

        AXUIElementRef dockItem = copyDockItemAtPointer();
        if (!dockItem) {
            fprintf(stderr, "No Dock item found under the pointer.\n");
            return 2;
        }

        AXError press = AXUIElementPerformAction(dockItem, kAXPressAction);
        CFRelease(dockItem);
        if (press != kAXErrorSuccess) {
            fprintf(stderr, "Could not activate the Dock item (AX error %d).\n", press);
            return 3;
        }

        // Give Dock enough time to activate the selected application before
        // the global Command-H reaches the frontmost app.
        usleep(160000);
        sendCommandH();
        return 0;
    }
}
