# Setup Guide

Everything you need to get AI FileRenamer working, with **exact values** for
every field. If you follow this top to bottom you should have a renamed
file in about 10 minutes.

---

## 1. What you need before starting

- macOS 13+ with the Xcode Command Line Tools installed
  (`xcode-select --install` if you don't have them)
- An LLM you can talk to over HTTP. Any **OpenAI-compatible** server works:
  a local one (Ollama, llama.cpp, LM Studio, vLLM) or a cloud API
  (OpenAI, DeepSeek, Groq, OpenRouter, …)
- For **photos**: a model that can *see* (a "vision" model). Without one,
  photos still get renamed, but with a plain date name like
  `2026-01-15-photo.jpg` instead of a description. PDFs, markdown, and
  other text files never need vision.

That's it. No accounts are required if you run a local model.

---

## 2. Build and run

```bash
git clone git@github.com:<you>/file-renamer.git
cd file-renamer
./make_app.sh          # builds the app + installs the Finder service
open FileRenamer.app
```

A paperclip 📎 appears in the menu bar. (If nothing appears, the app was
launched from a terminal — it must be started with `open`.)

---

## 3. Open Settings

Click the 📎 menu bar icon → **Settings…** (or ⌘,).

The window has three sections: **Providers**, **Routing**, **Naming style**.
Do them in that order.

---

## 4. Add a provider (the LLM part)

Each provider is one row with five fields:

| Field | What goes in it |
|---|---|
| **Name** | Anything. A label you'll recognize in the Routing dropdowns. |
| **Base URL** | The server's OpenAI-compatible root. The app appends `/chat/completions` to whatever you type, so for most servers this ends in `/v1`. |
| **Model** | The exact model name/ID that server serves. |
| **API Key** | The server's key. Local servers usually ignore it — a placeholder like `ollama` is fine. |
| **✓ vision** | Check **only** if this model can see images. This is what allows the row to be used for the Images route. |

Press **+ Add Provider** to add a row, fill it in, and press **Save** at the bottom of the window. (There's also an **Import my local setup…** button that pre-fills a provider from a key/endpoint it finds already on this machine — handy if you've run these tools before.)

### Scenario A — OpenAI (easiest, handles both photos and text)

Get a key at <https://platform.openai.com/api-keys>.

| Field | Value |
|---|---|
| Name | `OpenAI` |
| Base URL | `https://api.openai.com/v1` |
| Model | `gpt-4o` |
| API Key | `sk-...` (yours) |
| vision | **checked** |

One provider is enough: route both Images and Text files to it.
(Other vision-capable options: `gpt-4o-mini` — cheaper, or `gpt-4.1`.)

### Scenario B — Ollama on this Mac (local, free)

```bash
brew install ollama
ollama serve &            # runs on http://localhost:11434
ollama pull llama3.2      # text + vision in one model
```

| Field | Value |
|---|---|
| Name | `Ollama` |
| Base URL | `http://localhost:11434/v1` |
| Model | `llama3.2` |
| API Key | `ollama` (anything — Ollama ignores it) |
| vision | **checked** (`llama3.2` can see; so can `llava`, `qwen2.5vl`) |

If you pull a non-vision model instead (e.g. `llama3.1`), leave the
checkbox off and use the provider for the Text route only.

### Scenario C — llama.cpp server (Grant's setup, for reference)

Grant's machine runs llama.cpp serving a Qwen GGUF. If you're on his
network you can point straight at it:

| Field | Value |
|---|---|
| Name | `Local LLM` |
| Base URL | `http://<server-host>:8188` |
| Model | `your-model-id` |
| API Key | whatever the server expects (it's set in Grant's setup) |
| vision | **unchecked** (this Qwen build is text-only) |

Running your own llama.cpp server instead?

```bash
llama-server -m your-model.gguf --port 8188
```

Then Base URL `http://localhost:8188` (llama.cpp accepts both
`/chat/completions` and `/v1/chat/completions`), Model = however the
server advertises the model (check the server's startup log — it prints
the model id).

### Scenario D — LM Studio (local, GUI)

Start the local server in LM Studio (Developer tab → Start Server,
default port 1234), with any model loaded:

| Field | Value |
|---|---|
| Name | `LM Studio` |
| Base URL | `http://localhost:1234/v1` |
| Model | the model ID LM Studio shows (e.g. `llama-3.2-11b-vision-instruct`) |
| API Key | `lmstudio` (anything) |
| vision | **checked** if you loaded a vision model (look for "vision" in its name) |

### Scenario E — Other OpenAI-compatible clouds

| Provider | Base URL | Example Model |
|---|---|---|
| DeepSeek | `https://api.deepseek.com/v1` | `deepseek-chat` (text) |
| Groq | `https://api.groq.com/openai/v1` | `llama-3.3-70b-versatile` (text) |
| OpenRouter | `https://openrouter.ai/api/v1` | `anthropic/claude-3.5-sonnet` (vision) |
| vLLM | `http://<host>:8000/v1` | whatever you launched it with |

### A two-provider setup (Grant's actual configuration)

- **Text files** (PDFs, .md, …) → the cheap local model:
  Name `Local LLM`, text-only, no cost, runs on your own hardware.
- **Images** → the cloud vision model:
  Name `OpenAI`, `gpt-4o`, vision checked.

You can have as many provider rows as you like; Routing (next section)
decides which handles what.

---

## 5. Routing

Two dropdowns at the top of the Settings window:

- **Images are named by:** → pick a provider **with the vision box checked**.
  If you pick one without vision (or it's down when a photo arrives), the
  photo gets the date-based fallback name (`2026-01-15-photo.jpg`) instead.
- **Text files are named by:** → any provider. PDFs, markdown, .txt,
  .csv, etc. all go through this route.

---

## 6. Add a folder to watch

Back in the 📎 menu: **Add Folder…** and pick a folder. It appears under the folder section of the menu, with its own submenu.

Two things to know:

- **New files only.** Adding a folder does *not* touch what's already in
  it. Existing files get named only if you explicitly choose
  **Rename all files in folder…** for that folder.
- **Auto-approve toggle** (per folder, in the menu): on = renames happen
  immediately; off = each name shows up as a pending suggestion you
  approve or discard one by one. Start with it **off** so you can see
  what the model comes up with, then flip it on for folders you trust.

---

## 7. Naming style

The Settings window has three dropdowns plus a text box (defaults are
sensible — you can skip this entirely):

| Knob | Default | Options |
|---|---|---|
| Date prefix | Images only | All files / Images only / Off |
| Case | Kebab-case | Kebab-case / camelCase / Title Case |
| Words | 3 to 6 | "2 to 4" / "3 to 6" / "4 to 8" words |

Plus a free-text **Custom rules** box: anything you type is appended to
the prompt, e.g. `start with the location of the photo`.
(Dates use `yyyy-MM-dd` — fixed for now.)

Final names look like: `2026-01-15-airstream-trailer-in-field.jpg`

---

## 8. Test it (2 minutes)

1. Drop a text file into the watched folder — the fastest end-to-end
   check:
   ```bash
   echo "Invoice from Acme Corp: 120 units of steel, total $4,860.00, due net 30, PO A-1142." > /tmp/receipt.txt
   mv /tmp/receipt.txt /path/to/your/watched-folder/
   ```
   (any `.txt`/`.md` with a few sentences works)
2. Click the 📎. Within a few seconds the file shows under
   **Pending approval (n)** (auto-approve off) or it's already renamed (on).
   Hover a pending item to get **✓ Approve** / **✕ Discard**.
3. Check **Activity…** for the rename entry.

Then test a photo: copy any `.jpg` into the folder. If you have a vision
provider it gets a descriptive name; without one you'll see
`2026-01-15-photo.jpg` in the activity log — that's the documented
fallback, not an error.

---

## 9. Troubleshooting

Symptoms are logged in **Activity…**, so look there first.

| Symptom | Cause / fix |
|---|---|
| "connection refused" / provider errors in Activity | Server not running, or wrong host/port in Base URL. Test in a browser: the Base URL should serve an OpenAI-compatible API. |
| 401 / unauthorized | Wrong API Key. |
| 404 on every file | Base URL probably needs `/v1` (or has it twice). The app calls `<Base URL>/chat/completions`. |
| Photos all become `2026-01-15-photo.jpg` | Images are routed to a provider without the vision box checked (or it's failing). See the Activity log for the underlying error. |
| Names come back empty | Rare with local models — see ARCHITECTURE.md (the `max_tokens` gotcha). |
| Nothing happens when files land | The file type may not be supported (see USER_GUIDE.md's file-type table), or you discarded the file earlier (discards persist until you rename or re-force the file). |
| No 📎 in the menu bar | The app was started from a terminal; use `open FileRenamer.app`. |
