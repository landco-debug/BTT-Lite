// Short-lived helper for one BTT-compatible action:
// activate the application icon currently hovered in Dock, then send Command-H.
//
// TP08 combines the accepted TP04 swipe coalescing with the TP07 Dock fix.
// Dock handling: do not infer "hovered" from pointer geometry first. The Dock publishes
// its current hovered item through AXSelectedChildren. Use that semantic state
// directly, then fall back to a recursive geometry scan only if needed.
// The helper is launched only by Trickpad's 3-finger double-tap binding.

#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import <fcntl.h>
#import <sys/stat.h>
#import <sys/time.h>
#import <unistd.h>

static NSMutableString *gDebug = nil;

static void debugLine(NSString *format, ...) {
    if (!gDebug) gDebug = [NSMutableString string];
    va_list args;
    va_start(args, format);
    NSString *line = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    [gDebug appendFormat:@"%@\n", line];
}

static void writeFailureLog(void) {
    if (!gDebug.length) return;
    NSString *dir = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Logs/TrickpadPilot"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    NSString *path = [dir stringByAppendingPathComponent:@"dock-helper.log"];
    NSString *stamp = [NSDateFormatter localizedStringFromDate:[NSDate date]
                                                     dateStyle:NSDateFormatterShortStyle
                                                     timeStyle:NSDateFormatterMediumStyle];
    NSString *body = [NSString stringWithFormat:@"[%@]\n%@\n", stamp, gDebug];
    [body writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

static BOOL ensureAccessibility(BOOL prompt) {
    NSDictionary *options = @{
        (__bridge NSString *)kAXTrustedCheckOptionPrompt: @(prompt)
    };
    return AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options);
}

static CFTypeRef copyAttribute(AXUIElementRef element, CFStringRef attribute) {
    if (!element) return NULL;
    CFTypeRef value = NULL;
    AXError err = AXUIElementCopyAttributeValue(element, attribute, &value);
    if (err != kAXErrorSuccess || value == NULL) {
        if (value) CFRelease(value);
        return NULL;
    }
    return value;
}

static NSString *copyStringAttribute(AXUIElementRef element, CFStringRef attribute) {
    CFTypeRef value = copyAttribute(element, attribute);
    if (!value) return nil;
    NSString *result = nil;
    if (CFGetTypeID(value) == CFStringGetTypeID()) {
        result = [(__bridge NSString *)value copy];
    }
    CFRelease(value);
    return result;
}

static NSURL *copyURLAttribute(AXUIElementRef element) {
    CFTypeRef value = copyAttribute(element, kAXURLAttribute);
    if (!value) return nil;
    NSURL *result = nil;
    if (CFGetTypeID(value) == CFURLGetTypeID()) {
        result = [(__bridge NSURL *)value copy];
    }
    CFRelease(value);
    return result;
}

static CFArrayRef copyChildren(AXUIElementRef element) {
    CFTypeRef value = copyAttribute(element, kAXChildrenAttribute);
    if (!value) return NULL;
    if (CFGetTypeID(value) != CFArrayGetTypeID()) {
        CFRelease(value);
        return NULL;
    }
    return (CFArrayRef)value;
}

static CFArrayRef copySelectedChildren(AXUIElementRef element) {
    CFTypeRef value = copyAttribute(element, kAXSelectedChildrenAttribute);
    if (!value) return NULL;
    if (CFGetTypeID(value) != CFArrayGetTypeID()) {
        CFRelease(value);
        return NULL;
    }
    return (CFArrayRef)value;
}

static BOOL copyFrame(AXUIElementRef element, CGRect *frameOut) {
    CFTypeRef positionValue = copyAttribute(element, kAXPositionAttribute);
    CFTypeRef sizeValue = copyAttribute(element, kAXSizeAttribute);
    if (!positionValue || !sizeValue) {
        if (positionValue) CFRelease(positionValue);
        if (sizeValue) CFRelease(sizeValue);
        return NO;
    }

    BOOL ok = NO;
    if (CFGetTypeID(positionValue) == AXValueGetTypeID() &&
        CFGetTypeID(sizeValue) == AXValueGetTypeID()) {
        CGPoint origin = CGPointZero;
        CGSize size = CGSizeZero;
        AXValueRef p = (AXValueRef)positionValue;
        AXValueRef s = (AXValueRef)sizeValue;
        if (AXValueGetType(p) == kAXValueCGPointType &&
            AXValueGetType(s) == kAXValueCGSizeType &&
            AXValueGetValue(p, kAXValueCGPointType, &origin) &&
            AXValueGetValue(s, kAXValueCGSizeType, &size) &&
            size.width > 0 && size.height > 0) {
            *frameOut = CGRectMake(origin.x, origin.y, size.width, size.height);
            ok = YES;
        }
    }

    CFRelease(positionValue);
    CFRelease(sizeValue);
    return ok;
}

static BOOL isApplicationDockItem(AXUIElementRef item) {
    NSString *subrole = copyStringAttribute(item, kAXSubroleAttribute);
    return [subrole isEqualToString:@"AXApplicationDockItem"];
}

static AXUIElementRef copySelectedApplicationDockItemRecursive(AXUIElementRef element,
                                                               int depth,
                                                               int *visited) {
    if (!element || depth > 8 || *visited > 512) return NULL;
    (*visited)++;

    CFArrayRef selected = copySelectedChildren(element);
    if (selected) {
        CFIndex count = CFArrayGetCount(selected);
        if (count > 0) {
            AXUIElementRef candidate = (AXUIElementRef)CFArrayGetValueAtIndex(selected, 0);
            NSString *role = copyStringAttribute(candidate, kAXRoleAttribute);
            NSString *subrole = copyStringAttribute(candidate, kAXSubroleAttribute);
            NSString *title = copyStringAttribute(candidate, kAXTitleAttribute);
            debugLine(@"selected child depth=%d role=%@ subrole=%@ title=%@",
                      depth, role ?: @"<nil>", subrole ?: @"<nil>", title ?: @"<nil>");
            if ([subrole isEqualToString:@"AXApplicationDockItem"]) {
                CFRetain(candidate);
                CFRelease(selected);
                return candidate;
            }
        }
        CFRelease(selected);
    }

    CFArrayRef children = copyChildren(element);
    if (!children) return NULL;

    CFIndex count = CFArrayGetCount(children);
    for (CFIndex i = 0; i < count; i++) {
        AXUIElementRef child = (AXUIElementRef)CFArrayGetValueAtIndex(children, i);
        AXUIElementRef found = copySelectedApplicationDockItemRecursive(child, depth + 1, visited);
        if (found) {
            CFRelease(children);
            return found;
        }
    }

    CFRelease(children);
    return NULL;
}

typedef struct {
    CGPoint pointer;
    AXUIElementRef exact;
    AXUIElementRef nearest;
    CGFloat nearestDistance;
    int appItemCount;
    int visited;
} GeometrySearch;

static CGFloat distancePointToRect(CGPoint point, CGRect rect) {
    CGFloat dx = 0;
    if (point.x < CGRectGetMinX(rect)) dx = CGRectGetMinX(rect) - point.x;
    else if (point.x > CGRectGetMaxX(rect)) dx = point.x - CGRectGetMaxX(rect);

    CGFloat dy = 0;
    if (point.y < CGRectGetMinY(rect)) dy = CGRectGetMinY(rect) - point.y;
    else if (point.y > CGRectGetMaxY(rect)) dy = point.y - CGRectGetMaxY(rect);

    return hypot(dx, dy);
}

static void searchDockGeometryRecursive(AXUIElementRef element, int depth, GeometrySearch *state) {
    if (!element || depth > 8 || state->visited > 512 || state->exact) return;
    state->visited++;

    NSString *role = copyStringAttribute(element, kAXRoleAttribute);
    NSString *subrole = copyStringAttribute(element, kAXSubroleAttribute);
    if ([role isEqualToString:(__bridge NSString *)kAXDockItemRole] &&
        [subrole isEqualToString:@"AXApplicationDockItem"]) {
        CGRect frame = CGRectZero;
        if (copyFrame(element, &frame)) {
            state->appItemCount++;
            CGFloat d = distancePointToRect(state->pointer, frame);
            NSString *title = copyStringAttribute(element, kAXTitleAttribute);
            debugLine(@"app item title=%@ frame={%.1f,%.1f %.1fx%.1f} distance=%.1f",
                      title ?: @"<nil>",
                      frame.origin.x, frame.origin.y, frame.size.width, frame.size.height, d);

            if (CGRectContainsPoint(frame, state->pointer)) {
                state->exact = (AXUIElementRef)CFRetain(element);
                return;
            }
            if (d < state->nearestDistance) {
                if (state->nearest) CFRelease(state->nearest);
                state->nearest = (AXUIElementRef)CFRetain(element);
                state->nearestDistance = d;
            }
        }
    }

    CFArrayRef children = copyChildren(element);
    if (!children) return;
    CFIndex count = CFArrayGetCount(children);
    for (CFIndex i = 0; i < count && !state->exact; i++) {
        AXUIElementRef child = (AXUIElementRef)CFArrayGetValueAtIndex(children, i);
        searchDockGeometryRecursive(child, depth + 1, state);
    }
    CFRelease(children);
}

static AXUIElementRef copyHoveredDockApplicationItem(AXUIElementRef dockRoot) {
    int visited = 0;
    AXUIElementRef selected = copySelectedApplicationDockItemRecursive(dockRoot, 0, &visited);
    debugLine(@"selected-state traversal visited=%d found=%@", visited, selected ? @"yes" : @"no");
    if (selected) return selected;

    CGEventRef pointerEvent = CGEventCreate(NULL);
    if (!pointerEvent) return NULL;
    CGPoint pointer = CGEventGetLocation(pointerEvent);
    CFRelease(pointerEvent);
    debugLine(@"pointer CG={%.1f,%.1f}", pointer.x, pointer.y);

    GeometrySearch state = {
        .pointer = pointer,
        .exact = NULL,
        .nearest = NULL,
        .nearestDistance = CGFLOAT_MAX,
        .appItemCount = 0,
        .visited = 0
    };

    searchDockGeometryRecursive(dockRoot, 0, &state);
    debugLine(@"geometry traversal visited=%d appItems=%d exact=%@ nearestDistance=%.1f",
              state.visited, state.appItemCount, state.exact ? @"yes" : @"no",
              state.nearestDistance);

    if (state.exact) {
        if (state.nearest) CFRelease(state.nearest);
        return state.exact;
    }

    if (state.nearest && state.nearestDistance <= 28.0) {
        return state.nearest;
    }

    if (state.nearest) CFRelease(state.nearest);
    return NULL;
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

static void postCommandH(void) {
    CGEventSourceRef source = CGEventSourceCreate(kCGEventSourceStateHIDSystemState);
    if (!source) return;

    CGEventRef down = CGEventCreateKeyboardEvent(source, (CGKeyCode)4, true);
    CGEventRef up = CGEventCreateKeyboardEvent(source, (CGKeyCode)4, false);
    if (down && up) {
        CGEventSetFlags(down, kCGEventFlagMaskCommand);
        CGEventSetFlags(up, kCGEventFlagMaskCommand);
        CGEventPost(kCGHIDEventTap, down);
        CGEventPost(kCGHIDEventTap, up);
    }
    if (down) CFRelease(down);
    if (up) CFRelease(up);
    CFRelease(source);
}

static BOOL activateDockItem(AXUIElementRef item) {
    AXError press = AXUIElementPerformAction(item, kAXPressAction);
    debugLine(@"AXPress result=%d", press);
    if (press == kAXErrorSuccess) return YES;

    NSURL *url = copyURLAttribute(item);
    debugLine(@"AXURL=%@", url.absoluteString ?: @"<nil>");
    if (!url) return NO;

    NSBundle *bundle = [NSBundle bundleWithURL:url];
    NSString *bundleID = bundle.bundleIdentifier;
    if (bundleID.length > 0) {
        NSArray<NSRunningApplication *> *apps =
            [NSRunningApplication runningApplicationsWithBundleIdentifier:bundleID];
        NSRunningApplication *running = apps.firstObject;
        if (running) {
            return [running activateWithOptions:NSApplicationActivateIgnoringOtherApps];
        }
    }

    return [[NSWorkspace sharedWorkspace] openURL:url];
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSString *mode = argc > 1 ? [NSString stringWithUTF8String:argv[1]] : @"";
        BOOL request = [mode isEqualToString:@"--request-accessibility"];
        BOOL checkOnly = [mode isEqualToString:@"--check"];

        BOOL trusted = ensureAccessibility(request);
        debugLine(@"trusted=%@", trusted ? @"yes" : @"no");
        if (!trusted) {
            if (checkOnly || request)
                fprintf(stderr, "Accessibility permission is not granted.\n");
            writeFailureLog();
            return 77;
        }
        if (checkOnly) {
            printf("trusted\n");
            return 0;
        }

        if ([mode isEqualToString:@"close-once"]) return runSwipeAction(@"close");
        if ([mode isEqualToString:@"reopen-once"]) return runSwipeAction(@"reopen");

        NSArray<NSRunningApplication *> *dockApps =
            [NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.apple.dock"];
        NSRunningApplication *dockApp = dockApps.firstObject;
        if (!dockApp) {
            debugLine(@"Dock process not found");
            writeFailureLog();
            return 2;
        }
        debugLine(@"Dock pid=%d", dockApp.processIdentifier);

        AXUIElementRef dockRoot = AXUIElementCreateApplication(dockApp.processIdentifier);
        if (!dockRoot) {
            debugLine(@"AXUIElementCreateApplication failed");
            writeFailureLog();
            return 2;
        }

        AXUIElementRef dockItem = copyHoveredDockApplicationItem(dockRoot);
        CFRelease(dockRoot);

        if (!dockItem) {
            debugLine(@"No hovered application Dock item resolved");
            writeFailureLog();
            fprintf(stderr, "No hovered application Dock item resolved.\n");
            return 2;
        }

        NSString *title = copyStringAttribute(dockItem, kAXTitleAttribute);
        debugLine(@"resolved title=%@", title ?: @"<nil>");

        BOOL activated = activateDockItem(dockItem);
        CFRelease(dockItem);
        if (!activated) {
            debugLine(@"activation failed");
            writeFailureLog();
            return 3;
        }

        usleep(180000);
        postCommandH();
        return 0;
    }
}
