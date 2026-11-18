# FileRenamer

A macOS menu bar app that watches folders and uses LLMs to give new files
descriptive names. Drop a photo in, and it becomes
`2025-07-11-golden-retriever-in-snow.jpg`. Drop in a markdown report, and it
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
provider returns a name stem  →  sanitized (kebab-case, ≤40 chars)
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

## Requirements

- macOS 13+
- Swift 5.9+ (ships with Xcode)

## Build

```sh
swift build
```

## Run

```sh
swift run
```

A paperclip (📎) appears in the menu bar. It starts with no folders — that's
by design, yours are yours to pick.

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
   - **Save.**
3. Drop a file into the watched folder. Either it renames itself (if that
   folder is set to auto-approve) or it appears under **Pending approval** in
   the menu.

## Per-folder settings

Each watched folder has its own **Auto-approve** toggle in its menu-bar
submenu. Leave it off to review every rename; turn it on for folders where
you trust the model.

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

Clone, `swift run`, add your own folders and providers in Settings. No
secrets live in this repo — if you find one, tell Grant, delete it, and we
rotate the key.

## License

MIT
