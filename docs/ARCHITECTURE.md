# AI FileRenamer — Architecture

Developer documentation for the codebase. User-facing help lives in
[USER_GUIDE.md](USER_GUIDE.md).

## Layout

A Swift Package with **three targets**:

```
Package.swift                     swift-tools-version:5.9, macOS 13+
Sources/
  FileRenamerCore/                shared library
    Models.swift                  AppSettings, Provider, FolderConfig,
                                  NamingStyle + enums, Suggestion,
                                  RenameRecord, ActivityEvent, StoreState
    Naming.swift                  extension → FileKind classification,
                                  prompts, sanitize/case, datePrefix,
                                  looksAutoNamed(), pdfText(), pdfTitle()
    NamingEngine.swift            propose() — the per-file decision pipeline
    AI.swift                      OpenAI-compatible chat client (URLSession,
                                  base64 image_data for vision), max_tokens 512
    ImageTool.swift               downscale to 1024 px / ~1 MP JPEG → base64
    FolderWatcher.swift           FSEvents stream per folder (0.5 s latency)
    Store.swift                   singleton state machine: settings, queue,
                                  pump, processNext, rename/undo, scan,
                                  activity, persistence
    UI.swift                      notifications + menu refresh glue
  FileRenamer/                    the menu bar executable
    main.swift                    NSApplication, .accessory policy (LSUIElement)
    AppDelegate.swift             menu bar item + menu construction,
                                  openFiles() drag entry point, actions
    DropTargetView.swift          transparent NSView over the status button;
                                  hitTest → nil (clicks pass through),
                                  registerForDraggedTypes([.fileURL])
    SettingsController.swift      settings window (providers, routing,
                                  naming style)
    ProviderRow.swift             one provider row (two-line NSView)
    ActivityWindow.swift          full activity log window
  FileRenamerService/             Finder Services helper executable
    main.swift                    ServiceDelegate,
                                  @objc RenameWithAIFileRenamer(_:)
make_app.sh                       THE build entry point (see Build)
```

**Visibility rule:** `FileRenamerCore` exposes only what the two
executables need: `Store`, `UI`, and the model types are `public`.
`Naming`, `NamingEngine`, `NamingResult`, `AI`, `ImageTool`, and
`FolderWatcher` are internal — the service target never names anything
itself, it just hands file URLs to `Store`.

## The pipeline

```
FSEvent (0.5 s debounce)          drag-drop / Rename Files… /
   │                              Finder service / Rename-all
   ▼                                          │
Store.scan(folder, force)  ◄──────────────────┘
   │  for each regular, non-dot file:
   │    in processed?  in inFlight?  unsupported ext?
   │    birth < folder.activatedAt? (unless force)
   ▼
queue  ──►  pump()  (one MainActor task, sequential)
   │
   ▼
NamingEngine.propose(url, settings, autoApprove, batchID, forceNaming)
   │  1. kind = Naming.kind(ext)          (.unsupported → skipped)
   │  2. !force && looksAutoNamed(stem)?  → skipped "already has a human name"
   │  3. image: ImageTool.downscale → base64 → vision provider
   │     text : first 4 000 chars → text provider
   │     pdf  : Naming.pdfText (PDFKit, first 5 pages)
   │             empty → Naming.pdfTitle (CGPDFDocument C API, /Title)
   │             still empty → skipped "no extractable text in PDF"
   │  4. sanitize(model reply, style) → kebab/camel/title, ≤40 chars
   │     empty stem (provider down/parse fail):
   │        image → date-based fallback name
   │        text/pdf → skipped (file left untouched)
   │  5. same name as current? → skipped "suggested name unchanged"
   ▼
Store.handle(Suggestion)
   ├─ autoApprove → rename()            (moveItem, conflict → -2, -3 …)
   │                  → records.append, processed.insert, notify
   └─ else          → pending.append (in-memory only), menu shows "old → new"
```

Everything user-visible goes through `Store.log(kind, message)` →
`ActivityEvent` array (capped at 300) → `saveState()` + menu refresh.
Undo restores the **last batch** (batchID groups one drop / one approval run).

### Why sequential

`pump()` drains the queue with one `await` per file so provider rate
limits are never exceeded and ordering in the activity log matches
reality. 29 files overnight ≈ a few seconds each, no throttling seen.

## FSEvents details

- One stream per folder, `kFSEventStreamCreateFlagFileEvents | NoDefer`,
  0.5 s latency, started at `kFSEventStreamEventIdSinceNow` — so **files
  that already exist when the watcher starts are invisible to it by
  design**. That's the whole "new files only" mechanism, reinforced by
  the `activatedAt` birth-time gate in `scan()`.
- `activatedAt` is persisted per folder (a `Date`, JSON-encoded as
  `timeIntervalSinceReferenceDate` — **2001-based, not epoch**). Set to
  `Date()` when the folder is added; legacy/seeded folders may hold `0`.
- Any event triggers a **full rescan of the folder** (cheap: one
  `contentsOfDirectory`), which also gives free retry of previously
  skipped files (they're never added to `processed`).
- If `contentsOfDirectory` fails (e.g. permission), it's logged as an
  activity error, not silently dropped.

## PDF handling

- Classified as **text** (routed to the text provider).
- `Naming.pdfText`: PDFKit, first 5 pages concatenated, 4 000-char cap.
- `Naming.pdfTitle`: `PDFDocument.documentRef` → CGPDFDocument C API
  (`cg.info` → `CGPDFDictionaryGetString(info, "Title", …)` →
  `CGPDFStringCopyTextString`). Swift's PDFKit metadata surface turned
  out to be a property-only bridge; the C API is the reliable path.
- Order: text first, Title metadata fallback, else skip. Files are never
  modified, only renamed.

## Persistence

Both files in `~/Library/Application Support/FileRenamer/`, mode 600:

- **settings.json** — providers, routing, naming style, folders, paused.
  Written on every settings mutation. Tolerant decoders: unknown/missing
  naming enums fall back to safe defaults (`init(from:)`s throughout
  `Models.swift`).
- **state.json** — `processed` set, `records` (undo, capped 500),
  `events` (activity, capped 300). Written after every log/queue event.
  **`pending` is deliberately NOT persisted** — it's a transient review
  list; quitting discards it. (Open question: persist across restarts?)

## Build system

`make_app.sh` is the single entry point. It:

1. `swift build -c release`
2. assembles `FileRenamer.app` (Info.plist: `LSUIElement`,
   `NSAppTransportSecurity`/`NSAllowsArbitraryLoads = true` — required,
   local LLM endpoints are plain `http://`)
3. builds the service **directly into** `~/Library/Services/AI FileRenamer.service`
   (with the NSServices plist: `NSSendFileTypes [public.file-url]`)
4. ad-hoc signs both, `lsregister -f`, `killall pbs`

**Do not build a second copy of the service anywhere else** — LaunchServices
resolves NSServices by bundle ID, and a duplicate registration (e.g. a
project-dir copy) makes the menu item vanish. One copy, in
`~/Library/Services/`.

## Gotchas learned the hard way

- **Qwen3-style reasoning models** burn `max_tokens` on hidden reasoning
  before the visible answer → `max_tokens = 512`, not 80.
- **`init(rawValue:)` must not recurse** — the naming enums use tolerant
  `init(from: Decoder)` instead, else a bad value in settings.json
  crashes decoding (and a self-recursive rawValue init is a silent
  infinite-loop candidate).
- **Bare-binary runs inherit the terminal's TCC context**; a
  `open`-launched `.app` has its own. When in doubt, test via `open`.
- **NSLog vs `Store.log()`** — `log()` is the in-app activity log (the
  only place users see anything). NSLog exists only for real failure
  paths (save errors, FSEventStreamCreate failure).
- **`Date` in JSON is 2001-based** (`timeIntervalSinceReferenceDate`
  default strategy). Writing epoch seconds yields year ~58 000.
- **macOS 26.x:** `NSService`/`NSServiceRequest` are private — the Finder
  helper is a separate executable that instantiates its **own**
  `Store` (same on-disk `AppSettings`, so it can propose real names)
  and exits ~2.5 s later.
- **KNOWN GAP (service path):** `pending` is in-memory only, so
  suggestions created by the Finder service process for non-auto-approve
  files die with that process — the menu bar app never sees them
  (state.json is read once at launch, never re-read). Auto-approve
  files are fine (renamed directly, event shared via state.json on next
  app launch). Fix options on the table: persist `pending` in
  state.json + merge on menu open, or have the service hand off
  otherwise. See USER_GUIDE troubleshooting until fixed.

## Extending

- **New file type:** add the extension in `Naming.kind(of:)` + a branch
  in `NamingEngine.propose`.
- **New case style / word count:** enum + `Naming.sanitize`/`range` +
  one popup item in `SettingsController`.
- **New activity kind:** just a string; `ActivityWindow` shows them all.
