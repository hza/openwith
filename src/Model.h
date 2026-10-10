// Model: installed apps, the associations they claim, and search/filter helpers.
#import <Cocoa/Cocoa.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface Assoc : NSObject
@property NSString *kind;        // "UTI", "Extension", "URL scheme"
@property NSString *identifier;  // UTI / ".ext" / "scheme"
@property NSString *extensions;
@property NSString *role;
@property NSString *rank;
@property NSString *defaultApp;  // current default handler name
@property BOOL isDefault;
@property UTType *type;          // nil for URL schemes / unresolvable extensions
@property NSString *scheme;      // set for URL schemes
@end

@interface AppEntry : NSObject
@property NSString *name;
@property NSString *bundleID;
@property NSURL *url;
@property NSImage *icon;
@property NSArray<Assoc *> *assocs; // loaded lazily
@property NSSet<NSString *> *exts;   // lowercase extensions claimed, for ".ext" filtering
@property NSSet<NSString *> *utis;   // UTIs claimed; an extension whose type conforms to one also matches
@end

// Collect every filename extension an app claims, directly or via its declared UTIs.
NSSet<NSString *> *ClaimedExtensions(NSDictionary *info);

NSSet<NSString *> *ClaimedUTIs(NSDictionary *info);

// The claimed UTI that `t` conforms to (e.g. public.text for .md), or nil.
NSString *ConformingUTI(NSSet<NSString *> *utis, UTType *t);

// ".c .cpp" / ".c, .cpp": the lowercased extensions (no dots) when every term is a ".ext", else nil.
NSArray<NSString *> *ExtTerms(NSString *q);

NSArray<AppEntry *> *FilterApps(NSArray<AppEntry *> *apps, NSString *q);

NSString *Join(id v);

NSString *DefaultAppNameForURL(NSURL *appURL, NSString **outBundleID);

NSArray<Assoc *> *LoadAssocs(AppEntry *app);

NSArray<AppEntry *> *ScanApps(void);

// One row per extension claimed by any app (shown when no app is selected).
NSArray<Assoc *> *BuildOverview(NSArray<AppEntry *> *apps);

// Bundle ID of the app currently handling every one of the given associations, or nil if they differ.
NSString *SharedDefaultBundleID(NSArray<Assoc *> *items);

// How `e` relates to association `a`: "Default" if it currently handles it, otherwise the claim's
// LSHandlerRank ("Owner", "Alternate", …; "Common" when unranked), "Generic" when only claimed via a
// parent UTI (e.g. public.text for .md), or "" when it doesn't claim it at all.
NSString *ClaimKind(AppEntry *e, Assoc *a, NSString *defaultBundleID);
