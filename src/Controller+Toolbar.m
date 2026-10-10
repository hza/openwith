#import "Controller.h"

static NSToolbarItemIdentifier const kTransferItem = @"transfer";
static NSToolbarItemIdentifier const kTitleItem = @"title";
static NSToolbarItemIdentifier const kAssignItem = @"assign";

@implementation Controller (Toolbar)

- (NSArray<NSToolbarItemIdentifier> *)toolbarDefaultItemIdentifiers:(NSToolbar *)tb {
    return @[NSToolbarToggleSidebarItemIdentifier, NSToolbarSidebarTrackingSeparatorItemIdentifier,
             kTitleItem, NSToolbarFlexibleSpaceItemIdentifier, kAssignItem, kTransferItem];
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarAllowedItemIdentifiers:(NSToolbar *)tb {
    return @[kAssignItem, kTransferItem, kTitleItem, NSToolbarToggleSidebarItemIdentifier, NSToolbarSidebarTrackingSeparatorItemIdentifier,
             NSToolbarFlexibleSpaceItemIdentifier, NSToolbarSpaceItemIdentifier];
}

- (NSToolbarItem *)toolbar:(NSToolbar *)tb itemForItemIdentifier:(NSToolbarItemIdentifier)ident
 willBeInsertedIntoToolbar:(BOOL)flag {
    if ([ident isEqual:kTitleItem]) return [self makeTitleItem];
    if ([ident isEqual:kAssignItem]) {
        self.assignItem = [self flatItem:ident title:@"Assign to App" width:140 action:@selector(assignToCurrent:)
            toolTip:@"Make the selected app the default handler for the selected associations"];
        self.assignButton = (NSButton *)self.assignItem.view;
        self.assignButton.lineBreakMode = NSLineBreakByTruncatingMiddle;
        [self syncAssignTitle];
        return self.assignItem;
    }
    if (![ident isEqual:kTransferItem]) return nil;
    self.transferItem = [self flatItem:ident title:@"Assign to…  ↩" width:120 action:@selector(transfer:)
        toolTip:@"Make another app the default handler for the selected associations (Return)"];
    self.transferButton = (NSButton *)self.transferItem.view;
    return self.transferItem;
}

// Flat toolbar button: no bezel, background drawn by the layer (see -setFlatButton:enabled:).
- (NSToolbarItem *)flatItem:(NSToolbarItemIdentifier)ident title:(NSString *)title width:(CGFloat)w
                     action:(SEL)action toolTip:(NSString *)tip {
    NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:ident];
    item.label = title;
    item.paletteLabel = title;
    item.toolTip = tip;
    NSButton *b = [NSButton buttonWithTitle:title target:self action:action];
    b.bordered = NO;
    b.refusesFirstResponder = YES;  // clicking it must not take focus from the list
    b.wantsLayer = YES;
    b.layer.cornerRadius = 6;
    b.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
    b.toolTip = tip;
    b.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [b.widthAnchor constraintEqualToConstant:w],
        [b.heightAnchor constraintEqualToConstant:32],
    ]];
    [self setFlatButton:b enabled:NO];  // enabled by updateTransferButton once apps are loaded
    item.view = b;
    item.autovalidates = NO;
    return item;
}

- (void)setFlatButton:(NSButton *)b enabled:(BOOL)on {
    b.enabled = on;
    b.layer.backgroundColor = (on ? NSColor.systemBlueColor : [NSColor colorWithWhite:0.5 alpha:0.12]).CGColor;
    b.contentTintColor = on ? [NSColor whiteColor] : [NSColor tertiaryLabelColor];
}

// Toolbar title: app icon, then title and subtitle (replaces the hidden system title).
- (NSToolbarItem *)makeTitleItem {
    NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:kTitleItem];
    self.titleIcon = [NSImageView new];
    self.titleIcon.imageScaling = NSImageScaleProportionallyUpOrDown;
    self.titleIcon.translatesAutoresizingMaskIntoConstraints = NO;
    [self.titleIcon.widthAnchor constraintEqualToConstant:28].active = YES;
    [self.titleIcon.heightAnchor constraintEqualToConstant:28].active = YES;
    self.titleLabel = [NSTextField labelWithString:@""];
    self.titleLabel.font = [NSFont boldSystemFontOfSize:13];
    self.subtitleLabel = [NSTextField labelWithString:@""];
    self.subtitleLabel.font = [NSFont systemFontOfSize:11];
    self.subtitleLabel.textColor = [NSColor secondaryLabelColor];
    for (NSTextField *f in @[self.titleLabel, self.subtitleLabel]) {
        f.lineBreakMode = NSLineBreakByTruncatingTail;
        [f setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
        // Don't let the toolbar squeeze the two lines into each other
        [f setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationVertical];
    }
    NSStackView *text = [NSStackView stackViewWithViews:@[self.titleLabel, self.subtitleLabel]];
    text.orientation = NSUserInterfaceLayoutOrientationVertical;
    text.alignment = NSLayoutAttributeLeading;
    text.spacing = 1;
    NSStackView *row = [NSStackView stackViewWithViews:@[self.titleIcon, text]];
    row.spacing = 8;
    item.view = row;
    item.label = @"Title";
    return item;
}

- (void)syncTitle:(NSImage *)icon {
    self.titleLabel.stringValue = self.window.title ?: @"";
    self.subtitleLabel.stringValue = self.window.subtitle ?: @"";
    self.titleIcon.image = icon ?: [NSImage imageNamed:NSImageNameApplicationIcon];
}

- (void)updateTransferButton {
    BOOL on = !self.refreshing && [self transferableSelection].count > 0;
    self.transferItem.enabled = on;
    [self setFlatButton:self.transferButton enabled:on];
    BOOL canAssign = !self.refreshing && [self assignableSelection].count > 0;
    self.assignItem.enabled = canAssign;
    [self setFlatButton:self.assignButton enabled:canAssign];
    [self syncAssignTitle];
}

// "Assign to <selected app>": the button grows with the name, up to a cap, then truncates.
- (void)syncAssignTitle {
    NSButton *b = self.assignButton;
    if (!b) return;
    NSString *name = self.selectedApp.name;
    NSString *title = [NSString stringWithFormat:@"Assign to %@  ⌘D", name ?: @"App"];
    if ([b.title isEqual:title]) return;
    b.title = title;
    b.toolTip = name ? [NSString stringWithFormat:@"Make %@ the default handler for the selected associations (⌘D)", name]
                     : @"Make the selected app the default handler for the selected associations (⌘D)";
    CGFloat w = MIN(250, MAX(140, ceil(b.attributedTitle.size.width) + 24));
    for (NSLayoutConstraint *c in b.constraints)
        if (c.firstAttribute == NSLayoutAttributeWidth) c.constant = w;
}

- (BOOL)validateToolbarItem:(NSToolbarItem *)item {
    if (self.refreshing) return NO;
    if ([item.itemIdentifier isEqual:kTransferItem])
        return [self transferableSelection].count > 0;
    if ([item.itemIdentifier isEqual:kAssignItem])
        return [self assignableSelection].count > 0;
    return YES;
}

@end
