EMACS ?= emacs
ELPA_DIR := $(CURDIR)/.elpa

# Dependencies are installed into ./.elpa, so your own config isn't touched.
INIT_PACKAGES := --eval "(progn \
  (require 'package) \
  (setq package-user-dir \"$(ELPA_DIR)\") \
  (add-to-list 'package-archives '(\"melpa\" . \"https://melpa.org/packages/\") t) \
  (package-initialize))"

BATCH := $(EMACS) -Q --batch -L . $(INIT_PACKAGES)

# rcf-sword.el is the package; rcf-sword-org.el is its optional Org links.
FILES := rcf-sword.el rcf-sword-org.el

.PHONY: all deps compile checkdoc lint test clean

all: compile checkdoc lint test

deps:
	$(BATCH) --eval "(progn \
	  (package-refresh-contents) \
	  (dolist (p '(package-lint markdown-mode olivetti)) \
	    (unless (package-installed-p p) (package-install p))))"

compile: deps
	$(BATCH) --eval "(setq byte-compile-error-on-warn t)" \
	  -f batch-byte-compile $(FILES)

checkdoc:
	for f in $(FILES); do \
	  $(EMACS) -Q --batch --eval "(checkdoc-file \"$$f\")" || exit 1; \
	done

lint: deps
	$(BATCH) --eval "(require 'package-lint)" \
	  --eval "(setq package-lint-main-file \"rcf-sword.el\")" \
	  -f package-lint-batch-and-exit $(FILES)

test: deps
	$(BATCH) -L test -l rcf-sword-test -f ert-run-tests-batch-and-exit

clean:
	rm -f *.elc test/*.elc
