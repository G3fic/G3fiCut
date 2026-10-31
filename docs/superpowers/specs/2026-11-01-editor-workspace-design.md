# Editor Workspace and Media Intake — Sub-project Specification

**Status:** Draft for approval  
**Parent:** [GifCut v0.3.79 Multimedia Editing Workspace](2026-11-01-editor-v0.3.79-design.md)

## Intent

Reorganize the desktop editor to match the supplied CapCut screenshots while making the left media library a real import surface for project assets.

## Goals

- Replace the permanent left tool rail with compact category tabs at the top of the left dock: Media, Audio, Text, Stickers, Effects, Transitions, Captions and Filters.
- Keep the editor workspace ordered left-to-right as library, preview, right inspector. The bottom timeline spans the whole window.
- Make Media accept multiple video/image/audio imports from the file picker and multiple files dropped from Windows Explorer.
- Show imported assets in a usable library with type-specific thumbnails, filename, duration and clear missing-file states.
- Let users drag a media-library card to a compatible track to create a timeline clip.
- Keep the existing resizable panel behavior and protect useful minimum widths.

## Non-goals

- Online asset marketplace, generated media, cloud sync, or a full AI panel.
- Implementing actual multi-track editing/rendering inside the workspace layer; that is owned by the multimedia-engine spec.
- Showing inert buttons for tools that are not implemented.

## Approach

Keep Flutter and the current docked desktop shell. Extract workspace categories, media library cards, import classification and native drop handling into focused widgets/services. Use `file_picker` for explicit multi-file selection and evaluate/pin the stable `super_drag_and_drop` package for native external file drop. Keep import classification independent of the UI so mixed drops can accept valid assets while reporting unsupported ones.

## Layout contract

1. App header includes the visible product/version label.
2. The left dock starts with horizontal category tabs as shown in reference two. Subcategories and asset cards appear below the tabs.
3. The player occupies the center.
4. The inspector is docked at the far right.
5. The timeline is below the entire workspace, not beneath only the preview.
6. Timeline ruler and clip content start at the left edge. Track labels are compact overlays / header controls, not a permanent 112 px spacer.

## Acceptance

- Widget tests verify category switching, panel ordering, asset card rendering, import actions, right dock inspector placement and timeline left alignment.
- Drop classification tests cover mixed valid/invalid files, multiple files, duplicate paths and unsupported extensions.
- Windows manual test: drag two video files, two image files and two audio files from Explorer; all supported files appear in the Media library and remain local.
- Resizing the library and inspector does not cause overflow or collapse the preview below its minimum useful width.

## Constraints

- Keep local-first processing; source files are not uploaded.
- Preserve existing desktop shortcuts, project open/save and export actions.
- External drag-and-drop must work on Windows; do not claim desktop-wide support for other platforms without tests.
