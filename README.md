# rcf-sword

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
| `rcf-sword-insert-random-verse`   | Insert a random verse.                                |
| `rcf-sword-insert-random-proverb` | Insert a random verse from Proverbs.                  |
| `rcf-sword-read-book`             | Open a whole book in a read-only reader buffer.       |
| `rcf-sword-close-database`        | Close the database, e.g. after switching translations. |

References accept partial or abbreviated book names: `Gen 3`, `1 Cor 13:4-7`,
`Tim 2`.

In the reader buffer the cursor is hidden and `scroll-lock-mode` is on, so
movement keys scroll the text. The keys are:

| Key       | Does                                   |
|-----------|----------------------------------------|
| `j` / `k` | Scroll down / up.                      |
| `l`       | Recenter.                              |
| `n` / `p` | Scroll one line down / up.             |
| `w` / `c` | Toggle centered margins (olivetti).    |
| `q`       | Close the reader.                      |

## Options

| Variable                      | Default | Purpose                                         |
|-------------------------------|---------|-------------------------------------------------|
| `rcf-sword-bblx-file`         | `nil`   | Path to your `.bblx` file. **Required.**        |
| `rcf-sword-md-link-reference` | `nil`   | Link the Markdown attribution to Bible Gateway. |
| `rcf-sword-md-use-footnotes`  | `nil`   | Add a Markdown footnote linking to the passage. |
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
