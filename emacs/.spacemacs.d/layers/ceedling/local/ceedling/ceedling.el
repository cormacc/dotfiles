;;; ceedling.el --- c unit testing with ceedling/unity  -*- lexical-binding: t; -*-

;; Copyright (C) 2018  Cormac Cannon

;; Author: Cormac Cannon <cormacc@nmdburger>
;; Keywords: c
;; Version 0.0.1

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; This package defines a number of functions that are useful when working with
;; ceedling/unity (www.throwtheswitch.org)

;;; Code:

;; code goes here
(defun ceedling--run (opts module)
  (compile (format "rake %s test:%s" opts module)))

(defun ceedling--run-default-opts (testgroup) (ceedling--run "options:project options:test-framework" testgroup))

(defun ceedling--run-tests-this-file-with-opts (opts)
  (let ((module-name (replace-regexp-in-string ".*/" "" (replace-regexp-in-string "\\.[ch]" "" buffer-file-name))))
    (compile (format "rake %s test:%s" opts module-name))))

(defun ceedling-run-tests-this-file ()
  (interactive)
  (ceedling--run-tests-this-file-with-opts "options:project options:test-framework"))

(defun ceedling-clobber-tests-this-file ()
  (interactive)
  (ceedling--run-tests-this-file-with-opts "options:project options:test-framework clobber"))

;; (defun ceedling-clobber ()
;;   (interactive)
;;   (ceedling--run-default-opts "all"))

(defun ceedling-test-all ()
  (interactive)
  (ceedling--run-default-opts "all"))

(defun ceedling-test-delta ()
  (interactive)
  (ceedling--run-default-opts "delta"))

(defun ceedling-test-project ()
  (interactive)
  (ceedling--run "options:project" "all"))

(defun ceedling-test-framework ()
  (interactive)
  (ceedling--run "options:test-framework" "all"))
;; for future reference...

;; Get test name in current file...
;; (defun ceedling//get-current-test-name ()
;;   (save-excursion
;;     (let ((pos)
;;            (test-name))
;;       (re-search-backward "test \"\\([^\"]+\\)\" do")
;;       (setq test-name (buffer-substring-no-properties (match-beginning 1) (match-end 1)))
;;       (concat "test_" (replace-regexp-in-string " " "_" test-name)))))

;; (defun run-test-at-point ()
;;   (interactive)
;;   (let ((root-dir (projectile-project-root)))
;;     (compile (format "ruby -Ilib:test -I%s/test %s -n %s" root-dir (expand-file-name (buffer-file-name)) (get-current-test-name)))))


(provide 'ceedling)
;;; ceedling.el ends here
