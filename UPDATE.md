# Software Update Implementation

## Architecture Overview

```
┌──────────────────────────────────────────────────┐
│                  UpdateService                    │
│  @Observable, @MainActor singleton               │
│                                                   │
│  checkForUpdates()  →  URLSession  →  JSON parse  │
│       ↓                                           │
│  downloadAndInstall()  →  URLSessionDownloadTask  │
│       ↓                                           │
│  silentInstall()  →  hdiutil mount DMG            │
│                   →  cp .app to temp location      │
│                   →  bash script (fire & forget)   │
│                   →  exit(0)                       │
│       ↓                                           │
│  bash script runs as orphan process:              │
│    sleep 4 → rm old .app → mv new .app → open     │
└──────────────────────────────────────────────────┘
```

## Update Check

- URL: `https://shelldeck.782389.xyz` (returns GitHub release JSON format)
- Expected response format:
  ```json
  {
    "tag_name": "v1.0.0",
    "body": "Release notes...",
    "html_url": "https://...",
    "assets": [
      {
        "name": "ShellDeck-aarch64-v1.0.0.dmg",
        "browser_download_url": "https://..."
      }
    ]
  }
  ```
- ARM/x86_64 asset selection via `#if arch(arm64)` compile flag
- Fallback: any `.dmg` asset if arch-specific not found
- Version comparison: semver-like (`1.0.0` > `0.9.9`)

## Silent Install Flow

### Step-by-step

1. **Mount DMG** via `hdiutil attach -nobrowse -readonly -plist`
2. **Find `.app`** in mounted volume (search by `pathExtension == "app"`)
3. **Copy** new app to `{parentDir}/ShellDeck.app.new` (alongside current app)
4. **Write bash script** to `NSFileManager.temporaryDirectory`:
   ```bash
   #!/bin/bash
   sleep 4
   rm -rf "/path/to/ShellDeck.app"
   mv "/path/to/ShellDeck.app.new" "/path/to/ShellDeck.app"
   rm -f "/tmp/ShellDeck-update.dmg" 2>/dev/null
   hdiutil detach "/Volumes/ShellDeck" -force 2>/dev/null
   open "/path/to/ShellDeck.app"
   ```
5. **Launch script** via `Process` (`/bin/bash script.sh`) — fire & forget, no wait
6. **`exit(0)`** on `MainActor` — immediate process termination

### After exit

- The bash script becomes an **orphan process** (reparented to PID 1 / launchd)
- After `sleep 4`, it replaces the old app with the new one and calls `open`
- The old DMG is unmounted and cleaned up

### Why `exit(0)` instead of `NSApp.terminate()`

| Method | Behavior | Issue |
|--------|----------|-------|
| `NSApp.terminate(nil)` | Posts event to run loop, triggers window closing, delegate callbacks | Can **hang** if bundle was renamed (macOS 14+), or in debug builds |
| `exit(0)` | Immediate process death, atexit handlers only | Skips Swift `defer` blocks, no UI cleanup |

Using `exit(0)` is intentional — we've already copied the new app and launched the helper script. The old process is disposable.

### Error fallback

If `silentInstall()` throws (DMG mount failure, no `.app` found), the catch block:
1. Resets UI state
2. Calls `NSWorkspace.shared.open(fileUrl)` to open the DMG in Finder for manual install

## Key Technical Details

### macOS allows renaming/moving the running .app bundle

`FileManager.default.moveItem()` on `Bundle.main.bundleURL` works while the app is running. The running binary keeps its file descriptor to the executable, so the process continues normally even after the bundle path changes.

### Child processes survive parent exit

A `Process`-launched child is NOT killed when the parent calls `exit(0)`. It becomes an orphan and continues running under launchd.

### Temporary directory persistence

Scripts written to `FileManager.default.temporaryDirectory` must be executed **before** the parent exits, or the file must be opened/read before exit. The script content is loaded into bash's memory at `proc.run()`, so the file can be deleted afterward.

### DMG mount requires `/usr/bin/hdiutil`

- `attach` with `-nobrowse` (no Finder popup), `-readonly` (prevent modification), `-plist` (machine-parseable output)
- `detach` with `-force` to handle busy volumes
- Mount point is extracted from plist output: `system-entities[].mount-point`

## Version Management

### Single source of truth

All version info reads from the **`VERSION`** file at project root:

```
ShellDeck/VERSION -> ../VERSION  (symlink)
```

- `UpdateService.currentVersion` — reads from `Bundle.main` at runtime
- `CFBundleShortVersionString` / `CFBundleVersion` — set by a Run Script build phase that reads `$(SRCROOT)/VERSION` and patches the built `Info.plist` via `PlistBuddy`
- CI (`VERSION` file check in GitHub Actions) — compares tag with `VERSION` content

### Release workflow

1. Update `VERSION` file (e.g. `echo "1.0.1" > VERSION`)
2. Commit + tag (`git tag v1.0.1`)
3. CI reads `VERSION`, builds, and releases

No need to touch Swift code or Xcode project settings for version bumps.

## Porting to Another Project

### Required changes

1. **`ShellDeck/VERSION -> ../VERSION`**: Create a symlink so the app bundle includes the version file
2. **Run Script build phase**: Add a "Sync Version from VERSION file" phase that reads `$(SRCROOT)/VERSION` and patches the built `Info.plist`
3. **Update URL**: Replace `https://shelldeck.782389.xyz` with your server endpoint
4. **Response format**: Either match GitHub release JSON or change the `Codable` struct
5. **App bundle name**: Replace `ShellDeck.app` in script if your app has a different name
6. **DMG asset naming**: The `#if arch(arm64)` / `targetArch` matching logic — adjust if your DMG naming convention differs

### Minimal server requirements

Your server should return JSON with at minimum:
- `tag_name` — version string (e.g. `"v1.0.0"`)
- `assets[n].name` — filename for arch matching
- `assets[n].browser_download_url` — download URL for the DMG

Optional:
- `body` — release notes
- `html_url` — web link for the release

### Dependency

No external dependencies. Uses only Foundation, AppKit, and Observation (iOS 17+ / macOS 14+).

## References

- [hdiutil man page](https://ss64.com/osx/hdiutil.html)
- [NSWorkspace.openApplication](https://developer.apple.com/documentation/appkit/nsworkspace/3172693-openapplication)
- [Swift Process](https://developer.apple.com/documentation/foundation/process)
- [Sparkle Project](https://sparkle-project.org/) (reference for macOS update patterns)
