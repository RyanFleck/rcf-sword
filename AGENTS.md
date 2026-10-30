# AGENTS.md

Guidance for AI coding agents (and humans) working on `rcf-sword`.

## What this is

`rcf-sword` is an Emacs Lisp package: one core file, `rcf-sword.el`, plus the
optional Org links in `rcf-sword-org.el`. It reads scripture from a
local e-Sword style `.bblx` SQLite database, and either inserts passages into
the current buffer (org, markdown or plain text) or opens a whole book in a
read-only reader buffer.

The repository *is* the package. It is meant to be installed straight from
GitHub with `package-vc-install`, `use-package :vc`, straight.el or elpaca,
and to be ready for a MELPA submission.

## Layout

| Path                 | Purpose                                                    |
|----------------------|------------------------------------------------------------|
| `rcf-sword.el`       | The package. All core code lives here.                     |
| `rcf-sword-org.el`   | Optional Org `scripture:` links. Users `require` it from their init file, because package-lint (rightly) rejects `with-eval-after-load` in packages, and rcf-sword must never load Org itself. |
| `test/`              | ERT tests. They build a tiny fixture `.bblx` on the fly.   |
| `recipes/rcf-sword`  | MELPA recipe, kept here for when the package is submitted. |
| `Makefile`           | `make compile`, `make checkdoc`, `make lint`, `make test`. |
| `.github/workflows/` | CI: the Makefile targets on several Emacs versions, a vanilla `package-vc` install, and a tag/`Version:` check. Actions are pinned to commit SHAs; `.github/dependabot.yml` proposes updates. |
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
   `Author`, `Assisted-by` (see rule 16), `Maintainer`, `Version`,
   `Package-Requires`, `Keywords`, `URL`, and an `SPDX-License-Identifier`. `Package-Requires` is a list on one line,
   currently just `((emacs "29.1"))`. `Keywords` use standard
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
10. **No third-party dependencies.** Use built-in libraries only, so the
    package installs on a vanilla Emacs with no archive set up. For string
    handling, use the built-ins rather than s.el. They all exist in Emacs
    29.1, the minimum version:

    | s.el                         | Built-in                                    |
    |------------------------------|---------------------------------------------|
    | `(s-split SEP S OMIT)`       | `(split-string S SEP OMIT)`                 |
    | `(s-trim S)`                 | `(string-trim S)`                           |
    | `(s-join SEP LIST)`          | `(string-join LIST SEP)` (arguments swap)   |
    | `(s-starts-with? P S t)`     | `(string-prefix-p P S t)`                   |
    | `(s-ends-with? P S t)`       | `(string-suffix-p P S t)`                   |
    | `(s-contains? N S)`          | `(string-search N S)`                       |
    | `(s-contains? N S t)`        | `(let ((case-fold-search t)) (string-match-p (regexp-quote N) S))` |

    Both `s-split` and `split-string` treat SEP as a regexp, so quote a
    literal separator that contains regexp characters. The "Built-in string
    handling" tests pin the behaviour of each replacement.
    The Makefile doesn't install s.el, so a stray `s-` call fails the build.
    **Only hard dependencies go in `Package-Requires`.** Optional integrations
    (markdown-mode, olivetti) are used through `declare-function` / `defvar`
    plus a runtime `(require 'x nil t)` or `featurep` check.
11. **Use `#'` for function references** and avoid obsolete or interactive-only
    functions in Lisp code (`beginning-of-buffer`, `replace-regexp`, ...).
12. **Docstrings pass `checkdoc`.** The first line is a complete sentence, and
    arguments are mentioned in CAPS.
13. **The file byte-compiles with zero warnings** and passes `package-lint`.
14. **Versioning and releases.** A release is a commit that changes the
    `;; Version:` header, tagged `vX.Y.Z`. The install routes find releases
    in different ways:
    - **MELPA Stable** builds from git tags.
    - **`package-vc`** ignores tags. `package-vc-install` installs the
      newest commit by default. With `:last-release` (or a `C-u` prefix),
      it installs the latest commit that changed the `Version:` header.
    - **`use-package :vc`** (Emacs 30+) defaults to `:last-release`, and
      `:rev :newest` opts into the newest commit.
    - **MELPA** (unstable) and straight.el/elpaca by default track the
      newest commit.

    So make the `Version:` bump the final change of a release, and tag that
    same commit. Squash-merging the release PR does this naturally. A bump
    made early in a multi-commit PR would make `:last-release` pick a commit
    that is missing the later fixes. Don't change `Version:` outside a
    release. CI fails on a `v*` tag that doesn't match `;; Version:`.
15. **Don't ship non-package files to MELPA.** The recipe restricts `:files` to
    `rcf-sword.el` and `rcf-sword-org.el`. README, tests and CI stay in the repo only.
16. **AI attribution.** MELPA asks AI-assisted packages to carry an
    `;; Assisted-by: AGENT_NAME:MODEL_VERSION` line under `;; Author:`. Keep
    that line, and have the human maintainer fill in the model version
    before submitting to MELPA. MELPA also expects the human author to be
    the first and most thorough reviewer of AI-written code.

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
  It's a user option (for other languages and canons), so refer to books
  by number in code, never by English name.
- Keep functions small and pure where possible (parsing, formatting), so they
  can be unit-tested without a database.
- Behaviour that differs by major mode uses `derived-mode-p`. Don't
  `require` org or markdown-mode just to check the mode.
