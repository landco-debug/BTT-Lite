// TP10: hide the application owning the visible window under the pointer.
// The historical executable path/identifier are retained for existing grants.
#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import <fcntl.h>
#import <sys/stat.h>
#import <sys/time.h>
#import <unistd.h>

static BOOL ensureAccessibility(BOOL prompt) {
    NSDictionary *options = @{(__bridge NSString *)kAXTrustedCheckOptionPrompt: @(prompt)};
    return AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options);
}

// WindowServer supplies visible windows in front-to-back order. Only ordinary
// windows are targets; Dock, menu bar, desktop and transparent overlays are not.
// Bounds and owner PID suffice; neither window titles nor screen pixels are read.
static pid_t windowOwnerAtPoint(NSArray *windows, CGPoint point) {
    for (NSDictionary *window in windows) {
        NSNumber *layer = window[(__bridge NSString *)kCGWindowLayer];
        NSNumber *alpha = window[(__bridge NSString *)kCGWindowAlpha];
        NSNumber *owner = window[(__bridge NSString *)kCGWindowOwnerPID];
        NSDictionary *bounds = window[(__bridge NSString *)kCGWindowBounds];
        if (!layer || layer.integerValue != 0 || !alpha || alpha.doubleValue <= 0 ||
            !owner || owner.intValue <= 0 || !bounds) continue;
        CGRect rect;
        if (CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)bounds, &rect) &&
            rect.size.width > 0 && rect.size.height > 0 && CGRectContainsPoint(rect, point))
            return owner.intValue;
    }
    return 0;
}

static void recordHideFailure(CGPoint point, pid_t pid, NSRunningApplication *app, AXError axError) {
    NSString *dir = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Logs/TrickpadPilot"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES
                                               attributes:nil error:nil];
    NSString *body = [NSString stringWithFormat:
        @"date=%@ pointer={%.1f,%.1f} pid=%d bundle=%@ name=%@ frontmost=%@ hidden=%@ terminated=%@ axSetHidden=%d\n",
        [NSDate date], point.x, point.y, pid, app.bundleIdentifier ?: @"<nil>",
        app.localizedName ?: @"<nil>", app.active ? @"yes" : @"no",
        app.hidden ? @"yes" : @"no", app.terminated ? @"yes" : @"no", axError];
    [body writeToFile:[dir stringByAppendingPathComponent:@"window-hide.log"]
          atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

static int hideWindowApplication(void) {
    CGEventRef event = CGEventCreate(NULL);
    if (!event) { fprintf(stderr, "Cannot read pointer position.\n"); return 2; }
    CGPoint point = CGEventGetLocation(event);
    CFRelease(event);
    NSArray *windows = CFBridgingRelease(CGWindowListCopyWindowInfo(
        kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements,
        kCGNullWindowID));
    if (!windows) { fprintf(stderr, "Cannot read visible windows.\n"); return 2; }
    pid_t pid = windowOwnerAtPoint(windows, point);
    // Outside an app window the gesture intentionally does nothing. Never hide
    // an unrelated frontmost app as a fallback.
    if (!pid) return 0;
    NSRunningApplication *app = [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
    if (!app || app.terminated || app.activationPolicy != NSApplicationActivationPolicyRegular)
        return 0;
    // Native app-specific hide avoids activation races and global key injection.
    if ([app hide]) return 0;
    // AppKit can reject a cross-process hide request. The already-authorized
    // Accessibility helper can request that same target app's AXHidden state.
    AXUIElementRef axApp = AXUIElementCreateApplication(pid);
    AXError axError = axApp ? AXUIElementSetAttributeValue(axApp, kAXHiddenAttribute,
                                                          kCFBooleanTrue) : kAXErrorInvalidUIElement;
    if (axApp) CFRelease(axApp);
    if (axError == kAXErrorSuccess) return 0;
    // NSRunningApplication properties update on a turn of the main run loop.
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.08]];
    if (app.hidden || app.terminated) return 0;
    recordHideFailure(point, pid, app, axError);
    fprintf(stderr, "Could not hide application pid=%d; details in ~/Library/Logs/TrickpadPilot/window-hide.log.\n", pid);
    return 3;
}

static NSDictionary *testWindow(pid_t pid, int layer, double alpha, CGRect rect) {
    return @{
        (__bridge NSString *)kCGWindowOwnerPID: @(pid),
        (__bridge NSString *)kCGWindowLayer: @(layer),
        (__bridge NSString *)kCGWindowAlpha: @(alpha),
        (__bridge NSString *)kCGWindowBounds: CFBridgingRelease(CGRectCreateDictionaryRepresentation(rect))
    };
}

static int selfTestHideGate(void);

static int selfTest(void) {
    NSArray *windows = @[
        testWindow(90, 24, 1, CGRectMake(0, 0, 1000, 24)), // menu bar
        testWindow(91, 0, 0, CGRectMake(0, 0, 1000, 900)), // invisible
        testWindow(10, 0, 1, CGRectMake(100, 100, 400, 300)),
        testWindow(20, 0, 1, CGRectMake(0, 30, 900, 700)),
        testWindow(30, 0, 1, CGRectMake(-1000, -400, 800, 600)),
        testWindow(92, -2147483623, 1, CGRectMake(0, 0, 2000, 1200)) // desktop
    ];
    struct { CGPoint point; pid_t expected; } cases[] = {
        {{150, 150}, 10}, // overlapping: front window wins
        {{700, 500}, 20}, // exposed part of a background window
        {{-500, -100}, 30}, // another display, negative coordinates
        {{850, 9}, 0}, // user's earlier menu-bar point
        {{1500, 1000}, 0}, // desktop
        {{2000, 2000}, 0}
    };
    for (size_t i = 0; i < sizeof(cases)/sizeof(cases[0]); i++) {
        if (windowOwnerAtPoint(windows, cases[i].point) != cases[i].expected) {
            fprintf(stderr, "Window targeting test %zu failed.\n", i); return 1;
        }
    }
    if (windowOwnerAtPoint(@[], CGPointZero) != 0) return 1;
    puts("TP10 window targeting: 7 tests passed");
    return 0;
}

static const useconds_t kSwipeQuietWindowUS = 300000;

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

    // Repeated dispatch from the same continuing Trickpad swipe extends the
    // current quiet window, but does not emit a second shortcut.
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
        postShortcut((CGKeyCode)13, kCGEventFlagMaskCommand); // ⌘W
    } else {
        postShortcut((CGKeyCode)17,
                     kCGEventFlagMaskCommand | kCGEventFlagMaskShift); // ⇧⌘T
    }

    holdSwipeGateUntilQuiet(lockPath);
    return 0;
}

static int selfTestHideGate(void) {
    NSString *action = [NSString stringWithFormat:@"window-hide-test-%d", getpid()];
    NSString *path = nil;
    if (!acquireSwipeGate(action, &path)) return 1;
    NSString *ignored = nil;
    if (acquireSwipeGate(action, &ignored)) { unlink(path.fileSystemRepresentation); return 1; }
    holdSwipeGateUntilQuiet(path);
    NSString *again = nil;
    if (!acquireSwipeGate(action, &again)) return 1;
    holdSwipeGateUntilQuiet(again);
    puts("TP11 duplicate-hide gate: passed");
    return 0;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSString *mode = argc > 1 ? [NSString stringWithUTF8String:argv[1]] : @"";
        if ([mode isEqualToString:@"--self-test"]) {
            int result = selfTest();
            return result ? result : selfTestHideGate();
        }
        BOOL request = [mode isEqualToString:@"--request-accessibility"];
        BOOL check = [mode isEqualToString:@"--check"];
        if (!ensureAccessibility(request)) {
            fprintf(stderr, "Accessibility permission is not granted.\n");
            return 77;
        }
        if (check || request) { puts("trusted"); return 0; }
        if ([mode isEqualToString:@"close-once"]) return runSwipeAction(@"close");
        if ([mode isEqualToString:@"reopen-once"]) return runSwipeAction(@"reopen");
        if (mode.length) { fprintf(stderr, "Unknown argument.\n"); return 64; }
        // Trickpad may dispatch one physical double-tap more than once. Use
        // the proven TP04 quiet-window gate with a separate action key so a
        // repeated dispatch cannot hide the window newly revealed underneath.
        NSString *lockPath = nil;
        if (!acquireSwipeGate(@"window-hide", &lockPath)) return 0;
        int result = hideWindowApplication();
        holdSwipeGateUntilQuiet(lockPath);
        return result;
    }
}
