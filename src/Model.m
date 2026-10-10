#import "Model.h"

@implementation Assoc
@end

@implementation AppEntry
@end

// Collect every filename extension an app claims, directly or via its declared UTIs.
NSSet<NSString *> *ClaimedExtensions(NSDictionary *info) {
    NSMutableSet *s = [NSMutableSet set];
    for (NSDictionary *dt in info[@"CFBundleDocumentTypes"]) {
        if (![dt isKindOfClass:[NSDictionary class]]) continue;
        NSArray *exts = dt[@"CFBundleTypeExtensions"];
        if ([exts isKindOfClass:[NSArray class]])
            for (NSString *e in exts) if ([e isKindOfClass:[NSString class]]) [s addObject:e.lowercaseString];
        NSArray *utis = dt[@"LSItemContentTypes"];
        if ([utis isKindOfClass:[NSArray class]])
            for (NSString *u in utis) {
                if (![u isKindOfClass:[NSString class]]) continue;
                for (NSString *e in [UTType typeWithIdentifier:u].tags[UTTagClassFilenameExtension])
                    [s addObject:e.lowercaseString];
            }
    }
    return s;
}

NSSet<NSString *> *ClaimedUTIs(NSDictionary *info) {
    NSMutableSet *s = [NSMutableSet set];
    for (NSDictionary *dt in info[@"CFBundleDocumentTypes"]) {
        if (![dt isKindOfClass:[NSDictionary class]]) continue;
        NSArray *utis = dt[@"LSItemContentTypes"];
        if ([utis isKindOfClass:[NSArray class]])
            for (NSString *u in utis) if ([u isKindOfClass:[NSString class]]) [s addObject:u];
    }
    return s;
}

NSSet<NSString *> *ClaimedSchemes(NSDictionary *info) {
    NSMutableSet *s = [NSMutableSet set];
    for (NSDictionary *ut in info[@"CFBundleURLTypes"]) {
        if (![ut isKindOfClass:[NSDictionary class]]) continue;
        NSArray *schemes = ut[@"CFBundleURLSchemes"];
        if ([schemes isKindOfClass:[NSArray class]])
            for (NSString *x in schemes) if ([x isKindOfClass:[NSString class]]) [s addObject:x.lowercaseString];
    }
    return s;
}

// The claimed UTI that `t` conforms to (e.g. public.text for .md), or nil.
NSString *ConformingUTI(NSSet<NSString *> *utis, UTType *t) {
    if (!t) return nil;
    for (NSString *u in utis) {
        UTType *parent = [UTType typeWithIdentifier:u];
        if (parent && [t conformsToType:parent]) return u;
    }
    return nil;
}

// "mailto:" / "http://": the lowercased scheme, else nil.
NSString *SchemeTerm(NSString *q) {
    NSRange r = [q rangeOfString:@":"];
    if (r.location == NSNotFound || r.location == 0) return nil;
    NSString *rest = [q substringFromIndex:r.location];
    if (!([rest isEqual:@":"] || [rest isEqual:@":/"] || [rest isEqual:@"://"])) return nil;
    return [q substringToIndex:r.location].lowercaseString;
}

// Filter: ".md" matches apps claiming that extension, directly or via a parent UTI (Notes claims
// public.text, which .md conforms to); "mailto:" / "http://" matches apps claiming that URL scheme;
// anything else matches name / bundle ID, or a claimed URL scheme spelled out exactly ("https").
static BOOL AppMatches(AppEntry *e, NSString *q, UTType *extType) {
    if (!q.length) return YES;
    if ([q hasPrefix:@"."] && q.length > 1)
        return [e.exts containsObject:[q substringFromIndex:1].lowercaseString] || ConformingUTI(e.utis, extType);
    NSString *scheme = SchemeTerm(q);
    if (scheme) return [e.schemes containsObject:scheme];
    return [e.name localizedCaseInsensitiveContainsString:q] ||
           [e.bundleID localizedCaseInsensitiveContainsString:q] ||
           [e.schemes containsObject:q.lowercaseString];
}

// ".c .cpp" / ".c, .cpp": the lowercased extensions (no dots) when every term is a ".ext", else nil.
NSArray<NSString *> *ExtTerms(NSString *q) {
    NSMutableCharacterSet *seps = [NSMutableCharacterSet whitespaceCharacterSet];
    [seps addCharactersInString:@","];
    NSMutableArray *exts = [NSMutableArray array];
    for (NSString *t in [q componentsSeparatedByCharactersInSet:seps]) {
        if (!t.length) continue;
        if (![t hasPrefix:@"."] || t.length < 2) return nil;
        [exts addObject:[t substringFromIndex:1].lowercaseString];
    }
    return exts.count ? exts : nil;
}

NSArray<AppEntry *> *FilterApps(NSArray<AppEntry *> *apps, NSString *q) {
    if (!q.length) return apps;
    NSArray<NSString *> *exts = ExtTerms(q);
    if (!exts) return [apps filteredArrayUsingPredicate:
        [NSPredicate predicateWithBlock:^BOOL(AppEntry *e, id b) { return AppMatches(e, q, nil); }]];
    NSMutableArray *types = [NSMutableArray array];
    for (NSString *x in exts) [types addObject:[UTType typeWithFilenameExtension:x] ?: (id)NSNull.null];
    return [apps filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(AppEntry *e, id b) {
        for (NSUInteger i = 0; i < exts.count; i++) {
            UTType *t = types[i] == NSNull.null ? nil : types[i];
            if (AppMatches(e, [@"." stringByAppendingString:exts[i]], t)) return YES;
        }
        return NO;
    }]];
}

NSString *Join(id v) {
    if ([v isKindOfClass:[NSArray class]]) return [(NSArray *)v componentsJoinedByString:@", "];
    return [v isKindOfClass:[NSString class]] ? v : @"";
}

NSString *DefaultAppNameForURL(NSURL *appURL, NSString **outBundleID) {
    if (!appURL) return @"—";
    NSBundle *b = [NSBundle bundleWithURL:appURL];
    if (outBundleID) *outBundleID = b.bundleIdentifier;
    return [[NSFileManager defaultManager] displayNameAtPath:appURL.path];
}

NSArray<Assoc *> *LoadAssocs(AppEntry *app) {
    NSMutableArray *out = [NSMutableArray array];
    NSDictionary *info = [NSBundle bundleWithURL:app.url].infoDictionary;
    NSWorkspace *ws = [NSWorkspace sharedWorkspace];

    for (NSDictionary *dt in info[@"CFBundleDocumentTypes"]) {
        if (![dt isKindOfClass:[NSDictionary class]]) continue;
        NSString *role = Join(dt[@"CFBundleTypeRole"]);
        NSString *rank = Join(dt[@"LSHandlerRank"]);
        NSArray *utis = dt[@"LSItemContentTypes"];
        NSArray *exts = dt[@"CFBundleTypeExtensions"];

        NSMutableArray *ids = [NSMutableArray array];
        if ([utis isKindOfClass:[NSArray class]] && utis.count) {
            for (NSString *u in utis) [ids addObject:@[@"UTI", u]];
        } else if ([exts isKindOfClass:[NSArray class]]) {
            for (NSString *e in exts) [ids addObject:@[@"Extension", e]];
        }

        for (NSArray *pair in ids) {
            Assoc *a = [Assoc new];
            a.kind = pair[0];
            a.role = role;
            a.rank = rank;
            UTType *t = nil;
            if ([a.kind isEqual:@"UTI"]) {
                a.identifier = pair[1];
                t = [UTType typeWithIdentifier:pair[1]];
                NSArray *tagExts = t.tags[UTTagClassFilenameExtension];
                a.extensions = tagExts.count ? Join(tagExts) : @"";
            } else {
                a.identifier = [@"." stringByAppendingString:pair[1]];
                a.extensions = pair[1];
                if (![pair[1] isEqual:@"*"]) t = [UTType typeWithFilenameExtension:pair[1]];
            }
            a.type = t;
            if (t) {
                NSString *bid = nil;
                a.defaultApp = DefaultAppNameForURL([ws URLForApplicationToOpenContentType:t], &bid);
                a.isDefault = bid && [bid isEqualToString:app.bundleID];
            } else {
                a.defaultApp = @"—";
            }
            [out addObject:a];
        }
    }

    for (NSDictionary *ut in info[@"CFBundleURLTypes"]) {
        if (![ut isKindOfClass:[NSDictionary class]]) continue;
        for (NSString *scheme in ut[@"CFBundleURLSchemes"]) {
            if (![scheme isKindOfClass:[NSString class]]) continue;
            Assoc *a = [Assoc new];
            a.kind = @"URL scheme";
            a.scheme = scheme;
            a.identifier = [scheme stringByAppendingString:@"://"];
            a.extensions = @"";
            a.role = Join(ut[@"CFBundleTypeRole"]);
            a.rank = @"";
            NSURL *probe = [NSURL URLWithString:[scheme stringByAppendingString:@"://"]];
            NSString *bid = nil;
            a.defaultApp = DefaultAppNameForURL(probe ? [ws URLForApplicationToOpenURL:probe] : nil, &bid);
            a.isDefault = bid && [bid isEqualToString:app.bundleID];
            [out addObject:a];
        }
    }
    return out;
}

NSArray<AppEntry *> *ScanApps(void) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *roots = @[@"/Applications", @"/System/Applications",
                       @"/System/Library/CoreServices",
                       [NSHomeDirectory() stringByAppendingPathComponent:@"Applications"]];
    NSMutableDictionary<NSString *, AppEntry *> *byID = [NSMutableDictionary dictionary];
    for (NSString *root in roots) {
        NSDirectoryEnumerator *en = [fm enumeratorAtURL:[NSURL fileURLWithPath:root]
                             includingPropertiesForKeys:nil
                                                options:NSDirectoryEnumerationSkipsHiddenFiles
                                           errorHandler:nil];
        for (NSURL *u in en) {
            if (![u.pathExtension isEqualToString:@"app"]) continue;
            [en skipDescendants];
            NSBundle *b = [NSBundle bundleWithURL:u];
            NSString *bid = b.bundleIdentifier ?: u.path;
            if (byID[bid]) continue;
            NSDictionary *info = b.infoDictionary;
            if (![info[@"CFBundleDocumentTypes"] count] && ![info[@"CFBundleURLTypes"] count]) continue;
            AppEntry *e = [AppEntry new];
            e.url = u;
            e.bundleID = bid;
            e.name = [fm displayNameAtPath:u.path];
            e.exts = ClaimedExtensions(info);
            e.utis = ClaimedUTIs(info);
            e.schemes = ClaimedSchemes(info);
            byID[bid] = e;
        }
    }
    return [byID.allValues sortedArrayUsingComparator:^(AppEntry *a, AppEntry *b) {
        return [a.name localizedCaseInsensitiveCompare:b.name];
    }];
}

// One row per extension claimed by any app (shown when no app is selected).
NSArray<Assoc *> *BuildOverview(NSArray<AppEntry *> *apps) {
    NSCountedSet *counts = [NSCountedSet set];
    for (AppEntry *e in apps) for (NSString *x in e.exts) if (![x isEqual:@"*"]) [counts addObject:x];
    NSWorkspace *ws = [NSWorkspace sharedWorkspace];
    NSMutableDictionary<NSString *, NSString *> *names = [NSMutableDictionary dictionary];  // app path -> name
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *x in counts) {
        Assoc *a = [Assoc new];
        a.kind = @"Extension";
        a.identifier = [@"." stringByAppendingString:x];
        UTType *t = [UTType typeWithFilenameExtension:x];
        a.type = t;
        a.extensions = t.identifier ?: @"";
        NSUInteger n = [counts countForObject:x];
        a.role = [NSString stringWithFormat:@"%lu app%@", (unsigned long)n, n == 1 ? @"" : @"s"];
        a.rank = @"";
        NSURL *u = t ? [ws URLForApplicationToOpenContentType:t] : nil;
        NSString *name = u ? names[u.path] : nil;
        if (u && !name) names[u.path] = name = DefaultAppNameForURL(u, NULL);
        a.defaultApp = name ?: @"—";
        [out addObject:a];
    }
    NSCountedSet *schemes = [NSCountedSet set];
    for (AppEntry *e in apps) for (NSString *x in e.schemes) [schemes addObject:x];
    for (NSString *x in schemes) {
        Assoc *a = [Assoc new];
        a.kind = @"URL scheme";
        a.scheme = x;
        a.identifier = [x stringByAppendingString:@"://"];
        a.extensions = @"";
        NSUInteger n = [schemes countForObject:x];
        a.role = [NSString stringWithFormat:@"%lu app%@", (unsigned long)n, n == 1 ? @"" : @"s"];
        a.rank = @"";
        NSURL *probe = [NSURL URLWithString:a.identifier];
        NSURL *u = probe ? [ws URLForApplicationToOpenURL:probe] : nil;
        NSString *name = u ? names[u.path] : nil;
        if (u && !name) names[u.path] = name = DefaultAppNameForURL(u, NULL);
        a.defaultApp = name ?: @"—";
        [out addObject:a];
    }
    return [out sortedArrayUsingComparator:^NSComparisonResult(Assoc *a, Assoc *b) {
        if (!a.scheme != !b.scheme) return a.scheme ? NSOrderedDescending : NSOrderedAscending;
        return [a.identifier localizedCaseInsensitiveCompare:b.identifier];
    }];
}

BOOL IsProtectedAssoc(Assoc *a) {
    if (a.scheme) return [a.scheme caseInsensitiveCompare:@"file"] == NSOrderedSame;
    if (!a.type) return NO;
    // Exact only: document packages (.pages, .rtfd) conform to these and stay assignable.
    for (NSString *u in @[@"public.item", @"public.data", @"public.content", @"public.directory", @"com.apple.package",
                          @"public.executable"])
        if ([a.type.identifier isEqualToString:u]) return YES;
    // Not public.executable by conformance: .js/.mjs/.cjs, .exe and .jar conform to it and are fine to reassign.
    for (NSString *u in @[@"com.apple.application", @"public.unix-executable", @"com.apple.bundle",
                          @"public.folder", @"public.volume"]) {
        UTType *p = [UTType typeWithIdentifier:u];
        if (p && [a.type conformsToType:p]) return YES;
    }
    return NO;
}

// Bundle ID of the app currently handling every one of the given associations, or nil if they differ.
NSString *SharedDefaultBundleID(NSArray<Assoc *> *items) {
    NSWorkspace *ws = NSWorkspace.sharedWorkspace;
    NSString *shared = nil;
    for (Assoc *a in items) {
        NSURL *app = a.scheme ? [ws URLForApplicationToOpenURL:[NSURL URLWithString:[a.scheme stringByAppendingString:@":"]]]
                   : a.type   ? [ws URLForApplicationToOpenContentType:a.type] : nil;
        NSString *bid = app ? [NSBundle bundleWithURL:app].bundleIdentifier : nil;
        if (!bid || (shared && ![shared isEqualToString:bid])) return nil;
        shared = bid;
    }
    return shared;
}

// How `e` relates to association `a`: "Default" if it currently handles it, otherwise the claim's
// LSHandlerRank ("Owner", "Alternate", …; "Common" when unranked), "Generic" when only claimed via a
// parent UTI (e.g. public.text for .md), or "" when it doesn't claim it at all.
NSString *ClaimKind(AppEntry *e, Assoc *a, NSString *defaultBundleID) {
    if (defaultBundleID && [e.bundleID isEqualToString:defaultBundleID]) return @"Default";
    NSDictionary *info = [NSBundle bundleWithURL:e.url].infoDictionary;
    if (a.scheme) {
        for (NSDictionary *ut in info[@"CFBundleURLTypes"]) {
            if (![ut isKindOfClass:[NSDictionary class]]) continue;
            for (NSString *s in ut[@"CFBundleURLSchemes"])
                if ([s isKindOfClass:[NSString class]] && [s caseInsensitiveCompare:a.scheme] == NSOrderedSame)
                    return @"Common";
        }
        return @"";
    }
    NSString *ext = a.type.preferredFilenameExtension.lowercaseString;
    if ([a.kind isEqual:@"Extension"] && [a.identifier hasPrefix:@"."]) ext = [a.identifier substringFromIndex:1].lowercaseString;
    BOOL generic = NO;
    for (NSDictionary *dt in info[@"CFBundleDocumentTypes"]) {
        if (![dt isKindOfClass:[NSDictionary class]]) continue;
        BOOL exact = NO;
        NSArray *utis = dt[@"LSItemContentTypes"], *exts = dt[@"CFBundleTypeExtensions"];
        if ([utis isKindOfClass:[NSArray class]] && utis.count) {
            for (NSString *u in utis) {
                if (![u isKindOfClass:[NSString class]]) continue;
                if (a.type && [u isEqualToString:a.type.identifier]) exact = YES;
                else if (ConformingUTI([NSSet setWithObject:u], a.type)) generic = YES;
            }
        } else if ([exts isKindOfClass:[NSArray class]]) {
            for (NSString *x in exts)
                if ([x isKindOfClass:[NSString class]] && ext && [x.lowercaseString isEqualToString:ext]) exact = YES;
        }
        if (exact) {
            NSString *rank = Join(dt[@"LSHandlerRank"]);
            return rank.length && ![rank isEqual:@"Default"] ? rank : @"Common";
        }
    }
    return generic ? @"Generic" : @"";
}
