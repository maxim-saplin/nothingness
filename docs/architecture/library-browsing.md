# Library Browsing

This document describes the folder browsing pipeline after moving MediaStore logic out of the UI layer.

## Components

- **LibraryBrowser (service)**: Pure logic for building folder listings from MediaStore song paths (Android) or from the local file system (macOS). Returns `LibraryListing` with folders and `AudioTrack` items.
- **LibraryController (ChangeNotifier)**: Owns library state (current path, loading, errors, folders, tracks, permissions). Delegates all data work to `LibraryBrowser`, handles permission requests on Android, and exposes navigation helpers for the UI.
- **VoidBrowser (widget)** (`lib/widgets/void_browser.dart`): Presentation-only `HookWidget`. Listens to `LibraryController` via Provider, renders the breadcrumb, folders, and tracks, and triggers actions such as `requestPermission`, `loadFolder`, `navigateUp`, `repairCurrentFolderListing`, and `tracksForCurrentPath`. Supports a sliding-up presentation (collapsed hint band → expanded drawer) controlled by the `BrowserPresentation` setting, plus full-name recursive search across the entire library (not just the current folder). A `VoidBrowserController` lets the shell drive scroll-to-track reactively (no `GlobalKey<State>`).
- **LibraryService (macOS bookmarks)**: Persists user-selected roots on macOS; the controller consults it when navigating back to root.
- **PlatformChannels (Android MediaStore bridge)**: Exposes MediaStore version checks, change notifications, and the folder-level rescan method used by the manual repair action.

## Data Flow (Android)

1. User taps **Grant Library Access** → `LibraryController.requestPermission()` requests storage/audio permissions.
2. Controller queries MediaStore (via `on_audio_query`) into `LibrarySong` list **once** per scan.
   - **Async Scanning**: Queries run in isolates using `compute()` to prevent UI blocking.
   - **One query, not N×M**: `LibrarySong` caches `path` + `title` + `artist` from that single scan. Folder listings (`buildVirtualListing`) and play queues (`tracksForCurrentPath`) build their `AudioTrack`s via the query-free `buildTrackFromTags` (`metadata_extractor.dart`) — they do **not** call `extractMetadata`/`querySongs` per song (which used to re-scan the whole MediaStore for each track → O(N×M); fixed in 3.8.0).
   - **Lazy Initialization**: On Android, MediaStore is not queried at app launch. The library is initialized only when the user opens the Library panel and navigates to the Folders tab.
   - **Change Detection (Fast Path)**:
     - A native `ContentObserver` watches `MediaStore.Audio.Media.EXTERNAL_CONTENT_URI` and marks the app’s library cache as “dirty” when changes occur.
     - On Android 11+, the app also reads `MediaStore.getVersion(...)` as a low-cost way to detect significant MediaStore changes.
    - **Refresh Policy**:
       - Automatic: when the user navigates to the **Folders** tab, the controller refreshes only if MediaStore is detected as changed; otherwise it reuses cached results.
       - Per-navigation freshness: `loadFolder` and `tracksForCurrentPath` also consult `consumeIfChanged()` before reading the cached song list, so newly added/removed songs surface in folder browsing **and** reshuffle even mid-session — not only on a Folders-tab switch (3.8.0). This replaces the freshness the removed per-song re-query used to provide incidentally.
       - Manual repair: when the user is already inside an Android folder, the UI shows **Repair list** beside **Up**. This button requests a native MediaStore rescan for the direct files in the current folder, then performs a short bounded reload loop so late MediaStore propagation can settle before the folder view is rebuilt.
       - Scope: the manual repair path is hidden in the Android smart-root view and root view. It is only available for an opened folder and is disabled while a scan or refresh is already running.
3. Controller computes **Smart Roots** from the MediaStore song paths and discovered Android storage mount points.
   - **Goal**: Reduce clicks by starting users as close as possible to music folders (e.g. show `/storage/emulated/0/Music` instead of `/storage` → `emulated` → `0` → `Music`).
   - **Grouped by device**: Smart roots are grouped by storage device/mount point (internal vs USB volumes).
   - **Cap to avoid flooding**: If a device would produce more than 5 smart entries, the UI falls back to showing only the device root (e.g. `/storage/emulated/0`) for that device.
   - **First branching folder heuristic**: For each device, smart roots are chosen by finding the first folder in the media directory tree that actually *branches* into multiple child folders containing audio. This avoids unhelpful picks like `Android` when audio is stored under deep app-scoped paths (e.g. Nextcloud under `.../Android/media/.../Music/CDs/...`).
     - If there is no branching (everything is under a single deep chain), the smart root falls back to the partition root (e.g. `/.../Music`) to avoid overly deep entries.
4. When the user taps a smart root entry, the controller calls `LibraryBrowser.buildVirtualListing()` to construct a virtual folder tree from MediaStore song paths under that base path.
5. UI renders folders/files; **Play All** uses `tracksForCurrentPath()` to send a queue to the player.
   - **Manual Repair Path**: `repairCurrentFolderListing()` reuses the normal Android refresh flow after the native scan request is issued. Native completion means scan requests were submitted, not that MediaStore finished indexing.
   - **Error Handling**: Missing files are marked with an `isNotFound` flag and displayed with a red error icon. During playback (tap/Next/Previous/natural advance), missing/known-failed tracks are skipped deterministically while preserving the red marking in the queue.

## Data Flow (macOS)

1. User picks a folder (persisted by `LibraryService`).
2. Controller calls `LibraryBrowser.listFileSystem()` to read folders/files directly from disk.
3. UI renders folders/files; **Play All** uses the existing recursive scan and queues the tracks into `PlaybackController`.

## Rationale

- Removes storage and MediaStore logic from the browser widget (`VoidBrowser`) to keep it focused on presentation.
- Enables unit testing of the folder-building logic (`LibraryBrowser`) without Flutter bindings.
- Keeps Android on the existing MediaStore-first model while still giving users a targeted repair path for stale folder indexes.
- Maintains feature parity: Android uses MediaStore; macOS keeps filesystem browsing with security-scoped bookmarks.
