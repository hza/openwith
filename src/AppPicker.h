// AppPicker: filterable app list (search field + table) used in the Assign sheet and file chooser.
#import "Model.h"

@interface AppPicker : NSObject <NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate>
@property NSArray<AppEntry *> *all, *shown;
@property NSTableView *table;
@property NSSearchField *search;
@property NSView *view;
@property (copy) void (^onDoubleClick)(void);
@property (copy, nonatomic) NSString *(^detail)(AppEntry *);  // optional second column
@property (copy) BOOL (^include)(AppEntry *);                 // optional extra filter on top of the search
- (void)refilter:(id)sender;
- (instancetype)initWithApps:(NSArray<AppEntry *> *)apps selectBundleID:(NSString *)bid;
- (AppEntry *)selected;
- (void)selectBundleID:(NSString *)bid;
@end
