;;; rcf-sword-org.el --- Org links to scripture for rcf-sword  -*- lexical-binding: t; -*-

;; Copyright (C) 2024-2026 Ryan Fleck

;; Author: Ryan Fleck <dev@ryanfleck.ca>
;; Assisted-by: Claude Code
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

;; Org links like [[scripture:John 3:16]] that open the rcf-sword reader
;; at that verse.  Enable them in your init file with:
;;
;;   (with-eval-after-load 'org (require 'rcf-sword-org))
;;
;; Then C-c C-l offers "scripture:" as a link type and prompts for the
;; reference, and exported links show their description (or else the
;; reference) as plain text.
;;
;; This is a separate file so that rcf-sword itself never loads Org:
;; packages shouldn't use `with-eval-after-load', so the user's init file
;; decides when this loads.

;;; Code:

(require 'ol)
(require 'rcf-sword)

(org-link-set-parameters
 "scripture"
 :follow (lambda (reference &optional _) (rcf-sword-read-book reference))
 ;; C-c C-l prompts for a reference, offering the one at point.
 :complete (lambda (&optional _)
             (concat "scripture:" (rcf-sword--read-reference "Reference")))
 ;; Export the description, or else the reference, as plain text.
 :export (lambda (reference description &rest _) (or description reference)))

(provide 'rcf-sword-org)
;;; rcf-sword-org.el ends here
