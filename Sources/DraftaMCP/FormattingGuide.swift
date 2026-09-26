import Foundation

/// What Drafta's Markdown actually supports.
///
/// An assistant writing into these notes has no other way to know that `#tag`
/// is a real tag, that a diagram is a fenced `mermaid` block, or that a heading
/// path in a tag creates notebooks. Without this it writes plain GitHub
/// Markdown and the note comes out flat.
enum FormattingGuide {

    static let text = """
    # Writing notes for Drafta

    Notes are Markdown files. Beyond the usual (headings, lists, tables, links,
    bold/italic), Drafta renders the following — use them, they are what makes a
    note readable in the app.

    ## Tags

    `#bug`, `#idea`, `#drafta/export` — written inline in the text and picked up
    automatically. A tag with slashes is a path: `#drafta/export` means the tag
    `export` under `drafta`. Cyrillic tags work.

    Tags in the body cannot be removed through the API — only tags added
    separately (via `tag_note`) can. Prefer body tags for things that belong to
    the text, and `tag_note` for bookkeeping.

    ## Task lists

    ```
    - [ ] not done
    - [x] done
    ```

    Checkboxes are clickable in the app, so a checklist is a working to-do list,
    not decoration.

    ## Callouts

    ```
    > [!NOTE] plain remark
    > [!TIP] advice
    > [!WARNING] something that bites
    > [!IMPORTANT] must not be missed
    > [!CAUTION] risk of damage
    ```

    Rendered as a coloured box with an icon. Good for the one line a reader must
    not skim past.

    ## Code

    Fenced blocks with a language get syntax highlighting, a copy button and
    (optionally) line numbers:

    ````
    ```swift
    let note = try library.note(id: id)
    ```
    ````

    Always name the language — an unlabelled block is printed flat.

    ## Diagrams

    ````
    ```mermaid
    graph LR
      A[Bug reported] --> B{Reproducible?}
      B -->|yes| C[Fix]
      B -->|no| D[Need info]
    ```
    ````

    Flowcharts, state, sequence, class, ER and xy charts render natively;
    other diagram types fall back to mermaid.js. Diagrams survive export to PDF
    and DOCX as images.

    ## Maths

    Inline `$E = mc^2$` and display:

    ```
    $$
    \\int_0^\\infty e^{-x^2}\\,dx = \\frac{\\sqrt{\\pi}}{2}
    $$
    ```

    ## Links between notes

    `[[Note title]]` links to another note by title — the way to connect a bug
    to the idea it came from. A link to a title that does not exist yet is shown
    as broken, which is a useful signal rather than an error.

    ## Highlights and footnotes

    `<mark>highlighted</mark>` for reading highlights; `text[^1]` with `[^1]: …`
    for footnotes.

    ## Structure that lives outside the text

    - **Title** — the first line of the body. Start a note with `# Title`; a
      title passed as a parameter is written there for you.
    - **Notebook** — where the note is filed. Without one a note is an orphan,
      so anything created here goes to the Inbox unless told otherwise.
    - **Status** — `active`, `onHold`, `completed`, `dropped`, or `none`. This
      is how a bug is marked fixed: set the status, do not write "DONE" in the
      text.
    """
}
