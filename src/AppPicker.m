#import "AppPicker.h"

@implementation AppPicker

- (instancetype)initWithApps:(NSArray<AppEntry *> *)apps selectBundleID:(NSString *)bid {
    if (!(self = [super init])) return nil;
    _all = _shown = apps;

    _search = [NSSearchField new];
    _search.placeholderString = @"Filter apps";
    _search.controlSize = NSControlSizeLarge;
    _search.font = [NSFont systemFontOfSize:[NSFont systemFontSizeForControlSize:NSControlSizeLarge]];
    _search.delegate = self;

    _table = [NSTableView new];
    NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"name"];
    col.width = 240;
    col.resizingMask = NSTableColumnAutoresizingMask;
    [_table addTableColumn:col];
    NSTableColumn *kind = [[NSTableColumn alloc] initWithIdentifier:@"kind"];
    kind.width = 76;
    kind.resizingMask = NSTableColumnNoResizing;
    kind.hidden = YES;
    [_table addTableColumn:kind];
    _table.columnAutoresizingStyle = NSTableViewFirstColumnOnlyAutoresizingStyle;
    _table.headerView = nil;
    _table.rowHeight = 22;
    _table.style = NSTableViewStyleFullWidth;
    _table.usesAlternatingRowBackgroundColors = NO;
    _table.backgroundColor = NSColor.textBackgroundColor;  // white in light mode, dark in dark mode
    _table.dataSource = self;
    _table.delegate = self;
    _table.target = self;
    _table.doubleAction = @selector(doubleClicked:);

    NSScrollView *scroll = [NSScrollView new];
    scroll.documentView = _table;
    scroll.hasVerticalScroller = YES;
    scroll.borderType = NSBezelBorder;

    _view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 340, 340)];
    for (NSView *v in @[_search, scroll]) { v.translatesAutoresizingMaskIntoConstraints = NO; [_view addSubview:v]; }
    [NSLayoutConstraint activateConstraints:@[
        [_search.topAnchor constraintEqualToAnchor:_view.topAnchor],
        [_search.leadingAnchor constraintEqualToAnchor:_view.leadingAnchor],
        [_search.trailingAnchor constraintEqualToAnchor:_view.trailingAnchor],
        [scroll.topAnchor constraintEqualToAnchor:_search.bottomAnchor constant:6],
        [scroll.leadingAnchor constraintEqualToAnchor:_view.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:_view.trailingAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:_view.bottomAnchor],
    ]];

    [_table reloadData];
    [self selectBundleID:bid];
    return self;
}

- (void)selectBundleID:(NSString *)bid {
    NSUInteger i = bid ? [_shown indexOfObjectPassingTest:^BOOL(AppEntry *e, NSUInteger idx, BOOL *stop) {
        return [e.bundleID isEqualToString:bid];
    }] : NSNotFound;
    if (i == NSNotFound) i = 0;
    if (i < _shown.count) {
        [_table selectRowIndexes:[NSIndexSet indexSetWithIndex:i] byExtendingSelection:NO];
        [_table scrollRowToVisible:i];
    }
}

- (AppEntry *)selected {
    NSInteger r = _table.selectedRow;
    return r >= 0 && r < (NSInteger)_shown.count ? _shown[r] : nil;
}

- (void)doubleClicked:(id)sender {
    if (_table.clickedRow >= 0 && self.onDoubleClick) self.onDoubleClick();
}

- (void)controlTextDidChange:(NSNotification *)n { [self refilter:nil]; }

- (void)refilter:(id)sender {
    NSString *keep = self.selected.bundleID;
    _shown = FilterApps(_all, _search.stringValue);
    if (_include)
        _shown = [_shown filteredArrayUsingPredicate:
            [NSPredicate predicateWithBlock:^BOOL(AppEntry *e, id b) { return self.include(e); }]];
    [_table reloadData];
    [self selectBundleID:keep];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)t { return _shown.count; }

- (void)setDetail:(NSString *(^)(AppEntry *))detail {
    _detail = [detail copy];
    [_table tableColumnWithIdentifier:@"kind"].hidden = !detail;
    [_table reloadData];
}

- (NSView *)tableView:(NSTableView *)t viewForTableColumn:(NSTableColumn *)col row:(NSInteger)row {
    if ([col.identifier isEqual:@"kind"]) {
        NSTableCellView *cell = [t makeViewWithIdentifier:@"kind" owner:self];
        if (!cell) {
            cell = [NSTableCellView new];
            cell.identifier = @"kind";
            NSTextField *tf = [NSTextField labelWithString:@""];
            tf.textColor = NSColor.secondaryLabelColor;
            tf.lineBreakMode = NSLineBreakByTruncatingTail;
            tf.translatesAutoresizingMaskIntoConstraints = NO;
            [cell addSubview:tf];
            cell.textField = tf;
            [NSLayoutConstraint activateConstraints:@[
                [tf.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:2],
                [tf.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-4],
                [tf.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
            ]];
        }
        cell.textField.stringValue = _detail ? _detail(_shown[row]) ?: @"" : @"";
        return cell;
    }
    NSTableCellView *cell = [t makeViewWithIdentifier:@"pick" owner:self];
    if (!cell) {
        cell = [NSTableCellView new];
        cell.identifier = @"pick";
        NSImageView *iv = [NSImageView new];
        NSTextField *tf = [NSTextField labelWithString:@""];
        tf.lineBreakMode = NSLineBreakByTruncatingTail;
        for (NSView *v in @[iv, tf]) { v.translatesAutoresizingMaskIntoConstraints = NO; [cell addSubview:v]; }
        cell.imageView = iv;
        cell.textField = tf;
        [NSLayoutConstraint activateConstraints:@[
            [iv.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:4],
            [iv.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
            [iv.widthAnchor constraintEqualToConstant:16],
            [iv.heightAnchor constraintEqualToConstant:16],
            [tf.leadingAnchor constraintEqualToAnchor:iv.trailingAnchor constant:6],
            [tf.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-2],
            [tf.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
        ]];
    }
    AppEntry *e = _shown[row];
    if (!e.icon) e.icon = [[NSWorkspace sharedWorkspace] iconForFile:e.url.path];
    cell.imageView.image = e.icon;
    cell.textField.stringValue = e.name;
    cell.toolTip = [NSString stringWithFormat:@"%@\n%@", e.bundleID, e.url.path];
    return cell;
}

@end
