#import "Controller.h"

@implementation Controller (Table)

- (NSInteger)numberOfRowsInTableView:(NSTableView *)t {
    return t == self.appTable ? self.apps.count + 1 : self.assocs.count;
}

- (NSView *)tableView:(NSTableView *)t viewForTableColumn:(NSTableColumn *)col row:(NSInteger)row {
    NSTableCellView *cell = [t makeViewWithIdentifier:col.identifier owner:self];
    if (!cell) {
        cell = [NSTableCellView new];
        cell.identifier = col.identifier;
        NSTextField *tf = [NSTextField labelWithString:@""];
        tf.lineBreakMode = NSLineBreakByTruncatingTail;
        tf.translatesAutoresizingMaskIntoConstraints = NO;
        [cell addSubview:tf];
        cell.textField = tf;
        NSLayoutXAxisAnchor *lead = cell.leadingAnchor;
        CGFloat pad = 2;
        if (t == self.appTable) {
            NSImageView *iv = [NSImageView new];
            iv.translatesAutoresizingMaskIntoConstraints = NO;
            [cell addSubview:iv];
            cell.imageView = iv;
            [NSLayoutConstraint activateConstraints:@[
                [iv.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:4],
                [iv.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
                [iv.widthAnchor constraintEqualToConstant:22],
                [iv.heightAnchor constraintEqualToConstant:22],
            ]];
            lead = iv.trailingAnchor;
            pad = 6;
        }
        [NSLayoutConstraint activateConstraints:@[
            [tf.leadingAnchor constraintEqualToAnchor:lead constant:pad],
            [tf.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-2],
            [tf.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
        ]];
    }

    if (t == self.appTable && row == 0) {
        // a bit larger than the default symbol size
        cell.imageView.image = [[NSImage imageWithSystemSymbolName:@"square.grid.2x2" accessibilityDescription:nil]
            imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPointSize:16 weight:NSFontWeightRegular]];
        cell.textField.stringValue = @"All Apps";
        cell.textField.font = [NSFont systemFontOfSize:0];
        cell.toolTip = @"Every extension claimed by any app";
    } else if (t == self.appTable) {
        AppEntry *e = self.apps[row - 1];
        if (!e.icon) e.icon = [[NSWorkspace sharedWorkspace] iconForFile:e.url.path];
        cell.imageView.image = e.icon;
        cell.textField.stringValue = e.name;
        BOOL dflt = self.extDefaultURL && [e.url.URLByStandardizingPath isEqual:self.extDefaultURL];
        cell.textField.font = dflt ? [NSFont boldSystemFontOfSize:0] : [NSFont systemFontOfSize:0];
        cell.toolTip = [NSString stringWithFormat:@"%@\n%@", e.bundleID, e.url.path];
    } else {
        Assoc *a = self.assocs[row];
        NSString *v = [a valueForKey:col.identifier] ?: @"";
        cell.textField.stringValue = v;
        BOOL dflt = [col.identifier isEqual:@"defaultApp"] && a.isDefault;
        cell.textField.textColor = dflt ? [NSColor systemGreenColor]
                                 : IsProtectedAssoc(a) ? [NSColor tertiaryLabelColor] : [NSColor labelColor];
        cell.textField.font = dflt ? [NSFont boldSystemFontOfSize:0] : [NSFont systemFontOfSize:0];
        cell.toolTip = IsProtectedAssoc(a) ? @"Protected: reassigning this could break Finder or launching apps" : v;
    }
    return cell;
}

- (void)tableViewSelectionDidChange:(NSNotification *)n {
    if (n.object == self.appTable) [self reloadAssocs];
    else [self updateTransferButton];
}

- (void)reloadAssocs {
    AppEntry *e = self.selectedApp;
    if (!e) {
        [self setOverviewHeaders:YES];
        NSString *q = self.search.stringValue;
        NSArray<NSString *> *exts = [self extFilter];
        unichar last = q.length ? [q characterAtIndex:q.length - 1] : 0;
        BOOL termDone = last == ',' || [[NSCharacterSet whitespaceCharacterSet] characterIsMember:last];
        NSArray *rows = self.overview ?: @[];
        if (q.length)
            rows = [rows filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(Assoc *a, id b) {
                if (exts) {
                    // A finished term (followed by a space/comma) is exact: ".c " is just .c; the term
                    // still being typed is a prefix: ".c" also shows .cpp, .cs, ...
                    NSString *ident = a.identifier.lowercaseString;
                    for (NSUInteger i = 0; i < exts.count; i++) {
                        NSString *x = [@"." stringByAppendingString:exts[i]];
                        if (i + 1 < exts.count || termDone ? [ident isEqualToString:x] : [ident hasPrefix:x]) return YES;
                    }
                    return NO;
                }
                NSString *scheme = SchemeTerm(q);
                if (scheme) return [a.scheme isEqualToString:scheme];
                return [a.identifier localizedCaseInsensitiveContainsString:q] ||
                       [a.extensions localizedCaseInsensitiveContainsString:q] ||
                       [a.defaultApp localizedCaseInsensitiveContainsString:q];
            }]];
        if (self.assocTable.sortDescriptors.count)
            rows = [rows sortedArrayUsingDescriptors:self.assocTable.sortDescriptors];
        self.assocs = rows;
        [self.assocTable reloadData];
        [self updateTransferButton];
        NSUInteger schemes = [[rows filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"scheme != nil"]] count];
        self.window.title = @"All Extensions";
        self.window.subtitle = [NSString stringWithFormat:@"%lu extensions and %lu URL schemes claimed by %lu applications",
                                (unsigned long)(rows.count - schemes), (unsigned long)schemes, (unsigned long)self.apps.count];
        [self syncTitle:nil];
        return;
    }
    [self setOverviewHeaders:NO];
    if (!e.assocs) e.assocs = LoadAssocs(e);
    self.assocs = e.assocs;
    NSArray<NSString *> *exts = [self extFilter];
    if (exts) {
        NSMutableArray *matched = [NSMutableArray array];
        for (NSString *ext in exts) {
            NSArray *direct = [self.assocs filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(Assoc *a, id b) {
                for (NSString *x in [a.extensions componentsSeparatedByString:@", "])
                    if ([x.lowercaseString isEqualToString:ext]) return YES;
                return NO;
            }]];
            if (!direct.count) direct = [self inheritedAssocsForExt:ext app:e];
            for (Assoc *a in direct)
                if ([matched indexOfObjectIdenticalTo:a] == NSNotFound) [matched addObject:a];
        }
        self.assocs = matched;
    }
    if (self.assocTable.sortDescriptors.count)
        self.assocs = [self.assocs sortedArrayUsingDescriptors:self.assocTable.sortDescriptors];
    NSUInteger defaults = [[self.assocs filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"isDefault == YES"]] count];
    NSString *scope = exts ? [NSString stringWithFormat:@" matching .%@", [exts componentsJoinedByString:@", ."]] : @"";
    self.window.title = e.name;
    self.window.subtitle = [NSString stringWithFormat:@"%@ · %lu associations%@ · default for %lu",
                            e.bundleID, (unsigned long)self.assocs.count, scope, (unsigned long)defaults];
    [self syncTitle:e.icon ?: [[NSWorkspace sharedWorkspace] iconForFile:e.url.path]];
    [self.assocTable reloadData];
    [self updateTransferButton];
}

// The overview reuses the association columns with different meanings.
- (void)setOverviewHeaders:(BOOL)overview {
    NSDictionary *titles = overview
        ? @{@"identifier": @"Extension", @"extensions": @"UTI", @"role": @"Claimed by"}
        : @{@"identifier": @"Type / Scheme", @"extensions": @"Extensions", @"role": @"Role"};
    for (NSString *ident in titles) [self.assocTable tableColumnWithIdentifier:ident].title = titles[ident];
    [self.assocTable tableColumnWithIdentifier:@"rank"].hidden = overview;
}

- (void)rebuildOverview {
    NSArray *apps = self.allApps;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray *overview = BuildOverview(apps);
        dispatch_async(dispatch_get_main_queue(), ^{
            self.overview = overview;
            if (!self.selectedApp) [self reloadAssocs];
        });
    });
}

// App claims a parent type of ".ext" (e.g. public.text for .md): synthesize one row for the extension.
- (NSArray<Assoc *> *)inheritedAssocsForExt:(NSString *)ext app:(AppEntry *)app {
    UTType *t = [UTType typeWithFilenameExtension:ext];
    NSString *parentID = ConformingUTI(app.utis, t);
    if (!parentID) return @[];
    Assoc *parent = nil;
    for (Assoc *a in app.assocs) if ([a.identifier isEqualToString:parentID]) { parent = a; break; }
    Assoc *a = [Assoc new];
    a.kind = @"Extension";
    a.identifier = [NSString stringWithFormat:@".%@ (via %@)", ext, parentID];
    a.extensions = ext;
    a.role = parent.role ?: @"";
    a.rank = parent.rank ?: @"";
    a.type = t;
    NSString *bid = nil;
    a.defaultApp = DefaultAppNameForURL([[NSWorkspace sharedWorkspace] URLForApplicationToOpenContentType:t], &bid);
    a.isDefault = bid && [bid isEqualToString:app.bundleID];
    return @[a];
}

- (void)tableView:(NSTableView *)t sortDescriptorsDidChange:(NSArray *)old {
    if (t != self.assocTable) return;
    self.assocs = [self.assocs sortedArrayUsingDescriptors:t.sortDescriptors];
    [t reloadData];
}

@end
