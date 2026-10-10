# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

"Open With" is a small native macOS app (bundle ID `io.github.hza.openwith`, macOS 12+) for viewing and changing
file-type / URL-scheme default-app associations. It's written in plain Objective-C with AppKit, with no Xcode
project: sources are in `src/`, and the `Makefile` compiles every `src/*.m` with clang. There are no tests and no linter.
`-Wall` is the only check, so builds should stay warning-free.

## Commands

- `make`: compile all `src/*.m` into `build/openwith` and assemble and ad-hoc codesign `build/Open With.app`
- `make run`: build and open the app from `build/`
- `make open`: kill the running instance, install to `~/Applications` (re-registering with LaunchServices via `lsregister`), and launch it. Use this when testing "Open With" / document-type behavior, which depends on LaunchServices registration
- `make kill`, `make clean`, `make uninstall` (also deletes the app's `defaults` domain)
- `make icns`: regenerate `icon/app.icns` from `icon/source.png` (rules in `icon/Makefile`) → `icon/mask.swift` (finds the tile, rounds it, makes the background transparent) → `iconutil`. The intermediate PNG goes to `build/`; `icon/app.icns` is committed.

## Architecture (src/)

| File | Contents |
|---|---|
| `Model.h/.m` | `Assoc`, `AppEntry`, and plain C functions: `ScanApps`, `LoadAssocs`, `BuildOverview`, `FilterApps`/`ExtTerms`, `ClaimKind`, `SharedDefaultBundleID`, `ConformingUTI` |
| `AppPicker.h/.m` | Filterable app list used in the Assign sheet and the file chooser |
| `Controller.h` | The `Controller` interface (all properties) plus one category declaration per file below. Add new cross-file methods here |
| `Controller.m` | Window, split view, and menu setup; `refreshApps:`, sidebar search (`applyFilter`, `extFilter`), and copy |
| `Controller+OpenWith.m` | Being an "Open With" target: `application:openURLs:` → `chooseAppForFile:` |
| `Controller+Toolbar.m` | Toolbar delegate: title item, "Make Default" / "Assign to…" buttons, and their enabled state |
| `Controller+Assign.m` | Selection helpers, `transfer:` (the Assign sheet), and `assign:toApp:` (writes defaults) |
| `Controller+Table.m` | Table data source and delegate, `reloadAssocs`, overview, and sorting |
| `main.m` | `main()` only |

- **Model**: `AppEntry` is an installed app (its URL, bundle ID, claimed extensions and UTIs, and cached `assocs`). `Assoc` is one association row (kind `UTI` / `Extension` / `URL scheme`, plus role, rank, resolved `UTType`, current default app, and `isDefault`).
  - `ScanApps()` walks `/Applications`, `/System/Applications`, `/System/Library/CoreServices` and `~/Applications`, dedupes by bundle ID, and keeps only apps that declare `CFBundleDocumentTypes` or `CFBundleURLTypes`.
  - `LoadAssocs()` parses an app's Info.plist. `LSItemContentTypes` takes precedence over `CFBundleTypeExtensions`. The current default comes from `NSWorkspace URLForApplicationToOpen…`.
  - `BuildOverview()` is the view shown when no app is selected: one row per extension that any app claims.
  - `FilterApps()` does search, matching by name or by claimed extension/UTI (with UTType conformance).
- **Controller**: the app delegate. Info.plist claims `public.data`/`public.content` at `Alternate` rank, so the app shows up as an "Open With" target. `assign:toApp:` writes defaults with `NSWorkspace setDefaultApplicationAtURL:…` and then invalidates every cached `assocs` before reloading. The last transfer target is persisted in `NSUserDefaults` (`LastTransferTarget`).
