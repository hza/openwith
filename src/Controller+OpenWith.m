#import "Controller.h"

@implementation Controller (OpenWith)

- (void)application:(NSApplication *)app openURLs:(NSArray<NSURL *> *)urls {
    if (!self.window) self.launchedWithFiles = YES;  // arrives before didFinishLaunching on launch
    dispatch_async(dispatch_get_main_queue(), ^{
        for (NSURL *u in urls) if (u.isFileURL) [self chooseAppForFile:u];
        if (!self.window.isVisible) [NSApp terminate:nil];
    });
}

- (void)manageAssociations:(id)sender { [NSApp stopModalWithCode:NSModalResponseContinue]; }

// Ask which app should open the file; the choice opens it (and optionally becomes the default for its type).
- (void)chooseAppForFile:(NSURL *)file {
    NSWorkspace *ws = [NSWorkspace sharedWorkspace];
    NSString *ext = file.pathExtension.lowercaseString;
    UTType *type = nil;
    [file getResourceValue:&type forKey:NSURLContentTypeKey error:nil];
    if (!type && ext.length) type = [UTType typeWithFilenameExtension:ext];

    NSString *selfID = NSBundle.mainBundle.bundleIdentifier;
    NSMutableArray<AppEntry *> *apps = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    for (NSURL *u in [ws URLsForApplicationsToOpenURL:file]) {
        NSBundle *b = [NSBundle bundleWithURL:u];
        NSString *bid = b.bundleIdentifier ?: u.path;
        if ([bid isEqualToString:selfID] || [seen containsObject:bid]) continue;
        [seen addObject:bid];
        AppEntry *e = [AppEntry new];
        e.url = u;
        e.bundleID = bid;
        e.name = [[NSFileManager defaultManager] displayNameAtPath:u.path].stringByDeletingPathExtension;
        // Every app here can open the file, so it matches the file's ".ext" even if it claims it via a parent UTI.
        NSMutableSet *exts = [ClaimedExtensions(b.infoDictionary) mutableCopy];
        if (ext.length) [exts addObject:ext];
        e.exts = exts;
        e.utis = ClaimedUTIs(b.infoDictionary);
        [apps addObject:e];
    }
    [apps sortUsingComparator:^NSComparisonResult(AppEntry *a, AppEntry *b) {
        return [a.name localizedCaseInsensitiveCompare:b.name];
    }];
    NSURL *cur = type ? [ws URLForApplicationToOpenContentType:type] : nil;
    NSString *curID = cur ? [NSBundle bundleWithURL:cur].bundleIdentifier : nil;
    if ([curID isEqualToString:selfID]) curID = nil;
    // Not the default for this type (e.g. reached via Finder's "Open With"): offer to become it, pinned on top.
    if (type && curID) {
        AppEntry *me = [AppEntry new];
        me.url = NSBundle.mainBundle.bundleURL;
        me.bundleID = selfID;
        me.name = @"Open With (ask every time)";
        me.exts = ext.length ? [NSSet setWithObject:ext] : [NSSet set];
        [apps insertObject:me atIndex:0];
    }
    // Preselect the app last chosen for this extension, if it's still offered.
    NSUserDefaults *defs = NSUserDefaults.standardUserDefaults;
    NSString *lastID = ext.length ? [defs dictionaryForKey:@"LastOpenWith"][ext] : nil;
    NSString *selectID = curID;
    for (AppEntry *e in apps) if ([e.bundleID isEqualToString:lastID]) { selectID = lastID; break; }
    AppPicker *picker = [[AppPicker alloc] initWithApps:apps selectBundleID:selectID];
    if (ext.length) {
        picker.search.stringValue = [@"." stringByAppendingString:ext];
        [picker controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification object:picker.search]];
    }

    NSPanel *panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 380, 490)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
        backing:NSBackingStoreBuffered defer:NO];
    panel.title = [NSString stringWithFormat:@"Open “%@” with", file.lastPathComponent];
    panel.releasedWhenClosed = NO;

    NSTextField *info = [NSTextField wrappingLabelWithString:
        @"Choose the app to open this file with. Open With stays the default, so you can pick again next time."];
    info.textColor = NSColor.secondaryLabelColor;
    // Off by default: making another app the default would bypass this picker for future files.
    NSButton *makeDefault = [NSButton checkboxWithTitle: ext.length
        ? [NSString stringWithFormat:@"Always open .%@ files with this app", ext]
        : @"Always open files of this type with this app" target:nil action:nil];
    makeDefault.state = NSControlStateValueOff;
    makeDefault.enabled = type != nil;
    NSButton *manage = [NSButton buttonWithTitle:@"Manage Associations…" target:self action:@selector(manageAssociations:)];
    NSButton *cancel = [NSButton buttonWithTitle:@"Cancel" target:NSApp action:@selector(abortModal)];
    cancel.keyEquivalent = @"\e";
    NSButton *ok = [NSButton buttonWithTitle:@"Open" target:NSApp action:@selector(stopModal)];
    ok.keyEquivalent = @"\r";
    ok.enabled = apps.count > 0;
    picker.onDoubleClick = ^{ [NSApp stopModal]; };

    NSView *content = panel.contentView;
    for (NSView *v in @[info, picker.view, makeDefault, manage, cancel, ok]) {
        v.translatesAutoresizingMaskIntoConstraints = NO;
        [content addSubview:v];
    }
    [NSLayoutConstraint activateConstraints:@[
        [info.topAnchor constraintEqualToAnchor:content.topAnchor constant:14],
        [info.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:20],
        [info.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-20],
        [picker.view.topAnchor constraintEqualToAnchor:info.bottomAnchor constant:12],
        [picker.view.leadingAnchor constraintEqualToAnchor:info.leadingAnchor],
        [picker.view.trailingAnchor constraintEqualToAnchor:info.trailingAnchor],
        [picker.view.heightAnchor constraintEqualToConstant:340],
        [makeDefault.topAnchor constraintEqualToAnchor:picker.view.bottomAnchor constant:10],
        [makeDefault.leadingAnchor constraintEqualToAnchor:info.leadingAnchor],
        [makeDefault.trailingAnchor constraintLessThanOrEqualToAnchor:info.trailingAnchor],
        [ok.topAnchor constraintEqualToAnchor:makeDefault.bottomAnchor constant:14],
        [ok.trailingAnchor constraintEqualToAnchor:info.trailingAnchor],
        [ok.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-16],
        [cancel.centerYAnchor constraintEqualToAnchor:ok.centerYAnchor],
        [cancel.trailingAnchor constraintEqualToAnchor:ok.leadingAnchor constant:-10],
        [manage.centerYAnchor constraintEqualToAnchor:ok.centerYAnchor],
        [manage.leadingAnchor constraintEqualToAnchor:info.leadingAnchor],
    ]];

    id obs = [[NSNotificationCenter defaultCenter] addObserverForName:NSWindowWillCloseNotification
        object:panel queue:nil usingBlock:^(NSNotification *n) { [NSApp abortModal]; }];
    [NSApp activateIgnoringOtherApps:YES];
    [panel center];
    [panel makeFirstResponder:picker.table];
    NSModalResponse r = [NSApp runModalForWindow:panel];
    [[NSNotificationCenter defaultCenter] removeObserver:obs];
    [panel orderOut:nil];

    if (r == NSModalResponseContinue) {
        if (ext.length) {
            self.search.stringValue = [@"." stringByAppendingString:ext];
            [self applyFilter];
        }
        [self showMainWindow];
        return;
    }
    AppEntry *target = picker.selected;
    if (r != NSModalResponseStop || !target) return;

    if ([target.bundleID isEqualToString:selfID]) {
        // Make this app the default for the type, then ask again which app opens this file.
        dispatch_semaphore_t done = dispatch_semaphore_create(0);
        __block NSError *error = nil;
        [ws setDefaultApplicationAtURL:target.url toOpenContentType:type completionHandler:^(NSError *err) {
            error = err;
            dispatch_semaphore_signal(done);
        }];
        dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC));
        for (AppEntry *e in self.allApps) e.assocs = nil;
        [self applyFilter];
        if (error) {
            NSAlert *al = [NSAlert new];
            al.messageText = @"Could not make Open With the default";
            al.informativeText = error.localizedDescription;
            [al runModal];
            return;
        }
        [self chooseAppForFile:file];
        return;
    }

    if (ext.length) {
        NSMutableDictionary *last = [[defs dictionaryForKey:@"LastOpenWith"] mutableCopy] ?: [NSMutableDictionary dictionary];
        last[ext] = target.bundleID;
        [defs setObject:last forKey:@"LastOpenWith"];
        [defs synchronize];  // the app may terminate right after opening the file
    }

    NSWorkspaceOpenConfiguration *cfg = [NSWorkspaceOpenConfiguration configuration];
    // Wait for the hand-off: the app may terminate right after this when launched just to open the file.
    void (^open)(void) = ^{
        dispatch_semaphore_t opened = dispatch_semaphore_create(0);
        [ws openURLs:@[file] withApplicationAtURL:target.url configuration:cfg
            completionHandler:^(NSRunningApplication *app, NSError *err) { dispatch_semaphore_signal(opened); }];
        dispatch_semaphore_wait(opened, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC));
    };
    if (!type || makeDefault.state != NSControlStateValueOn) { open(); return; }
    // Keep the process alive until the default is set and the file handed off.
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    __block NSError *error = nil;
    [ws setDefaultApplicationAtURL:target.url toOpenContentType:type completionHandler:^(NSError *err) {
        error = err;
        dispatch_semaphore_signal(done);
    }];
    dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC));
    open();
    if (error) {
        NSAlert *al = [NSAlert new];
        al.messageText = [NSString stringWithFormat:@"Could not make %@ the default", target.name];
        al.informativeText = error.localizedDescription;
        [al runModal];
    }
    for (AppEntry *e in self.allApps) e.assocs = nil;
    [self applyFilter];
}

@end
