;;; rcf-sword-test.el --- Tests for rcf-sword  -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; ERT tests.  Database tests build a tiny .bblx fixture in a temp file.
;; Run with `make test'.

;;; Code:

(require 'ert)
(require 'rcf-sword)

;;;; Fixture

(defconst rcf-sword-test--verses
  '((1 1 1 " In the beginning God created the heavens and the earth.")
    (1 1 2 " The earth was without form, and void;{\\cf2\\super [1]} and darkness was on the face of the deep.")
    (1 1 3 " Then God said, \"Let there be light\"; and there was light.")
    (43 3 16 " For God so loved the world that He gave His only begotten Son,")
    (43 3 17 " that whoever believes in Him should not perish.")
    (43 3 18 " He who believes in Him is not condemned.")
    (20 1 1 " The proverbs of Solomon the son of David, king of Israel:"))
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
             (sqlite-execute db "INSERT INTO Details VALUES ('New King James Version', 'NKJV');")
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
  (should-not (rcf-sword--book-number "Nonexistent")))

(ert-deftest rcf-sword-test-book-numbers-are-sequential ()
  (should (equal (mapcar #'cadr rcf-sword-books) (number-sequence 1 66))))

(ert-deftest rcf-sword-test-parse-reference ()
  (should (equal (rcf-sword--parse-reference "Genesis 6") '("Genesis" 6 nil)))
  (should (equal (rcf-sword--parse-reference "Genesis 6:1") '("Genesis" 6 (1))))
  (should (equal (rcf-sword--parse-reference "Genesis 6:1-2") '("Genesis" 6 (1 2))))
  (should (equal (rcf-sword--parse-reference "  1 Cor 13:4-7 ") '("1 Cor" 13 (4 7)))))

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

;;;; Database-backed

(ert-deftest rcf-sword-test-missing-file ()
  (let ((rcf-sword-bblx-file nil))
    (should-error (rcf-sword--get-db) :type 'user-error))
  (let ((rcf-sword-bblx-file "/nonexistent/file.bblx"))
    (should-error (rcf-sword--get-db) :type 'user-error)))

(ert-deftest rcf-sword-test-lookup ()
  (rcf-sword-test--with-db
    (should (equal (rcf-sword-translation-name) "New King James Version"))
    (should (equal (rcf-sword-translation-abbreviation) "NKJV"))
    (should (equal (mapcar #'cl-caddr (rcf-sword--lookup "Gen 1")) '(1 2 3)))
    (should (equal (mapcar #'cl-caddr (rcf-sword--lookup "Gen 1:2")) '(2)))
    (should (equal (mapcar #'cl-caddr (rcf-sword--lookup "John 3:16-17")) '(16 17)))
    (should-error (rcf-sword--lookup "Nonexistent 1:1") :type 'user-error)))

(ert-deftest rcf-sword-test-insert-plain ()
  (rcf-sword-test--with-db
    (with-temp-buffer
      (rcf-sword-insert-verse "John 3:16-18")
      (should (= (point) (point-min)))
      (should (equal (buffer-string)
                     (concat "For God so loved the world that He gave His only begotten Son, that\n"
                             "whoever believes in Him should not perish.\n"
                             "\n"
                             "He who believes in Him is not condemned.\n"
                             "\n"
                             " -- John 3:16-18 NKJV"))))))

(ert-deftest rcf-sword-test-insert-org ()
  (rcf-sword-test--with-db
    (with-temp-buffer
      (org-mode)
      (rcf-sword-insert-verse "Gen 1:1-2")
      (should (equal (buffer-string)
                     (concat "#+verse: Genesis 1:1-2 NKJV\n"
                             "#+begin_quote\n"
                             "In the beginning God created the heavens and the earth.\n"
                             "\n"
                             "The earth was without form, and void; and darkness was on the face of\n"
                             "the deep.\n"
                             "#+end_quote\n"))))))

(ert-deftest rcf-sword-test-insert-markdown ()
  (skip-unless (require 'markdown-mode nil t))
  (rcf-sword-test--with-db
    (with-temp-buffer
      (markdown-mode)
      (let ((rcf-sword-md-link-reference t))
        (rcf-sword-insert-verse "John 3:16-18"))
      (should (equal (buffer-string)
                     (concat "> For God so loved the world that He gave His only begotten Son, that\n"
                             "> whoever believes in Him should not perish.\n"
                             "> \n"
                             "> He who believes in Him is not condemned.\n"
                             ">  \n"
                             "> -- [John 3:16-18 NKJV](https://www.biblegateway.com/passage/"
                             "?search=John%203%3A16-18&version=NKJV)"))))))

(ert-deftest rcf-sword-test-random ()
  (rcf-sword-test--with-db
    (with-temp-buffer
      (rcf-sword-insert-random-proverb)
      (should (string-match-p "Proverbs 1:1 NKJV" (buffer-string))))))

(ert-deftest rcf-sword-test-read-book ()
  (rcf-sword-test--with-db
    (save-window-excursion
      (rcf-sword-read-book "Gen")
      (unwind-protect
          (with-current-buffer "Scripture: Genesis"
            (should (derived-mode-p 'rcf-sword-reader-mode))
            (should buffer-read-only)
            (should (string-match-p "¹In the beginning" (buffer-string)))
            (should-not (string-match-p "cf2" (buffer-string))))
        (kill-buffer "Scripture: Genesis")))))

(provide 'rcf-sword-test)
;;; rcf-sword-test.el ends here
