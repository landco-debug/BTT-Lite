// Short-lived helper for one BTT-compatible action:
// activate the application icon currently hovered in Dock, then send Command-H.
// It is launched only by Trickpad's 3-finger double-tap binding.
//
// TP06 deliberately does NOT change any swipe binding. The Dock action no longer
// relies on AXUIElementCopyElementAtPosition(systemWide,...), because that path
// returned no Dock item on the user's macOS Sequoia setup. Instead we inspect
// Dock's own Accessibility tree and match the pointer against AXApplicationDockItem
// frames directly.

#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import <unistd.h>

static BOOL ensureAccessibility(BOOL prompt) {
    NSDictionary *options = @{
        (__bridge NSString *)kAXTrustedCheckOptionPrompt: @(prompt)
    };
    return AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options);
}

static NSString *copyStringAttribute(AXUIElementRef element, CFStringRef attribute) {
    CFTypeRef value = NULL;
    if (AXUIElementCopyAttributeValue(element, attribute, &value) != kAXErrorSuccess || value == NULL) {
        return nil;
    }

    NSString *result = nil;
    if (CFGetTypeID(value) == CFStringGetTypeID()) {
        result = [(__bridge NSString *)value copy];
    }
    CFRelease(value);
    return result;
}

static CFArrayRef copyChildren(AXUIElementRef element) {
    CFTypeRef value = NULL;
    if (AXUIElementCopyAttributeValue(element, kAXChildrenAttribute, &value) != kAXErrorSuccess ||
        value == NULL ||
        CFGetTypeID(value) != CFArrayGetTypeID()) {
        if (value) CFRelease(value);
        return NULL;
    }
    return (CFArrayRef)value; // caller releases
}

static BOOL copyFrame(AXUIElementRef element, CGRect *frameOut) {
    CFTypeRef positionValue = NULL;
    CFTypeRef sizeValue = NULL;

    AXError p = AXUIElementCopyAttributeValue(element, kAXPositionAttribute, &positionValue);
    AXError s = AXUIElementCopyAttributeValue(element, kAXSizeAttribute, &sizeValue);
    if (p != kAXErrorSuccess || s != kAXErrorSuccess || !positionValue || !sizeValue) {
        if (positionValue) CFRelease(positionValue);
        if (sizeValue) CFRelease(sizeValue);
        return NO;
    }

    BOOL ok = NO;
    if (CFGetTypeID(positionValue) == AXValueGetTypeID() &&
        CFGetTypeID(sizeValue) == AXValueGetTypeID()) {
        AXValueRef pValue = (AXValueRef)positionValue;
        AXValueRef sValue = (AXValueRef)sizeValue;
        CGPoint origin = CGPointZero;
        CGSize size = CGSizeZero;

        if (AXValueGetType(pValue) == kAXValueCGPointType &&
            AXValueGetType(sValue) == kAXValueCGSizeType &&
            AXValueGetValue(pValue, kAXValueCGPointType, &origin) &&
            AXValueGetValue(sValue, kAXValueCGSizeType, &size) &&
            size.width > 0.0 && size.height > 0.0) {
            *frameOut = CGRectMake(origin.x, origin.y, size.width, size.height);
            ok = YES;
        }
    }

    CFRelease(positionValue);
    CFRelease(sizeValue);
    return ok;
}

static CGFloat distanceFromPointToRect(CGPoint point, CGRect rect) {
    CGFloat dx = 0.0;
    if (point.x < CGRectGetMinX(rect)) dx = CGRectGetMinX(rect) - point.x;
    else if (point.x > CGRectGetMaxX(rect)) dx = point.x - CGRectGetMaxX(rect);

    CGFloat dy = 0.0;
    if (point.y < CGRectGetMinY(rect)) dy = CGRectGetMinY(rect) - point.y;
    else if (point.y > CGRectGetMaxY(rect)) dy = point.y - CGRectGetMaxY(rect);

    return hypot(dx, dy);
}

static AXUIElementRef copyHoveredDockApplicationItem(void) {
    CGEventRef pointerEvent = CGEventCreate(NULL);
    if (!pointerEvent) return NULL;
    CGPoint pointer = CGEventGetLocation(pointerEvent);
    CFRelease(pointerEvent);

    NSArray<NSRunningApplication *> *dockApps =
        [NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.apple.dock"];
    NSRunningApplication *dockApp = dockApps.firstObject;
    if (!dockApp) return NULL;

    AXUIElementRef dockRoot = AXUIElementCreateApplication(dockApp.processIdentifier);
    if (!dockRoot) return NULL;

    CFArrayRef rootChildren = copyChildren(dockRoot);
    if (!rootChildren) {
        CFRelease(dockRoot);
        return NULL;
    }

    AXUIElementRef dockList = NULL;
    CFIndex rootCount = CFArrayGetCount(rootChildren);
    for (CFIndex i = 0; i < rootCount; i++) {
        AXUIElementRef child = (AXUIElementRef)CFArrayGetValueAtIndex(rootChildren, i);
        NSString *role = copyStringAttribute(child, kAXRoleAttribute);
        if ([role isEqualToString:(__bridge NSString *)kAXListRole]) {
            dockList = (AXUIElementRef)CFRetain(child);
            break;
        }
    }
    CFRelease(rootChildren);
    CFRelease(dockRoot);
    if (!dockList) return NULL;

    CFArrayRef items = copyChildren(dockList);
    CFRelease(dockList);
    if (!items) return NULL;

    AXUIElementRef exact = NULL;
    AXUIElementRef nearest = NULL;
    CGFloat nearestDistance = CGFLOAT_MAX;

    CFIndex itemCount = CFArrayGetCount(items);
    for (CFIndex i = 0; i < itemCount; i++) {
        AXUIElementRef item = (AXUIElementRef)CFArrayGetValueAtIndex(items, i);
        NSString *role = copyStringAttribute(item, kAXRoleAttribute);
        if (![role isEqualToString:(__bridge NSString *)kAXDockItemRole]) continue;

        NSString *subrole = copyStringAttribute(item, kAXSubroleAttribute);
        if (![subrole isEqualToString:@"AXApplicationDockItem"]) continue;

        CGRect frame = CGRectZero;
        if (!copyFrame(item, &frame)) continue;

        if (CGRectContainsPoint(frame, pointer)) {
            exact = (AXUIElementRef)CFRetain(item);
            break;
        }

        CGFloat distance = distanceFromPointToRect(pointer, frame);
        if (distance < nearestDistance) {
            nearestDistance = distance;
            if (nearest) CFRelease(nearest);
            nearest = (AXUIElementRef)CFRetain(item);
        }
    }

    CFRelease(items);

    if (exact) {
        if (nearest) CFRelease(nearest);
        return exact;
    }

    // Dock magnification / label animation can make the AX frame lag the cursor
    // by a few points. Accept only a very close application item; never jump
    // across a visible gap to a different icon.
    if (nearest && nearestDistance <= 14.0) return nearest;
    if (nearest) CFRelease(nearest);
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

        AXUIElementRef dockItem = copyHoveredDockApplicationItem();
        if (!dockItem) {
            fprintf(stderr, "No application Dock item found under the pointer.\n");
            return 2;
        }

        AXError press = AXUIElementPerformAction(dockItem, kAXPressAction);
        CFRelease(dockItem);
        if (press != kAXErrorSuccess) {
            fprintf(stderr, "Could not activate the Dock item (AX error %d).\n", press);
            return 3;
        }

        usleep(180000);
        sendCommandH();
        return 0;
    }
}
