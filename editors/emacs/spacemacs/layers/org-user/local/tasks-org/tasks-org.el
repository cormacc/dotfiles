;;; tasks-org.el --- Plain-org task memory helpers -*- lexical-binding: t; -*-

;; Author: Cormac Cannon
;; URL: https://github.com/cormacc/dotfiles
;; Keywords: org, tasks, productivity
;; Package-Requires: ((emacs "27.1") (org "9.4"))

;;; Commentary:

;; Lightweight Emacs-side helpers for the plain-org task-memory protocol used
;; by the pi tasks extension.  Maintains stable :ID: properties, single-task
;; selection via the :selected: tag, and convenient :PLAN: open/create
;; helpers.
;;
;; Files remain plain org.  Pi reloads via its file watchers; there is no live
;; IPC.  All commands operate on the current org buffer using standard org
;; APIs (`org-id', `org-entry-get/put', org link parsing) so no special
;; serialization is required.
;;
;; Activation: `tasks-org-mode' auto-enables on buffers visiting `TASKS.org'
;; or any `*.org' under a `design/log/' directory (see
;; `tasks-org-auto-enable-paths').  Manual `M-x tasks-org-mode' is also
;; available.

;;; Code:

(require 'cl-lib)
(require 'org)
(require 'org-id)
(require 'subr-x)

;; Soft dependency on projectile.  When projectile is unavailable the package
;; falls back to the buffer's own directory for project-root resolution.
(declare-function projectile-project-root "projectile" (&optional dir))

;;; Customization

(defgroup tasks-org nil
  "Plain-org task memory helpers."
  :group 'org
  :prefix "tasks-org-")

(defcustom tasks-org-tasks-file-name "TASKS.org"
  "Filename of the project task root."
  :type 'string
  :group 'tasks-org)

(defcustom tasks-org-plans-directory "design/log"
  "Default directory under the project root for new plan files."
  :type 'string
  :group 'tasks-org)

(defcustom tasks-org-selected-tag "selected"
  "Reserved tag marking the currently selected task."
  :type 'string
  :group 'tasks-org)

(defcustom tasks-org-auto-enable-paths
  '("\\`TASKS\\.org\\'" "\\`design/log/.*\\.org\\'")
  "Path patterns (regexps) that auto-enable `tasks-org-mode'.
Each entry is matched against the buffer's file path relative to
the project root.  Activation also triggers on any org buffer that
contains a `#+DEFAULT-PLAN-DIR:' keyword, regardless of path."
  :type '(repeat regexp)
  :group 'tasks-org)

;;; Project root resolution

(defun tasks-org--project-root ()
  "Return the project root directory.
Uses `projectile-project-root' when available, falling back to the
current buffer's directory."
  (or (and (fboundp 'projectile-project-root)
           (ignore-errors (projectile-project-root)))
      (and buffer-file-name (file-name-directory buffer-file-name))
      default-directory))

(defun tasks-org--tasks-file ()
  "Return the absolute path of the project's TASKS.org."
  (expand-file-name tasks-org-tasks-file-name (tasks-org--project-root)))

;;; Activation

(defun tasks-org--has-plan-dir-keyword-p ()
  "Return non-nil when the current buffer contains a #+DEFAULT-PLAN-DIR: keyword."
  (save-excursion
    (goto-char (point-min))
    (re-search-forward "^#\\+DEFAULT-PLAN-DIR:" nil t)))

(defun tasks-org--should-auto-enable-p ()
  "Return non-nil when the current buffer matches activation rules.
Activates when the buffer's path (relative to the project root) matches
`tasks-org-auto-enable-paths', or when the buffer contains a
`#+DEFAULT-PLAN-DIR:' keyword (the canonical marker of a task-memory root)."
  (when (and buffer-file-name (derived-mode-p 'org-mode))
    (or (tasks-org--has-plan-dir-keyword-p)
        (let* ((root (tasks-org--project-root))
               (rel (file-relative-name buffer-file-name root)))
          (cl-some (lambda (re) (string-match-p re rel))
                   tasks-org-auto-enable-paths)))))

(defun tasks-org-maybe-enable ()
  "Enable `tasks-org-mode' if the current buffer matches activation rules."
  (when (tasks-org--should-auto-enable-p)
    (tasks-org-mode 1)))

;;; Task heading detection

(defun tasks-org--at-task-heading-p ()
  "Return non-nil when point is on or inside an actionable task heading.
A task heading is one that has a TODO keyword in the file's
declared TODO sequence."
  (save-excursion
    (when (or (org-at-heading-p)
              (ignore-errors (org-back-to-heading t)))
      (let ((kw (org-get-todo-state)))
        (and kw (member kw org-todo-keywords-1))))))

;;; ID helpers

(defun tasks-org--ensure-id-at-heading ()
  "Ensure the current heading has an :ID: property; add a UUID v4 if missing.
Internal helper used by plan creation.  ID backfill for existing tasks is
the responsibility of the pi tasks extension and the agent org-memory skill."
  (save-excursion
    (unless (org-at-heading-p)
      (org-back-to-heading t))
    (unless (org-entry-get nil "ID")
      (org-entry-put nil "ID" (org-id-new)))))

;;; Plan link parsing

(defun tasks-org--extract-plan-path (raw)
  "Extract a file path from a :PLAN: property value RAW.
Handles bare paths, [[file:...]] and [[file:...][label]] forms.
Search options (e.g. ::heading) are stripped from the extracted path."
  (cond
   ((null raw) nil)
   ((string-match "\\[\\[file:\\([^]]+?\\)\\(?:\\]\\[[^]]*\\)?\\]\\]" raw)
    (replace-regexp-in-string "::[^]]*\\'" "" (match-string 1 raw)))
   ((not (string-empty-p (string-trim raw)))
    (string-trim raw))
   (t nil)))

;;; Selection helpers

(defun tasks-org--collect-task-files ()
  "Return absolute paths of all org files in the project task graph.
Includes TASKS.org plus any files referenced by :PLAN: properties
inside it.  Files that do not exist or are unreadable are skipped."
  (let* ((tasks-file (tasks-org--tasks-file))
         (files (when (file-readable-p tasks-file) (list tasks-file))))
    (when (file-readable-p tasks-file)
      (with-temp-buffer
        (insert-file-contents tasks-file)
        (goto-char (point-min))
        (while (re-search-forward "^\\s-*:PLAN:\\s-*\\(.*\\)$" nil t)
          (let* ((raw (string-trim (match-string 1)))
                 (path (tasks-org--extract-plan-path raw)))
            (when path
              (let ((abs (expand-file-name
                          path (file-name-directory tasks-file))))
                (when (file-readable-p abs)
                  (push abs files))))))))
    (delete-dups files)))

(defun tasks-org--clear-selected-everywhere ()
  "Remove the `:selected:' tag from every task in every project task file.
Returns the list of files that were modified."
  (let ((modified-files '()))
    (dolist (file (tasks-org--collect-task-files))
      (when (file-writable-p file)
        (let* ((existing-buf (find-buffer-visiting file))
               (visit-buf (or existing-buf (find-file-noselect file))))
          (with-current-buffer visit-buf
            (let ((modified nil))
              (save-excursion
                (goto-char (point-min))
                (while (re-search-forward org-heading-regexp nil t)
                  (let ((tags (org-get-tags nil t)))
                    (when (member tasks-org-selected-tag tags)
                      (org-set-tags (delete tasks-org-selected-tag tags))
                      (setq modified t)))))
              (when modified
                (save-buffer)
                (push file modified-files))
              ;; Don't keep buffers we opened ourselves around.
              (unless existing-buf (kill-buffer)))))))
    modified-files))

;;;###autoload
(defun tasks-org-toggle-selected ()
  "Toggle the `:selected:' tag on the current task.
Clears any other selected task across the project task graph first
to enforce single-selection."
  (interactive)
  (unless (tasks-org--at-task-heading-p)
    (user-error "Point is not on an actionable task heading"))
  (let* ((tags (org-get-tags nil t))
         (was-selected (member tasks-org-selected-tag tags)))
    ;; Clear selection across all task files (including the current one)
    (tasks-org--clear-selected-everywhere)
    ;; Re-fetch tags from current heading (clear pass may have rewritten them)
    (let ((current-tags (org-get-tags nil t)))
      (if was-selected
          (message "Cleared selection: %s" (org-get-heading t t t t))
        (org-set-tags
         (cons tasks-org-selected-tag
               (delete tasks-org-selected-tag current-tags)))
        (message "Selected: %s" (org-get-heading t t t t))))
    (save-buffer)))

;;; Plan helpers

(defun tasks-org--plan-link (path)
  "Return a clickable :PLAN: value for the relative PATH."
  (format "[[file:%s]]" path))

(defun tasks-org--slugify (s)
  "Slugify the string S for use in a filename."
  (let* ((down (downcase (or s "")))
         (clean (replace-regexp-in-string "[^a-z0-9]+" "-" down))
         (trimmed (replace-regexp-in-string "\\(^-+\\|-+$\\)" "" clean)))
    (if (string-empty-p trimmed)
        "plan"
      (substring trimmed 0 (min 40 (length trimmed))))))

(defun tasks-org--scaffold-plan (title)
  "Return scaffolded plan-file content for TITLE."
  (let ((date (format-time-string "%Y-%m-%d %a")))
    (concat
     (format "#+TITLE: %s\n" title)
     (format "#+DATE: %s\n" date)
     "#+TODO: TODO(t) STARTED(s) WAITING(w) | DONE(d) CANCELLED(c)\n"
     "\n"
     "* Context\n\n"
     "* Plan\n")))

(defun tasks-org--open-plan-link (raw source-dir &optional find-fn)
  "Open the file extracted from RAW :PLAN: value, resolved against SOURCE-DIR.
FIND-FN defaults to `find-file'; pass `find-file-other-window' to split."
  (let* ((path (tasks-org--extract-plan-path raw))
         (abs (when path (expand-file-name path source-dir))))
    (if (and abs (file-readable-p abs))
        (funcall (or find-fn #'find-file) abs)
      (user-error "Plan file not found: %s" (or abs raw)))))

(defun tasks-org--create-plan-for-current-task (&optional find-fn)
  "Scaffold a new plan file for the current task and link it via :PLAN:.
FIND-FN defaults to `find-file'; pass `find-file-other-window' to split."
  (let* ((title (org-get-heading t t t t))
         (slug (tasks-org--slugify title))
         (today (format-time-string "%Y-%m-%d"))
         (default-rel (concat (file-name-as-directory tasks-org-plans-directory)
                              today "-" slug ".org"))
         (root (tasks-org--project-root))
         (default-abs (expand-file-name default-rel root))
         (chosen (read-file-name
                  "New plan file: "
                  (file-name-directory default-abs) nil nil
                  (file-name-nondirectory default-abs))))
    (unless (file-exists-p chosen)
      (make-directory (file-name-directory chosen) t)
      (with-temp-file chosen
        (insert (tasks-org--scaffold-plan title))))
    (let* ((source-dir (file-name-directory (or buffer-file-name "")))
           (rel (file-relative-name chosen source-dir)))
      (org-entry-put nil "PLAN" (tasks-org--plan-link rel))
      (tasks-org--ensure-id-at-heading))
    (save-buffer)
    (funcall (or find-fn #'find-file) chosen)))

;;;###autoload
(defun tasks-org-open-plan (&optional find-fn)
  "Open the :PLAN: linked from the current task, creating one if absent.
FIND-FN defaults to `find-file'; pass `find-file-other-window' to split."
  (interactive)
  (unless (tasks-org--at-task-heading-p)
    (user-error "Point is not on an actionable task heading"))
  (let ((plan-raw (org-entry-get nil "PLAN"))
        (source-dir (file-name-directory (or buffer-file-name ""))))
    (if (and plan-raw (not (string-empty-p (string-trim plan-raw))))
        (tasks-org--open-plan-link plan-raw source-dir find-fn)
      (tasks-org--create-plan-for-current-task find-fn))))

;;;###autoload
(defun tasks-org-open-plan-other-window ()
  "Open the :PLAN: linked from the current task in another window."
  (interactive)
  (tasks-org-open-plan #'find-file-other-window))

;;;###autoload
(defun tasks-org-jump-to-parent-task ()
  "Jump to the task in TASKS.org whose :PLAN: links to the current buffer."
  (interactive)
  (unless buffer-file-name
    (user-error "Current buffer is not visiting a file"))
  (let* ((tasks-file (tasks-org--tasks-file))
         (tasks-dir (file-name-directory (expand-file-name tasks-file)))
         (current-abs (expand-file-name buffer-file-name))
         found-point)
    (unless (file-readable-p tasks-file)
      (user-error "TASKS.org not found at %s" tasks-file))
    (with-current-buffer (find-file-noselect tasks-file)
      (save-excursion
        (goto-char (point-min))
        (while (and (not found-point)
                    (re-search-forward "^[ \t]*:PLAN:[ \t]*\\(.*\\)" nil t))
          (let* ((raw (string-trim (match-string 1)))
                 (path (tasks-org--extract-plan-path raw))
                 (abs (when path (expand-file-name path tasks-dir))))
            (when (and abs (string= (expand-file-name abs) current-abs))
              (org-back-to-heading t)
              (setq found-point (point)))))))
    (if found-point
        (progn
          (find-file tasks-file)
          (goto-char found-point)
          (org-show-entry)
          (recenter))
      (user-error "No task in %s links to the current file"
                  tasks-org-tasks-file-name))))

;;; Minor mode + keymap

(defvar tasks-org-mode-map (make-sparse-keymap)
  "Keymap for `tasks-org-mode'.
Spacemacs bindings are declared in the layer's `packages.el' under
the org local-leader prefix `, ;'.")

;;;###autoload
(define-minor-mode tasks-org-mode
  "Minor mode for plain-org task memory helpers.

When enabled, exposes commands for ensuring stable :ID: properties,
toggling the reserved :selected: tag, and opening or creating
:PLAN: linked files."
  :lighter " Tasks"
  :keymap tasks-org-mode-map
)

;;;###autoload
(add-hook 'org-mode-hook #'tasks-org-maybe-enable)

(provide 'tasks-org)
;;; tasks-org.el ends here
