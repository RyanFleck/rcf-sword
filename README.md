# rcf-sword.el - Bible Study Tools for Emacs

[![CI](https://github.com/RyanFleck/rcf-sword/actions/workflows/ci.yml/badge.svg?branch=master)](https://github.com/RyanFleck/rcf-sword/actions/workflows/ci.yml)

Emacs package for reading the Bible from a local SQLite (`.bblx`) file.

## Quick start

You need:

- **Emacs 29.1 or newer.** To check that your Emacs has SQLite, press
  `M-:`, type `(sqlite-available-p)` and press Enter. It should say `t`.
- **`git`**, which Emacs uses to download the package.
- **A Bible module** in e-Sword's `.bblx` format, saved somewhere like
  `~/bibles/`.

**1. Add these lines** to your Emacs init file, `~/.emacs.d/init.el`
(create the file if it doesn't exist). Change the path to your `.bblx` file.

```elisp
(unless (package-installed-p 'rcf-sword)
  (package-vc-install "https://github.com/RyanFleck/rcf-sword" :last-release))

(setq rcf-sword-bblx-file "~/bibles/my-translation.bblx")
```

**2. Restart Emacs.** The first start downloads and installs the package.

**3. Try it.** Press `M-x`, run `rcf-sword-insert-verse`, and type
`John 3:16`. Or run `rcf-sword-read-book` and type `Psalms`.

That's it. There's nothing else to install, and no package archive to set
up. To update later, run `M-x package-vc-upgrade` and choose `rcf-sword`.

## What it does

`rcf-sword` reads an e-Sword style `.bblx` database with the SQLite support
built into Emacs 29+. With it you can insert passages into your notes, or read
a whole book in a distraction-free reader buffer.

- In `org-mode`, passages are inserted as a `#+begin_quote` block with a
  `#+verse:` reference line.
- In `markdown-mode`, passages are inserted as a `>` block quote. The
  attribution can optionally link to Bible Gateway, or a footnote can be added.
- In any other mode, passages are inserted as plain text with a `-- Reference`
  line.

## Requirements

- Emacs 29.1 or newer, built with SQLite support. Check with
  `M-: (sqlite-available-p)`.
- `git`, for installing straight from GitHub.
- No other packages. rcf-sword only uses libraries built into Emacs.
- Optional: [`markdown-mode`](https://github.com/jrblevin/markdown-mode)
  for footnotes, and [`olivetti`](https://github.com/rnkn/olivetti) for
  centered reading.
- A `.bblx` Bible module.

## Other ways to install

The quick start uses `package-vc`. These are the details, and the
alternatives if you use another package manager.

### Emacs 29+ built-in (`package-vc`)

```elisp
(package-vc-install "https://github.com/RyanFleck/rcf-sword")
```

This installs the newest commit. To install the latest release instead,
pass `:last-release`, or use `C-u M-x package-vc-install`:

```elisp
(package-vc-install "https://github.com/RyanFleck/rcf-sword" :last-release)
```

`package-vc` defines a release as the latest commit that changed the
`Version:` header. It doesn't look at git tags.

### `use-package` with `:vc` (Emacs 30+)

```elisp
(use-package rcf-sword
  :vc (:url "https://github.com/RyanFleck/rcf-sword" :rev :newest)
  :custom
  (rcf-sword-bblx-file "~/bibles/my-translation.bblx"))
```

`:rev :newest` tracks the newest commit. Leave `:rev` out to get the latest
release, which is the `:vc` default.

On Emacs 29, install the package with `package-vc-install` first, then use
`use-package` without `:vc`.

### straight.el

```elisp
(straight-use-package
 '(rcf-sword :type git :host github :repo "RyanFleck/rcf-sword"))
```

or, with `use-package`:

```elisp
(use-package rcf-sword
  :straight (:host github :repo "RyanFleck/rcf-sword")
  :custom
  (rcf-sword-bblx-file "~/bibles/my-translation.bblx"))
```

### elpaca

```elisp
(use-package rcf-sword
  :ensure (:host github :repo "RyanFleck/rcf-sword")
  :custom
  (rcf-sword-bblx-file "~/bibles/my-translation.bblx"))
```

### MELPA

The package isn't on MELPA yet. A ready-made recipe is in
[`recipes/rcf-sword`](recipes/rcf-sword). Once it's there, MELPA Stable will
build from the `vX.Y.Z` release tags.

## Usage

| Command                           | Does                                                  |
|-----------------------------------|-------------------------------------------------------|
| `rcf-sword-insert-verse`          | Prompt for a reference like `John 3:16-18` and insert it. |
| `rcf-sword-copy-verse`            | Copy a passage as plain text, to paste into email or chat. |
| `rcf-sword-insert-random-verse`   | Insert a random verse.                                |
| `rcf-sword-insert-random-proverb` | Insert a random verse from Proverbs.                  |
| `rcf-sword-read-book`             | Open a whole book in a reader buffer. Add a chapter or verse (`John 5`, `John 5:1`) to open it there. |
| `rcf-sword-verse-of-the-day`      | Show today's verse, the same all day. `C-u` inserts it. From Lisp, it returns the text, e.g. for your `*scratch*` message. |
| `rcf-sword-search`                | List every verse containing a word or phrase. Press `RET` on one to open it in the reader. |
| `rcf-sword-switch-translation`    | Switch between the translations in `rcf-sword-bblx-files`. Open readers update. |
| `rcf-sword-insert-verse-compare`  | Insert a passage from every translation, one after another, to compare them. |
| `rcf-sword-close-database`        | Close the database, e.g. after replacing the `.bblx` file. |

References accept partial or abbreviated book names: `Gen 3`, `1 Cor 13:4-7`,
`Tim 2`. Ranges can cross chapters (`John 3:16-4:2`), and you can list verses
(`Ps 23:1, 4-6`). Common abbreviations work too (`Jn 3:16`, `Mt 5`,
`Song of Songs 2`), and so do numbered books written as `I John`, `First John`
or `1st Jn`. Add your own abbreviations with `rcf-sword-book-aliases`.

When the cursor is on a reference like `John 3:16` in your text, the prompt
offers it as the default, so you can just press Enter. Earlier references are
in the prompt's history: press `M-p` to recall them.

If a reference can't be read, or isn't in your Bible module, rcf-sword says
what's wrong and inserts nothing. For example:

| You type    | rcf-sword says                                              |
|-------------|-------------------------------------------------------------|
| `Jude`      | Add a chapter number, like "Jude 1"                         |
| `John3:16`  | Put a space before the chapter, like "John 3:16"            |
| `Ps 23:5-2` | The verses in "23:5-2" run backwards; did you mean 23:2-5?  |
| `Ps 151`    | Psalms ends at chapter 150, so there's no chapter 151       |

In Org files, links like `[[scripture:John 3:16]]` can open the reader at that
verse. Turn them on with this line in your init file:

```elisp
(with-eval-after-load 'org (require 'rcf-sword-org))
```

Then `C-c C-l` offers `scripture:` as a link type and prompts for the
reference, and exported links show their description (or the reference) as
plain text.

### The reader

In the reader the cursor is hidden and `scroll-lock-mode` is on, so movement
keys scroll the text. `M-x imenu` jumps to any chapter. The keys are:

| Key       | Does                                   |
|-----------|----------------------------------------|
| `j` / `k` | Scroll down / up.                      |
| `l`       | Recenter.                              |
| `n` / `p` | Scroll one line down / up.             |
| `]` / `[` | Next / previous chapter.               |
| `C-x r m` | Bookmark the verse under the cursor. `C-x r b` reopens it later, even after restarting Emacs. |
| `y`       | Copy the verse under the cursor.       |
| `g`       | Re-read the book from the database, e.g. after switching translations. |
| `w` / `c` | Toggle centered margins (olivetti).    |
| `q`       | Close the reader.                      |

### Keys

rcf-sword doesn't bind any global keys. To reach every command from one
key, bind either a menu or a prefix map. They use the same letters (`i`
insert, `c` copy, `b` book, `s` search, `d` verse of the day, and so on):

```elisp
(keymap-global-set "C-c b" #'rcf-sword-menu)          ; a menu that shows the keys
(keymap-global-set "C-c b" 'rcf-sword-command-map)    ; or keys alone
```

## Options

| Variable                      | Default | Purpose                                         |
|-------------------------------|---------|-------------------------------------------------|
| `rcf-sword-bblx-file`         | `nil`   | Path to your `.bblx` file. **Required.**        |
| `rcf-sword-bblx-files`        | `nil`   | All your `.bblx` files, one per translation, for switching and comparing. |
| `rcf-sword-md-link-reference` | `nil`   | Link the Markdown attribution to Bible Gateway. |
| `rcf-sword-md-use-footnotes`  | `nil`   | Add a Markdown footnote linking to the passage. |
| `rcf-sword-books`             | 66 books | Book numbers and names. Rename them for another language, or add books such as the Apocrypha. |
| `rcf-sword-book-aliases`      | common abbreviations | Extra abbreviations, like `Jn` for John. |
| `rcf-sword-org-before` / `rcf-sword-org-after` | quote block | Text around a passage in org. `%s` is the reference. Use `#+begin_verse` for a verse block. |
| `rcf-sword-attribution-format` | `-- %s` | The attribution line in Markdown and plain text, e.g. `— %s`. |
| `rcf-sword-insert-verse-numbers` | `nil` | Show verse numbers (¹²³) in inserted passages. `C-u` flips it for one insertion. |
| `rcf-sword-reader-width`      | `72`    | Body width for centered reading.                |

## Development

```sh
make          # byte-compile, checkdoc, package-lint and ERT tests
make test     # tests only
```

Dependencies for the checks are installed into `./.elpa`. See
[`AGENTS.md`](AGENTS.md) for the packaging conventions this repo follows.

## License

GPL-3.0-or-later. See [`LICENSE`](LICENSE).

## Interesting notes

Findings from replacing the s.el library with functions built into Emacs
(version 0.2.2).

**The swap changed nothing.** A one-off script compared the last s.el-based
release (0.2.0) with the built-in version over about 90 tricky inputs:
whitespace variants, mixed case, regexp characters, Unicode and empty
strings. All 17,383 comparisons matched. The tests that now pin this
behaviour also pass when run against the old s.el code.

**How references are read:**

- Book names match regardless of case, first by how a name starts, then by
  anything inside it, in Bible order. So `TIM` finds 1 Timothy, and `OHN`
  finds John before 1 John.
- Characters like `.`, `*`, `[` or `\` in a book name are matched literally.
  They never act as wildcards, so `J.hn` finds nothing.
- Extra spaces are fine: `Song  of   Solomon 2:1` works. Before 0.2.2 only
  spaces separated words, so a pasted tab or non-breaking space broke a
  reference. Now any whitespace works.
- A trailing colon or dash is forgiven: `Ps 23:` gives the whole chapter,
  and `Ps 23:1-` gives verse 1.
- A blank reference used to show a raw Lisp error (`wrong-type-argument`),
  with s.el too. Since 0.2.2, malformed references get a friendly message
  instead (see [Usage](#usage)).

**For contributors:**

- `s-split` was a thin wrapper around the built-in `split-string`. Both treat
  the separator as a regular expression, not literal text.
- `string-join` takes its arguments in the opposite order to `s-join`:
  `(string-join LIST SEP)` versus `(s-join SEP LIST)`.
- [`AGENTS.md`](AGENTS.md) has a full table of s.el functions and their
  built-in equivalents.
