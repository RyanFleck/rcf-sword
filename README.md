# rcf-sword

Emacs package for reading the Bible from a local SQLite (`.bblx`) file.

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
- [`s`](https://github.com/magnars/s.el), installed automatically.
- Optional: [`markdown-mode`](https://github.com/jrblevin/markdown-mode)
  for footnotes, and [`olivetti`](https://github.com/rnkn/olivetti) for
  centered reading.
- A `.bblx` Bible module.

## Installation

### Emacs 29+ built-in (`package-vc`)

```elisp
(package-vc-install "https://github.com/RyanFleck/rcf-sword")
```

### `use-package` with `:vc` (Emacs 30+)

```elisp
(use-package rcf-sword
  :vc (:url "https://github.com/RyanFleck/rcf-sword" :rev :newest)
  :custom
  (rcf-sword-bblx-file "~/emacs/sword/new.king.james.version.bblx"))
```

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
  (rcf-sword-bblx-file "~/emacs/sword/new.king.james.version.bblx"))
```

### elpaca

```elisp
(use-package rcf-sword
  :ensure (:host github :repo "RyanFleck/rcf-sword")
  :custom
  (rcf-sword-bblx-file "~/emacs/sword/new.king.james.version.bblx"))
```

### MELPA

The package isn't on MELPA yet. A ready-made recipe is in
[`recipes/rcf-sword`](recipes/rcf-sword).

## Usage

| Command                           | Does                                                  |
|-----------------------------------|-------------------------------------------------------|
| `rcf-sword-insert-verse`          | Prompt for a reference like `John 3:16-18` and insert it. |
| `rcf-sword-insert-random-verse`   | Insert a random verse.                                |
| `rcf-sword-insert-random-proverb` | Insert a random verse from Proverbs.                  |
| `rcf-sword-read-book`             | Open a whole book in a read-only reader buffer.       |
| `rcf-sword-close-database`        | Close the database, e.g. after switching translations. |

References accept partial or abbreviated book names: `Gen 3`, `1 Cor 13:4-7`,
`Tim 2`.

In the reader buffer:

| Key       | Does                                   |
|-----------|----------------------------------------|
| `j` / `k` | Scroll down / up.                      |
| `l`       | Recenter.                              |
| `w` / `c` | Toggle centered margins (olivetti).    |
| `q`       | Close the reader.                      |

## Options

| Variable                      | Default | Purpose                                         |
|-------------------------------|---------|-------------------------------------------------|
| `rcf-sword-bblx-file`         | `nil`   | Path to your `.bblx` file. **Required.**        |
| `rcf-sword-md-link-reference` | `nil`   | Link the Markdown attribution to Bible Gateway. |
| `rcf-sword-md-use-footnotes`  | `nil`   | Add a Markdown footnote linking to the passage. |
| `rcf-sword-reader-width`      | `70`    | Body width for centered reading.                |

## Development

```sh
make          # byte-compile, checkdoc, package-lint and ERT tests
make test     # tests only
```

Dependencies for the checks are installed into `./.elpa`. See
[`AGENTS.md`](AGENTS.md) for the packaging conventions this repo follows.

## License

GPL-3.0-or-later. See [`LICENSE`](LICENSE).
