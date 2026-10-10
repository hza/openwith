#import "Controller.h"

static NSString *const kLastTargetKey = @"LastTransferTarget";
static NSString *const kShowGenericKey = @"ShowGenericHandlers";

@implementation Controller (Assign)

// Selected association rows, ignoring indexes left over from a previous (longer) list.
- (NSArray<Assoc *> *)selectedAssocs {
    NSMutableArray *sel = [NSMutableArray array];
    NSArray *assocs = self.assocs;
    [self.assocTable.selectedRowIndexes enumerateIndexesUsingBlock:^(NSUInteger i, BOOL *stop) {
        if (i < assocs.count) [sel addObject:assocs[i]]; else *stop = YES;
    }];
    return sel;
}

- (NSArray<Assoc *> *)transferableSelection {
    NSArray *sel = [self selectedAssocs];
    return [sel filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(Assoc *a, id b) {
        return a.type || a.scheme;
    }]];
}

// Selected associations the current app isn't already the default for.
- (NSArray<Assoc *> *)assignableSelection {
    if (!self.selectedApp) return @[];
    return [[self transferableSelection] filteredArrayUsingPredicate:
        [NSPredicate predicateWithFormat:@"isDefault == NO"]];
}

- (void)assignToCurrent:(id)sender {
    NSArray<Assoc *> *items = [self assignableSelection];
    if (!items.count) { NSBeep(); return; }
    [self assign:items toApp:self.selectedApp];  // assignableSelection checked it
}

- (void)assocDoubleClicked:(id)sender {
    if (self.assocTable.clickedRow >= 0) [self transfer:sender];
}

- (void)transfer:(id)sender {
    NSArray<Assoc *> *items = [self transferableSelection];
    if (!items.count) { NSBeep(); return; }
    AppEntry *source = self.selectedApp;

    NSArray<AppEntry *> *targets = [self.allApps filteredArrayUsingPredicate:
        [NSPredicate predicateWithBlock:^BOOL(AppEntry *e, id b) { return e != source; }]];
    if (!targets.count) return;

    AppPicker *picker = [[AppPicker alloc] initWithApps:targets selectBundleID:nil];
    // Single association: pre-filter to apps claiming its extension
    if (items.count == 1) {
        Assoc *it = items[0];
        NSString *ext = [it.kind isEqual:@"Extension"] && [it.identifier hasPrefix:@"."]
            ? [[it.identifier substringFromIndex:1] componentsSeparatedByString:@" "].firstObject
            : [it.extensions componentsSeparatedByString:@", "].firstObject;
        if (!ext.length) ext = it.type.preferredFilenameExtension;
        if (ext.length) {
            picker.search.stringValue = [@"." stringByAppendingString:ext];
            [picker controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification object:picker.search]];
        }
    }
    // Preselect the current default (if all selected rows share one), else the last used target.
    NSString *cur = SharedDefaultBundleID(items);
    // Second column: how each app relates to the selection (first row's type when several are selected).
    Assoc *first = items[0];
    picker.detail = ^NSString *(AppEntry *e) { return ClaimKind(e, first, cur); };
    // Apps that only claim a parent UTI (e.g. public.text) are hidden unless the user opts in.
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSButton *showGeneric = [NSButton checkboxWithTitle:@"Show generic handlers (⌘G)" target:picker action:@selector(refilter:)];
    showGeneric.keyEquivalent = @"g";
    showGeneric.keyEquivalentModifierMask = NSEventModifierFlagCommand;
    showGeneric.toolTip = @"Also list apps that only claim a parent type, e.g. public.text (⌘G)";
    showGeneric.state = [ud boolForKey:kShowGenericKey] ? NSControlStateValueOn : NSControlStateValueOff;
    __weak NSButton *weakShow = showGeneric;
    picker.include = ^BOOL(AppEntry *e) {
        BOOL show = weakShow.state == NSControlStateValueOn;
        [ud setBool:show forKey:kShowGenericKey];
        return show || ![ClaimKind(e, first, cur) isEqual:@"Generic"];
    };
    [picker refilter:nil];
    NSString *last = [[NSUserDefaults standardUserDefaults] stringForKey:kLastTargetKey];
    for (NSString *bid in @[cur ?: @"", last ?: @""]) {
        if ([picker.shown indexOfObjectPassingTest:^BOOL(AppEntry *e, NSUInteger i, BOOL *s) {
                return [e.bundleID isEqualToString:bid]; }] != NSNotFound) {
            [picker selectBundleID:bid];
            break;
        }
    }

    // Regular titled window (title bar + close button), run app-modal.
    NSPanel *panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 380, 460)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
        backing:NSBackingStoreBuffered defer:NO];
    panel.title = [NSString stringWithFormat:@"Assign %lu association%@ to",
                   (unsigned long)items.count, items.count == 1 ? @"" : @"s"];
    panel.releasedWhenClosed = NO;

    NSTextField *info = [NSTextField wrappingLabelWithString:
        @"The chosen app becomes the default handler for the selected types and URL schemes."];
    info.textColor = NSColor.secondaryLabelColor;
    NSButton *cancel = [NSButton buttonWithTitle:@"Cancel" target:NSApp action:@selector(abortModal)];
    cancel.keyEquivalent = @"\e";
    NSButton *ok = [NSButton buttonWithTitle:@"Assign" target:NSApp action:@selector(stopModal)];
    ok.keyEquivalent = @"\r";
    picker.onDoubleClick = ^{ [NSApp stopModal]; };

    NSView *content = panel.contentView;
    for (NSView *v in @[info, picker.view, showGeneric, cancel, ok]) {
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
        [ok.topAnchor constraintEqualToAnchor:picker.view.bottomAnchor constant:16],
        [ok.trailingAnchor constraintEqualToAnchor:info.trailingAnchor],
        [ok.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-16],
        [cancel.centerYAnchor constraintEqualToAnchor:ok.centerYAnchor],
        [cancel.trailingAnchor constraintEqualToAnchor:ok.leadingAnchor constant:-10],
        [showGeneric.centerYAnchor constraintEqualToAnchor:ok.centerYAnchor],
        [showGeneric.leadingAnchor constraintEqualToAnchor:info.leadingAnchor],
    ]];

    // Close button ends the modal session as a cancel.
    id obs = [[NSNotificationCenter defaultCenter] addObserverForName:NSWindowWillCloseNotification
        object:panel queue:nil usingBlock:^(NSNotification *n) { [NSApp abortModal]; }];
    [panel center];
    [panel makeFirstResponder:picker.table];
    NSModalResponse r = [NSApp runModalForWindow:panel];
    [[NSNotificationCenter defaultCenter] removeObserver:obs];
    [panel orderOut:nil];

    AppEntry *target = picker.selected;
    if (r != NSModalResponseStop || !target) { [self focusAssocList]; return; }
    [[NSUserDefaults standardUserDefaults] setObject:target.bundleID forKey:kLastTargetKey];
    [self assign:items toApp:target];
}

// After a toolbar action or the modal picker: make the main window key again with the list focused.
// Deferred so it runs after the modal session / button tracking has fully unwound.
- (void)focusAssocList {
    [self focusAssocListSelecting:nil];
}

// The reload replaces the row objects, so reselect the given ones by identifier.
- (void)focusAssocListSelecting:(NSArray<Assoc *> *)items {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.window makeKeyAndOrderFront:nil];
        [self.window makeFirstResponder:self.assocTable];
        if (!items.count) return;
        NSSet *ids = [NSSet setWithArray:[items valueForKey:@"identifier"]];
        NSIndexSet *rows = [self.assocs indexesOfObjectsPassingTest:^BOOL(Assoc *a, NSUInteger i, BOOL *stop) {
            return [ids containsObject:a.identifier];
        }];
        if (!rows.count) return;
        [self.assocTable selectRowIndexes:rows byExtendingSelection:NO];
        [self.assocTable scrollRowToVisible:rows.firstIndex];
    });
}

- (void)assign:(NSArray<Assoc *> *)items toApp:(AppEntry *)target {
    NSWorkspace *ws = [NSWorkspace sharedWorkspace];
    dispatch_group_t group = dispatch_group_create();
    NSMutableArray<NSString *> *errors = [NSMutableArray array];
    for (Assoc *a in items) {
        dispatch_group_enter(group);
        void (^done)(NSError *) = ^(NSError *err) {
            if (err) @synchronized (errors) {
                [errors addObject:[NSString stringWithFormat:@"%@: %@", a.identifier, err.localizedDescription]];
            }
            dispatch_group_leave(group);
        };
        if (a.scheme)
            [ws setDefaultApplicationAtURL:target.url toOpenURLsWithScheme:a.scheme completionHandler:done];
        else
            [ws setDefaultApplicationAtURL:target.url toOpenContentType:a.type completionHandler:done];
    }
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        for (AppEntry *e in self.allApps) e.assocs = nil;  // defaults changed: drop cached state
        [self reloadAssocs];
        [self rebuildOverview];
        [self focusAssocListSelecting:items];
        if (errors.count) {
            NSAlert *al = [NSAlert new];
            al.messageText = [NSString stringWithFormat:@"%lu of %lu could not be assigned to %@",
                              (unsigned long)errors.count, (unsigned long)items.count, target.name];
            al.informativeText = [errors componentsJoinedByString:@"\n"];
            [al beginSheetModalForWindow:self.window completionHandler:nil];
        }
    });
}

@end
