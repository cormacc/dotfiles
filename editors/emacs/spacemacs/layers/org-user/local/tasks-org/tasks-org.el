;;; tasks-org.el --- Plain-org task memory helpers -*- lexical-binding: t; -*-

;; Author: Cormac Cannon
;; URL: https://github.com/cormacc/dotfiles
;; Keywords: org, tasks, productivity
;; Package-Requires: ((emacs "27.1") (org "9.4"))

;;; Commentary:

;; Lightweight Emacs-side helpers for the plain-org task-memory protocol used
;; by the pi tasks extension.  Maintains stable :ID: properties, single-task
;; selection via TASKS.local.org, convenient navigation to existing
;; #+IMPORT:'d change-records, and `:STARTED:' first-transition timestamps
;; via `org-after-todo-state-change-hook'.
;;
;; Scope: review, edit, and reorganisation of existing task graphs and
;; change-records.  Plan creation and task creation are the remit of the
;; agent harness (the pi tasks extension's `/tasks new', `n', `N', and
;; `p' keybindings); this mode intentionally does not scaffold new
;; change-records or new tasks.
;;
;; Files remain plain org.  Pi reloads via its file watchers; there is no live
;; IPC.  All commands operate on the current org buffer using standard org
;; APIs (`org-id', regex search, org link parsing) so no special
;; serialization is required.
;;
;; Activation: `tasks-org-mode' auto-enables on buffers visiting `TASKS.org'
;; or any `*.org' under a `design/log/' directory (see
;; `tasks-org-auto-enable-paths').  Manual `M-x tasks-org-mode' is also
;; available.

;;; Code:

(require 'cl-lib)
(require 'filenotify)
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
  "Fallback project-relative directory for change-records.
Used by the auto-enable predicate when `TASKS.org' does not declare a
`#+DEFAULT_PLAN_DIR:' keyword. This mode does not create change-records;
the directory is consulted only to decide whether `tasks-org-mode'
should activate on a buffer."
  :type 'string
  :group 'tasks-org)

(defcustom tasks-org-local-file-name "TASKS.local.org"
  "Filename of the per-contributor gitignored selection state file."
  :type 'string
  :group 'tasks-org)

(defcustom tasks-org-auto-enable-paths
  '("\\`TASKS\\.org\\'" "\\`design/log/.*\\.org\\'")
  "Path patterns (regexps) that auto-enable `tasks-org-mode'.
Each entry is matched against the buffer's file path relative to
the project root.  Activation also triggers on any org buffer that
contains a `#+DEFAULT_PLAN_DIR:' keyword, regardless of path."
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
  "Return non-nil when the current buffer contains a #+DEFAULT_PLAN_DIR: keyword."
  (save-excursion
    (goto-char (point-min))
    (re-search-forward "^#\\+DEFAULT_PLAN_DIR:" nil t)))

(defun tasks-org--read-default-plan-dir ()
  "Return the project's `#+DEFAULT_PLAN_DIR:' value, or nil.
Reads `TASKS.org' from the project root and extracts the directory
from the org-link form `[[file:./path/to/dir]]' or a bare path.
Returns a string relative to the project root (no leading `./')
or nil when the keyword is absent or the file is unreadable."
  (let ((tasks-file (tasks-org--tasks-file)))
    (when (file-readable-p tasks-file)
      (with-temp-buffer
        (insert-file-contents tasks-file)
        (goto-char (point-min))
        (when (re-search-forward
               "^#\\+DEFAULT_PLAN_DIR:[ \t]*\\(.*\\)" nil t)
          (let* ((raw (string-trim (match-string-no-properties 1)))
                 (path (or (tasks-org--extract-import-path raw)
                           (and (not (string-empty-p raw)) raw))))
            (when path
              (replace-regexp-in-string "\\`\\./" "" path))))))))

(defun tasks-org--effective-plans-directory ()
  "Return the project's plan directory: `#+DEFAULT_PLAN_DIR:' or fallback.
The fallback is `tasks-org-plans-directory'."
  (or (tasks-org--read-default-plan-dir)
      tasks-org-plans-directory))

(defun tasks-org--should-auto-enable-p ()
  "Return non-nil when the current buffer matches activation rules.
Activates when the buffer's path (relative to the project root) matches
`tasks-org-auto-enable-paths', when the buffer's directory matches the
project's `#+DEFAULT_PLAN_DIR:' (or its `tasks-org-plans-directory'
fallback), or when the buffer itself contains a `#+DEFAULT_PLAN_DIR:'
keyword (the canonical marker of a task-memory root)."
  (when (and buffer-file-name (derived-mode-p 'org-mode))
    (or (tasks-org--has-plan-dir-keyword-p)
        (let* ((root (tasks-org--project-root))
               (rel (file-relative-name buffer-file-name root))
               (plans-dir (ignore-errors
                            (tasks-org--effective-plans-directory))))
          (or (cl-some (lambda (re) (string-match-p re rel))
                       tasks-org-auto-enable-paths)
              (and plans-dir
                   (string-prefix-p
                    (file-name-as-directory plans-dir) rel)))))))

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

(defun tasks-org--extract-import-path (raw)
  "Extract a file path from a #+IMPORT: value RAW.
Handles bare paths, [[file:...]] and [[file:...][label]] forms.
Search options (e.g. ::heading) are stripped from the extracted path."
  (cond
   ((null raw) nil)
   ((string-match "\\[\\[file:\\([^]]+?\\)\\(?:\\]\\[[^]]*\\)?\\]\\]" raw)
    (replace-regexp-in-string "::[^]]*\\'" "" (match-string 1 raw)))
   ((not (string-empty-p (string-trim raw)))
    (string-trim raw))
   (t nil)))

(defun tasks-org--get-import-raw ()
  "Return the raw #+IMPORT: value from the current heading body, or nil.
Searches forward from the heading to the next heading boundary."
  (save-excursion
    (unless (org-at-heading-p)
      (org-back-to-heading t))
    (let ((end (save-excursion (outline-next-heading) (point))))
      (when (re-search-forward "^[ \t]*#\\+IMPORT:[ \t]*\\(.*\\)" end t)
        (let ((val (string-trim (match-string-no-properties 1))))
          (and (not (string-empty-p val)) val))))))

(defun tasks-org--set-import (link-value)
  "Insert or replace #+IMPORT: in the current heading body.
LINK-VALUE is the full value to write, e.g. \"[[file:plan.org]]\".
Inserts after the :END: of the properties drawer (or CLOSED: line,
or directly after the heading when neither is present)."
  (save-excursion
    (unless (org-at-heading-p)
      (org-back-to-heading t))
    (let ((end (save-excursion (outline-next-heading) (point))))
      (if (re-search-forward "^[ \t]*#\\+IMPORT:.*$" end t)
          (replace-match (format "#+IMPORT: %s" link-value))
        ;; Insert at the right place: after drawer :END: or CLOSED:, else
        ;; immediately after the heading line.
        (goto-char (org-entry-beginning-position))
        (forward-line 1)
        (when (looking-at "[ \t]*CLOSED:")
          (forward-line 1))
        (when (looking-at "[ \t]*:PROPERTIES:")
          (while (not (looking-at "[ \t]*:END:"))
            (forward-line 1))
          (forward-line 1))
        (insert (format "#+IMPORT: %s\n" link-value))))))

;;; Timestamp helpers

(defvar org-state)

(defun tasks-org--org-timestamp ()
  "Return an org-style inactive timestamp value, e.g. `2026-04-28 Tue 11:00'.
Matches the format used by `:STARTED:', `:CREATED:', and `CLOSED:'."
  (format-time-string "%Y-%m-%d %a %H:%M"))

(defun tasks-org--maybe-record-started ()
  "Record `:STARTED: [...]' on the current heading if missing.
Called from `org-after-todo-state-change-hook' when a task transitions
into `STARTED'. Re-opens (DONE -> STARTED) preserve the original value:
the property is written only when absent."
  (when (and (bound-and-true-p tasks-org-mode)
             (boundp 'org-state)
             (string= org-state "STARTED")
             (tasks-org--at-task-heading-p)
             (not (org-entry-get nil "STARTED")))
    (org-entry-put nil "STARTED"
                   (format "[%s]" (tasks-org--org-timestamp)))))

;;; Selection helpers — TASKS.local.org scheme

(defun tasks-org--local-file ()
  "Return the absolute path of the per-contributor local selection file."
  (expand-file-name tasks-org-local-file-name (tasks-org--project-root)))

(defun tasks-org-selected-id ()
  "Return the UUID of the currently selected task from TASKS.local.org, or nil."
  (let ((local-file (tasks-org--local-file)))
    (when (file-readable-p local-file)
      (with-temp-buffer
        (insert-file-contents local-file)
        (goto-char (point-min))
        (when (re-search-forward "^#\\+SELECTED:\\s-*\\([^[:space:]\n]+\\)" nil t)
          (match-string-no-properties 1))))))

(defun tasks-org--write-local-selection (id)
  "Write ID to TASKS.local.org atomically.
When ID is nil the file is retained with an empty #+SELECTED: keyword
rather than deleted, so it remains present for .gitignore purposes."
  (let* ((local-file (tasks-org--local-file))
         (tmp-file (concat local-file ".tmp")))
    (make-directory (file-name-directory local-file) t)
    (with-temp-file tmp-file
      (insert (if id (format "#+SELECTED: %s\n" id) "#+SELECTED:\n")))
    (rename-file tmp-file local-file t)))

;;;###autoload
(defun tasks-org-toggle-selected ()
  "Toggle the selection of the current task via TASKS.local.org.
Writes #+SELECTED: <UUID> to TASKS.local.org (creating it if absent).
Deselecting clears the `#+SELECTED:' value; the file is retained
(it remains gitignored and may carry local drafts and #+IMPORT:
keywords alongside the selection keyword)."
  (interactive)
  (unless (tasks-org--at-task-heading-p)
    (user-error "Point is not on an actionable task heading"))
  ;; Ensure the task has an :ID:
  (tasks-org--ensure-id-at-heading)
  (let* ((id (org-entry-get nil "ID"))
         (current-selected (tasks-org-selected-id))
         (was-selected (and id (string= id current-selected))))
    (if was-selected
        (progn
          (tasks-org--write-local-selection nil)
          (message "Cleared selection: %s" (org-get-heading t t t t)))
      (tasks-org--write-local-selection id)
      (message "Selected: %s" (org-get-heading t t t t))))
  (tasks-org--refresh-all-selection-overlays))

;;; Selection overlay

(defface tasks-org-selected-face
  '((((class color) (background dark))
     :background "#2d5c2d" :extend t)
    (((class color) (background light))
     :background "#b8ddb8" :extend t)
    (t :weight bold))
  "Face applied to the heading line of the currently selected task."
  :group 'tasks-org)

(defvar-local tasks-org--selection-overlay nil
  "Buffer-local overlay marking the currently selected task heading.")

(defvar tasks-org--local-file-watchers '()
  "Alist of (local-file-path . watch-descriptor) for file-notify watchers.")

(defun tasks-org--clear-selection-overlay ()
  "Remove the selection overlay from the current buffer."
  (when (overlayp tasks-org--selection-overlay)
    (delete-overlay tasks-org--selection-overlay))
  (setq tasks-org--selection-overlay nil))

(defun tasks-org--find-heading-pos-by-id (id)
  "Return the buffer position of the heading with :ID: ID, or nil."
  (org-with-wide-buffer
   (goto-char (point-min))
   (let (found)
     (while (and (not found)
                 (re-search-forward
                  (concat "^[ \t]*:ID:[ \t]+" (regexp-quote id) "[ \t]*$")
                  nil t))
       (ignore-errors
         (org-back-to-heading t)
         (setq found (point))))
     found)))

(defun tasks-org--refresh-selection-overlay ()
  "Update the selection overlay for the current org buffer."
  (when (derived-mode-p 'org-mode)
    (tasks-org--clear-selection-overlay)
    (when-let* ((id (tasks-org-selected-id))
                (pos (tasks-org--find-heading-pos-by-id id)))
      (save-excursion
        (goto-char pos)
        (let* ((bol (line-beginning-position))
               (eol (line-end-position))
               (ov  (make-overlay bol (1+ eol))))
          (overlay-put ov 'face 'tasks-org-selected-face)
          (overlay-put ov 'evaporate t)
          (overlay-put ov 'tasks-org-selection t)
          (setq tasks-org--selection-overlay ov))))))

(defun tasks-org--refresh-all-selection-overlays ()
  "Refresh selection overlays in all live `tasks-org-mode' buffers."
  (dolist (buf (buffer-list))
    (when (buffer-live-p buf)
      (with-current-buffer buf
        (when (bound-and-true-p tasks-org-mode)
          (tasks-org--refresh-selection-overlay))))))

(defun tasks-org--setup-local-file-watch ()
  "Watch the project root for changes to TASKS.local.org.
Uses `filenotify' so that selection changes written by the pi extension
or another Emacs session are reflected immediately via an idle-timer
debounce."
  (let* ((local-file (expand-file-name (tasks-org--local-file)))
         (root-dir   (file-name-directory local-file)))
    (unless (assoc local-file tasks-org--local-file-watchers)
      (condition-case nil
          (let* ((lf local-file)
                 (desc (file-notify-add-watch
                        root-dir '(change)
                        (lambda (event)
                          (when (string= (expand-file-name (nth 2 event)) lf)
                            (run-with-idle-timer
                             0.1 nil
                             #'tasks-org--refresh-all-selection-overlays))))))
            (push (cons local-file desc) tasks-org--local-file-watchers))
        (error nil)))))

(defun tasks-org--teardown-local-file-watch ()
  "Remove the file-notify watcher for the current project's TASKS.local.org."
  (let* ((local-file (expand-file-name (tasks-org--local-file)))
         (entry (assoc local-file tasks-org--local-file-watchers)))
    (when entry
      (ignore-errors (file-notify-rm-watch (cdr entry)))
      (setq tasks-org--local-file-watchers
            (delq entry tasks-org--local-file-watchers)))))

;;; Change-record navigation

(defun tasks-org--open-import-link (raw source-dir &optional find-fn)
  "Open the file extracted from RAW #+IMPORT: value, resolved against SOURCE-DIR.
FIND-FN defaults to `find-file'; pass `find-file-other-window' to split."
  (let* ((path (tasks-org--extract-import-path raw))
         (abs (when path (expand-file-name path source-dir))))
    (if (and abs (file-readable-p abs))
        (funcall (or find-fn #'find-file) abs)
      (user-error "Change-record file not found: %s" (or abs raw)))))

;;;###autoload
(defun tasks-org-open-plan (&optional find-fn)
  "Open the change-record linked from the current task via `#+IMPORT:'.
FIND-FN defaults to `find-file'; pass `find-file-other-window' to split.
Signals a `user-error' when the task has no `#+IMPORT:' link \u2014
change-record creation is the remit of the agent harness (use the pi
tasks extension's `p' keybinding to scaffold one)."
  (interactive)
  (unless (tasks-org--at-task-heading-p)
    (user-error "Point is not on an actionable task heading"))
  (let ((import-raw (tasks-org--get-import-raw))
        (source-dir (file-name-directory (or buffer-file-name ""))))
    (unless import-raw
      (user-error
       "No #+IMPORT: on this task; use the pi tasks extension's `p' to create one"))
    (tasks-org--open-import-link import-raw source-dir find-fn)))

;;;###autoload
(defun tasks-org-open-plan-other-window ()
  "Open the change-record linked from the current task in another window."
  (interactive)
  (tasks-org-open-plan #'find-file-other-window))

;;;###autoload
(defun tasks-org-publish-task ()
  "Publish the task subtree at point to TASKS.org.
Moves the subtree from the current file (typically TASKS.local.org) to the
project's TASKS.org as a new top-level entry.  Both files are saved.
Prompts for confirmation before making any changes."
  (interactive)
  (unless (tasks-org--at-task-heading-p)
    (user-error "Point is not on an actionable task heading"))
  (unless buffer-file-name
    (user-error "Current buffer is not visiting a file"))
  (let* ((tasks-file (tasks-org--tasks-file))
         (summary (org-get-heading t t t t)))
    (unless (yes-or-no-p
             (format "Publish '%s' to %s? " summary tasks-org-tasks-file-name))
      (user-error "Cancelled"))
    (org-cut-subtree)
    (save-buffer)
    (with-current-buffer (find-file-noselect tasks-file)
      (goto-char (point-max))
      (unless (bolp) (insert "\n"))
      (unless (looking-back "\n\n" 2) (insert "\n"))
      (org-paste-subtree 1)
      (save-buffer))
    (message "Published '%s' to %s" summary tasks-org-tasks-file-name)))

;;;###autoload
(defun tasks-org-unpublish-task ()
  "Unpublish the top-level task at point from TASKS.org to TASKS.local.org.
Only level-1 tasks may be unpublished.  Both files are saved.
Prompts for confirmation before making any changes."
  (interactive)
  (unless (tasks-org--at-task-heading-p)
    (user-error "Point is not on an actionable task heading"))
  (save-excursion
    (unless (org-at-heading-p)
      (org-back-to-heading t))
    (unless (= (org-outline-level) 1)
      (user-error "Only top-level tasks can be unpublished (current level: %d)"
                  (org-outline-level))))
  (let* ((local-file (tasks-org--local-file))
         (summary (org-get-heading t t t t)))
    (unless (yes-or-no-p
             (format "Unpublish '%s' to %s (removes from git tracking)? "
                     summary tasks-org-local-file-name))
      (user-error "Cancelled"))
    (org-cut-subtree)
    (save-buffer)
    (with-current-buffer (find-file-noselect local-file)
      (goto-char (point-max))
      (unless (bolp) (insert "\n"))
      (unless (looking-back "\n\n" 2) (insert "\n"))
      (org-paste-subtree 1)
      (save-buffer))
    (message "Unpublished '%s' to %s" summary tasks-org-local-file-name)))

;;;###autoload
(defun tasks-org-jump-to-parent-task ()
  "Jump to the task in TASKS.org whose #+IMPORT: links to the current buffer."
  (interactive)
  (unless buffer-file-name
    (user-error "Current buffer is not visiting a file"))
  (let* ((tasks-file (tasks-org--tasks-file))
         (tasks-dir (file-name-directory (expand-file-name tasks-file)))
         (current-abs (expand-file-name buffer-file-name))
         (tasks-buf (find-file-noselect tasks-file))
         found-point)
    (with-current-buffer tasks-buf
      (save-excursion
        (goto-char (point-min))
        (while (and (not found-point)
                    (re-search-forward "^[ \t]*#\\+IMPORT:[ \t]*\\(.*\\)" nil t))
          (let* ((raw (string-trim (match-string 1)))
                 (path (tasks-org--extract-import-path raw))
                 (abs (when path (expand-file-name path tasks-dir))))
            (when (and abs (string= (expand-file-name abs) current-abs))
              (org-back-to-heading t)
              (setq found-point (point)))))))
    (if found-point
        (let ((win (get-buffer-window tasks-buf)))
          (if win
              (select-window win)
            (switch-to-buffer tasks-buf))
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
toggling task selection via TASKS.local.org, and opening or creating
#+IMPORT: linked files.  Highlights the currently selected task heading
using `tasks-org-selected-face' and watches TASKS.local.org for
external changes (e.g. from the pi extension)."
  :lighter " Tasks"
  :keymap tasks-org-mode-map
  (if tasks-org-mode
      (progn
        (add-hook 'after-save-hook #'tasks-org--refresh-selection-overlay nil t)
        (add-hook 'org-after-todo-state-change-hook
                  #'tasks-org--maybe-record-started nil t)
        (tasks-org--setup-local-file-watch)
        (tasks-org--refresh-selection-overlay))
    (remove-hook 'after-save-hook #'tasks-org--refresh-selection-overlay t)
    (remove-hook 'org-after-todo-state-change-hook
                 #'tasks-org--maybe-record-started t)
    (tasks-org--clear-selection-overlay)))

;;;###autoload
(add-hook 'org-mode-hook #'tasks-org-maybe-enable)

(provide 'tasks-org)
;;; tasks-org.el ends here
