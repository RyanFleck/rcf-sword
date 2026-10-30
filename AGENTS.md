# AGENTS.md

Guidance for AI coding agents (and humans) working on `rcf-sword`.

## What this is

`rcf-sword` is a single-file Emacs Lisp package. It reads scripture from a
local e-Sword style `.bblx` SQLite database, and either inserts passages into
the current buffer (org, markdown or plain text) or opens a whole book in a
read-only reader buffer.

The repository *is* the package. It is meant to be installed straight from
GitHub with `package-vc-install`, `use-package :vc`, straight.el or elpaca,
and to be ready for a MELPA submission.

## Layout

| Path                 | Purpose                                                    |
|----------------------|------------------------------------------------------------|
| `rcf-sword.el`       | The package. All code lives here.                          |
| `test/`              | ERT tests. They build a tiny fixture `.bblx` on the fly.   |
| `recipes/rcf-sword`  | MELPA recipe, kept here for when the package is submitted. |
| `Makefile`           | `make compile`, `make checkdoc`, `make lint`, `make test`. |
| `.github/workflows/` | CI that runs the Makefile targets on several Emacs versions. |
| `LICENSE`            | GPL-3.0-or-later.                                          |

## Packaging rules (distilled from the Elisp manual, MELPA and package-lint)

These are the rules that make a GitHub-hosted Elisp file installable by
`package.el` / `package-vc`, straight.el, elpaca and MELPA. Keep them true on
every change.

1. **The file name, feature and package name all match.** `rcf-sword.el`
   ends with `(provide 'rcf-sword)` and the line
   `;;; rcf-sword.el ends here`.
2. **First line**: `;;; rcf-sword.el --- Summary  -*- lexical-binding: t; -*-`.
   The summary is short, has no trailing period, and doesn't repeat "Emacs".
3. **Library headers** go before `;;; Commentary:`, in the standard format:
   `Author`, `Maintainer`, `Version`, `Package-Requires`, `Keywords`, `URL`,
   and an `SPDX-License-Identifier`. `Package-Requires` is a list on one line,
   e.g. `((emacs "29.1") (s "1.13.0"))`. `Keywords` use standard
   `finder-known-keywords`, so package-lint stays quiet.
4. **License boilerplate** (the GPL notice) sits above `;;; Commentary:`, and
   a `LICENSE` file sits at the repository root.
5. **`;;; Commentary:` and `;;; Code:` sections.** package.el shows the
   commentary as the package description.
6. **Namespace everything.** Every global symbol starts with `rcf-sword-`.
   Internal helpers use `rcf-sword--` (double dash). Never `setq` an
   undeclared global, and never set another package's variables globally.
   Use `setq-local` in buffers we own.
7. **No side effects at load time.** Loading the file must not open files or
   databases, signal errors, add advice or change keymaps. Resources such as
   the SQLite handle are opened lazily, the first time a command needs them.
8. **User options are `defcustom`s** in the `rcf-sword` `defgroup`, with a
   `:type` and a docstring.
9. **Interactive entry points carry `;;;###autoload` cookies**, so that
   `package.el` / `package-vc` generate autoloads and nothing has to be
   `require`d eagerly.
10. **Only hard dependencies go in `Package-Requires`.** Optional integrations
    (markdown-mode, olivetti) are used through `declare-function` / `defvar`
    plus a runtime `(require 'x nil t)` or `featurep` check.
11. **Use `#'` for function references** and avoid obsolete or interactive-only
    functions in Lisp code (`beginning-of-buffer`, `replace-regexp`, ...).
12. **Docstrings pass `checkdoc`.** The first line is a complete sentence, and
    arguments are mentioned in CAPS.
13. **The file byte-compiles with zero warnings** and passes `package-lint`.
14. **Versioning.** Bump `;; Version:` for user-visible changes and tag
    releases `vX.Y.Z`. MELPA Stable and `package-vc` both read git tags.
15. **Don't ship non-package files to MELPA.** The recipe restricts `:files` to
    `rcf-sword.el`. README, tests and CI stay in the repo only.

## Before you commit

```sh
make compile   # byte-compile with warnings treated as errors
make checkdoc  # docstring style
make lint      # package-lint (fetches package-lint from MELPA)
make test      # ERT tests (needs Emacs 29+ with SQLite)
```

Or just run `make` to run all four.

## Conventions specific to this repo

- The `.bblx` schema is the e-Sword one. The `Bible` table has columns
  `Book, Chapter, Verse, Scripture`, and the `Details` table has
  `Description, Abbreviation`. Always name the columns explicitly in SQL,
  never `select *`.
- Book numbering follows the 66-book Protestant canon in
  `rcf-sword-books`. Each element is a `(TESTAMENT NUMBER NAME)` triple.
- Keep functions small and pure where possible (parsing, formatting), so they
  can be unit-tested without a database.
- Behaviour that differs by major mode uses `derived-mode-p`. Don't
  `require` org or markdown-mode just to check the mode.
