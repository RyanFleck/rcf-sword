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
(require 'bookmark)

;;;; Fixture

(defconst rcf-sword-test--verses
  ;; Public domain King James Version text.
  '((1 1 1 " In the beginning God created the heaven and the earth.")
    (1 1 2 " And the earth was without form, and void;{\\cf2\\super [1]} and darkness was upon the face of the deep.")
    (1 1 3 " And God said, Let there be light: and there was light.")
    (19 1 1 " Blessed is the man that walketh not in the counsel of the ungodly, nor standeth in the way of sinners, nor sitteth in the seat of the scornful.")
    (19 2 1 " Why do the heathen rage, and the people imagine a vain thing?")
    (19 23 1 " The LORD is my shepherd; I shall not want.")
    (19 23 2 " He maketh me to lie down in green pastures: he leadeth me beside the still waters.")
    (19 23 3 " He restoreth my soul: he leadeth me in the paths of righteousness for his name's sake.")
    (20 1 1 " The proverbs of Solomon the son of David, king of Israel;")
    ;; Book 67 isn't in the default `rcf-sword-books', like an apocryphal
    ;; book in some modules.
    (67 1 1 " The book of the words of Tobit."))
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

(ert-deftest rcf-sword-test-book-aliases ()
  ;; Common abbreviations that prefix and substring matching miss.
  (pcase-dolist (`(,partial ,number)
                 '(("Jn" 43) ("jn" 43) ("Mt" 40) ("Mk" 41) ("Lk" 42)
                   ("Jas" 59) ("Phlm" 57) ("Rv" 66) ("Revelations" 66)
                   ("song of songs" 22) ("Canticles" 22) ("Qoh" 21)
                   ;; Ordinals in any form, with or without an alias.
                   ("1 Jn" 62) ("I John" 62) ("First John" 62) ("1st Jn" 62)
                   ("II Kings" 12) ("III Jn" 64) ("2 Tm" 55) ("1 Pt" 60)
                   ;; Existing matches are unaffected.
                   ("Is" 23) ("Phil" 50) ("Jud" 7) ("1 Cor" 46)))
    (should (equal (cons partial (rcf-sword--book-number partial))
                   (cons partial number))))
  ;; Every alias must resolve to a book.
  (pcase-dolist (`(,alias . ,_) rcf-sword-book-aliases)
    (should (rcf-sword--find-book alias))))

(ert-deftest rcf-sword-test-book-numbers-are-sequential ()
  (should (equal (mapcar #'cadr rcf-sword-books) (number-sequence 1 66))))

(ert-deftest rcf-sword-test-reference-spans ()
  (pcase-dolist (`(,input ,parsed)
                 '(("Genesis 6" ("Genesis" ((6 nil 6 nil))))
                   ("Genesis 6:1" ("Genesis" ((6 1 6 1))))
                   ("Genesis 6:1-2" ("Genesis" ((6 1 6 2))))
                   ("  1 Cor 13:4-7 " ("1 Cor" ((13 4 13 7))))
                   ("Song  of Solomon 2" ("Song of Solomon" ((2 nil 2 nil))))
                   ;; Ranges across chapters.
                   ("John 3:16-4:2" ("John" ((3 16 4 2))))
                   ;; Lists, with or without spaces; they belong to the last
                   ;; chapter named.
                   ("Ps 23:1,4" ("Ps" ((23 1 23 1) (23 4 23 4))))
                   ("Ps 23:1-2, 4-5,  6" ("Ps" ((23 1 23 2) (23 4 23 5) (23 6 23 6))))
                   ("John 3:16-4:2,5" ("John" ((3 16 4 2) (4 5 4 5))))
                   ;; Not a chapter and verses.
                   ("Jude" nil) ("Ps 23:1-2-3" nil) ("Ps 23:1,,4" nil)))
    (should (equal (cons input (rcf-sword--reference-spans input))
                   (cons input parsed)))))

(ert-deftest rcf-sword-test-reference-string ()
  ;; Labels collapse consecutive verses, across chapters too.
  (pcase-dolist (`(,verses ,label)
                 '((((19 23 1)) "Psalms 23:1")
                   (((19 23 1) (19 23 2) (19 23 3)) "Psalms 23:1-3")
                   (((19 23 1) (19 23 2) (19 23 4)) "Psalms 23:1-2, 4")
                   (((43 3 35) (43 3 36) (43 4 1) (43 4 2)) "John 3:35-4:2")
                   (((19 1 1) (19 2 3)) "Psalms 1:1, 2:3")))
    (should (equal (rcf-sword--reference-string verses) label))))

(ert-deftest rcf-sword-test-split-by-chapter ()
  (should (equal (rcf-sword--split-by-chapter
                  '((19 1 1 "a") (19 1 2 "b") (19 2 1 "c") (19 3 1 "d") (19 3 2 "e")))
                 '(((19 1 1 "a") (19 1 2 "b"))
                   ((19 2 1 "c"))
                   ((19 3 1 "d") (19 3 2 "e")))))
  (should-not (rcf-sword--split-by-chapter nil)))

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
  (should (equal (car (rcf-sword--reference-spans " \t1 Cor 13:4-7\r\n "))
                 "1 Cor"))
  (should (equal (car (rcf-sword--reference-spans "1   Cor   13")) "1 Cor"))
  ;; `string-join' replaced `s-join': book words rejoin with single spaces.
  (should (equal (car (rcf-sword--reference-spans "Song  of   Solomon 2:1"))
                 "Song of Solomon"))
  ;; Since 0.2.2, tabs, newlines and non-breaking spaces separate words
  ;; too.  (With s.el only spaces did, so "Ps\t23" was one word.)
  (should (equal (rcf-sword--reference-spans "Ps\t23") '("Ps" ((23 nil 23 nil)))))
  (should (equal (rcf-sword--reference-spans "1\u00a0Cor\n13:4") '("1 Cor" ((13 4 13 4))))))

(ert-deftest rcf-sword-test-strings-parse-verse-ranges ()
  ;; A trailing colon or dash is forgiven: "Ps 23:" is the whole chapter
  ;; and "Ps 23:1-" is verse 1.  (Since 0.3.0 a regexp parses these.)
  (should (equal (rcf-sword--reference-spans "Ps 23:") '("Ps" ((23 nil 23 nil)))))
  (should (equal (rcf-sword--reference-spans "Ps 23:1-") '("Ps" ((23 1 23 1)))))
  (should-not (rcf-sword--reference-spans "Ps 23:1-2-3"))
  (should-not (rcf-sword--reference-spans "Ps :1")))

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

(ert-deftest rcf-sword-test-footnotes-dont-break-paragraphs ()
  ;; A footnote marker after a verse's closing semicolon used to hide the
  ;; semicolon from the continuation check, starting a new paragraph.
  (with-temp-buffer
    (rcf-sword--insert-lines '((1 1 1 "The earth was void;{\\cf2\\super [1]}")
                               (1 1 2 "The deep was dark."))
                             nil)
    (should (equal (buffer-string)
                   "The earth was void; The deep was dark."))))

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
         ("Ps abc" "Can't read \"abc\" as a chapter and verses; use a form like 3, 3:16, 3:16-18, 3:16,18 or 3:16-4:2")
         ("Ps 23:a" "Can't read \"23:a\" as a chapter and verses; use a form like 3, 3:16, 3:16-18, 3:16,18 or 3:16-4:2")
         ("Ps 23:1-2-3" "Can't read \"23:1-2-3\" as a chapter and verses; use a form like 3, 3:16, 3:16-18, 3:16,18 or 3:16-4:2")
         ("Ps 23::1" "Can't read \"23::1\" as a chapter and verses; use a form like 3, 3:16, 3:16-18, 3:16,18 or 3:16-4:2")
         ("Ps :1" "Can't read \":1\" as a chapter and verses; use a form like 3, 3:16, 3:16-18, 3:16,18 or 3:16-4:2")
         ("Ps -1" "Can't read \"-1\" as a chapter and verses; use a form like 3, 3:16, 3:16-18, 3:16,18 or 3:16-4:2")
         ("Ps 0" "Chapters and verses start at 1, so \"0\" doesn't exist")
         ("Ps 23:0" "Chapters and verses start at 1, so \"23:0\" doesn't exist")
         ("Ps 23:5-2" "The verses in \"23:5-2\" run backwards; did you mean 23:2-5?")
         ("John 4:2-3:16" "The verses in \"4:2-3:16\" run backwards; did you mean 3:16-4:2?")
         ("Ps 23:1,5-2" "The verses in \"23:1,5-2\" run backwards; did you mean 23:2-5?")
         ("Ps 23:1,0" "Chapters and verses start at 1, so \"23:1,0\" doesn't exist")))
    (should (equal (cons input (rcf-sword--reference-problem input))
                   (cons input message)))))

(ert-deftest rcf-sword-test-reference-problems-accepts-valid ()
  ;; Well-formed references pass, including the forgiving forms.
  (dolist (input '("Ps 23" "Ps 23:" "Ps 23:1" "Ps 23:1-" "Ps 23:1-2"
                   "John 3:16-4:2" "Ps 23:1,3" "Ps 23:1, 3"
                   " 1 Cor 13:4-7 " "Song of Solomon 2" "Ps\t23" "gen 1"))
    (should (equal (cons input (rcf-sword--reference-problem input))
                   (list input)))))

(ert-deftest rcf-sword-test-malformed-input-needs-no-database ()
  ;; Malformed input is reported before the database is opened, so the
  ;; message is accurate even when the database isn't set up.
  (let ((rcf-sword-bblx-file nil))
    (should (equal (rcf-sword-test--user-error #'rcf-sword--lookup "Jude")
                   "Add a chapter number, like \"Jude 1\""))))

;;;; Prompting

(ert-deftest rcf-sword-test-reference-at-point ()
  (with-temp-buffer
    (insert "As John 3:16 says, and 1 Cor 13:4-7 too; see Foo 3 or chapter 9.")
    (pcase-dolist (`(,text ,reference)
                   '(("John" "John 3:16") ("3:16" "John 3:16")
                     ("Cor" "1 Cor 13:4-7") ("4-7" "1 Cor 13:4-7")
                     ;; Not references: an unknown book, or no number.
                     ("Foo" nil) ("chapter" nil) ("says" nil)))
      (goto-char (point-min))
      (search-forward text)
      (backward-char)
      (should (equal (cons text (rcf-sword--reference-at-point))
                     (cons text reference))))))

(ert-deftest rcf-sword-test-read-reference ()
  ;; The prompt offers the reference at point and records history.
  (with-temp-buffer
    (insert "Read Ps 23 today")
    (goto-char 8)
    (cl-letf (((symbol-function 'read-string)
               (lambda (prompt _initial history default)
                 (list prompt history default))))
      (should (equal (rcf-sword--read-reference "Enter verse")
                     '("Enter verse (default Ps 23): "
                       rcf-sword-reference-history "Ps 23"))))))

;;;; Database-backed

(ert-deftest rcf-sword-test-missing-file ()
  (let ((rcf-sword-bblx-file nil))
    (should-error (rcf-sword--get-db) :type 'user-error))
  (let ((rcf-sword-bblx-file "/nonexistent/file.bblx"))
    (should-error (rcf-sword--get-db) :type 'user-error)))

(ert-deftest rcf-sword-test-not-a-bible-module ()
  ;; A file that isn't SQLite, and a SQLite file without the e-Sword
  ;; tables, both get a friendly message instead of a raw SQL error.
  (dolist (make-file
           (list (lambda (file) (with-temp-file file (insert "Just some notes.\n")))
                 (lambda (file)
                   (let ((db (sqlite-open file)))
                     (sqlite-execute db "CREATE TABLE Notes (Text TEXT);")
                     (sqlite-close db)))))
    (let* ((file (make-temp-file "rcf-sword-test" nil ".bblx"))
           (rcf-sword-bblx-file file))
      (unwind-protect
          (progn
            (funcall make-file file)
            (rcf-sword-close-database)
            (should (equal (rcf-sword-test--user-error #'rcf-sword--get-db)
                           (format "%s isn't an e-Sword Bible module: it needs Bible and Details tables"
                                   file)))
            ;; The failed connection isn't kept.
            (should-not rcf-sword--db))
        (delete-file file)))))

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

(ert-deftest rcf-sword-test-more-reference-forms ()
  (rcf-sword-test--with-db
    ;; A range across chapters, and a list; the label describes the result.
    (should (equal (mapcar (lambda (verse) (seq-take verse 3))
                           (rcf-sword--lookup "Ps 2:1-23:2"))
                   '((19 2 1) (19 23 1) (19 23 2))))
    (should (equal (mapcar #'cl-caddr (rcf-sword--lookup "Ps 23:1, 3")) '(1 3)))
    (with-temp-buffer
      (rcf-sword-insert-verse "Ps 23:1,3")
      (should (string-suffix-p " -- Psalms 23:1, 3 KJV" (buffer-string))))
    ;; Listed verses that don't exist are skipped, like partial ranges.
    (should (equal (mapcar #'cl-caddr (rcf-sword--lookup "Ps 23:3,9")) '(3)))
    ;; The reference at point understands the new forms.
    (with-temp-buffer
      (insert "See Ps 23:1,3 and John 3:16-4:2.")
      (goto-char 6)
      (should (equal (rcf-sword--reference-at-point) "Ps 23:1,3"))
      (search-forward "John")
      (should (equal (rcf-sword--reference-at-point) "John 3:16-4:2")))))

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

(ert-deftest rcf-sword-test-formatting-templates ()
  (rcf-sword-test--with-db
    (with-temp-buffer
      ;; An org verse block with the reference underneath.
      (org-mode)
      (let ((rcf-sword-org-before "#+begin_verse\n")
            (rcf-sword-org-after "\n#+end_verse\n-- %s\n"))
        (rcf-sword-insert-verse "Ps 23:1"))
      (should (equal (buffer-string)
                     (concat "#+begin_verse\n"
                             "The LORD is my shepherd; I shall not want.\n"
                             "#+end_verse\n"
                             "-- Psalms 23:1 KJV\n")))
      ;; An em dash attribution in plain text.
      (fundamental-mode)
      (erase-buffer)
      (let ((rcf-sword-attribution-format "— %s"))
        (rcf-sword-insert-verse "Ps 23:1"))
      (should (string-suffix-p "\n\n — Psalms 23:1 KJV" (buffer-string))))))

(ert-deftest rcf-sword-test-insert-verse-numbers ()
  (rcf-sword-test--with-db
    (with-temp-buffer
      ;; Off by default; a prefix argument turns them on for one insertion.
      (rcf-sword-insert-verse "Ps 23:1-2")
      (should-not (string-match-p "¹" (buffer-string)))
      (erase-buffer)
      (rcf-sword-insert-verse "Ps 23:1-2" '(4))
      (should (string-match-p "\\`¹The LORD.*\n\n²He maketh" (buffer-string)))
      ;; With the option on, the prefix argument turns them off.
      (let ((rcf-sword-insert-verse-numbers t))
        (erase-buffer)
        (rcf-sword-insert-verse "Ps 23:1")
        (should (string-prefix-p "¹The LORD" (buffer-string)))
        (erase-buffer)
        (rcf-sword-insert-verse "Ps 23:1" '(4))
        (should (string-prefix-p "The LORD" (buffer-string)))))))

(ert-deftest rcf-sword-test-copy-verse ()
  ;; Copied as plain text, without hard wrapping, and the buffer is untouched.
  (rcf-sword-test--with-db
    (with-temp-buffer
      (org-mode)
      (let ((kill-ring nil))
        (rcf-sword-copy-verse "Ps 23:2-3")
        (should (equal (buffer-string) ""))
        (should (equal (car kill-ring)
                       (concat "He maketh me to lie down in green pastures: he leadeth me beside the still waters.\n"
                               "\n"
                               "He restoreth my soul: he leadeth me in the paths of righteousness for his name's sake.\n"
                               "\n"
                               " -- Psalms 23:2-3 KJV")))))))

(ert-deftest rcf-sword-test-random-is-fair ()
  ;; Every verse is equally likely, wherever it is.  With the old
  ;; book-then-chapter-then-verse sampling, Proverbs 1:1 (alone in its
  ;; book) came up a third of the time.  Now each of the fixture's N
  ;; verses should come up about 1/N of the time: 100 N draws give ~100
  ;; each, and 50-160 is over 5 standard deviations either side.
  (rcf-sword-test--with-db
    (let ((counts (make-hash-table :test #'equal))
          (n (length rcf-sword-test--verses)))
      (dotimes (_ (* 100 n))
        (cl-incf (gethash (butlast (car (rcf-sword--random-verse)))
                          counts 0)))
      (should (= (hash-table-count counts) n))
      (maphash (lambda (_verse n) (should (< 50 n 160))) counts))
    ;; With a book, only that book's verses are drawn.
    (dotimes (_ 20)
      (should (= (caar (rcf-sword--random-verse 19)) 19)))
    (should-not (rcf-sword--random-verse 40))))

(ert-deftest rcf-sword-test-other-canons-and-languages ()
  (rcf-sword-test--with-db
    (with-temp-buffer
      ;; A book missing from `rcf-sword-books' still gets a label.
      (rcf-sword--insert-passage (rcf-sword--span-verses 67 1 1 1 1))
      (should (string-suffix-p " -- Book 67 1:1 KJV" (buffer-string)))
      ;; Adding it to the list makes it a normal book.
      (let ((rcf-sword-books (append rcf-sword-books '((3 67 "Tobit")))))
        (erase-buffer)
        (rcf-sword-insert-verse "Tob 1:1")
        (should (string-suffix-p " -- Tobit 1:1 KJV" (buffer-string))))
      ;; Renamed books are matched and labelled by their new names, and
      ;; the random proverb doesn't depend on the English name.
      (let ((rcf-sword-books
             (mapcar (lambda (book)
                       (pcase (nth 1 book)
                         (19 '(1 19 "Psalmen"))
                         (20 '(1 20 "Sprüche"))
                         (_ book)))
                     rcf-sword-books)))
        (erase-buffer)
        (rcf-sword-insert-verse "Psalmen 23:1")
        (should (string-suffix-p " -- Psalmen 23:1 KJV" (buffer-string)))
        (erase-buffer)
        (rcf-sword-insert-random-proverb)
        (should (string-suffix-p " -- Sprüche 1:1 KJV" (buffer-string)))))))

(ert-deftest rcf-sword-test-random ()
  (rcf-sword-test--with-db
    (with-temp-buffer
      (rcf-sword-insert-random-proverb)
      (should (string-match-p "Proverbs 1:1 KJV" (buffer-string))))))

(ert-deftest rcf-sword-test-reader-verse-at-point ()
  (rcf-sword-test--with-db
    (save-window-excursion
      (rcf-sword-read-book "Ps")
      (with-current-buffer "Scripture: Psalms"
        (unwind-protect
            (progn
              ;; Before the first verse there's no verse at point.
              (goto-char (point-min))
              (should-not (rcf-sword--verse-at-point))
              (search-forward "restoreth")
              (should (equal (rcf-sword--verse-at-point) '(19 23 3)))
              ;; Between verses, it's the verse before.
              (search-backward "still waters.")
              (goto-char (match-end 0))
              (should (equal (rcf-sword--verse-at-point) '(19 23 2)))
              ;; y copies the verse at point with its reference.
              (let ((kill-ring nil))
                (goto-char (point-min))
                (search-forward "shepherd")
                (call-interactively (keymap-lookup nil "y"))
                (should (equal (car kill-ring)
                               "The LORD is my shepherd; I shall not want.\n\n -- Psalms 23:1 KJV"))))
          (kill-buffer))))
    ;; Passages inserted into the user's buffers carry no verse properties.
    (with-temp-buffer
      (rcf-sword-insert-verse "Ps 23:1")
      (should-not (text-property-not-all (point-min) (point-max) 'rcf-sword-verse nil)))))

(ert-deftest rcf-sword-test-read-book-at-reference ()
  (rcf-sword-test--with-db
    (save-window-excursion
      (unwind-protect
          (progn
            ;; Open straight at a verse, then move within the open book.
            (rcf-sword-read-book "Ps 23:3")
            (with-current-buffer "Scripture: Psalms"
              (should (looking-at "³He restoreth")))
            (rcf-sword-read-book "Psalm 23:2")
            (with-current-buffer "Scripture: Psalms"
              (should (looking-at "²He maketh")))
            ;; A chapter alone goes to its first verse.
            (rcf-sword-read-book "Gen 1")
            (with-current-buffer "Scripture: Genesis"
              (should (looking-at "¹In the beginning")))
            ;; A numbered book name alone is still a book, not a reference.
            (should (equal (rcf-sword-test--user-error #'rcf-sword-read-book "1 John")
                           "No verses found for 1 John"))
            ;; Problems get the usual friendly messages.
            (should (equal (rcf-sword-test--user-error #'rcf-sword-read-book "Ps 23:9")
                           "Psalms 23 ends at verse 3, so there's no verse 9"))
            (should (equal (rcf-sword-test--user-error #'rcf-sword-read-book "Ps 23:5-2")
                           "The verses in \"23:5-2\" run backwards; did you mean 23:2-5?")))
        (dolist (name '("Scripture: Psalms" "Scripture: Genesis"))
          (when (get-buffer name) (kill-buffer name)))))))

(ert-deftest rcf-sword-test-reader-chapters ()
  ;; The fixture's Psalms has chapters 1, 2 and 23.
  (rcf-sword-test--with-db
    (save-window-excursion
      (rcf-sword-read-book "Ps")
      (with-current-buffer "Scripture: Psalms"
        (unwind-protect
            (progn
              (goto-char (point-min))
              ;; ] from above chapter 1 goes to chapter 1, then onwards,
              ;; skipping the missing chapter numbers.
              (dolist (chapter '(1 2 23))
                (call-interactively (keymap-lookup nil "]"))
                (should (equal (seq-take (rcf-sword--verse-at-point) 2)
                               (list 19 chapter))))
              (should-error (rcf-sword-reader-next-chapter) :type 'user-error)
              (call-interactively (keymap-lookup nil "["))
              (should (looking-at "¹Why do the heathen"))
              (rcf-sword-reader-previous-chapter)
              (should (looking-at "¹Blessed is the man"))
              (should-error (rcf-sword-reader-previous-chapter) :type 'user-error)
              ;; imenu lists every chapter, including the first.
              (should (equal (mapcar #'car (funcall imenu-create-index-function))
                             '("Chapter 1" "Chapter 2" "Chapter 23")))
              (goto-char (cdr (assoc "Chapter 23" (funcall imenu-create-index-function))))
              (should (looking-at "¹The LORD is my shepherd")))
          (kill-buffer))))))

(ert-deftest rcf-sword-test-reader-bookmarks ()
  (rcf-sword-test--with-db
    (save-window-excursion
      (let (bookmark)
        (with-current-buffer (rcf-sword-read-book "Ps 23:3")
          (setq bookmark (funcall bookmark-make-record-function))
          (should (equal (car bookmark) "Psalms 23:3"))
          (should (equal (bookmark-prop-get bookmark 'reference) "Psalms 23:3"))
          ;; Above the first verse, the first verse is bookmarked.
          (goto-char (point-min))
          (should (equal (car (funcall bookmark-make-record-function)) "Psalms 1:1"))
          (kill-buffer))
        ;; Jumping reopens the book at the verse and leaves it current.
        (with-temp-buffer
          (rcf-sword-bookmark-jump bookmark)
          (should (equal (buffer-name) "Scripture: Psalms"))
          (should (looking-at "³He restoreth"))
          (kill-buffer))))))

(ert-deftest rcf-sword-test-reader-revert ()
  ;; g re-renders from the database and stays on the same verse.
  (rcf-sword-test--with-db
    (save-window-excursion
      (with-current-buffer (rcf-sword-read-book "Ps 23:2")
        (unwind-protect
            (progn
              (sqlite-execute (rcf-sword--get-db)
                              "UPDATE Bible SET Scripture=' Changed text.' WHERE Book=19 AND Chapter=1;")
              (should-not (string-match-p "Changed text" (buffer-string)))
              (call-interactively (keymap-lookup nil "g"))
              (should (string-match-p "¹Changed text\\." (buffer-string)))
              (should (looking-at "²He maketh"))
              (should buffer-read-only))
          (kill-buffer))))))

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
