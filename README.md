# AI FileRenamer

A macOS menu bar app that watches folders and uses LLMs to give new files
descriptive names. Drop a photo in, and it becomes
`2026-11-19-golden-retriever-in-snow.jpg`. Drop in a markdown report, and it
becomes `quarterly-revenue-report.md`.

Built as a Swift Package — no Xcode project needed.

## How it works

```
new file appears
      │
      ▼
classify (extension) ──► image  ──► routed to your "image" provider (vision)
                    │            text  ──► routed to your "text" provider
                    └────────────────► anything else: ignored
      │
      ▼
provider returns a name stem  →  sanitized (kebab-case / camelCase / Title Case, ≤40 chars)
      │
      ▼
auto-approve on?  ──►  rename now (notify)
     no             ──►  show "old → new" in the menu bar; approve from there
      │
      ▼
logged (last batch undoable)
```

**Any number of providers, any routing.** A provider is just an
OpenAI-compatible chat endpoint (OpenAI, Groq, OpenRouter, llama.cpp, ollama,
…). You decide which one names images and which one names text — the same
model for both, or two different ones. If the image provider is unreachable,
photos fall back to a date-based name; if the text provider is down, text
files are left untouched.

**New files only, by default.** Adding a folder does not re-name what's
already in it. Files whose names already look human-chosen are left alone
(`IMG_1234.jpg`-style names, UUIDs, `Screenshot 2026-01-01…` etc. get renamed).
If you want a folder re-named anyway, there are explicit ways below.

## Requirements

- macOS 13+
- Swift 5.9+ (ships with Xcode)

## Build

```sh
./make_app.sh
```

This builds release binaries and assembles:

- `FileRenamer.app` — the menu bar app (drag files onto its 📎 icon to
  rename them impromptu)
- `~/Library/Services/AI FileRenamer.service` — the Finder Services helper,
  built directly into `~/Library/Services/` so it shows up in Finder's
  right-click → Services menu (keeping two copies with the same bundle ID
  elsewhere would confuse LaunchServices, so it lives in exactly one place)

## Run

```sh
open FileRenamer.app
```

(A paperclip 📎 appears in the menu bar. It starts with no folders — that's
by design, yours are yours to pick.)

> Note: run the `.app` bundle, not the bare binary — a bare process launched
> from a terminal doesn't get a menu bar item.

## First run

1. **Menu bar → Add Folder…** and choose a folder to watch.
2. **Menu bar → Settings…**
   - **Providers:** add one or more. Each needs a name, a base URL, an API
     key, a model name, and (if it can see images) the vision checkbox.
     - *OpenAI:* `https://api.openai.com/v1` / `sk-…` / `gpt-4o` / vision ✓
     - *Local llama.cpp or ollama:* `http://your-host:port` / any key / your model
     - **"Import my local setup…"** pre-fills anything it can find already
       on this machine (an OpenAI key in `OPENAI_API_KEY` or `~/new_openai_key`,
       or a pi `~/.pi/agent/models.json` endpoint). It never sends your keys
       anywhere; it just reads them off this machine.
   - **Routing:** pick which provider names images, and which names text.
   - **Naming style:** how names are shaped (see below).
   - **Save.**
3. Drop a file into the watched folder. Either it renames itself (if that
   folder is set to auto-approve) or it appears under **Pending approval** in
   the menu.

## Naming style

Configured once, in Settings (not per prompt):

| Knob        | Options                                            |
|-------------|----------------------------------------------------|
| Date prefix | Off · Images only · All files                       |
| Case        | Kebab-case · camelCase · Title Case                 |
| Words       | 2–4 · 3–6 · 4–8                                     |
| Custom rules| free text appended to the prompt, e.g. "start with the location" |

## Renaming on demand (not just watched folders)

Four ways to point the app at files directly:

- **Drag files onto the 📎 menu bar icon** — the recommended way for
  impromptu renames. Select one or many files in Finder, drag them onto the
  icon (it turns into 📥 while hovering), drop. The whole drop is one batch,
  processed one file at a time, and one "Undo Last Batch" reverts it all.
- **Menu bar → Rename Files… (⌘R)** — pick one or many files in a file
  picker. Anything is fair game, not just watched folders.
- **Finder: right-click a file → Services → "Rename with AI FileRenamer"** —
  works for one or many files. You need to run `./make_app.sh` once (it
  installs the service into `~/Library/Services/`).
- **Menu bar → folder → "Rename all files in folder…"** — re-scan a watched
  folder and rename everything in it, including files that look already-named.

All four force naming: they bypass the "new files only" and "looks already
named" heuristics. Files inside a watched folder follow that folder's
auto-approve setting; files from anywhere else always land in the pending
approval list.

## Per-folder settings

Each watched folder has its own **Auto-approve** toggle in its menu-bar
submenu. Leave it off to review every rename; turn it on for folders where
you trust the model.

## Activity

The menu bar shows the last few events; **Activity…** opens the full log
(what got queued, named, skipped, and why — including failures like a
provider being down).

## Privacy

- Keys are stored only in `~/Library/Application Support/FileRenamer/settings.json`
  (file mode 600). They are never read from or written into the repository.
- Images are downscaled to ~1 MP before a vision call and sent only to the
  provider you route images to.
- Text files are read locally, truncated to 4 KB, and sent only to the
  provider you route text to.
- Nothing is sent anywhere you haven't pointed a provider at.

## Data locations

| What                     | Where                                                        |
|--------------------------|--------------------------------------------------------------|
| Settings + API keys      | `~/Library/Application Support/FileRenamer/settings.json`    |
| Rename history / undo    | `~/Library/Application Support/FileRenamer/state.json`       |

## For contributors (Brandon)

Clone, `./make_app.sh`, `open FileRenamer.app`, add your own folders and
providers in Settings. No secrets live in this repo — if you find one, tell
Grant, delete it, and we rotate the key.

## License

MIT
