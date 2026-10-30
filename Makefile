EMACS ?= emacs
ELPA_DIR := $(CURDIR)/.elpa

# Dependencies are installed into ./.elpa, so your own config isn't touched.
INIT_PACKAGES := --eval "(progn \
  (require 'package) \
  (setq package-user-dir \"$(ELPA_DIR)\") \
  (add-to-list 'package-archives '(\"melpa\" . \"https://melpa.org/packages/\") t) \
  (package-initialize))"

BATCH := $(EMACS) -Q --batch -L . $(INIT_PACKAGES)

.PHONY: all deps compile checkdoc lint test clean

all: compile checkdoc lint test

deps:
	$(BATCH) --eval "(progn \
	  (package-refresh-contents) \
	  (dolist (p '(package-lint markdown-mode olivetti)) \
	    (unless (package-installed-p p) (package-install p))))"

compile: deps
	$(BATCH) --eval "(setq byte-compile-error-on-warn t)" \
	  -f batch-byte-compile rcf-sword.el

checkdoc:
	$(EMACS) -Q --batch --eval "(checkdoc-file \"rcf-sword.el\")"

lint: deps
	$(BATCH) --eval "(require 'package-lint)" \
	  -f package-lint-batch-and-exit rcf-sword.el

test: deps
	$(BATCH) -L test -l rcf-sword-test -f ert-run-tests-batch-and-exit

clean:
	rm -f *.elc test/*.elc
