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
;;            installs on a vanilla Emacs without MELPA.  (The v0.2.1
;;            tag marks a docs-only commit, so this release is 0.2.2.)

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'url-util)

;; Optional integrations.  These are only used after checking that the
;; package is available, so they aren't listed in Package-Requires.
(declare-function markdown-insert-footnote "ext:markdown-mode" ())
(declare-function olivetti-mode "ext:olivetti" (&optional arg))
(defvar olivetti-mode)
(defvar olivetti-body-width)
(defvar olivetti-minimum-body-width)

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

(defcustom rcf-sword-reader-width 72
  "Body width, in columns, used when centering text in the book reader.
Only takes effect when olivetti is installed."
  :type 'integer)

;;;; Book data

;; The 66-book Protestant canon, in the order e-Sword numbers books.
;; Sorry to those who use more than 66 books - you'll have to hack this
;; for yourself.
(defconst rcf-sword-books
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
to match what the user types and to label inserted passages.")

(defun rcf-sword--book-names ()
  "Return the names of all books in `rcf-sword-books'."
  (mapcar #'cl-caddr rcf-sword-books))

(defun rcf-sword--find-book (partial)
  "Return the first book triple whose name matches PARTIAL, or nil.
First look for a name that starts with PARTIAL, then for one that
contains it, each time in canonical order.  Matching ignores case,
so \"jo\" finds Joshua and \"tim\" finds 1 Timothy."
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
  "Return the name of book NUMBER, or nil if there is no such book."
  (nth 2 (seq-find (lambda (book) (equal (nth 1 book) number))
                   rcf-sword-books)))

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
if SQLite is unavailable or the file is unset or unreadable."
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
      (setq rcf-sword--db (sqlite-open file)
            rcf-sword--db-file file))
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

;; A random verse is chosen by picking a book, then a chapter in it, then
;; a verse in that chapter, each uniformly.  Verses in short books are
;; therefore more likely than verses in long ones.  Chapters and verses
;; are assumed to be numbered from 1 without gaps.

(defun rcf-sword--random-chapter (book)
  "Return a random chapter number in BOOK.
Return 1 if BOOK isn't in the database."
  (let ((max-chapter
         (or (caar (rcf-sword--query
                    "SELECT MAX(Chapter) FROM Bible WHERE Book=?;" (list book)))
             0)))
    (1+ (random (max 1 max-chapter)))))

(defun rcf-sword--random-verse-number (book chapter)
  "Return a random verse number in BOOK and CHAPTER.
Return 1 if the chapter isn't in the database."
  (let ((max-verse
         (or (caar (rcf-sword--query
                    "SELECT MAX(Verse) FROM Bible WHERE Book=? AND Chapter=?;"
                    (list book chapter)))
             0)))
    (1+ (random (max 1 max-verse)))))

(defun rcf-sword--random-verse-in-book (book)
  "Return a random verse from BOOK as a list of one verse.
Return nil if BOOK isn't in the database."
  (let* ((chapter (rcf-sword--random-chapter book))
         (verse (rcf-sword--random-verse-number book chapter)))
    (rcf-sword--verses book chapter verse verse)))

;;;; Parsing references

(defun rcf-sword--parse-reference (str)
  "Parse a reference STR like \"1 John 3:1-2\".
Return (BOOK CHAPTER VERSES).  BOOK is everything before the last
word, as typed (it may be partial, and is \"\" if STR is one word).
CHAPTER is a number, 0 if the last word doesn't start with one.
VERSES is nil for a whole chapter, (VERSE) for one verse, or
\(FIRST LAST) for a range."
  (let* ((words (split-string (string-trim str) " " t))
         (chapter-verse (car (last words)))
         (book (string-join (butlast words) " "))
         (chapter-verse-split (split-string chapter-verse ":"))
         (verses? (length> chapter-verse-split 1))
         (chapter (car chapter-verse-split))
         (verses (split-string (car (last chapter-verse-split)) "-" t)))
    (list book
          (string-to-number chapter)
          (when verses? (mapcar #'string-to-number verses)))))

(defun rcf-sword--lookup (str)
  "Return the verses described by the reference STR.
Signal a `user-error' if no book matches.  Return nil if the book
matches but the chapter or verses aren't in the database."
  (pcase-let* ((`(,book-str ,chapter ,verses) (rcf-sword--parse-reference str))
               (book (and (not (string-empty-p book-str))
                          (rcf-sword--book-number book-str))))
    (unless book
      (user-error "Couldn't find a book matching \"%s\"" book-str))
    (rcf-sword--verses book chapter (car verses) (cadr verses))))

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
      (let ((text (string-trim (nth 3 verse))))
        (when previous
          (insert (if (or (rcf-sword--end-is-continuation-p previous)
                          (rcf-sword--start-is-continuation-p text))
                      " "
                    paragraph-break)))
        (when show-verse-numbers
          (insert (rcf-sword--superscript (nth 2 verse))))
        (insert text)
        (setq previous text)))
    ;; A marker, because stripping and filling change the text's length.
    (set-marker end (point))
    ;; For now, just remove footnote markers like {\cf2\super [18]}.
    ;; Note that the continuation checks above see the raw text, so a
    ;; verse ending in a marker after its punctuation isn't treated as
    ;; continuing.
    (replace-regexp-in-region "{[^}]*}" "" start end)
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
      (rcf-sword--insert-lines verses nil)
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
(defun rcf-sword-insert-verse (reference)
  "Insert the passage described by REFERENCE at point.
REFERENCE looks like \"Gen 3\" (a whole chapter), \"John 3:16\" or
\"1 Cor 13:4-7\".  Book names may be abbreviated or partial.  The
passage is formatted for the current major mode; see
`rcf-sword--insert-passage'."
  (interactive (list (read-string "Enter verse: ")))
  (rcf-sword--insert-passage (rcf-sword--lookup reference)))

;;;###autoload
(defun rcf-sword-insert-random-verse ()
  "Insert a random verse at point."
  (interactive)
  (rcf-sword--insert-passage
   ;; Book numbers run from 1 to the number of books.
   (rcf-sword--random-verse-in-book
    (1+ (random (length rcf-sword-books))))))

;;;###autoload
(defun rcf-sword-insert-random-proverb ()
  "Insert a random verse from Proverbs at point."
  (interactive)
  (rcf-sword--insert-passage
   (rcf-sword--random-verse-in-book (rcf-sword--book-number "Proverbs"))))

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
  "p" #'previous-line)

(define-derived-mode rcf-sword-reader-mode special-mode "Scripture"
  "Major mode for reading a book of scripture.
The buffer is read-only, the cursor is hidden and `scroll-lock-mode'
is on, so movement keys scroll the text.

\\{rcf-sword-reader-mode-map}"
  ;; Wrap rather than truncate if the window is narrower than the text.
  (setq-local truncate-lines nil
              cursor-type nil)
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

(defun rcf-sword--render-book (book-name verses)
  "Insert the book called BOOK-NAME made of VERSES into the current buffer.
VERSES must be ordered by chapter, then verse.  Each verse is shown
with a superscript verse number."
  ;; A little top margin, then the book's title.
  (insert "\n\n\n")
  (rcf-sword--insert-heading book-name (+ 4 (length book-name)))
  (insert "\n")
  (let ((chapters (seq-uniq (mapcar #'cadr verses))))
    (dolist (chapter chapters)
      ;; Insert a chapter heading, except for the first chapter, which sits
      ;; under the book's title.
      (unless (eq chapter (car chapters))
        (insert "\n\n")
        (rcf-sword--insert-heading (format "%s Ch. %d" book-name chapter)))
      (rcf-sword--insert-lines
       (seq-filter (lambda (verse) (eq (nth 1 verse) chapter)) verses)
       t))
    (insert "\n")))

;; TODO: Accept "John 5" or "John 5:1" and jump right to that point when
;; the book is opened.

;;;###autoload
(defun rcf-sword-read-book (book)
  "Open BOOK of the Bible in a read-only reader buffer.
BOOK may be abbreviated or partial, like \"Gen\" or \"Tim\".  If the
book is already open, switch to its buffer as is; kill that buffer to
reload it, e.g. after changing translations.  Centers the text when
olivetti is installed.  See `rcf-sword-reader-mode' for the keys."
  (interactive
   (list (completing-read "Enter book: " (rcf-sword--book-names))))
  (let* ((data (or (rcf-sword--find-book book)
                   (user-error "Couldn't find a book starting with or including `%s' - try again?"
                               book)))
         (book-name (nth 2 data))
         (buffer-name (concat "Scripture: " book-name))
         (existing (get-buffer buffer-name)))
    (if existing
        (pop-to-buffer-same-window existing)
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
            (rcf-sword-toggle-margins)))))))

(provide 'rcf-sword)
;;; rcf-sword.el ends here
