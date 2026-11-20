# What is AI FileRenamer?

A tiny menu bar app that watches your folders and gives new files
descriptive names using a language model. Drop a photo in and it becomes
`2026-11-19-golden-retriever-in-snow.jpg`. Drop in a tax form PDF and it
becomes `form-1099-nec-2025.pdf`.

It lives in your menu bar (a paperclip 📎). It does nothing until you point
it at a folder or a file — nothing is pre-configured.

---

## Installing

You need a Mac with Xcode (or the command line tools) installed.

```sh
git clone <repo-url> file-renamer
cd file-renamer
./make_app.sh
open FileRenamer.app
```

`make_app.sh` builds the app and installs a Finder helper (see
"Renaming on demand" below). A 📎 appears in your menu bar.

> Run `open FileRenamer.app` — launching the bare binary from a terminal
> works but won't show the menu bar icon.

To update after pulling new code, just re-run `./make_app.sh` and
`open FileRenamer.app` again.

---

## First run: 3 things to set up

> **Want exact, copy-paste values for every field** (OpenAI, Ollama,
> llama.cpp, LM Studio, other OpenAI-compatible servers)? Follow
> **[SETUP.md](SETUP.md)** — this section is the short version.

### 1. Providers (the brains)

**Menu bar → Settings… → Providers.** A provider is any
OpenAI-compatible chat endpoint. Add one or more; each needs:

| Field | What to put |
|---|---|
| Name | Anything, e.g. `OpenAI` or `Local LLM` |
| Base URL | e.g. `https://api.openai.com/v1`, `http://your-server:8188/` |
| API key | Your key for that endpoint (can be anything if the endpoint doesn't check) |
| Model | e.g. `gpt-4o` |
| Vision | ✓ only if the model can see images (needed for naming photos) |

Examples that are known to work:

- **OpenAI** — `https://api.openai.com/v1`, your `sk-…` key, `gpt-4o`, vision ✓
- **Local llama.cpp / ollama / LM Studio** — `http://host:port`, any key, your model
- **Groq, OpenRouter, Together…** — their OpenAI-compatible endpoints

There is an **"Import my local setup…"** button that pre-fills providers
from things already on your machine (an OpenAI key in `OPENAI_API_KEY` or
`~/new_openai_key`, or a pi `~/.pi/agent/models.json` endpoint). It only
reads; it never sends your keys anywhere.

### 2. Routing (who names what)

In Settings → **Routing**: pick which provider names **images** and which
names **text** (including PDFs). The same provider for both is fine — two
different ones is fine too (e.g. a local model for text, OpenAI for photos).

**If a provider is down:** photos fall back to a date-based name like
`2026-11-19-photo.jpg` (never lost, never blocked); text/PDF files are left
untouched and logged as skipped. Nothing ever gets half-renamed.

### 3. A folder to watch

**Menu bar → Add Folder…** and pick a folder. From then on, files that
*arrive* in that folder get named. Files already sitting there are not
touched (see "Rename all files in folder…" if you want otherwise).

---

## What it can name

| Kind | Extensions |
|---|---|
| **Images** (sent to your image provider as a downscaled ~1 MP image) | jpg, jpeg, png, heic, heif, webp, gif, tiff, bmp, dng, cr3 (RAW decodes fine) |
| **Text** (first ~4 KB read locally, sent to your text provider) | txt, md, markdown, csv, json, log, ini, toml, yaml, yml, xml, swift, py, js, ts, html, css, sh, rb, go, rs, c, h, cpp |
| **PDFs** (first 5 pages of text extracted locally, sent to your text provider) | pdf |

Anything else is ignored. PDFs deserve a note: the app extracts the PDF's
own text and names the document from its *content*. If a PDF has no
extractable text (scanned page or protected), it first tries the PDF's Title
metadata; if that's empty too, the file is left alone and the skip is logged.
**It never damages or modifies files — it only renames.**

Files whose names already look human-chosen are left alone
(`IMG_1234.jpg`-style, UUIDs, `Screenshot 2026-01-01 …` and similar are all
renamed). Explicit actions (below) override this.

---

## Daily use

### Auto-watching

New file lands in a watched folder → the app:

1. classifies it (image / text / PDF / ignore)
2. asks the routed provider for a short descriptive name
3. sanitizes it (your case style, word count, optional date prefix, max 40 chars)
4. **auto-approve on for that folder?** → renames immediately and notifies you
   **off** (default) → it appears under **Pending approval** in the menu

Files are processed **one at a time**, so your rate limits are respected and
a slow model just means a queue, not chaos.

### Pending approval

In the menu, each suggestion appears as `old name → new name`; hover it for
a submenu:

- **✓ Approve** — rename it
- **✕ Discard** — remove it from the list. Discarding is remembered: the
  app won't re-propose that file on later scans (an explicit rename —
  drag-drop, ⌘R, or "Rename all files in folder…" — still can name it)

**Approve All (n)** takes the whole list; **Clear All Pending (n)** purges
it (each entry also counts as discarded, so they don't come back). If you
simply leave a suggestion unapproved, it stays in the list until you
discard or clear it. Pending items live in memory: if you quit the app
without acting, they're discarded and the files remain untouched.

### Undo

Every rename batch (one drop, one approval run) can be reversed with
**Undo Last Batch** (⌘Z in the menu).

### Pause / Resume

**⏸ Pause** freezes all watching and pending work instantly. Nothing is
lost: queued and pending items wait until you hit **▶ Resume**.

### Per-folder settings

Each folder has its own submenu in the menu:

- **Auto-approve** — flip it on for folders you trust the model with
  (e.g. a downloads folder full of receipts), leave it off everywhere else.
- **Rename all files in folder…** — re-scan and name *everything* in that
  folder, including files that look already-named. This is how you process
  a folder of backlogged files.
- **Remove folder** — stop watching it.

---

## Renaming on demand (not just watched folders)

Four ways to point the app at files directly. All four **force naming**
(bypass the "new files only" and "looks already named" heuristics). Files
inside a watched folder follow that folder's auto-approve setting; files
from anywhere else always land in Pending approval.

1. **Drag files onto the 📎 icon** — the recommended impromptu method.
   Select one or many files in Finder, drag onto the icon (it turns into 📥
   while hovering), drop. The whole drop is one batch; one Undo reverts it all.
2. **Menu → Rename Files… (⌘R)** — pick files in a file picker.
3. **Finder right-click → Services → "Rename with AI FileRenamer"** — one or
   many files. (If it's missing, see Troubleshooting.)
4. **Folder submenu → "Rename all files in folder…"** — for a whole backlog.

---

## Naming style

One global setting, **Settings → Naming style** — knobs, not prompts:

| Knob | Options | What it does |
|---|---|---|
| Date prefix | Off · Images only · All files | Prepends e.g. `2026-11-19-` |
| Case | Kebab-case · camelCase · Title Case | `my-receipt.pdf` · `myReceipt.pdf` · `My Receipt.pdf` |
| Words | 2–4 · 3–6 · 4–8 | How descriptive the name gets |
| Custom rules | free text | Appended to the prompt, e.g. *"start with the location"* |

Names are always capped at 40 characters and stripped of anything the
filesystem dislikes. If a suggested name equals the current one, nothing
happens (logged as "suggested name unchanged").

---

## Activity

- The menu itself shows the last few events.
- **Activity…** opens the full window: queued, proposed, renamed, skipped
  (with the *reason* — "provider down", "no extractable text in PDF",
  "already has a human name"), and errors. Every rename records which
  provider suggested the name.

---

## Troubleshooting

**"Rename with AI FileRenamer" isn't in Finder → Services.**
Re-run `./make_app.sh` (it installs the service into
`~/Library/Services/` and re-registers it). Log out and back in if it
still doesn't appear. Only *one* copy of the service should exist — that's
the one in `~/Library/Services/`.

**Finder Services named a file but there's nothing in Pending approval.**
Known limitation: the Finder service runs in its own short-lived process,
and its pending suggestions don't reach the menu bar app (they're cleared
when that process exits). Files in auto-approve folders are renamed
directly and are unaffected. Workaround until this is fixed: drag the
files onto the 📎 icon instead, or use **Menu → Rename Files… (⌘R)** —
those two paths hand off to the menu bar app correctly.

**A PDF was skipped: "no extractable text (scanned or protected)".**
Expected behavior for scanned-page PDFs with no Title metadata. Run the
scan through OCR first, or rename it manually.

**Nothing happens when I drop a file in the folder.**
- Is the app actually running (📎 in menu bar) and not Paused?
- Did the file arrive *after* the folder was added? (Existing files are
  only named via "Rename all files in folder…".)
- Open **Activity…** — it logs why a file was skipped or a provider failed.
- Check the folder still exists and you have access.

**Photos are getting `2026-11-19-photo.jpg`-style names.**
Your image provider is unreachable or isn't a vision model. Check the
provider's base URL/key/model and that Vision is ticked for it.

**Text files are being skipped with a provider error.**
Same diagnosis, for your text provider. The files are left untouched and
will be retried next time the app scans (e.g. after Resume, or a new file
arrives in the folder).

**The app was reinstalled/updated and a folder stopped working.**
macOS may ask for permission to access a folder the first time. Re-add the
folder via **Add Folder…** if it ever misbehaves after an update.

**Two apps named FileRenamer running?**
`pkill -x FileRenamer` and `open FileRenamer.app` once. Only one should run.

---

## Privacy

- API keys live only in
  `~/Library/Application Support/FileRenamer/settings.json` (mode 600).
  They are never in this repository.
- Images are downscaled to ~1 MP and sent **only** to your image provider.
- Text is read locally, truncated to ~4 KB, sent **only** to your text provider.
- Nothing goes anywhere you haven't pointed a provider at. A local model
  means the file contents never leave your machine.

## Where things live

| What | Where |
|---|---|
| Settings + API keys | `~/Library/Application Support/FileRenamer/settings.json` |
| History, undo, activity | `~/Library/Application Support/FileRenamer/state.json` |
| App bundle (built) | `<repo>/FileRenamer.app` |
| Finder service | `~/Library/Services/AI FileRenamer.service` |
