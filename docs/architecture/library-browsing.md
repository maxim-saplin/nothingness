# Library Browsing

This document describes the folder browsing pipeline after moving MediaStore logic out of the UI layer.

## Components

- **LibraryBrowser (service)**: Pure logic for building folder listings from MediaStore song paths (Android) or from the local file system (macOS). Returns `LibraryListing` with folders and `AudioTrack` items.
- **LibraryController (ChangeNotifier)**: Owns library state (current path, loading, errors, folders, tracks, permissions). Delegates all data work to `LibraryBrowser`, handles permission requests on Android, and exposes navigation helpers for the UI.
- **LibraryPanel (widget)**: Presentation-only. Listens to `LibraryController` via Provider, renders folders/tracks, and triggers actions such as `requestPermission`, `loadFolder`, `navigateUp`, and `tracksForCurrentPath`.
- **LibraryService (macOS bookmarks)**: Persists user-selected roots on macOS; the controller consults it when navigating back to root.

## Data Flow (Android)

1. User taps **Grant Library Access** → `LibraryController.requestPermission()` requests storage/audio permissions.
2. Controller queries MediaStore (via `on_audio_query`) into `LibrarySong` list.
   - **Async Scanning**: Queries run in isolates using `compute()` to prevent UI blocking.
   - **Smart Caching**: `LibraryService` persists the last scan timestamp. On launch, the controller compares this with the MediaStore's latest `dateAdded`/`dateModified`. A full rescan only occurs if new content is detected.
   - **Refresh**: A manual refresh button in the UI clears the cache and forces a MediaStore rescan.
3. Controller computes **Smart Roots** from the MediaStore song paths and discovered Android storage mount points.
   - **Goal**: Reduce clicks by starting users as close as possible to music folders (e.g. show `/storage/emulated/0/Music` instead of `/storage` → `emulated` → `0` → `Music`).
   - **Grouped by device**: Smart roots are grouped by storage device/mount point (internal vs USB volumes).
   - **Cap to avoid flooding**: If a device would produce more than 5 smart entries, the UI falls back to showing only the device root (e.g. `/storage/emulated/0`) for that device.
   - **First branching folder heuristic**: For each device, smart roots are chosen by finding the first folder in the media directory tree that actually *branches* into multiple child folders containing audio. This avoids unhelpful picks like `Android` when audio is stored under deep app-scoped paths (e.g. Nextcloud under `.../Android/media/.../Music/CDs/...`).
     - If there is no branching (everything is under a single deep chain), the smart root falls back to the partition root (e.g. `/.../Music`) to avoid overly deep entries.
4. When the user taps a smart root entry, the controller calls `LibraryBrowser.buildVirtualListing()` to construct a virtual folder tree from MediaStore song paths under that base path.
4. UI renders folders/files; **Play All** uses `tracksForCurrentPath()` to send a queue to the player.
   - **Error Handling**: Missing files are marked with an `isNotFound` flag and displayed with a red error icon. During playback (tap/Next/Previous/natural advance), missing/known-failed tracks are skipped deterministically while preserving the red marking in the queue.

## Data Flow (macOS)

1. User picks a folder (persisted by `LibraryService`).
2. Controller calls `LibraryBrowser.listFileSystem()` to read folders/files directly from disk.
3. UI renders folders/files; **Play All** uses the existing recursive scan in `AudioPlayerProvider`.

## Rationale

- Removes storage and MediaStore logic from `LibraryPanel` to keep the widget focused on presentation.
- Enables unit testing of the folder-building logic (`LibraryBrowser`) without Flutter bindings.
- Maintains feature parity: Android uses MediaStore; macOS keeps filesystem browsing with security-scoped bookmarks.
