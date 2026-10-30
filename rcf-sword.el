;;; rcf-sword.el --- Insert and read scripture from a local .bblx file  -*- lexical-binding: t; -*-

;; Copyright (C) 2024-2026 Ryan Fleck

;; Author: Ryan Fleck <dev@ryanfleck.ca>
;; Assisted-by: Claude Code
;; Maintainer: Ryan Fleck <dev@ryanfleck.ca>
;; Created: 2024-08-01
;; Version: 0.2.2
;; Package-Requires: ((emacs "29.1"))
;; Keywords: convenience, wp
;; URL: https://github.com/RyanFleck/rcf-sword
;; SPDX-License-Identifier: GPL-3.0-or-later

;; This file is not part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; For scriptural study.
;;
;; rcf-sword reads scripture from a local e-Sword style .bblx file (a
;; SQLite database) using the SQLite support built into Emacs 29+.
;;
;; Set `rcf-sword-bblx-file' to the path of your .bblx file, then use:
;;
;;   M-x rcf-sword-insert-verse          Insert a passage, e.g. "John 3:16-18".
;;   M-x rcf-sword-copy-verse            Copy a passage, to paste elsewhere.
;;   M-x rcf-sword-insert-random-verse   Insert a random verse.
;;   M-x rcf-sword-insert-random-proverb Insert a random proverb.
;;   M-x rcf-sword-read-book             Read a whole book in a reader buffer.
;;   M-x rcf-sword-close-database        Close the database, e.g. after
;;                                       switching translations.
;;
;; Passages are formatted for the current buffer: an org quote block in
;; `org-mode', a block quote in `markdown-mode', and plain text otherwise.
;;
;; markdown-mode and olivetti are optional.  Markdown formatting applies to
;; any buffer whose mode derives from `markdown-mode', and footnotes (see
;; `rcf-sword-md-use-footnotes') use its footnote command.  olivetti, when
;; installed, centers the text in the book reader.

;; Changelog:
;;
;; 2024-08-01 First version: check the sqlite db, read the user input
;;            string, and insert an org-mode quote block into the buffer.
;; 2024-08-02 Cleaned up the code.  Added 'insert random verse'.
;; 2024-09-10 Change position of verse-version insertion.
;; 2024-09-23 Fixed a bug where 'string includes?' would pick the wrong
;;            book during casual insertion of scripture.
;; 2024-11-11 Added Markdown and plaintext insertion support.
;; 2024-11-23 Pull translation title/abbreviation from database.
;; 2025-05-12 New functions to show entire books.
;; 2026-10-30 0.1.0: Packaged for package-vc, straight, elpaca and MELPA.
;;            All symbols renamed to the `rcf-sword-' prefix, the database
;;            path is now a defcustom opened lazily, markdown-mode and
;;            olivetti are optional, and Lamentations is book 25.
;; 2026-10-30 0.2.0: Reader hides the cursor, scrolls with
;;            `scroll-lock-mode', adds n/p keys and defaults to a 72
;;            column body.  Books are grouped by section.  Examples
;;            no longer name a particular translation.
;; 2026-10-30 0.2.2: Use built-in string functions instead of s.el, so
;;            the package has no dependencies beyond Emacs 29.1 and
;;            installs on a vanilla Emacs without MELPA.  Malformed
;;            references and passages missing from the database now get
;;            a friendly message saying what's wrong.  (The v0.2.1 tag
;;            marks a docs-only commit, so this release is 0.2.2.)

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'text-property-search)
(require 'thingatpt)
(require 'url-util)

;; Optional integrations.  These are only used after checking that the
;; package is available, so they aren't listed in Package-Requires.
(declare-function markdown-insert-footnote "ext:markdown-mode" ())
(declare-function olivetti-mode "ext:olivetti" (&optional arg))
(defvar olivetti-mode)
(defvar olivetti-body-width)
(defvar olivetti-minimum-body-width)
(defvar imenu-create-index-function)
(defvar bookmark-make-record-function)
(declare-function bookmark-prop-get "bookmark" (bookmark prop))

;;;; Customization

(defgroup rcf-sword nil
  "Insert and read scripture from a local .bblx database."
  :group 'applications
  :prefix "rcf-sword-"
  :link '(url-link "https://github.com/RyanFleck/rcf-sword"))

(defcustom rcf-sword-bblx-file nil
  "Path to the e-Sword style .bblx (SQLite) scripture database.
For example \"~/bibles/my-translation.bblx\"."
  :type '(choice (const :tag "Unset" nil) file))

(defcustom rcf-sword-md-link-reference nil
  "When non-nil, link the Markdown attribution line to Bible Gateway.
The link opens the passage in the same translation, using the
abbreviation from the database."
  :type 'boolean)

(defcustom rcf-sword-md-use-footnotes nil
  "When non-nil, add a Markdown footnote linking to the passage.
The footnote links to Bible Gateway's page comparing translations.
Requires `markdown-mode'."
  :type 'boolean)

(defcustom rcf-sword-insert-verse-numbers nil
  "When non-nil, inserted passages show verse numbers, like \"¹⁶For God\".
A prefix argument to `rcf-sword-insert-verse' flips this for one
insertion.  The book reader always shows verse numbers."
  :type 'boolean)

(defcustom rcf-sword-reader-width 72
  "Body width, in columns, used when centering text in the book reader.
Only takes effect when olivetti is installed."
  :type 'integer)

;;;; Book data

;; The 66-book Protestant canon, in the order e-Sword numbers books.
;; It's a user option, so other canons and languages can adjust it.
(defcustom rcf-sword-books
  '(;; THE OLD TESTAMENT
    ;; The Law
    (1 1 "Genesis")
    (1 2 "Exodus")
    (1 3 "Leviticus")
    (1 4 "Numbers")
    (1 5 "Deuteronomy")
    ;; History
    (1 6 "Joshua")
    (1 7 "Judges")
    (1 8 "Ruth")
    (1 9 "1 Samuel")
    (1 10 "2 Samuel")
    (1 11 "1 Kings")
    (1 12 "2 Kings")
    (1 13 "1 Chronicles")
    (1 14 "2 Chronicles")
    (1 15 "Ezra")
    (1 16 "Nehemiah")
    (1 17 "Esther")
    ;; Wisdom & Poetry
    (1 18 "Job")
    (1 19 "Psalms")
    (1 20 "Proverbs")
    (1 21 "Ecclesiastes")
    (1 22 "Song of Solomon")
    ;; Major Prophets
    (1 23 "Isaiah")
    (1 24 "Jeremiah")
    (1 25 "Lamentations")
    (1 26 "Ezekiel")
    (1 27 "Daniel")
    ;; Minor Prophets
    (1 28 "Hosea")
    (1 29 "Joel")
    (1 30 "Amos")
    (1 31 "Obadiah")
    (1 32 "Jonah")
    (1 33 "Micah")
    (1 34 "Nahum")
    (1 35 "Habakkuk")
    (1 36 "Zephaniah")
    (1 37 "Haggai")
    (1 38 "Zechariah")
    (1 39 "Malachi")

    ;; THE NEW TESTAMENT
    ;; The Gospels
    (2 40 "Matthew")
    (2 41 "Mark")
    (2 42 "Luke")
    (2 43 "John")
    ;; Historical Book
    (2 44 "Acts")
    ;; Paul's Letters
    (2 45 "Romans")
    (2 46 "1 Corinthians")
    (2 47 "2 Corinthians")
    (2 48 "Galatians")
    (2 49 "Ephesians")
    (2 50 "Philippians")
    (2 51 "Colossians")
    (2 52 "1 Thessalonians")
    (2 53 "2 Thessalonians")
    (2 54 "1 Timothy")
    (2 55 "2 Timothy")
    (2 56 "Titus")
    (2 57 "Philemon")
    ;; General Letters
    (2 58 "Hebrews") ; Authorship unknown, maybe Paul
    (2 59 "James")
    (2 60 "1 Peter")
    (2 61 "2 Peter")
    (2 62 "1 John")
    (2 63 "2 John")
    (2 64 "3 John")
    (2 65 "Jude")
    ;; Prophecy
    (2 66 "Revelation"))
  "Books of the Bible as (TESTAMENT NUMBER NAME) triples.
TESTAMENT is 1 for the Old Testament and 2 for the New.  NUMBER
matches the Book column of the .bblx database.  NAME is used both
to match what the user types and to label inserted passages.

The default is the 66-book Protestant canon in English.  To use
another language, change the names.  To add books, such as the
Apocrypha, add triples with the numbers your module uses; list them
with sqlite3: SELECT DISTINCT Book FROM Bible WHERE Book > 66;
A book missing from this list is shown as \"Book N\"."
  :type '(repeat (list (integer :tag "Testament")
                       (integer :tag "Number")
                       (string :tag "Name"))))

(defun rcf-sword--book-names ()
  "Return the names of all books in `rcf-sword-books'."
  (mapcar #'cl-caddr rcf-sword-books))

(defcustom rcf-sword-book-aliases
  '(("Gn" . "Genesis") ("Lv" . "Leviticus") ("Nm" . "Numbers")
    ("Dt" . "Deuteronomy") ("Jdg" . "Judges") ("Jg" . "Judges")
    ("Jb" . "Job") ("Pss" . "Psalms") ("Prv" . "Proverbs")
    ("Qoh" . "Ecclesiastes") ("Song of Songs" . "Song of Solomon")
    ("Canticles" . "Song of Solomon") ("SoS" . "Song of Solomon")
    ("Sg" . "Song of Solomon") ("Ezk" . "Ezekiel") ("Dn" . "Daniel")
    ("Jl" . "Joel") ("Zp" . "Zephaniah") ("Mt" . "Matthew")
    ("Mk" . "Mark") ("Lk" . "Luke") ("Jn" . "John") ("Jas" . "James")
    ("Phlm" . "Philemon") ("Tm" . "Timothy") ("Pt" . "Peter")
    ("Rv" . "Revelation") ("Revelations" . "Revelation"))
  "Book abbreviations that don't otherwise match a book's name.
Each element is (ALIAS . NAME).  When what the user types equals an
ALIAS (ignoring case), NAME is looked up instead.  Only aliases that
the normal prefix and substring matching misses are needed: \"Gen\"
and \"Rom\" already work.  An alias also works after a number, so
\"Jn\" makes \"1 Jn\" find 1 John."
  :type '(alist :key-type string :value-type string))

(defconst rcf-sword--ordinals
  '(("1" . "1") ("I" . "1") ("First" . "1") ("1st" . "1")
    ("2" . "2") ("II" . "2") ("Second" . "2") ("2nd" . "2")
    ("3" . "3") ("III" . "3") ("Third" . "3") ("3rd" . "3"))
  "Ways of writing the number that starts names like \"1 John\".")

(defun rcf-sword--expand-book-alias (partial)
  "Return PARTIAL with its leading ordinal and any alias expanded.
For example \"I Jn\" and \"First Jn\" both become \"1 John\".
Anything else is returned unchanged."
  (let ((expand (lambda (name)
                  (or (cdr (assoc-string name rcf-sword-book-aliases t)) name))))
    (if (and (string-match "\\`\\([^ ]+\\) +\\(.+\\)\\'" partial)
             (assoc-string (match-string 1 partial) rcf-sword--ordinals t))
        ;; A leading ordinal: normalize it, then expand the rest.
        (concat (cdr (assoc-string (match-string 1 partial) rcf-sword--ordinals t))
                " " (funcall expand (match-string 2 partial)))
      (funcall expand partial))))

(defun rcf-sword--find-book (partial)
  "Return the first book triple whose name matches PARTIAL, or nil.
First expand ordinals and aliases (see `rcf-sword-book-aliases'), then
look for a name that starts with PARTIAL, then for one that contains
it, each time in canonical order.  Matching ignores case, so \"jo\"
finds Joshua, \"tim\" finds 1 Timothy and \"I Jn\" finds 1 John."
  (setq partial (rcf-sword--expand-book-alias partial))
  (or (seq-find (lambda (book) (string-prefix-p partial (nth 2 book) t))
                rcf-sword-books)
      (let ((case-fold-search t)
            (regexp (regexp-quote partial)))
        (seq-find (lambda (book) (string-match-p regexp (nth 2 book)))
                  rcf-sword-books))))

(defun rcf-sword--book-number (partial)
  "Return the book number matching PARTIAL, or nil."
  (nth 1 (rcf-sword--find-book partial)))

(defun rcf-sword--book-name-from-number (number)
  "Return the name of book NUMBER, or \"Book NUMBER\" if it isn't listed.
Modules can contain books missing from `rcf-sword-books', such as the
Apocrypha, so they still get a usable label."
  (or (nth 2 (seq-find (lambda (book) (equal (nth 1 book) number))
                       rcf-sword-books))
      (format "Book %d" number)))

;;;; Database

;; The database is an e-Sword Bible module, a SQLite file usually shipped
;; with a '.bblx' extension.  Inspect one with sqlite3 (.tables,
;; .headers on).  This package reads two tables.
;;
;; Table 'Bible', one row per verse:
;;
;; Book  Chapter  Verse  Scripture
;; -----------------------------------------------------------------------
;; 1     1        1      In the beginning God created the heaven and the ...
;; 1     1        2      And the earth was without form, and void; and ...
;;
;; Book numbers follow `rcf-sword-books'.  Scripture may contain RTF
;; footnote markup like {\cf2\super [1]}, which is stripped on insertion.
;;
;; Table 'Details', one row: the translation's Description (its full name)
;; and Abbreviation.
;;
;; The connection is opened lazily by `rcf-sword--get-db', so loading
;; this file never touches the disk.

(defvar rcf-sword--db nil
  "Open SQLite connection to the scripture database, or nil.")

(defvar rcf-sword--db-file nil
  "Expanded file name that `rcf-sword--db' was opened from.")

(defvar rcf-sword--db-info nil
  "Cached (DESCRIPTION ABBREVIATION) for `rcf-sword--db'.")

(defun rcf-sword--get-db ()
  "Return a connection to `rcf-sword-bblx-file', opening it if needed.
If `rcf-sword-bblx-file' has changed since the connection was opened,
close the old connection and open the new file.  Signal a `user-error'
if SQLite is unavailable, the file is unset or unreadable, or it isn't
an e-Sword Bible module."
  (unless (and (fboundp 'sqlite-available-p) (sqlite-available-p))
    (user-error "The rcf-sword package needs Emacs 29+ built with SQLite support"))
  (unless rcf-sword-bblx-file
    (user-error "Set `rcf-sword-bblx-file' to the path of your .bblx file"))
  (let ((file (expand-file-name rcf-sword-bblx-file)))
    ;; Check first: `sqlite-open' would silently create an empty database.
    (unless (file-readable-p file)
      (user-error "Can't read scripture database %s" file))
    (unless (and rcf-sword--db (equal file rcf-sword--db-file))
      (rcf-sword-close-database)
      (let ((db (sqlite-open file)))
        ;; Check it's a Bible module now, rather than failing later with a
        ;; raw SQL error.  A file that isn't SQLite at all only fails on
        ;; its first query ("file is not a database"), so catch that too.
        (unless (ignore-error sqlite-error
                  (= 2 (caar (sqlite-select
                              db "SELECT COUNT(*) FROM sqlite_master WHERE type='table'
                                    AND lower(name) IN ('bible', 'details');"))))
          (sqlite-close db)
          (user-error "%s isn't an e-Sword Bible module: it needs Bible and Details tables"
                      file))
        (setq rcf-sword--db db
              rcf-sword--db-file file)))
    rcf-sword--db))

(defun rcf-sword-close-database ()
  "Close the scripture database connection, if one is open.
The next command that needs the database reopens it, so use this after
changing the file behind `rcf-sword-bblx-file'."
  (interactive)
  (when rcf-sword--db
    (ignore-errors (sqlite-close rcf-sword--db)))
  (setq rcf-sword--db nil
        rcf-sword--db-file nil
        rcf-sword--db-info nil))

(defun rcf-sword--query (sql &optional values)
  "Run SQL with VALUES against the scripture database.
VALUES fills in the ? placeholders in SQL.  Return a list of rows,
each a list of column values."
  (sqlite-select (rcf-sword--get-db) sql values))

(defun rcf-sword--db-info ()
  "Return the translation's (DESCRIPTION ABBREVIATION).
Read from the Details table once, then cached until the database is
closed or changed."
  (or rcf-sword--db-info
      (setq rcf-sword--db-info
            (car (rcf-sword--query
                  "SELECT Description, Abbreviation FROM Details;")))))

(defun rcf-sword-translation-name ()
  "Return the translation name, like \"King James Version\"."
  (car (rcf-sword--db-info)))

(defun rcf-sword-translation-abbreviation ()
  "Return the translation abbreviation, like \"KJV\"."
  (cadr (rcf-sword--db-info)))

(defconst rcf-sword--verse-columns "Book, Chapter, Verse, Scripture"
  "Columns selected for each verse, in the order the code expects.
Code reads verses positionally, as (BOOK CHAPTER VERSE TEXT), so name
the columns rather than relying on the table's own column order.")

(defun rcf-sword--verses (book &optional chapter verse-min verse-max)
  "Return the verses of BOOK, in order.
With CHAPTER, return only that chapter.  With VERSE-MIN too, return
verses VERSE-MIN to VERSE-MAX inclusive; VERSE-MAX defaults to
VERSE-MIN, giving a single verse.  CHAPTER is required when VERSE-MIN
is given.  Each verse is (BOOK CHAPTER VERSE TEXT); the result is nil
if nothing matches."
  (cond
   (verse-min
    (rcf-sword--query
     (concat "SELECT " rcf-sword--verse-columns " FROM Bible"
             " WHERE Book=? AND Chapter=? AND Verse>=? AND Verse<=?"
             " ORDER BY Verse;")
     (list book chapter verse-min (or verse-max verse-min))))
   (chapter
    (rcf-sword--query
     (concat "SELECT " rcf-sword--verse-columns " FROM Bible"
             " WHERE Book=? AND Chapter=? ORDER BY Verse;")
     (list book chapter)))
   (t
    (rcf-sword--query
     (concat "SELECT " rcf-sword--verse-columns " FROM Bible"
             " WHERE Book=? ORDER BY Chapter, Verse;")
     (list book)))))

;;;; Random verses

(defun rcf-sword--random-verse (&optional book)
  "Return a random verse, as a list of one verse, or nil if none.
With BOOK, a book number, pick from that book only.  Every verse is
equally likely: SQLite shuffles the rows and keeps the first."
  (rcf-sword--query
   (concat "SELECT " rcf-sword--verse-columns " FROM Bible"
           (if book " WHERE Book=?" "")
           " ORDER BY RANDOM() LIMIT 1;")
   (and book (list book))))

;;;; Parsing references

(defconst rcf-sword--word-separators "[ \t\n\r\f\v\u00a0]+"
  "Regexp matching the whitespace between words of a reference.
Includes tabs and non-breaking spaces, which are easy to paste in.")

(defun rcf-sword--parse-reference (str)
  "Parse a reference STR like \"1 John 3:1-2\".
Words are separated by any run of `rcf-sword--word-separators'.
Return (BOOK CHAPTER VERSES).  BOOK is the words before the last one,
joined by single spaces (it may be partial, and is \"\" if STR is one
word).
CHAPTER is a number, 0 if the last word doesn't start with one.
VERSES is nil for a whole chapter, (VERSE) for one verse, or
\(FIRST LAST) for a range."
  (let* ((words (split-string str rcf-sword--word-separators t))
         (chapter-verse (car (last words)))
         (book (string-join (butlast words) " "))
         (chapter-verse-split (split-string chapter-verse ":"))
         (verses? (length> chapter-verse-split 1))
         (chapter (car chapter-verse-split))
         (verses (split-string (car (last chapter-verse-split)) "-" t)))
    (list book
          (string-to-number chapter)
          (when verses? (mapcar #'string-to-number verses)))))

;;;; Checking references
;;
;; Malformed input is reported with `user-error', which Emacs shows as a
;; plain message in the echo area, without a backtrace or the debugger.
;; Each message says what's wrong and gives an example of the fix.

(defconst rcf-sword--chapter-verse-regexp
  (rx bos (group (+ digit))
      (? ":" (? (group (+ digit)) (? "-" (group (* digit)))))
      eos)
  "Match a chapter and optional verses, like 3, 3:16 or 3:16-18.
Group 1 is the chapter, group 2 the first verse and group 3 the last
verse.  A trailing colon or dash, as in 3: or 3:16-, is allowed.")

(defconst rcf-sword--missing-space-regexp
  (rx bos (group (* nonl) alpha) (group digit (* (in digit ":-"))) eos)
  "Match a book name run into its chapter, like John3:16.
Group 1 is the book and group 2 the chapter and verses.")

(defun rcf-sword--no-book-message (book-str)
  "Return a message saying no book matches BOOK-STR."
  (format "No book matches \"%s\"; try a name like \"Gen\", \"1 Cor\" or \"Psalms\""
          book-str))

(defun rcf-sword--reference-problem (str)
  "Return a message explaining what's wrong with the reference STR.
Return nil if STR is well formed and names a known book.  This only
checks the form of STR, not whether the database has the passage, so it
can run without a database."
  (let* ((words (split-string str rcf-sword--word-separators t))
         (last-word (car (last words)))
         (book-str (string-join (butlast words) " "))
         ;; (CHAPTER FIRST-VERSE LAST-VERSE), with nil for parts not given,
         ;; or nil if LAST-WORD isn't a chapter and verses.
         (numbers
          (when (and last-word
                     (string-match rcf-sword--chapter-verse-regexp last-word))
            (mapcar (lambda (group)
                      (let ((digits (match-string group last-word)))
                        (and digits (not (string-empty-p digits))
                             (string-to-number digits))))
                    '(1 2 3)))))
    (pcase-let ((`(,chapter ,first ,last) numbers))
      (cond
       ((null words)
        "Type a reference, like \"John 3:16\", \"Gen 1\" or \"1 Cor 13:4-7\"")
       ((and (null numbers)
             (string-match rcf-sword--missing-space-regexp last-word))
        (format "Put a space before the chapter, like \"%s\""
                (string-trim (concat book-str " " (match-string 1 last-word)
                                     " " (match-string 2 last-word)))))
       ((and (null numbers) (null (cdr words)))
        ;; A single word that isn't a chapter: probably a book on its own.
        (if-let ((book (rcf-sword--find-book last-word)))
            (format "Add a chapter number, like \"%s 1\"" (nth 2 book))
          (rcf-sword--no-book-message last-word)))
       ((null numbers)
        (format "Can't read \"%s\" as a chapter and verses; use a form like 3, 3:16 or 3:16-18"
                last-word))
       ((string-empty-p book-str)
        (format "Add a book name before \"%s\", like \"John %s\"" last-word last-word))
       ((memq 0 numbers)
        (format "Chapters and verses start at 1, so \"%s\" doesn't exist" last-word))
       ((and first last (< last first))
        (format "The verses in \"%s\" run backwards; did you mean %d:%d-%d?"
                last-word chapter last first))
       ((null (rcf-sword--find-book book-str))
        (rcf-sword--no-book-message book-str))))))

(defun rcf-sword--missing-passage (book chapter verse)
  "Signal a `user-error' saying the database lacks a passage.
BOOK is a book triple, CHAPTER a chapter number and VERSE the first
verse asked for, or nil for a whole chapter.  Say whether the book,
the chapter or the verse is what's missing."
  (let* ((number (nth 1 book))
         (name (nth 2 book))
         (last-chapter (caar (rcf-sword--query
                              "SELECT MAX(Chapter) FROM Bible WHERE Book=?;"
                              (list number))))
         (last-verse (caar (rcf-sword--query
                            "SELECT MAX(Verse) FROM Bible WHERE Book=? AND Chapter=?;"
                            (list number chapter)))))
    (cond
     ((null last-chapter)
      (user-error "This translation doesn't include %s" name))
     ((null last-verse)
      (user-error "%s ends at chapter %d, so there's no chapter %d"
                  name last-chapter chapter))
     (t
      (user-error "%s %d ends at verse %d, so there's no verse %d"
                  name chapter last-verse verse)))))

(defvar rcf-sword-reference-history nil
  "Minibuffer history of references typed at rcf-sword prompts.")

(defconst rcf-sword--reference-at-point-regexp
  "[1-3]? ?[[:alpha:]]+ [0-9]+\\(?::[0-9]+\\(?:-[0-9]+\\)?\\)?"
  "Match a reference like \"John 3:16\" or \"1 Cor 13:4-7\" in text.
Only one-word book names, optionally numbered, are recognized, so that
the words before a reference aren't mistaken for part of the book.
The optional space before the book lets `thing-at-point-looking-at',
which backs up one character at a time, step from \"Cor\" through
\" Cor\" to \"1 Cor\"; the match is trimmed afterwards.")

(defun rcf-sword--reference-at-point ()
  "Return the reference around point, like \"John 3:16\", or nil.
Only return text that `rcf-sword--reference-problem' accepts, so
ordinary words followed by a number aren't offered."
  (when (thing-at-point-looking-at rcf-sword--reference-at-point-regexp 100)
    (let ((reference (string-trim (match-string-no-properties 0))))
      (unless (rcf-sword--reference-problem reference)
        reference))))

(defun rcf-sword--read-reference (prompt)
  "Read a reference in the minibuffer with PROMPT.
Offer the reference at point as the default, and keep a history in
`rcf-sword-reference-history', so \\`M-p' recalls earlier ones."
  (let ((default (rcf-sword--reference-at-point)))
    (read-string (format-prompt prompt default)
                 nil 'rcf-sword-reference-history default)))

(defun rcf-sword--lookup (str)
  "Return the verses described by the reference STR.
Signal a `user-error' explaining the problem if STR is malformed (see
`rcf-sword--reference-problem') or names a book, chapter or verses
that aren't in the database.  A range that only partly exists, like
verses 5-99 of a 10-verse chapter, returns the verses that do."
  (when-let ((problem (rcf-sword--reference-problem str)))
    (user-error "%s" problem))
  (pcase-let* ((`(,book-str ,chapter ,verses) (rcf-sword--parse-reference str))
               (book (rcf-sword--find-book book-str)))
    (or (rcf-sword--verses (nth 1 book) chapter (car verses) (cadr verses))
        (rcf-sword--missing-passage book chapter (car verses)))))

;;;; Formatting

;; The database stores one verse per row, but sentences often run across
;; verses.  When inserting several verses, these heuristics decide whether
;; the next verse continues the current paragraph or starts a new one.
;; I really ought to use a proper 'versification' table instead.

(defconst rcf-sword--conjunctions
  '("and" "that" "but" "or" "as" "if" "when" "than" "because" "while"
    "where" "after" "so" "though" "since" "until" "whether" "before"
    "although" "nor" "like" "once" "unless" "now" "except")
  "Words that, starting a verse, continue the previous sentence.
Compared case-insensitively against the verse's whole first word.")

(defun rcf-sword--start-is-continuation-p (text)
  "Return non-nil if verse TEXT continues the previous verse.
That is the case when its first word is one of
`rcf-sword--conjunctions' (in any case), or starts with a lowercase
letter.  A verse starting with a quote mark or digit doesn't count."
  (let ((first-word (car (split-string text " " t))))
    (and first-word
         (or (member (downcase first-word) rcf-sword--conjunctions)
             (let ((case-fold-search nil))
               (string-match-p "\\`[[:lower:]]" first-word))))))

(defun rcf-sword--end-is-continuation-p (text)
  "Return non-nil if verse TEXT ends with continuation punctuation.
That is a semicolon, colon or comma, meaning the sentence carries on
into the next verse."
  (string-match-p "[;:,]\\'" text))

(defun rcf-sword--superscript (number)
  "Return NUMBER as a string of Unicode superscript digits.
Used to mark verse numbers inline, as in \"¹In the beginning\"."
  (mapconcat (lambda (c)
               (if (<= ?0 c ?9)
                   (string (aref "⁰¹²³⁴⁵⁶⁷⁸⁹" (- c ?0)))
                 ""))
             (number-to-string number)
             ""))

(defun rcf-sword--insert-lines (verses show-verse-numbers)
  "Insert VERSES at point, one paragraph per run of connected verses.
A verse starts a new paragraph unless the previous verse ends with
continuation punctuation or this one starts like a continuation.
When SHOW-VERSE-NUMBERS is non-nil, prefix each verse with its number.
Strip e-Sword footnote markup and fill the inserted text to
`fill-column'.  No newline is added after the last verse; point is
left at the end of the inserted text."
  (let ((start (point))
        (end (make-marker))
        ;; In Markdown every line, including the blank one between
        ;; paragraphs, must keep the "> " prefix to stay in the quote.
        (paragraph-break (if (derived-mode-p 'markdown-mode) "\n> \n> " "\n\n"))
        (previous nil))
    (dolist (verse verses)
      ;; Remove footnote markers like {\cf2\super [18]} first, so the
      ;; continuation checks below see the verse's real punctuation.
      (let ((text (string-trim (replace-regexp-in-string
                                "{[^}]*}" "" (nth 3 verse)))))
        (when previous
          (insert (if (or (rcf-sword--end-is-continuation-p previous)
                          (rcf-sword--start-is-continuation-p text))
                      " "
                    paragraph-break)))
        (let ((verse-start (point)))
          (when show-verse-numbers
            (insert (rcf-sword--superscript (nth 2 verse))))
          (insert text)
          ;; In the reader, tag the verse with (BOOK CHAPTER VERSE), so
          ;; commands can tell which verse point is on.  Inserted passages
          ;; in the user's own buffers stay free of hidden properties.
          (when (derived-mode-p 'rcf-sword-reader-mode)
            (put-text-property verse-start (point)
                               'rcf-sword-verse (butlast verse))))
        (setq previous text)))
    ;; A marker, because filling changes the text's length.
    (set-marker end (point))
    (fill-region start end)
    (goto-char end)
    (set-marker end nil)))

(defun rcf-sword--reference-string (verses)
  "Return a reference like \"Galatians 1:1-24\" describing VERSES.
VERSES must be non-empty and from a single chapter, as they are when
looked up by `rcf-sword--lookup'."
  (let* ((first-verse (car verses))
         (last-verse (car (last verses)))
         (first-num (nth 2 first-verse))
         (last-num (nth 2 last-verse)))
    (format "%s %d:%s"
            (rcf-sword--book-name-from-number (nth 0 first-verse))
            (nth 1 first-verse)
            (if (equal first-num last-num)
                first-num
              (format "%d-%d" first-num last-num)))))

(defun rcf-sword--insert-passage (verses)
  "Insert VERSES at point, formatted for the current major mode.
In `org-mode', insert a quote block preceded by a \"#+verse:\" line
holding the reference.  In `markdown-mode', insert a block quote ending
in an attribution line, optionally linked or footnoted.  Otherwise
insert plain text followed by a \" -- Reference\" line.  Point is left
at the start of the inserted passage.  If VERSES is nil, insert
nothing and say so."
  (if (null verses)
      (message "Couldn't find that verse.")
    (let* ((start (point))
           (org? (derived-mode-p 'org-mode))
           (markdown? (derived-mode-p 'markdown-mode))
           (reference (rcf-sword--reference-string verses))
           (abbreviation (or (rcf-sword-translation-abbreviation) ""))
           ;; For example "Galatians 1:1-24 KJV".
           (info (string-trim (concat reference " " abbreviation))))
      ;; Open the quote.  In org, the reference goes on its own keyword
      ;; line, because quotes weren't formatted nicely with it on the
      ;; #+begin_quote line.
      (cond
       (org? (insert "#+verse: " info "\n#+begin_quote\n"))
       (markdown? (insert "> ")))
      (rcf-sword--insert-lines verses rcf-sword-insert-verse-numbers)
      ;; Close the quote and add the attribution.
      (cond
       (org?
        (insert "\n#+end_quote\n"))
       (markdown?
        ;; An empty quoted line separates the attribution from the
        ;; passage, keeping both inside the block quote.
        (insert "\n>  \n> -- ")
        (if rcf-sword-md-link-reference
            (insert (format "[%s](https://www.biblegateway.com/passage/?search=%s&version=%s)"
                            info
                            (url-hexify-string reference)
                            (url-hexify-string abbreviation)))
          (insert info))
        (when rcf-sword-md-use-footnotes
          (if (fboundp 'markdown-insert-footnote)
              (progn
                (markdown-insert-footnote)
                (insert (format "[%s](https://www.biblegateway.com/verse/en/%s)"
                                info (url-hexify-string reference))))
            (message "Footnotes need `markdown-mode'"))))
       (t
        (insert "\n\n -- " info)))
      (goto-char start))))

;;;; Commands

;;;###autoload
(defun rcf-sword-insert-verse (reference &optional flip-numbers)
  "Insert the passage described by REFERENCE at point.
With a prefix argument (FLIP-NUMBERS), show verse numbers if
`rcf-sword-insert-verse-numbers' is off, or hide them if it's on.
Interactively, offer the reference at point as the default; earlier
references are in the history (\\`M-p').
REFERENCE looks like \"Gen 3\" (a whole chapter), \"John 3:16\" or
\"1 Cor 13:4-7\".  Book names may be abbreviated or partial.  The
passage is formatted for the current major mode; see
`rcf-sword--insert-passage'.  If REFERENCE is malformed or isn't in
the database, say what's wrong and insert nothing."
  (interactive (list (rcf-sword--read-reference "Enter verse")
                     current-prefix-arg))
  (let ((rcf-sword-insert-verse-numbers
         (xor rcf-sword-insert-verse-numbers flip-numbers)))
    (rcf-sword--insert-passage (rcf-sword--lookup reference))))

;;;###autoload
(defun rcf-sword-copy-verse (reference &optional flip-numbers)
  "Copy the passage described by REFERENCE to the kill ring.
The passage is formatted as plain text, one line per paragraph, ready
to paste into an email or chat.  Arguments are as for
`rcf-sword-insert-verse', including the prefix argument FLIP-NUMBERS."
  (interactive (list (rcf-sword--read-reference "Copy verse")
                     current-prefix-arg))
  (with-temp-buffer
    ;; Don't hard-wrap: the app it's pasted into will wrap the text.
    (setq fill-column most-positive-fixnum)
    (rcf-sword-insert-verse reference flip-numbers)
    (kill-new (buffer-string)))
  (message "Copied %s" reference))

;;;###autoload
(defun rcf-sword-insert-random-verse ()
  "Insert a random verse at point."
  (interactive)
  (rcf-sword--insert-passage (rcf-sword--random-verse)))

;;;###autoload
(defun rcf-sword-insert-random-proverb ()
  "Insert a random verse from Proverbs at point."
  (interactive)
  (rcf-sword--insert-passage
   ;; By number, not name, so it works when the books are renamed.
   (rcf-sword--random-verse 20)))

;;;; Book reader

(defun rcf-sword-toggle-margins ()
  "Toggle centered text in the current buffer.
Use `olivetti-mode' with a body `rcf-sword-reader-width' columns wide,
set only for this buffer.  If olivetti isn't installed, just say so."
  (interactive)
  (if (require 'olivetti nil t)
      (progn
        (setq-local olivetti-body-width rcf-sword-reader-width
                    olivetti-minimum-body-width rcf-sword-reader-width)
        (olivetti-mode (if olivetti-mode -1 1)))
    (message "Install the olivetti package for centered reading")))

(defvar-keymap rcf-sword-reader-mode-map
  :doc "Keymap for `rcf-sword-reader-mode'."
  :parent special-mode-map
  "q" #'kill-current-buffer
  "w" #'rcf-sword-toggle-margins
  "c" #'rcf-sword-toggle-margins
  ;; VIM never dies: j moves forward through the text and k back, by a
  ;; screenful.  Emacs calls these scroll "up" and "down" because it
  ;; names the direction the text moves, not the reader.
  "j" #'scroll-up-command
  "k" #'scroll-down-command
  "l" #'recenter-top-bottom
  ;; `scroll-lock-mode' remaps these to scroll the text one line at a
  ;; time, since the cursor is hidden.
  "n" #'next-line
  "p" #'previous-line
  "y" #'rcf-sword-reader-copy-verse
  "]" #'rcf-sword-reader-next-chapter
  "[" #'rcf-sword-reader-previous-chapter)

(defun rcf-sword--verse-at-point ()
  "Return (BOOK CHAPTER VERSE) for the verse at or before point, or nil.
Between verses, this is the verse just before point.  Only the reader
marks verses, with the `rcf-sword-verse' text property."
  (or (get-text-property (point) 'rcf-sword-verse)
      (when-let ((match (save-excursion
                          (text-property-search-backward 'rcf-sword-verse))))
        (prop-match-value match))))

(defun rcf-sword--verse-reference (verse)
  "Return a reference like \"Psalms 23:1\" for VERSE, a (BOOK CHAPTER VERSE)."
  (pcase-let ((`(,book ,chapter ,number) verse))
    (format "%s %d:%d" (rcf-sword--book-name-from-number book) chapter number)))

(defun rcf-sword-reader-copy-verse ()
  "Copy the verse at point, with its reference, to the kill ring."
  (interactive)
  (rcf-sword-copy-verse
   (rcf-sword--verse-reference
    (or (rcf-sword--verse-at-point) (user-error "No verse here")))))

(defun rcf-sword-reader-next-chapter (&optional previous)
  "Move to the start of the next chapter, or the previous one if PREVIOUS.
Chapters are found through the verse tags, so modules that skip
chapter numbers work too."
  (interactive)
  (let* ((here (nth 1 (rcf-sword--verse-at-point))) ; nil above chapter 1
         (match (save-excursion
                  (funcall (if previous #'text-property-search-backward
                             #'text-property-search-forward)
                           'rcf-sword-verse nil
                           (lambda (_ found)
                             (and found
                                  (or (null here)
                                      (funcall (if previous #'< #'>)
                                               (nth 1 found) here))))))))
    (unless match
      (user-error "No %s chapter" (if previous "previous" "next")))
    (rcf-sword--goto-verse (nth 1 (prop-match-value match)))
    ;; Show the chapter's heading, a few lines above its first verse.
    (when (eq (window-buffer) (current-buffer))
      (recenter 4))))

(defun rcf-sword-reader-previous-chapter ()
  "Move to the start of the previous chapter."
  (interactive)
  (rcf-sword-reader-next-chapter t))

(defun rcf-sword--reader-imenu-index ()
  "Return an `imenu' index of the reader's chapters.
Each entry is (\"Chapter N\" . POSITION of its first verse)."
  (save-excursion
    (goto-char (point-min))
    (let (index chapter match)
      (while (setq match (text-property-search-forward 'rcf-sword-verse))
        (unless (eql chapter (setq chapter (nth 1 (prop-match-value match))))
          (push (cons (format "Chapter %d" chapter) (prop-match-beginning match))
                index)))
      (nreverse index))))

(defun rcf-sword--reader-verse ()
  "Return the reader's current verse: the one at point, or else the first.
The result is (BOOK CHAPTER VERSE), or nil if the buffer has no verses."
  (or (rcf-sword--verse-at-point)
      (save-excursion
        (goto-char (point-min))
        (when-let ((match (text-property-search-forward 'rcf-sword-verse)))
          (prop-match-value match)))))

(defun rcf-sword--reader-revert (&rest _)
  "Re-render the reader from the database, staying on the same verse.
This is the reader's `revert-buffer-function', so \\`g' runs it: use it
after switching translations, or after the database file changes."
  (pcase-let ((`(,book ,chapter ,verse) (rcf-sword--reader-verse))
              (inhibit-read-only t))
    (erase-buffer)
    (rcf-sword--render-book (rcf-sword--book-name-from-number book)
                            (rcf-sword--verses book))
    (or (rcf-sword--goto-verse chapter verse)
        (goto-char (point-min)))))

(defun rcf-sword--bookmark-make-record ()
  "Return a bookmark for the verse at point in the reader.
Above the first verse, bookmark the first verse.  The bookmark stores a
reference, like \"Psalms 23:3\", rather than a buffer position, so it
survives re-rendering and switching translations."
  (let ((reference (rcf-sword--verse-reference (rcf-sword--reader-verse))))
    `(,reference (reference . ,reference)
                 (handler . rcf-sword-bookmark-jump))))

;;;###autoload
(defun rcf-sword-bookmark-jump (bookmark)
  "Open the reader at the verse saved in BOOKMARK.
This is the bookmark handler for reader bookmarks; it is autoloaded
so bookmarks work before rcf-sword is loaded."
  ;; `bookmark-jump' displays whatever buffer the handler leaves current.
  (set-buffer (save-window-excursion
                (rcf-sword-read-book (bookmark-prop-get bookmark 'reference)))))

;; Label reader bookmarks in M-x list-bookmarks.
(put 'rcf-sword-bookmark-jump 'bookmark-handler-type "Scripture")

(define-derived-mode rcf-sword-reader-mode special-mode "Scripture"
  "Major mode for reading a book of scripture.
The buffer is read-only, the cursor is hidden and `scroll-lock-mode'
is on, so movement keys scroll the text.

\\{rcf-sword-reader-mode-map}"
  ;; Wrap rather than truncate if the window is narrower than the text.
  (setq-local truncate-lines nil
              cursor-type nil
              ;; M-x imenu (or consult-imenu) jumps to any chapter.
              imenu-create-index-function #'rcf-sword--reader-imenu-index
              ;; C-x r m bookmarks the verse at point.
              bookmark-make-record-function #'rcf-sword--bookmark-make-record
              ;; g re-renders from the database.
              revert-buffer-function #'rcf-sword--reader-revert)
  (scroll-lock-mode 1))

(defun rcf-sword--insert-heading (title &optional underline-length)
  "Insert TITLE centered, with an em dash underline beneath it.
The underline is UNDERLINE-LENGTH characters long, or as long as
TITLE if that is nil."
  (let ((start (point)))
    (insert title "\n"
            (make-string (or underline-length (length title)) ?—)
            "\n")
    (center-region start (point))))

(defun rcf-sword--split-by-chapter (verses)
  "Split VERSES, ordered by chapter, into one list of verses per chapter.
Done in a single pass: a new group starts whenever the chapter changes."
  (let (chapters)
    (dolist (verse verses (nreverse (mapcar #'nreverse chapters)))
      (if (eq (nth 1 verse) (nth 1 (caar chapters)))
          (push verse (car chapters))
        (push (list verse) chapters)))))

(defun rcf-sword--render-book (book-name verses)
  "Insert the book called BOOK-NAME made of VERSES into the current buffer.
VERSES must be ordered by chapter, then verse.  Each verse is shown
with a superscript verse number."
  ;; A little top margin, then the book's title.
  (insert "\n\n\n")
  (rcf-sword--insert-heading book-name (+ 4 (length book-name)))
  (insert "\n")
  (let ((chapters (rcf-sword--split-by-chapter verses)))
    (dolist (chapter chapters)
      ;; Insert a chapter heading, except for the first chapter, which sits
      ;; under the book's title.
      (unless (eq chapter (car chapters))
        (insert "\n\n")
        (rcf-sword--insert-heading
         (format "%s Ch. %d" book-name (nth 1 (car chapter)))))
      (rcf-sword--insert-lines chapter t))
    (insert "\n")))

(defun rcf-sword--goto-verse (chapter &optional verse)
  "Move point to VERSE of CHAPTER in the reader, or to CHAPTER's start.
Return the new position, or nil (leaving point alone) if it isn't in
the buffer.  Uses the `rcf-sword-verse' tags on each verse."
  (when-let ((match (save-excursion
                      (goto-char (point-min))
                      (text-property-search-forward
                       'rcf-sword-verse nil
                       (lambda (_ found)
                         (and found (= (nth 1 found) chapter)
                              (or (null verse) (= (nth 2 found) verse))))))))
    (goto-char (prop-match-beginning match))))

;;;###autoload
(defun rcf-sword-read-book (book)
  "Open BOOK of the Bible in a read-only reader buffer.
BOOK may be abbreviated or partial, like \"Gen\" or \"Tim\".  It may
end with a chapter or verse, like \"John 5\" or \"John 5:1\", to open
the book at that point.  If the book is already open, switch to its
buffer; press \\`g' there to re-render it from the database.
Centers the text when olivetti is installed.  See
`rcf-sword-reader-mode' for the keys.  Return the reader buffer."
  (interactive
   (list (completing-read "Enter book or reference: " (rcf-sword--book-names))))
  (when (string-blank-p book)
    (user-error "Type a book name, like \"Genesis\" or \"Ps\""))
  ;; If the last word starts with a digit, BOOK is a reference like
  ;; "John 5:1"; check it like any other.  Otherwise it's just a name,
  ;; which may itself start with a number, like "1 John".
  (pcase-let* ((`(,book-str ,chapter ,verses)
                (if (string-match-p " [0-9][^ ]*\\'" (string-trim book))
                    (progn
                      (when-let ((problem (rcf-sword--reference-problem book)))
                        (user-error "%s" problem))
                      (rcf-sword--parse-reference book))
                  (list (string-trim book) nil nil)))
               (data (or (rcf-sword--find-book book-str)
                         (user-error "%s" (rcf-sword--no-book-message book))))
               (book-name (nth 2 data))
               (buffer-name (concat "Scripture: " book-name)))
    (if (get-buffer buffer-name)
        (pop-to-buffer-same-window buffer-name)
      (let ((verses (rcf-sword--verses (nth 1 data))))
        (unless verses
          (user-error "No verses found for %s" book-name))
        (with-current-buffer (get-buffer-create buffer-name)
          (rcf-sword-reader-mode)
          (let ((inhibit-read-only t))
            (erase-buffer)
            (rcf-sword--render-book book-name verses))
          (goto-char (point-min))
          (pop-to-buffer-same-window (current-buffer))
          ;; Start centered, but stay quiet if olivetti isn't installed.
          (when (require 'olivetti nil t)
            (rcf-sword-toggle-margins)))))
    (when chapter
      (with-current-buffer buffer-name
        (or (rcf-sword--goto-verse chapter (car verses))
            ;; Say whether the chapter or the verse is missing.
            (rcf-sword--missing-passage data chapter (car verses)))))
    (get-buffer buffer-name)))

(provide 'rcf-sword)
;;; rcf-sword.el ends here
