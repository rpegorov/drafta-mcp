# drafta-mcp

A [Model Context Protocol](https://modelcontextprotocol.io) server that exposes a
Drafta note library to an AI assistant — Claude Code, Zed, or
any other MCP client that launches servers over stdio.

The assistant can search and read your notes, and (unless you start the server
with `--read-only`) create notes, append to them, tag them, set their status and
file them into notebooks. Everything it writes lands in the same Markdown files the
Drafta app reads, so a note created from a chat is indistinguishable from one you
typed.

## Privacy

This repository exists so that you can check for yourself where your notes go.
The answer is: nowhere.

- **stdio only.** The server talks to the client that launched it over stdin and
  stdout. It opens no socket and listens on no port.
- **Local files only.** It reads and writes files under the library directory and
  nothing else. It never touches the app's settings, keychain items or sync state.
- **No network.** No code in this package makes a network request. There is no
  `URLSession`, `Network` framework or socket anywhere in `Sources/`; the only
  dependency is the official MCP Swift SDK, used for its stdio transport.
- **No accounts, no licence check, no telemetry.**

What your notes are exposed to is whatever the MCP client does with the text it
reads — that part is up to the client you connect.

## Build

Requires macOS 13 or later and Swift 6 (Xcode 16 or newer).

```sh
swift build -c release
```

The binary is `.build/release/drafta-mcp`.

```sh
swift test   # the test suite
```

## Install

Copy the binary somewhere stable, for example:

```sh
install -m 755 .build/release/drafta-mcp /usr/local/bin/drafta-mcp
```

## Usage

```
usage: drafta-mcp [--library <path>] [--read-only]

  -l, --library <path>  library root (default: ~/Library/Application Support/Drafta/Library)
  -r, --read-only       publish read tools only
  -h, --help            print this help and exit
```

Without `--library` the server opens the library the Drafta app uses. A `~` in the
path is expanded by the server, since client configs are JSON and no shell sees
them. An unknown flag is an error: `--readonly` (a typo) does not start a
writable server.

### Claude Code

```sh
claude mcp add drafta -- /usr/local/bin/drafta-mcp --library "~/Library/Application Support/Drafta/Library"
```

Add `--read-only` at the end to give the assistant read access only.

### Zed

In `settings.json`:

```json
{
  "context_servers": {
    "drafta": {
      "command": "/usr/local/bin/drafta-mcp",
      "args": ["--library", "~/Library/Application Support/Drafta/Library"]
    }
  }
}
```

## Tools

Read tools (always published):

| Tool | What it does |
|------|--------------|
| `search_notes` | Full-text search over titles, bodies and tags, filtered by `tag`, `status`, `notebook`; newest first, `limit` up to 100. An empty query lists the most recent notes. |
| `read_note` | One note in full, by id or exact title. |
| `list_notebooks` | Notebooks with their hierarchy. |
| `list_tags` | Every tag in use. |
| `formatting_guide` | The Markdown Drafta renders: callouts, mermaid, task lists, tags, wiki links, maths. |

Write tools (not published with `--read-only`):

| Tool | What it does |
|------|--------------|
| `create_note` | New note; goes to the Inbox unless a notebook is given. Optional `tags` and `status`. |
| `append_to_note` | Adds text to the end; the previous text is kept as a revision. |
| `update_note` | Replaces the body; the previous text is kept as a revision. |
| `set_note_status` | `active`, `onHold`, `completed`, `dropped` or `none`. |
| `tag_note` | Adds tags (array, or a comma-separated string). |
| `create_notebook` | Creates a notebook, or returns the existing one with that name. |
| `trash_note` | Moves a note to the trash; the file is kept. |

Notes are also published as MCP resources (`drafta://note/<uuid>`, the 200 most
recent), so a client can attach one as context without a tool call.

## Library format

A library is a plain directory:

```
Library/
  library.json              notebooks (pretty-printed, sorted JSON)
  notes/<UUID>.md           one note: YAML front matter + Markdown body
  revisions/<UUID>/<ms>.md  previous bodies of a note, one file per revision
  editor-hold.json          written by the app while it holds unsaved text
```

Things worth knowing if you read or write these files yourself:

- **Tags are not stored.** They are derived from `#tags` in the body on every read;
  only tags added separately live in the `extraTags` front-matter field.
- **The title is the first line of the body.** `create_note` writes the title as
  a `# heading` when the body has none.
- **A note without a notebook is an orphan**, visible only under All Notes, so new
  notes are filed into the Inbox (created if missing).
- **Edits keep history.** `update_note` and `append_to_note` save the replaced
  text under `revisions/` (30 per note), where the app shows it as history.
- **Open notes are protected.** While the Drafta app holds unsaved text for a note,
  it lists that note in `editor-hold.json`; `update_note` and `append_to_note`
  refuse to write that note's body and say so, instead of reporting a success the
  app would overwrite a moment later.
- **`library.json` is edited under file coordination**, so a notebook the app adds
  at the same moment is not lost.

The server works whether or not the app is running. When it is, the app's file
watcher picks up what the server wrote.

## Relationship to Drafta.app

Drafta.app ships its own copy of `drafta-mcp` inside the app bundle. **This
repository is not that binary.** It is an independent, community-editable snapshot
of the same server: same tool names, same arguments, same on-disk format, with the
app's licence check removed — writes here are gated only by `--read-only`. The two
are developed separately and may drift; if the app ever changes its library format,
this snapshot does not follow automatically.

Contributions are welcome.

## Licence

Apache License 2.0 — see [LICENSE](LICENSE) and [NOTICE](NOTICE).

---

## Кратко по-русски

`drafta-mcp` — MCP-сервер для библиотеки заметок Drafta. Работает только через
stdio, читает и пишет только файлы в каталоге библиотеки и не делает ни одного
сетевого запроса. Сборка: `swift build -c release`. Подключение к Claude Code:
`claude mcp add drafta -- /путь/к/drafta-mcp --library <путь к библиотеке>`.
Флаг `--read-only` оставляет только инструменты чтения. Это независимый снимок
сервера, а не бинарник, который поставляется внутри Drafta.app.
