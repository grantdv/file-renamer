# AI FileRenamer

A macOS menu bar app that watches folders and uses LLMs to give new files
descriptive names. Drop a photo in and it becomes
`2026-11-19-golden-retriever-in-snow.jpg`. Drop in a tax form PDF and it
becomes `form-1099-nec-2025.pdf`.

- **Menu bar app** (📎) — no dock icon, no main window
- **Watches folders** for new files; per-folder auto-approve
- **Any OpenAI-compatible LLM** — add as many providers as you like and
  route images and text to whichever ones you want (OpenAI, Groq,
  OpenRouter, llama.cpp, ollama, LM Studio, …). A local model means file
  contents never leave your machine.
- **Images, text, and PDFs** — PDFs are named from their extracted content,
  with the PDF's Title metadata as a fallback; scanned/protected PDFs are
  left alone
- **Rename on demand**: drag files onto the 📎 icon, **Rename Files…**,
  Finder right-click → **Services**, or "Rename all files in folder…"
- **Review before it happens** by default: pending suggestions with
  approve / approve-all / undo, plus a full activity log with reasons
- **No secrets in this repo** — keys live in your Application Support

## Quick start

```sh
./make_app.sh          # build the .app + install the Finder service
open FileRenamer.app   # 📎 appears in the menu bar
```

1. **Menu bar → Add Folder…** — pick a folder to watch.
2. **Menu bar → Settings…** — add provider(s) (name, base URL, key, model,
   vision ✓), choose routing (which provider names images / text), and
   pick a naming style. "Import my local setup…" pre-fills what it can
   find already on your machine.
3. Drop a file in. Auto-approve is off by default, so it lands in
   **Pending approval** in the menu — click it (or **Approve All**) to rename.

Requirements: macOS 13+, Swift 5.9+ (ships with Xcode).

## Documentation

- **[docs/USER_GUIDE.md](docs/USER_GUIDE.md)** — user help: setup, daily
  use, naming style, undo, troubleshooting, privacy
- **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** — developer doc:
  targets, pipeline, FSEvents details, persistence, build system, gotchas

## For contributors (Brandon)

Clone, `./make_app.sh`, `open FileRenamer.app`, add your own folders and
providers in Settings. No secrets live in this repo — if you find one,
tell Grant, delete it, and we rotate the key.

## License

MIT
