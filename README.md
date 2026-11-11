# PaperFront

A Catppuccin Mocha book and document reader for iOS 26, built with SwiftUI and Liquid Glass.

## Features

- **Library** with separate *Books* and *Documents* shelves, search, covers and reading progress.
- **Import** from Files, from a URL (direct links, or web pages saved as readable documents), or via "Open in…".
  Formats: PDF, EPUB, TXT, Markdown, RTF, HTML and images. Everything except PDF is typeset into a paginated PDF, so every format reads the same way.
- **New Document** – write or paste text and keep it as a document.
- **Real page-turning** – the system page-curl transition (the same one Apple Books uses), with true two-page spreads on iPad in landscape.
- **Highlights** – drag across text; tap a highlight to add a note, recolour or delete it.
- **Drawing** – PencilKit pen, marker and eraser with undo/redo; finger or Apple Pencil.
- **Secret annotation layer** – highlights and drawings are stored in a sidecar file (`annotations.json`) and drawn on top of the page. The imported file is never modified.
  You can hide the layer, export an annotated copy (standard PDF highlight/ink annotations that work in other apps), or explicitly *bake* the layer into PaperFront's copy.
- **Mocha Night** page tint (with an Original Paper option) and Liquid Glass controls throughout.

## Build

Requires Xcode 26 or later (iOS 26 SDK, for Liquid Glass).

1. Open `PaperFront.xcodeproj`.
2. Select the *PaperFront* target → *Signing & Capabilities* → choose your team.
3. Run on a device or simulator.

The `Build` GitHub Action compiles the app for the iOS Simulator on every push.

## Layout

```
PaperFront/
  Theme/     Catppuccin Mocha palette
  Model/     LibraryItem, Highlight
  Store/     LibraryStore, AnnotationStore, Router
  Import/    Converters (text/Markdown/HTML/RTF/EPUB/image → PDF)
  Reader/    Page-curl controller, page view, annotation layers, exporter, reader UI
  Library/   Tabs, shelves, import sheets
Config/Info.plist
```
