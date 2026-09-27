// Short-lived helper for the Trickpad pilot.
//
// No arguments:
//   activate the Dock item under the pointer, then send Command-H.
//
// close-once / reopen-once:
//   send Command-W or Command-Shift-T once per physical swipe. Trickpad's
//   upstream recognizers intentionally allow swipe repetition while the same
//   contact sequence remains owned, so this helper coalesces rapid repeats
//   without changing Trickpad itself.

#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import <fcntl.h>
#import <sys/stat.h>
#import <sys/time.h>
#import <unistd.h>

static const useconds_t kSwipeQuietWindowUS = 300000;

static BOOL ensureAccessibility(BOOL prompt) {
    NSDictionary *options = @{
        (__bridge NSString *)kAXTrustedCheckOptionPrompt: @(prompt)
    };
    return AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options);
}

static CGPoint quartzPointerLocation(void) {
    CGEventRef event = CGEventCreate(NULL);
    if (!event) return CGPointZero;
    CGPoint point = CGEventGetLocation(event);
    CFRelease(event);
    return point;
}

static AXUIElementRef copyDockItemAtPointer(void) {
    CGPoint mouse = quartzPointerLocation();

    AXUIElementRef systemWide = AXUIElementCreateSystemWide();
    AXUIElementRef element = NULL;
    AXError err = AXUIElementCopyElementAtPosition(
        systemWide, (float)mouse.x, (float)mouse.y, &element);
    CFRelease(systemWide);
    if (err != kAXErrorSuccess || element == NULL) return NULL;

    AXUIElementRef current = element;
    for (int depth = 0; depth < 10 && current != NULL; depth++) {
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

static void postShortcut(CGKeyCode keyCode, CGEventFlags flags) {
    CGEventSourceRef source = CGEventSourceCreate(kCGEventSourceStateHIDSystemState);
    if (!source) return;

    CGEventRef down = CGEventCreateKeyboardEvent(source, keyCode, true);
    CGEventRef up = CGEventCreateKeyboardEvent(source, keyCode, false);
    if (down && up) {
        CGEventSetFlags(down, flags);
        CGEventSetFlags(up, flags);
        CGEventPost(kCGHIDEventTap, down);
        CGEventPost(kCGHIDEventTap, up);
    }

    if (down) CFRelease(down);
    if (up) CFRelease(up);
    CFRelease(source);
}

static NSString *lockPathForAction(NSString *action) {
    return [NSString stringWithFormat:@"/tmp/local.trickpad.%u.%@.lock",
            (unsigned)getuid(), action];
}

static BOOL acquireSwipeGate(NSString *action, NSString **lockPathOut) {
    NSString *path = lockPathForAction(action);
    const char *fs = path.fileSystemRepresentation;
    int fd = open(fs, O_CREAT | O_EXCL | O_WRONLY, 0600);
    if (fd >= 0) {
        close(fd);
        *lockPathOut = path;
        return YES;
    }

    struct timeval tv[2];
    gettimeofday(&tv[0], NULL);
    tv[1] = tv[0];
    utimes(fs, tv);
    return NO;
}

static void holdSwipeGateUntilQuiet(NSString *lockPath) {
    const char *fs = lockPath.fileSystemRepresentation;

    for (;;) {
        struct stat st;
        if (stat(fs, &st) != 0) break;

        struct timeval now;
        gettimeofday(&now, NULL);

        double modified =
            (double)st.st_mtimespec.tv_sec +
            (double)st.st_mtimespec.tv_nsec / 1000000000.0;
        double current =
            (double)now.tv_sec +
            (double)now.tv_usec / 1000000.0;

        if ((current - modified) * 1000000.0 >= kSwipeQuietWindowUS) break;
        usleep(25000);
    }

    unlink(fs);
}

static int runSwipeAction(NSString *action) {
    NSString *lockPath = nil;
    if (!acquireSwipeGate(action, &lockPath)) return 0;

    if ([action isEqualToString:@"close"]) {
        postShortcut((CGKeyCode)13, kCGEventFlagMaskCommand);
    } else {
        postShortcut((CGKeyCode)17,
                     kCGEventFlagMaskCommand | kCGEventFlagMaskShift);
    }

    holdSwipeGateUntilQuiet(lockPath);
    return 0;
}

static int runDockHide(void) {
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

    usleep(180000);
    postShortcut((CGKeyCode)4, kCGEventFlagMaskCommand);
    return 0;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSString *mode = argc > 1 ? [NSString stringWithUTF8String:argv[1]] : @"";
        BOOL request = [mode isEqualToString:@"--request-accessibility"];
        BOOL checkOnly = [mode isEqualToString:@"--check"];

        if (!ensureAccessibility(request)) {
            if (checkOnly || request)
                fprintf(stderr, "Accessibility permission is not granted.\n");
            return 77;
        }

        if (checkOnly) {
            printf("trusted\n");
            return 0;
        }

        if ([mode isEqualToString:@"close-once"]) return runSwipeAction(@"close");
        if ([mode isEqualToString:@"reopen-once"]) return runSwipeAction(@"reopen");

        return runDockHide();
    }
}
