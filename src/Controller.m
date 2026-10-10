#import "Controller.h"

@implementation Controller

static NSTableView *MakeTable(NSArray *cols, id owner) {
    NSTableView *t = [NSTableView new];
    for (NSArray *c in cols) {
        NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:c[0]];
        col.title = c[1];
        col.width = [c[2] doubleValue];
        col.sortDescriptorPrototype = [NSSortDescriptor sortDescriptorWithKey:c[0] ascending:YES
                                                                     selector:@selector(localizedCaseInsensitiveCompare:)];
        [t addTableColumn:col];
    }
    t.dataSource = owner;
    t.delegate = owner;
    t.usesAlternatingRowBackgroundColors = YES;
    t.style = NSTableViewStyleFullWidth;
    return t;
}

static NSScrollView *Wrap(NSView *v) {
    NSScrollView *s = [NSScrollView new];
    s.documentView = v;
    s.hasVerticalScroller = YES;
    s.hasHorizontalScroller = YES;
    s.autohidesScrollers = YES;
    return s;
}

- (void)applicationDidFinishLaunching:(NSNotification *)n {
    [self buildMenu];
    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 1100, 680)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable |
                  NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskFullSizeContentView
          backing:NSBackingStoreBuffered defer:NO];
    self.window.title = @"Open With";
    self.window.subtitle = @"Loading applications…";
    self.window.titleVisibility = NSWindowTitleHidden;

    // Sidebar: search + app source list (System Settings style)
    self.search = [NSSearchField new];
    self.search.placeholderString = @"Search apps or .ext";
    self.search.controlSize = NSControlSizeLarge;
    self.search.font = [NSFont systemFontOfSize:[NSFont systemFontSizeForControlSize:NSControlSizeLarge]];
    self.search.delegate = self;
    self.appTable = MakeTable(@[@[@"name", @"Application", @240]], self);
    self.appTable.headerView = nil;
    self.appTable.style = NSTableViewStyleSourceList;
    self.appTable.usesAlternatingRowBackgroundColors = NO;
    self.appTable.rowHeight = 30;
    self.appTable.backgroundColor = [NSColor clearColor];
    // Keep the single column exactly as wide as the sidebar, so rows truncate with "…" from the start
    self.appTable.columnAutoresizingStyle = NSTableViewFirstColumnOnlyAutoresizingStyle;
    self.appTable.tableColumns.firstObject.resizingMask = NSTableColumnAutoresizingMask;
    NSScrollView *appScroll = Wrap(self.appTable);
    appScroll.drawsBackground = NO;
    appScroll.hasHorizontalScroller = NO;

    NSView *left = [NSView new];
    for (NSView *v in @[self.search, appScroll]) { v.translatesAutoresizingMaskIntoConstraints = NO; [left addSubview:v]; }
    [NSLayoutConstraint activateConstraints:@[
        [self.search.topAnchor constraintEqualToAnchor:left.safeAreaLayoutGuide.topAnchor constant:6],
        [self.search.leadingAnchor constraintEqualToAnchor:left.leadingAnchor constant:10],
        [self.search.trailingAnchor constraintEqualToAnchor:left.trailingAnchor constant:-10],
        [appScroll.topAnchor constraintEqualToAnchor:self.search.bottomAnchor constant:8],
        [appScroll.leadingAnchor constraintEqualToAnchor:left.leadingAnchor],
        [appScroll.trailingAnchor constraintEqualToAnchor:left.trailingAnchor],
        [appScroll.bottomAnchor constraintEqualToAnchor:left.bottomAnchor],
    ]];

    // Content: inset, rounded associations table
    self.assocTable = MakeTable(@[@[@"kind", @"Kind", @80],
                                  @[@"identifier", @"Type / Scheme", @220],
                                  @[@"extensions", @"Extensions", @120],
                                  @[@"role", @"Role", @70],
                                  @[@"rank", @"Rank", @80],
                                  @[@"defaultApp", @"Current Default", @180]], self);
    self.assocTable.allowsMultipleSelection = YES;
    self.assocTable.style = NSTableViewStyleInset;
    self.assocTable.usesAlternatingRowBackgroundColors = NO;
    self.assocTable.rowHeight = 26;
    self.assocTable.target = self;
    self.assocTable.doubleAction = @selector(assocDoubleClicked:);
    self.assocTable.columnAutoresizingStyle = NSTableViewUniformColumnAutoresizingStyle;
    NSScrollView *assocScroll = Wrap(self.assocTable);
    assocScroll.hasHorizontalScroller = NO;

    NSView *right = [NSView new];
    assocScroll.translatesAutoresizingMaskIntoConstraints = NO;
    [right addSubview:assocScroll];
    [NSLayoutConstraint activateConstraints:@[
        [assocScroll.topAnchor constraintEqualToAnchor:right.topAnchor],
        [assocScroll.leadingAnchor constraintEqualToAnchor:right.leadingAnchor],
        [assocScroll.trailingAnchor constraintEqualToAnchor:right.trailingAnchor],
        [assocScroll.bottomAnchor constraintEqualToAnchor:right.bottomAnchor],
    ]];

    NSViewController *leftVC = [NSViewController new];
    leftVC.view = left;
    NSViewController *rightVC = [NSViewController new];
    rightVC.view = right;
    NSSplitViewItem *sidebar = [NSSplitViewItem sidebarWithViewController:leftVC];
    sidebar.minimumThickness = 220;
    sidebar.maximumThickness = 400;
    sidebar.canCollapse = YES;
    NSSplitViewItem *content = [NSSplitViewItem splitViewItemWithViewController:rightVC];
    content.minimumThickness = 420;
    NSSplitViewController *svc = [NSSplitViewController new];
    svc.splitView.autosaveName = @"MainSplit";
    [svc addSplitViewItem:sidebar];
    [svc addSplitViewItem:content];
    self.window.contentViewController = svc;

    NSToolbar *tb = [[NSToolbar alloc] initWithIdentifier:@"MainToolbar"];
    tb.delegate = self;
    tb.displayMode = NSToolbarDisplayModeIconOnly;
    self.window.toolbar = tb;
    self.window.toolbarStyle = NSWindowToolbarStyleUnified;
    [self syncTitle:nil];

    [self.window setContentSize:NSMakeSize(1100, 680)];
    [self.window center];
    self.window.frameAutosaveName = @"MainWindow";
    if (!self.launchedWithFiles) [self showMainWindow];

    [self refreshApps:nil];
}

- (void)showMainWindow {
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)buildMenu {
    NSMenu *bar = [NSMenu new];
    NSMenuItem *appItem = [NSMenuItem new];
    [bar addItem:appItem];
    NSMenu *appMenu = [NSMenu new];
    [appMenu addItemWithTitle:@"About Open With" action:@selector(showAbout:) keyEquivalent:@""].target = self;
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"Quit Open With" action:@selector(terminate:) keyEquivalent:@"q"];
    appItem.submenu = appMenu;

    NSMenuItem *editItem = [NSMenuItem new];
    [bar addItem:editItem];
    NSMenu *edit = [[NSMenu alloc] initWithTitle:@"Edit"];
    [edit addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];
    [edit addItemWithTitle:@"Find" action:@selector(focusSearch:) keyEquivalent:@"f"];
    editItem.submenu = edit;

    NSMenuItem *viewItem = [NSMenuItem new];
    [bar addItem:viewItem];
    NSMenu *view = [[NSMenu alloc] initWithTitle:@"View"];
    [view addItemWithTitle:@"Refresh" action:@selector(refreshApps:) keyEquivalent:@"r"].target = self;
    viewItem.submenu = view;

    // Same actions as the toolbar buttons; titles and enabled state follow them (validateMenuItem:)
    NSMenuItem *actionsItem = [NSMenuItem new];
    [bar addItem:actionsItem];
    NSMenu *actions = [[NSMenu alloc] initWithTitle:@"Actions"];
    [actions addItemWithTitle:@"Assign to App" action:@selector(assignToCurrent:) keyEquivalent:@"d"].target = self;
    NSMenuItem *transferMenu = [actions addItemWithTitle:@"Assign to…" action:@selector(transfer:) keyEquivalent:@"\r"];
    transferMenu.target = self;
    transferMenu.keyEquivalentModifierMask = 0;  // plain Return
    actionsItem.submenu = actions;
    NSApp.mainMenu = bar;
}

// Modal About panel: app icon, name, version, short description.
- (void)showAbout:(id)sender {
    NSDictionary *info = NSBundle.mainBundle.infoDictionary;
    NSAlert *alert = [NSAlert new];
    alert.icon = NSApp.applicationIconImage;
    alert.messageText = @"Open With";
    alert.informativeText = [NSString stringWithFormat:
        @"Version %@ (%@)\n\nBrowse installed apps and the file types and URL schemes they claim, "
        @"and change the default app for each. Open a file with this app to choose "
        @"which app opens it and make that app the default for its extension.",
        info[@"CFBundleShortVersionString"] ?: @"?", info[@"CFBundleVersion"] ?: @"?"];
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
}

- (BOOL)validateMenuItem:(NSMenuItem *)item {
    if (item.action == @selector(refreshApps:)) return !self.refreshing;
    if (item.action == @selector(assignToCurrent:)) {
        item.title = [NSString stringWithFormat:@"Assign to %@", self.selectedApp.name ?: @"App"];
        return !self.refreshing && [self assignableSelection].count > 0;
    }
    if (item.action == @selector(transfer:)) return !self.refreshing && !self.window.attachedSheet && [self transferableSelection].count > 0;
    return YES;
}

- (void)focusSearch:(id)sender { [self.window makeFirstResponder:self.search]; }

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)a { return YES; }

// Row 0 of the app list is "All Apps" (the overview); app rows start at 1.
- (AppEntry *)selectedApp {
    NSInteger row = self.appTable.selectedRow - 1;
    return row >= 0 && row < (NSInteger)self.apps.count ? self.apps[row] : nil;
}

- (void)selectAppAtIndex:(NSUInteger)i {
    NSInteger row = i == NSNotFound ? 0 : (NSInteger)i + 1;
    [self.appTable selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
    [self.appTable scrollRowToVisible:row];
}

- (void)refreshApps:(id)sender {
    if (self.refreshing) return;
    self.refreshing = YES;
    [self updateTransferButton];
    NSString *selectedBundleID = self.selectedApp.bundleID;

    if (self.allApps) self.window.subtitle = @"Refreshing applications…";
    [self syncTitle:nil];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray<AppEntry *> *apps = ScanApps();
        NSArray<Assoc *> *overview = BuildOverview(apps);
        dispatch_async(dispatch_get_main_queue(), ^{
            self.allApps = apps;
            self.overview = overview;
            [self.assocTable deselectAll:nil];  // old row indexes are meaningless for the new list
            [self applyFilter];
            NSUInteger row = selectedBundleID ? [self.apps indexOfObjectPassingTest:
                ^BOOL(AppEntry *entry, NSUInteger idx, BOOL *stop) {
                    return [entry.bundleID isEqualToString:selectedBundleID];
                }] : NSNotFound;
            [self selectAppAtIndex:row];
            [self reloadAssocs];
            self.refreshing = NO;
            [self updateTransferButton];
        });
    });
}

- (void)controlTextDidChange:(NSNotification *)n { [self applyFilter]; }

- (void)applyFilter {
    AppEntry *keep = self.selectedApp;
    self.apps = FilterApps(self.allApps, self.search.stringValue);
    NSArray<NSString *> *exts = [self extFilter];
    UTType *ut = exts.count == 1 ? [UTType typeWithFilenameExtension:exts[0]] : nil;
    self.extDefaultURL = ut ? [[NSWorkspace sharedWorkspace] URLForApplicationToOpenContentType:ut].URLByStandardizingPath : nil;
    [self.appTable reloadData];
    [self.appTable sizeLastColumnToFit];
    NSUInteger i = keep ? [self.apps indexOfObjectIdenticalTo:keep] : NSNotFound;
    [self selectAppAtIndex:i];
    [self reloadAssocs];  // re-apply the ".ext" filter to the right list
}

// The ".ext" filter terms, lowercased without the dot, or nil when not filtering by extension.
- (NSArray<NSString *> *)extFilter {
    return ExtTerms(self.search.stringValue);
}

// Copy selected association rows as tab-separated text.
- (void)copy:(id)sender {
    NSArray<Assoc *> *sel = [self selectedAssocs];
    if (!sel.count) return;
    NSMutableString *s = [NSMutableString string];
    for (Assoc *a in sel) {
        [s appendFormat:@"%@\t%@\t%@\t%@\t%@\t%@\n", a.kind, a.identifier, a.extensions, a.role, a.rank, a.defaultApp];
    }
    [[NSPasteboard generalPasteboard] clearContents];
    [[NSPasteboard generalPasteboard] setString:s forType:NSPasteboardTypeString];
}

@end
