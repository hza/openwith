// Controller: app delegate owning the main window. Split across files by category:
//   Controller.m           window/menu setup, app scan, sidebar search & filter
//   Controller+OpenWith.m  being an "Open With" target: chooser for opened files
//   Controller+Toolbar.m   toolbar items (title, Make Default, Assign to…) and their enabled state
//   Controller+Assign.m    selection helpers, transfer/assign actions, writing defaults
//   Controller+Table.m     table data sources, association loading, overview
#import "AppPicker.h"

@interface Controller : NSObject <NSApplicationDelegate, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, NSToolbarDelegate>
@property NSWindow *window;
@property NSTableView *appTable, *assocTable;
@property NSSearchField *search;
@property NSToolbarItem *transferItem, *assignItem;
@property NSButton *transferButton, *assignButton;
@property BOOL refreshing;  // a rescan is in flight
@property NSImageView *titleIcon;
@property NSTextField *titleLabel, *subtitleLabel;
@property NSArray<AppEntry *> *allApps, *apps;
@property NSURL *extDefaultURL;  // default handler for the ".ext" filter, shown bold in the sidebar
@property NSArray<Assoc *> *assocs;
@property NSArray<Assoc *> *overview;  // all extensions, shown when no app is selected
@property BOOL launchedWithFiles;  // opened via a document: skip the main window unless asked
@end

@interface Controller (Core)
- (void)showMainWindow;
- (void)buildMenu;
- (void)showAbout:(id)sender;
- (AppEntry *)selectedApp;
- (void)selectAppAtIndex:(NSUInteger)i;
- (void)refreshApps:(id)sender;
- (void)applyFilter;
- (NSArray<NSString *> *)extFilter;
@end

// Files opened with this app
@interface Controller (OpenWith)
- (void)chooseAppForFile:(NSURL *)file;
@end

// Toolbar
@interface Controller (Toolbar)
- (void)setFlatButton:(NSButton *)b enabled:(BOOL)on;
- (NSToolbarItem *)makeTitleItem;
- (void)syncTitle:(NSImage *)icon;
- (void)updateTransferButton;
- (void)syncAssignTitle;
@end

// Selection, transfer and assign
@interface Controller (Assign)
- (NSArray<Assoc *> *)selectedAssocs;
- (NSArray<Assoc *> *)transferableSelection;
- (NSArray<Assoc *> *)assignableSelection;
- (void)assignToCurrent:(id)sender;
- (void)assocDoubleClicked:(id)sender;
- (void)transfer:(id)sender;
- (void)focusAssocList;
- (void)focusAssocListSelecting:(NSArray<Assoc *> *)items;
- (void)assign:(NSArray<Assoc *> *)items toApp:(AppEntry *)target;
@end

// Table data
@interface Controller (Table)
- (void)reloadAssocs;
- (void)setOverviewHeaders:(BOOL)overview;
- (void)rebuildOverview;
- (NSArray<Assoc *> *)inheritedAssocsForExt:(NSString *)ext app:(AppEntry *)app;
@end
