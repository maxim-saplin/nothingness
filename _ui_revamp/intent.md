# UI Revamp — Intent

This document captures *what* we want the UI revamp to achieve and *why*. It is not a plan or a spec; concrete designs, prototypes, and implementation steps live elsewhere.

## What we are doing

We are redoing the app's UI from the ground up. The redo is **structural**, not a re-skin: it changes how the user finds and plays files, not just the colours.

## The three axes

The look and behaviour of the app are determined by three orthogonal, independently selectable factors:

1. **Theme** — the visual language of the *common, shared* elements: file browser, settings sheet, list rows, buttons, typography, palette. Examples (drawn from `ui_ideas/variants/`): Void, Paper, Phosphor, Synthwave, …
2. **Theme variant** — `dark` / `light` / `follow system`. Every theme must support both dark and light.
3. **Home screen** — the main view shown when nothing else is open. The existing four stay:
   - **Spectrum** (animated bars)
   - **Polo** (image-coordinate skin with LCD font)
   - **Dot** (minimal pulsing dot)
   - **Void** (new — minimal text track name, added with this revamp)

Themes and home screens are independent. Choosing a theme does not lock the home screen, and vice versa. The user can combine them freely (subject to a theme declaring which home screens it supports, if we end up needing that).

## Starting point: Void

Phase 1 ships the **Void** theme in both dark and light variants, together with the new Void home screen. Once the theme infrastructure proves itself with Void, we add Paper (and others) by authoring palette + variants — not by editing every widget.

The Void design reference is `ui_ideas/variants/void.html`. We will deviate from it deliberately where ergonomics or our file-first principle demand it.

## File-first principle

The app exists to find and play *files* on the device. No genre, artist, or album abstractions are introduced. The existing `LibraryController` + `LibraryBrowser` model layer is already aligned with this and stays.

What needs work is the **layout and ergonomics** of the browser:

- Search must exist. On phones the search box belongs in the **bottom thumb zone**, not at the top.
- The relationship between browsing and playing should feel direct: the file list you're looking at is, by default, what plays next.
- Cross-folder queueing, "now playing" visibility, and search scope are open UX questions to be resolved via prototypes before implementation.

## Out of scope

- Dropping or replacing the existing Spectrum / Polo / Dot home screens.
- Introducing genre / artist / album / playlist-as-data-model concepts.
- Backend audio changes (`PlaybackController`, `SoLoudTransport`, `audio_service` integration) — the revamp is UI/UX only.
- Rewriting `SettingsService` persistence — settings move under the new theming model but the storage layer is reused.

## Definition of done for phase 1

- A theme abstraction exists (likely a Flutter `ThemeExtension` + per-theme widget kit) such that `LibraryPanel` and `SettingsScreen` get their colours, typography, and component styling from the active theme rather than hardcoded values.
- The Void theme is implemented in both dark and light variants.
- The Void home screen is implemented and selectable.
- Spectrum / Polo / Dot still work and pick up the active theme where applicable (palette, fonts, common widgets).
- A dark / light / follow-system selector exists in settings.
- The new browser layout reflects the file-first principle and the bottom-search ergonomic, with a structural approach chosen from prototype review.
