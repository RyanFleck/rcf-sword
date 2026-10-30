;;; rcf-sword-test.el --- Tests for rcf-sword  -*- lexical-binding: t; no-byte-compile: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; ERT tests.  Database tests build a tiny .bblx fixture in a temp file.
;; Run with `make test'.
;;
;; `no-byte-compile' is set above because package-vc byte-compiles every
;; file in the repository on install, and these tests aren't part of the
;; package.  Without it, users would see test warnings when installing.

;;; Code:

(require 'ert)
(require 'rcf-sword)

;;;; Fixture

(defconst rcf-sword-test--verses
  ;; Public domain King James Version text.
  '((1 1 1 " In the beginning God created the heaven and the earth.")
    (1 1 2 " And the earth was without form, and void;{\\cf2\\super [1]} and darkness was upon the face of the deep.")
    (1 1 3 " And God said, Let there be light: and there was light.")
    (19 23 1 " The LORD is my shepherd; I shall not want.")
    (19 23 2 " He maketh me to lie down in green pastures: he leadeth me beside the still waters.")
    (19 23 3 " He restoreth my soul: he leadeth me in the paths of righteousness for his name's sake.")
    (20 1 1 " The proverbs of Solomon the son of David, king of Israel;"))
  "Verses inserted into the fixture database.")

(defmacro rcf-sword-test--with-db (&rest body)
  "Run BODY with `rcf-sword-bblx-file' bound to a fixture database."
  (declare (indent 0) (debug t))
  `(let* ((file (make-temp-file "rcf-sword-test" nil ".bblx"))
          (rcf-sword-bblx-file file))
     (unwind-protect
         (progn
           (let ((db (sqlite-open file)))
             (sqlite-execute db "CREATE TABLE Bible (Book INT, Chapter INT, Verse INT, Scripture TEXT);")
             (sqlite-execute db "CREATE TABLE Details (Description TEXT, Abbreviation TEXT);")
             (sqlite-execute db "INSERT INTO Details VALUES ('King James Version', 'KJV');")
             (dolist (verse rcf-sword-test--verses)
               (sqlite-execute db "INSERT INTO Bible VALUES (?, ?, ?, ?);" verse))
             (sqlite-close db))
           (rcf-sword-close-database)
           ,@body)
       (rcf-sword-close-database)
       (delete-file file))))

;;;; Pure functions

(ert-deftest rcf-sword-test-find-book ()
  (should (equal (rcf-sword--book-number "Gen") 1))
  (should (equal (rcf-sword--book-number "gen") 1))
  (should (equal (rcf-sword--book-number "Lam") 25))
  (should (equal (rcf-sword--book-number "1 John") 62))
  ;; "Tim" isn't a prefix of any book, so fall back to substring matching.
  (should (equal (rcf-sword--book-number "Tim") 54))
  ;; "Job" is a prefix of Job, so prefer it over substrings.
  (should (equal (rcf-sword--book-number "Job") 18))
  (should-not (rcf-sword--book-number "Nonexistent"))
  ;; Substring matches ignore case, and treat regexp characters literally.
  (should (equal (rcf-sword--book-number "TIM") 54))
  (should (equal (rcf-sword--book-number "of Sol") 22))
  (should-not (rcf-sword--book-number "."))
  (should-not (rcf-sword--book-number "Gen.*")))

(ert-deftest rcf-sword-test-book-numbers-are-sequential ()
  (should (equal (mapcar #'cadr rcf-sword-books) (number-sequence 1 66))))

(ert-deftest rcf-sword-test-parse-reference ()
  (should (equal (rcf-sword--parse-reference "Genesis 6") '("Genesis" 6 nil)))
  (should (equal (rcf-sword--parse-reference "Genesis 6:1") '("Genesis" 6 (1))))
  (should (equal (rcf-sword--parse-reference "Genesis 6:1-2") '("Genesis" 6 (1 2))))
  (should (equal (rcf-sword--parse-reference "  1 Cor 13:4-7 ") '("1 Cor" 13 (4 7))))
  (should (equal (rcf-sword--parse-reference "Song  of Solomon 2") '("Song of Solomon" 2 nil)))
  (should (equal (rcf-sword--parse-reference "Jude") '("" 0 nil))))

(ert-deftest rcf-sword-test-superscript ()
  (should (equal (rcf-sword--superscript 0) "⁰"))
  (should (equal (rcf-sword--superscript 123) "¹²³"))
  (should (equal (rcf-sword--superscript 4567890) "⁴⁵⁶⁷⁸⁹⁰")))

(ert-deftest rcf-sword-test-continuation ()
  (should (rcf-sword--start-is-continuation-p "and darkness"))
  (should (rcf-sword--start-is-continuation-p "And darkness"))
  (should (rcf-sword--start-is-continuation-p "whoever believes"))
  (should-not (rcf-sword--start-is-continuation-p "Then God said"))
  (should-not (rcf-sword--start-is-continuation-p "\"Let there be light\""))
  (should-not (rcf-sword--start-is-continuation-p ""))
  (should (rcf-sword--end-is-continuation-p "begotten Son,"))
  (should (rcf-sword--end-is-continuation-p "of Israel:"))
  (should-not (rcf-sword--end-is-continuation-p "and the earth.")))

(ert-deftest rcf-sword-test-loading-has-no-side-effects ()
  (should-not rcf-sword--db))

(ert-deftest rcf-sword-test-no-third-party-dependencies ()
  ;; The package only uses built-in libraries, so it installs on a vanilla
  ;; Emacs.  The Makefile doesn't install s.el, so a stray s- call would
  ;; also fail byte-compilation.
  (should-not (featurep 's)))

;;;; Built-in string handling
;;
;; rcf-sword used s.el until 0.2.2.  These tests pin the behaviour of each
;; built-in replacement at its call site.  The expected values were
;; checked against the s.el-based v0.2.0 release over a wide set of inputs
;; (whitespace variants, case, regexp characters, Unicode, empty strings),
;; and every result matched.

(ert-deftest rcf-sword-test-strings-prefix-ignores-case ()
  ;; `string-prefix-p' with IGNORE-CASE replaced `s-starts-with?'.
  (should (equal (rcf-sword--book-number "GEN") 1))
  (should (equal (rcf-sword--book-number "gEn") 1))
  (should (equal (rcf-sword--book-number "1 JOHN") 62))
  (should (equal (rcf-sword--book-number "song of") 22))
  ;; The empty string is a prefix of every name, so it finds the first book.
  (should (equal (rcf-sword--book-number "") 1)))

(ert-deftest rcf-sword-test-strings-contains-ignores-case ()
  ;; A case-folded `string-match-p' on a `regexp-quote'd needle replaced
  ;; `s-contains?' with IGNORE-CASE.
  (should (equal (rcf-sword--book-number "TIM") 54))
  (should (equal (rcf-sword--book-number "of sol") 22))
  ;; Contains matches go in canonical order: John before 1 John.
  (should (equal (rcf-sword--book-number "OHN") 43))
  (should (equal (rcf-sword--book-number "ohn") 43)))

(ert-deftest rcf-sword-test-strings-contains-is-literal ()
  ;; Regexp characters in what the user types match literally, so they
  ;; neither error nor act as wildcards.
  (dolist (needle '("." ".*" "J.hn" "Gen.*" "[" "]" "\\" "(" "?" "+" "^G" "s$"))
    (should-not (rcf-sword--find-book needle))))

(ert-deftest rcf-sword-test-strings-parse-whitespace ()
  ;; `split-string' with OMIT-NULLS replaced `s-trim' and `s-split'.
  ;; Outer whitespace of any kind is ignored, and runs of spaces between
  ;; words collapse.
  (should (equal (rcf-sword--parse-reference " \t1 Cor 13:4-7\r\n ")
                 '("1 Cor" 13 (4 7))))
  (should (equal (rcf-sword--parse-reference "1   Cor   13")
                 '("1 Cor" 13 nil)))
  ;; `string-join' replaced `s-join': book words rejoin with single spaces.
  (should (equal (rcf-sword--parse-reference "Song  of   Solomon 2:1")
                 '("Song of Solomon" 2 (1))))
  ;; Since 0.2.2, tabs, newlines and non-breaking spaces separate words
  ;; too.  (With s.el only spaces did, so "Ps\t23" was one word.)
  (should (equal (rcf-sword--parse-reference "Ps\t23") '("Ps" 23 nil)))
  (should (equal (rcf-sword--parse-reference "1\u00a0Cor\n13:4") '("1 Cor" 13 (4)))))

(ert-deftest rcf-sword-test-strings-parse-verse-ranges ()
  ;; `split-string' on ":" (keeping empty parts) and on "-" (omitting
  ;; them) replaced `s-split'.
  (should (equal (rcf-sword--parse-reference "Ps 23:") '("Ps" 23 nil)))
  (should (equal (rcf-sword--parse-reference "Ps 23:1-") '("Ps" 23 (1))))
  (should (equal (rcf-sword--parse-reference "Ps 23:1-2-3") '("Ps" 23 (1 2 3))))
  (should (equal (rcf-sword--parse-reference "Ps :1") '("Ps" 0 (1)))))

(ert-deftest rcf-sword-test-strings-blank-reference ()
  ;; A blank reference is rejected, with a friendly message since 0.2.2.
  (should-error (rcf-sword--lookup "") :type 'user-error)
  (should-error (rcf-sword--lookup "   ") :type 'user-error))

(ert-deftest rcf-sword-test-strings-first-word ()
  ;; `split-string' with OMIT-NULLS replaced `s-split' when taking a
  ;; verse's first word.
  (should (rcf-sword--start-is-continuation-p "  and so"))
  (should (rcf-sword--start-is-continuation-p "AND so"))
  (should-not (rcf-sword--start-is-continuation-p "   "))
  ;; The whole first word is compared, punctuation included, so "And,"
  ;; isn't a conjunction and isn't lowercase.
  (should-not (rcf-sword--start-is-continuation-p "And, behold")))

(ert-deftest rcf-sword-test-strings-trim-verses ()
  ;; `string-trim' replaced `s-trim' on each verse's text, removing
  ;; spaces, tabs, carriage returns and newlines at either end.
  (with-temp-buffer
    (rcf-sword--insert-lines '((1 1 1 "\t In the beginning.\r\n ")
                               (1 1 2 "\nAnd the earth was void. \t"))
                             nil)
    (should (equal (buffer-string)
                   "In the beginning. And the earth was void."))))

;;;; Malformed input

(defun rcf-sword-test--user-error (function &rest args)
  "Call FUNCTION with ARGS and return its `user-error' message, or nil."
  (condition-case err
      (progn (apply function args) nil)
    (user-error (error-message-string err))))

(ert-deftest rcf-sword-test-reference-problems ()
  ;; Each kind of malformed reference gets a message saying what's wrong
  ;; and how to fix it.  None of this needs a database.
  (pcase-dolist
      (`(,input ,message)
       '(("" "Type a reference, like \"John 3:16\", \"Gen 1\" or \"1 Cor 13:4-7\"")
         (" \t " "Type a reference, like \"John 3:16\", \"Gen 1\" or \"1 Cor 13:4-7\"")
         ("Jude" "Add a chapter number, like \"Jude 1\"")
         ("rev" "Add a chapter number, like \"Revelation 1\"")
         ("Foo" "No book matches \"Foo\"; try a name like \"Gen\", \"1 Cor\" or \"Psalms\"")
         ("Foo 3" "No book matches \"Foo\"; try a name like \"Gen\", \"1 Cor\" or \"Psalms\"")
         ("John3:16" "Put a space before the chapter, like \"John 3:16\"")
         ("1 John3" "Put a space before the chapter, like \"1 John 3\"")
         ("3:16" "Add a book name before \"3:16\", like \"John 3:16\"")
         ("Ps abc" "Can't read \"abc\" as a chapter and verses; use a form like 3, 3:16 or 3:16-18")
         ("Ps 23:a" "Can't read \"23:a\" as a chapter and verses; use a form like 3, 3:16 or 3:16-18")
         ("Ps 23:1-2-3" "Can't read \"23:1-2-3\" as a chapter and verses; use a form like 3, 3:16 or 3:16-18")
         ("Ps 23::1" "Can't read \"23::1\" as a chapter and verses; use a form like 3, 3:16 or 3:16-18")
         ("Ps :1" "Can't read \":1\" as a chapter and verses; use a form like 3, 3:16 or 3:16-18")
         ("Ps -1" "Can't read \"-1\" as a chapter and verses; use a form like 3, 3:16 or 3:16-18")
         ("Ps 0" "Chapters and verses start at 1, so \"0\" doesn't exist")
         ("Ps 23:0" "Chapters and verses start at 1, so \"23:0\" doesn't exist")
         ("Ps 23:5-2" "The verses in \"23:5-2\" run backwards; did you mean 23:2-5?")))
    (should (equal (cons input (rcf-sword--reference-problem input))
                   (cons input message)))))

(ert-deftest rcf-sword-test-reference-problems-accepts-valid ()
  ;; Well-formed references pass, including the forgiving forms.
  (dolist (input '("Ps 23" "Ps 23:" "Ps 23:1" "Ps 23:1-" "Ps 23:1-2"
                   " 1 Cor 13:4-7 " "Song of Solomon 2" "Ps\t23" "gen 1"))
    (should (equal (cons input (rcf-sword--reference-problem input))
                   (list input)))))

(ert-deftest rcf-sword-test-malformed-input-needs-no-database ()
  ;; Malformed input is reported before the database is opened, so the
  ;; message is accurate even when the database isn't set up.
  (let ((rcf-sword-bblx-file nil))
    (should (equal (rcf-sword-test--user-error #'rcf-sword--lookup "Jude")
                   "Add a chapter number, like \"Jude 1\""))))

;;;; Database-backed

(ert-deftest rcf-sword-test-missing-file ()
  (let ((rcf-sword-bblx-file nil))
    (should-error (rcf-sword--get-db) :type 'user-error))
  (let ((rcf-sword-bblx-file "/nonexistent/file.bblx"))
    (should-error (rcf-sword--get-db) :type 'user-error)))

(ert-deftest rcf-sword-test-lookup ()
  (rcf-sword-test--with-db
    (should (equal (rcf-sword-translation-name) "King James Version"))
    (should (equal (rcf-sword-translation-abbreviation) "KJV"))
    (should (equal (mapcar #'cl-caddr (rcf-sword--lookup "Gen 1")) '(1 2 3)))
    (should (equal (mapcar #'cl-caddr (rcf-sword--lookup "Gen 1:2")) '(2)))
    (should (equal (mapcar #'cl-caddr (rcf-sword--lookup "Ps 23:1-2")) '(1 2)))
    (should-error (rcf-sword--lookup "Nonexistent 1:1") :type 'user-error)))

(ert-deftest rcf-sword-test-insert-plain ()
  (rcf-sword-test--with-db
    (with-temp-buffer
      (rcf-sword-insert-verse "Psalm 23:1-3")
      (should (= (point) (point-min)))
      (should (equal (buffer-string)
                     (concat "The LORD is my shepherd; I shall not want.\n"
                             "\n"
                             "He maketh me to lie down in green pastures: he leadeth me beside the\n"
                             "still waters.\n"
                             "\n"
                             "He restoreth my soul: he leadeth me in the paths of righteousness for\n"
                             "his name's sake.\n"
                             "\n"
                             " -- Psalms 23:1-3 KJV"))))))

(ert-deftest rcf-sword-test-insert-org ()
  (rcf-sword-test--with-db
    (with-temp-buffer
      (org-mode)
      (rcf-sword-insert-verse "Gen 1:1-3")
      (should (equal (buffer-string)
                     (concat "#+verse: Genesis 1:1-3 KJV\n"
                             "#+begin_quote\n"
                             "In the beginning God created the heaven and the earth. And the earth\n"
                             "was without form, and void; and darkness was upon the face of the\n"
                             "deep. And God said, Let there be light: and there was light.\n"
                             "#+end_quote\n"))))))

(ert-deftest rcf-sword-test-insert-markdown ()
  (skip-unless (require 'markdown-mode nil t))
  (rcf-sword-test--with-db
    (with-temp-buffer
      (markdown-mode)
      (let ((rcf-sword-md-link-reference t))
        (rcf-sword-insert-verse "Psalm 23:1-2"))
      (should (equal (substring-no-properties (buffer-string))
                     (concat "> The LORD is my shepherd; I shall not want.\n"
                             "> \n"
                             "> He maketh me to lie down in green pastures: he leadeth me beside the\n"
                             "> still waters.\n"
                             ">  \n"
                             "> -- [Psalms 23:1-2 KJV](https://www.biblegateway.com/passage/"
                             "?search=Psalms%2023%3A1-2&version=KJV)"))))))

(ert-deftest rcf-sword-test-missing-passages ()
  ;; Well-formed references that aren't in the database say what's
  ;; missing.  The fixture has Genesis 1, Psalms 23 and Proverbs 1.
  (rcf-sword-test--with-db
    (should (equal (rcf-sword-test--user-error #'rcf-sword--lookup "Matt 1")
                   "This translation doesn't include Matthew"))
    (should (equal (rcf-sword-test--user-error #'rcf-sword--lookup "Ps 151")
                   "Psalms ends at chapter 23, so there's no chapter 151"))
    (should (equal (rcf-sword-test--user-error #'rcf-sword--lookup "Ps 23:50-60")
                   "Psalms 23 ends at verse 3, so there's no verse 50"))
    ;; A range that only partly exists returns the verses that do.
    (should (equal (mapcar #'cl-caddr (rcf-sword--lookup "Ps 23:2-50")) '(2 3)))))

(ert-deftest rcf-sword-test-insert-malformed-leaves-buffer-alone ()
  (rcf-sword-test--with-db
    (with-temp-buffer
      (insert "notes")
      (should (equal (rcf-sword-test--user-error #'rcf-sword-insert-verse "Ps 23:5-2")
                     "The verses in \"23:5-2\" run backwards; did you mean 23:2-5?"))
      (should (equal (rcf-sword-test--user-error #'rcf-sword-insert-verse "Ps 99")
                     "Psalms ends at chapter 23, so there's no chapter 99"))
      (should (equal (buffer-string) "notes")))))

(ert-deftest rcf-sword-test-read-book-malformed ()
  (rcf-sword-test--with-db
    (should (equal (rcf-sword-test--user-error #'rcf-sword-read-book "")
                   "Type a book name, like \"Genesis\" or \"Ps\""))
    (should (equal (rcf-sword-test--user-error #'rcf-sword-read-book "Foo")
                   "No book matches \"Foo\"; try a name like \"Gen\", \"1 Cor\" or \"Psalms\""))))

(ert-deftest rcf-sword-test-random-is-fair ()
  ;; Every verse is equally likely, wherever it is.  The fixture has 7
  ;; verses in 3 books, so with the old book-then-chapter-then-verse
  ;; sampling Proverbs 1:1 came up a third of the time.  Now each verse
  ;; should come up about 1/7 of the time: 700 draws give ~100 each.
  (rcf-sword-test--with-db
    (let ((counts (make-hash-table :test #'equal)))
      (dotimes (_ 700)
        (cl-incf (gethash (butlast (car (rcf-sword--random-verse)))
                          counts 0)))
      (should (= (hash-table-count counts) 7))
      (maphash (lambda (_verse n) (should (< 50 n 160))) counts))
    ;; With a book, only that book's verses are drawn.
    (dotimes (_ 20)
      (should (= (caar (rcf-sword--random-verse 19)) 19)))
    (should-not (rcf-sword--random-verse 40))))

(ert-deftest rcf-sword-test-random ()
  (rcf-sword-test--with-db
    (with-temp-buffer
      (rcf-sword-insert-random-proverb)
      (should (string-match-p "Proverbs 1:1 KJV" (buffer-string))))))

(ert-deftest rcf-sword-test-read-book ()
  (rcf-sword-test--with-db
    (save-window-excursion
      (rcf-sword-read-book "Gen")
      (unwind-protect
          (with-current-buffer "Scripture: Genesis"
            (should (derived-mode-p 'rcf-sword-reader-mode))
            (should buffer-read-only)
            (should (string-match-p "¹In the beginning" (buffer-string)))
            (should-not cursor-type)
            (should scroll-lock-mode)
            (should (eq (lookup-key rcf-sword-reader-mode-map "n") #'next-line))
            (should-not (string-match-p "cf2" (buffer-string))))
        (kill-buffer "Scripture: Genesis")))))

(provide 'rcf-sword-test)
;;; rcf-sword-test.el ends here
