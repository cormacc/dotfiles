;;; ceedling.el --- C unit testing with Ceedling/Unity  -*- lexical-binding: t; -*-

;; Copyright (C) 2018-2026  Cormac Cannon

;; Author: Cormac Cannon <cormacc@nmdburger>
;; Keywords: c, tools
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1"))

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

;; Commands for running Ceedling (https://www.throwtheswitch.org/ceedling)
;; through `compile', and for switching between a module and its Unity test
;; file.
;;
;; The Ceedling root is the directory holding `project.yml'.  The current
;; project.el root is preferred when it has one, so a component that ships its
;; own `project.yml' (e.g. inside a merged submodule) still runs the enclosing
;; project's suite.  Otherwise the nearest `project.yml' above the current file
;; is used.
;;
;; No key bindings are defined here; the caller binds the commands.

;;; Code:

(require 'project)
(require 'subr-x)

(defgroup ceedling nil
  "Run Ceedling unit tests."
  :group 'tools
  :prefix "ceedling-")

(defcustom ceedling-command "ceedling"
  "Command used to run Ceedling."
  :type 'string)

(defcustom ceedling-project-file "project.yml"
  "File name that marks a Ceedling project root."
  :type 'string)

(defcustom ceedling-test-file-prefix "test_"
  "Prefix of Unity test file names; Ceedling's `:test_file_prefix'."
  :type 'string)

(defun ceedling-root ()
  "Return the Ceedling root directory for the current buffer, or signal an error."
  (let ((project-root (when-let* ((pr (project-current)))
                        (project-root pr))))
    (or (and project-root
             (file-exists-p (expand-file-name ceedling-project-file project-root))
             (file-name-as-directory (expand-file-name project-root)))
        (when-let* ((dir (locate-dominating-file default-directory ceedling-project-file)))
          (file-name-as-directory (expand-file-name dir)))
        (user-error "No %s found above %s" ceedling-project-file default-directory))))

(defun ceedling--run (args)
  "Run Ceedling with ARGS, a string, from the Ceedling root."
  (let ((default-directory (ceedling-root)))
    (compile (string-trim (format "%s %s" ceedling-command args)))))

(defun ceedling--module-name ()
  "Return the module under test for the current buffer's file.
The test prefix and extension are stripped, so `Button.c', `Button.h'
and `test_Button.c' all give \"Button\"."
  (unless buffer-file-name
    (user-error "Buffer is not visiting a file"))
  (string-remove-prefix ceedling-test-file-prefix
                        (file-name-base buffer-file-name)))

;;;###autoload
(defun ceedling-test-this-file ()
  "Run the Ceedling tests for the current module."
  (interactive)
  (ceedling--run (format "test:%s" (ceedling--module-name))))

;;;###autoload
(defun ceedling-clobber-and-test-this-file ()
  "Clobber the build, then run the Ceedling tests for the current module."
  (interactive)
  (ceedling--run (format "clobber test:%s" (ceedling--module-name))))

;;;###autoload
(defun ceedling-test-all ()
  "Run every Ceedling test."
  (interactive)
  (ceedling--run "test:all"))

;;;###autoload
(defun ceedling-test-delta ()
  "Run the Ceedling tests affected by changes since the last build."
  (interactive)
  (ceedling--run "test:delta"))

;;;###autoload
(defun ceedling-clobber ()
  "Remove all Ceedling build output."
  (interactive)
  (ceedling--run "clobber"))

(defun ceedling--test-file-p (file)
  "Return non-nil if FILE is a Unity test file."
  (string-prefix-p ceedling-test-file-prefix (file-name-nondirectory file)))

(defun ceedling--counterpart-name (file)
  "Return the base name of FILE's test or implementation counterpart."
  (let ((name (file-name-nondirectory file)))
    (if (ceedling--test-file-p file)
        (concat (string-remove-prefix ceedling-test-file-prefix
                                      (file-name-sans-extension name))
                ".c")
      (concat ceedling-test-file-prefix (file-name-base name) ".c"))))

(defun ceedling--candidate-files (root)
  "Return the files to search under ROOT: project files, else a recursive listing."
  (let ((pr (project-current nil root)))
    (if pr
        (seq-filter (lambda (f) (string-prefix-p root (expand-file-name f)))
                    (project-files pr))
      (directory-files-recursively root "\\.c\\'"))))

;;;###autoload
(defun ceedling-toggle-test ()
  "Visit the Unity test for the current module, or the module for the current test.
A module's test is `test_NAME.c'; a test's module is `NAME.c'.  When
there are several candidates, prompt for one, nearest first."
  (interactive)
  (unless buffer-file-name
    (user-error "Buffer is not visiting a file"))
  (let* ((root (ceedling-root))
         (target (ceedling--counterpart-name buffer-file-name))
         (here (file-name-directory buffer-file-name))
         (matches (seq-filter (lambda (f) (string= (file-name-nondirectory f) target))
                              (ceedling--candidate-files root))))
    (pcase (mapcar #'expand-file-name matches)
      ('() (user-error "No %s under %s" target root))
      (`(,only) (find-file only))
      (all
       (let* ((sorted (seq-sort-by (lambda (f) (length (file-relative-name f here))) #'< all))
              (names (mapcar (lambda (f) (file-relative-name f root)) sorted))
              ;; Keep the nearest-first order instead of the UI's own sort.
              (table (lambda (string pred action)
                       (if (eq action 'metadata)
                           '(metadata (display-sort-function . identity))
                         (complete-with-action action names string pred)))))
         (find-file (expand-file-name (completing-read "Counterpart: " table nil t)
                                      root)))))))

(provide 'ceedling)
;;; ceedling.el ends here
