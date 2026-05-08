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

(defcustom tasks-org-archive-file-name "TASKS.archive.org"
  "Filename of the project's archived-task store."
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

(defun tasks-org--archive-file ()
  "Return the absolute path of the project's TASKS.archive.org."
  (expand-file-name tasks-org-archive-file-name (tasks-org--project-root)))

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

(defun tasks-org--build-task-block (level summary id timestamp)
  "Return a TODO task block string at outline LEVEL with SUMMARY, ID, TIMESTAMP.
Mirrors the pi `buildTaskBlock' shape: heading + :PROPERTIES: drawer with
:ID: / :CREATED: + :LOGBOOK: drawer seeded with `- Created [TIMESTAMP]'.  Files
created this way round-trip cleanly between pi and Emacs surfaces."
  (let ((stars (make-string level ?*)))
    (concat
     (format "%s TODO %s\n" stars summary)
     ":PROPERTIES:\n"
     (format ":ID: %s\n" id)
     (format ":CREATED: [%s]\n" timestamp)
     ":END:\n"
     ":LOGBOOK:\n"
     (format "- Created [%s]\n" timestamp)
     ":END:\n")))

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

;;; Status transitions (protocol-aware)

(defconst tasks-org--terminal-states '("DONE" "CANCELLED")
  "TODO keywords that emit a `CLOSED:' line and clear `:STARTED:' on reopen.")

(defun tasks-org--todo-sequence ()
  "Return the buffer's TODO keyword sequence as a list of strings.
Filters out the `|' separator and any keyword fast-access markers."
  (let ((kws (or (and (boundp 'org-todo-keywords-1)
                      org-todo-keywords-1)
                 '("TODO" "STARTED" "WAITING" "DONE" "CANCELLED"))))
    (mapcar (lambda (k)
              (replace-regexp-in-string "(.*)" "" k))
            kws)))

(defun tasks-org--ensure-logbook-drawer ()
  "Ensure the current heading has a `:LOGBOOK:' drawer; return its body insert pos.
The insert point is the position immediately before the drawer's `:END:'
line, suitable for inserting an append-only entry."
  (save-excursion
    (unless (org-at-heading-p)
      (org-back-to-heading t))
    (let* ((end (save-excursion (outline-next-heading) (point)))
           (logbook-start
            (save-excursion
              (when (re-search-forward "^[ \t]*:LOGBOOK:[ \t]*$" end t)
                (line-beginning-position)))))
      (unless logbook-start
        ;; Insert a new :LOGBOOK: drawer after :PROPERTIES: (or CLOSED:, or
        ;; the heading line) and before any body text.
        (goto-char (org-entry-beginning-position))
        (forward-line 1)
        (when (looking-at "[ \t]*CLOSED:")
          (forward-line 1))
        (when (looking-at "[ \t]*:PROPERTIES:")
          (while (not (looking-at "[ \t]*:END:"))
            (forward-line 1))
          (forward-line 1))
        (insert ":LOGBOOK:\n:END:\n")
        (forward-line -2)
        (setq logbook-start (line-beginning-position)))
      ;; Move to position before the :END: line.
      (goto-char logbook-start)
      (re-search-forward "^[ \t]*:END:[ \t]*$" end t)
      (line-beginning-position))))

(defun tasks-org--append-logbook-entry (text)
  "Append TEXT as a new line inside the heading's `:LOGBOOK:' drawer.
The drawer is created when absent.  TEXT is written verbatim with
no leading bullet — pass the full bullet (e.g.
`- State \"DONE\" from \"STARTED\" [...]')."
  (let ((insert-pos (tasks-org--ensure-logbook-drawer)))
    (save-excursion
      (goto-char insert-pos)
      (insert text "\n"))))

(defun tasks-org--write-closed (timestamp)
  "Set the heading's `CLOSED:' line to TIMESTAMP (org timestamp string).
Inserts immediately above `:PROPERTIES:' if absent, else replaces in place."
  (save-excursion
    (unless (org-at-heading-p)
      (org-back-to-heading t))
    (forward-line 1)
    (cond
     ((looking-at "[ \t]*CLOSED:.*$")
      (replace-match (format "CLOSED: [%s]" timestamp)))
     (t
      (let ((before-properties (point)))
        (when (looking-at "[ \t]*:PROPERTIES:")
          (goto-char before-properties))
        (insert (format "CLOSED: [%s]\n" timestamp)))))))

(defun tasks-org--clear-closed ()
  "Remove the `CLOSED:' line from the current heading if present."
  (save-excursion
    (unless (org-at-heading-p)
      (org-back-to-heading t))
    (forward-line 1)
    (when (looking-at "[ \t]*CLOSED:.*\n")
      (replace-match ""))))

(defun tasks-org--clear-started-property ()
  "Remove the `:STARTED:' property from the current heading."
  (save-excursion
    (unless (org-at-heading-p)
      (org-back-to-heading t))
    (org-entry-delete nil "STARTED")))

(defun tasks-org--apply-status-transition (new-status)
  "Transition the current heading to NEW-STATUS with full protocol writes.
Writes:
  * heading TODO keyword (via `org-todo' for normal org behaviour);
  * append-only `:LOGBOOK:' entry `- State \"NEW\" from \"OLD\" [ts]';
  * `CLOSED:' on entering DONE/CANCELLED, cleared on reopen;
  * `:STARTED:' on first transition into STARTED, preserved on reopen.

The append-only LOGBOOK and CLOSED bookkeeping are written here rather
than relying on `org-log-into-drawer' / `org-log-done', because the
project's `#+TODO:' line does not declare `(/!)' markers and the
protocol still expects the entries unconditionally."
  (let* ((old-status (org-get-todo-state))
         (ts (tasks-org--org-timestamp))
         (now-terminal (member new-status tasks-org--terminal-states))
         (was-terminal (and old-status (member old-status tasks-org--terminal-states))))
    ;; Heading keyword.  Suppress org's own logging because we drive
    ;; LOGBOOK / CLOSED ourselves.
    (let ((org-log-done nil)
          (org-log-into-drawer nil)
          (org-todo-log-states nil))
      (org-todo new-status))
    ;; LOGBOOK transition entry.
    (when (and old-status new-status
               (not (equal old-status new-status)))
      (tasks-org--append-logbook-entry
       (format "- State \"%s\"      from \"%s\"      [%s]"
               new-status old-status ts)))
    ;; CLOSED bookkeeping.
    (cond
     ((and now-terminal (not was-terminal))
      (tasks-org--write-closed ts))
     ((and now-terminal was-terminal)
      ;; Re-close: refresh CLOSED: with the new timestamp.
      (tasks-org--write-closed ts))
     ((and was-terminal (not now-terminal))
      (tasks-org--clear-closed)))
    ;; :STARTED: bookkeeping.
    (cond
     ((and (string= new-status "STARTED")
           (not (org-entry-get nil "STARTED")))
      (org-entry-put nil "STARTED" (format "[%s]" ts))))))

(defun tasks-org--cycle-direction (current-status direction)
  "Return the new status when cycling CURRENT-STATUS in DIRECTION.
DIRECTION is the symbol `forward' or `backward'.  Wraps modulo the
buffer's TODO sequence.  When CURRENT-STATUS is nil, returns the
first sequence keyword."
  (let* ((seq (tasks-org--todo-sequence))
         (n (length seq))
         (cur-idx (or (cl-position current-status seq :test #'equal) -1))
         (next-idx (mod (+ cur-idx (if (eq direction 'backward) -1 1)) n)))
    (nth next-idx seq)))

;;;###autoload
(defun tasks-org-cycle-status (&optional backward)
  "Cycle the current task's TODO state forward through the sequence.
With prefix arg BACKWARD non-nil, cycles backward.  Writes the
heading keyword, append-only `:LOGBOOK:' entry, `CLOSED:' line on
DONE/CANCELLED transitions (cleared on reopen), and `:STARTED:' on
first transition into STARTED."
  (interactive "P")
  (unless (tasks-org--at-task-heading-p)
    (user-error "Point is not on an actionable task heading"))
  (let* ((current (org-get-todo-state))
         (direction (if backward 'backward 'forward))
         (new-status (tasks-org--cycle-direction current direction)))
    (tasks-org--apply-status-transition new-status)
    (message "Status: %s -> %s" (or current "(none)") new-status)))

;;;###autoload
(defun tasks-org-cycle-status-back ()
  "Cycle the current task's TODO state backward through the sequence."
  (interactive)
  (tasks-org-cycle-status t))

(defun tasks-org-set-status-at (file pos new-status)
  "Programmatic entry point: transition the task at FILE / POS to NEW-STATUS.
Visits FILE via `find-file-noselect', moves to POS, runs
`tasks-org--apply-status-transition', and saves.  Used by the UI buffer
to persist a status change without requiring point to already be on the
task heading.  Returns the new status."
  (with-current-buffer (find-file-noselect file)
    (save-excursion
      (goto-char pos)
      (tasks-org--apply-status-transition new-status)
      (save-buffer)))
  new-status)

;;; Locate by UUID

(defun tasks-org-locate-by-id (id &optional extra-files)
  "Return (FILE . POS) for the task with `:ID:' ID, or nil.
Searches `TASKS.org', `TASKS.local.org', and any files in EXTRA-FILES
\(typically the current task graph's loaded change-record files\)."
  (let ((candidates (append (list (tasks-org--tasks-file)
                                  (tasks-org--local-file))
                            extra-files))
        result)
    (dolist (file candidates result)
      (when (and (not result)
                 file
                 (file-readable-p file))
        (with-current-buffer (find-file-noselect file)
          (when-let ((pos (tasks-org--find-heading-pos-by-id id)))
            (setq result (cons file pos))))))))

;;; Change-record scaffold

(defun tasks-org--slugify (s)
  "Return a filesystem-friendly slug for S."
  (let ((slug (downcase s)))
    (setq slug (replace-regexp-in-string "[^a-z0-9]+" "-" slug))
    (setq slug (replace-regexp-in-string "\\`-+\\|-+\\'" "" slug))
    slug))

(defun tasks-org--default-import-path-for-heading ()
  "Return a suggested change-record path for the heading at point.
Format: <DEFAULT_PLAN_DIR>/<YYYY-MM-DD>-<slug>.org"
  (let* ((heading (org-get-heading t t t t))
         (slug (tasks-org--slugify (or heading "change-record")))
         (date (format-time-string "%Y-%m-%d"))
         (dir (tasks-org--effective-plans-directory))
         (root (tasks-org--project-root)))
    (expand-file-name (format "%s-%s.org" date slug)
                      (expand-file-name dir root))))

(defun tasks-org--scaffold-change-record (file parent-id title)
  "Write the org-plan minimal skeleton to FILE for PARENT-ID + TITLE.
Refuses to overwrite an existing file.  Creates parent directories
as needed.  See `agents-src/skills/org-plan/SKILL.md' for the skeleton
contract."
  (when (file-exists-p file)
    (user-error "Refusing to overwrite existing change-record: %s" file))
  (make-directory (file-name-directory file) t)
  (with-temp-file file
    (insert (format "#+TITLE: %s\n" title))
    (insert (format "#+DATE: %s\n" (format-time-string "%Y-%m-%d %a")))
    (insert (format "#+PARENT_ID: %s\n" parent-id))
    (insert "#+STATUS: Draft\n")
    (insert "#+TODO: TODO(t) STARTED(s) WAITING(w) | DONE(d) CANCELLED(c)\n")
    (insert "\n* Context\n\n")
    (insert "** Design decisions\n\n")
    (insert "* Plan\n\n")
    (insert "* Implementation\n\n")
    (insert "* Open questions\n")))

;;;###autoload
(defun tasks-org-create-import-for-current-task (&optional path)
  "Scaffold a change-record for the current task and link it via `#+IMPORT:'.
Prompts for PATH (default suggestion derived from the task heading
and `#+DEFAULT_PLAN_DIR:').  Refuses to overwrite an existing file.
Ensures the parent task has an `:ID:'.  Saves the parent buffer.
Opens the new change-record in another window."
  (interactive)
  (unless (tasks-org--at-task-heading-p)
    (user-error "Point is not on an actionable task heading"))
  (when (tasks-org--get-import-raw)
    (user-error "Task already has a #+IMPORT: link; use `tasks-org-open-plan' to open it"))
  (tasks-org--ensure-id-at-heading)
  (let* ((default-path (tasks-org--default-import-path-for-heading))
         (chosen (or path
                     (read-file-name "Change-record path: "
                                     (file-name-directory default-path)
                                     nil nil
                                     (file-name-nondirectory default-path))))
         (title (org-get-heading t t t t))
         (parent-id (org-entry-get nil "ID"))
         (source-dir (file-name-directory (or buffer-file-name ""))))
    (tasks-org--scaffold-change-record chosen parent-id title)
    ;; Set #+IMPORT: as a clickable [[file:...]] relative to source-dir.
    (let ((rel (file-relative-name chosen source-dir)))
      (tasks-org--set-import (format "[[file:%s]]" rel)))
    (save-buffer)
    (find-file-other-window chosen)
    (message "Scaffolded change-record: %s" chosen)))

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
  "Write ID as the #+SELECTED: pointer in TASKS.local.org.
Preserves all other content in the file (local task headings,
#+IMPORT: keywords, etc.).  When ID is nil the #+SELECTED: keyword
is retained with an empty value so the file remains gitignored and
its other content stays intact.  When the file does not yet exist
it is created with just the keyword.

The write edits a live buffer visiting TASKS.local.org, then persists it via
an atomic temp-file rename.  That keeps any visible TASKS.local.org buffer in
sync and avoids Emacs' reload prompt when selection is toggled from the tree UI."
  (let* ((local-file (tasks-org--local-file))
         (tmp-file (concat local-file ".tmp"))
         (new-line (if id (format "#+SELECTED: %s\n" id) "#+SELECTED:\n")))
    (make-directory (file-name-directory local-file) t)
    (with-current-buffer (find-file-noselect local-file)
      (let ((pos (point))
            (inhibit-read-only t))
        (goto-char (point-min))
        (cond
         ;; Existing #+SELECTED: line: replace it in place.
         ((re-search-forward "^#\\+SELECTED:[^\n]*\n?" nil t)
          (replace-match new-line t t))
         ;; No keyword present: prepend.  If the file is empty this writes just
         ;; the keyword; otherwise the existing body follows unchanged because
         ;; NEW-LINE already ends with a newline.
         (t
          (goto-char (point-min))
          (insert new-line)))
        (let ((inhibit-message t))
          (write-region (point-min) (point-max) tmp-file nil nil)
          (rename-file tmp-file local-file t))
        (set-visited-file-modtime)
        (set-buffer-modified-p nil)
        (goto-char (min pos (point-max)))
        (when (bound-and-true-p tasks-org-mode)
          (tasks-org--refresh-selection-overlay))))))

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
          (if (fboundp 'org-fold-show-entry)
              (org-fold-show-entry)
            (with-no-warnings (org-show-entry)))
          (recenter))
      (user-error "No task in %s links to the current file"
                  tasks-org-tasks-file-name))))

;;; Archive

(defconst tasks-org--archive-far-future "9999-12-31 Zzz 23:59"
  "Sort-key fallback for archive entries with no resolvable timestamp.
Matches pi's `archiveSortTimestamp' fallback so the two surfaces order
entries identically when neither =CLOSED:= nor a LOGBOOK close event nor
=:ARCHIVED:= can be parsed.")

(defun tasks-org--archive-sort-key (subtree-text)
  "Return the archive-ordering key for SUBTREE-TEXT.
Priority mirrors pi's `archiveSortTimestamp':
  1. =CLOSED:= timestamp on its own line.
  2. Most recent =DONE= / =CANCELLED= LOGBOOK transition.
  3. =:ARCHIVED:= drawer property.
  4. Far-future fallback so undated entries sink to the bottom."
  (or (and (string-match "^CLOSED:[ \t]+\\[\\([^]]+\\)\\]" subtree-text)
           (match-string 1 subtree-text))
      (let ((logbook-key nil)
            (start 0))
        (while (string-match
                "^-[ \t]+State[ \t]+\"\\(DONE\\|CANCELLED\\)\"[ \t]+from[ \t]+\"[^\"]+\"[ \t]+\\[\\([^]]+\\)\\]"
                subtree-text start)
          (setq logbook-key (match-string 2 subtree-text)
                start (match-end 0)))
        logbook-key)
      (and (string-match "^:ARCHIVED:[ \t]+\\[\\([^]]+\\)\\]" subtree-text)
           (match-string 1 subtree-text))
      tasks-org--archive-far-future))

(defun tasks-org--collect-archive-entries ()
  "Return level-1 entries from the current buffer as `(SORT-KEY . TEXT)' pairs.
Text runs from each level-1 heading through the position immediately before
the next sibling (or buffer end).  Pre-heading content (file-level keywords,
comments) is left in place by the caller; this helper only inspects the
heading region."
  (let (entries)
    (save-excursion
      (goto-char (point-min))
      (while (re-search-forward "^\\* " nil t)
        (let* ((start (match-beginning 0))
               (end (save-excursion
                      (goto-char start)
                      (org-end-of-subtree t t)
                      (point)))
               (text (buffer-substring-no-properties start end)))
          (push (cons (tasks-org--archive-sort-key text) text) entries)
          (goto-char end))))
    (nreverse entries)))

(defun tasks-org--rewrite-archive-sorted (entries)
  "Replace the level-1 entry region of the current buffer with sorted ENTRIES.
ENTRIES is a list of `(SORT-KEY . TEXT)' pairs; the buffer is rewritten with
entries sorted ascending by SORT-KEY (string compare — ISO-style timestamps
order chronologically).  Any pre-heading preamble (keywords, comments) is
preserved verbatim."
  (let* ((sorted (sort (copy-sequence entries)
                       (lambda (a b) (string< (car a) (car b)))))
         (preamble-end (save-excursion
                         (goto-char (point-min))
                         (if (re-search-forward "^\\* " nil t)
                             (match-beginning 0)
                           (point-max)))))
    (delete-region preamble-end (point-max))
    (goto-char (point-max))
    (dolist (entry sorted)
      (let ((text (cdr entry)))
        (insert text)
        (unless (string-suffix-p "\n" text) (insert "\n"))))))

(defun tasks-org--promote-subtree-text (text)
  "Return TEXT with every heading line's leading star count reduced by one.
Used when transferring a level-2 task from `TASKS.org' to the archive—which
has no category section, so its tasks live at level 1."
  (replace-regexp-in-string
   "^\\(\\*+\\) "
   (lambda (m)
     (let ((stars (match-string 1 m)))
       (concat (substring stars 1) " ")))
   text))

(defun tasks-org--add-archived-property (text timestamp)
  "Return TEXT with =:ARCHIVED: [TIMESTAMP]= inserted before the first =:END:=.
Assumes the heading carries a =:PROPERTIES:= drawer; signals an error if
no drawer or no closing =:END:= is found.  Only the first drawer is
touched, so a later =:LOGBOOK:= drawer's =:END:= is unaffected."
  (let ((props-pos (string-match "^:PROPERTIES:$" text)))
    (unless props-pos
      (error "Archived task is missing :PROPERTIES: drawer"))
    (let ((end-pos (string-match "^:END:$" text props-pos)))
      (unless end-pos
        (error "Archived task has unterminated :PROPERTIES: drawer"))
      (concat (substring text 0 end-pos)
              ":ARCHIVED: [" timestamp "]\n"
              (substring text end-pos)))))

;;;###autoload
(defun tasks-org-archive-task ()
  "Archive the top-level task at point to `TASKS.archive.org'.
Mirrors the pi tasks extension's archive flow:
  - Refuses unless the heading is a level-2 task (top-level under a category
    section in `TASKS.org') with status =DONE= or =CANCELLED=.
  - Refuses for local-origin tasks (publish first).
  - Prompts for confirmation.
  - Transfers the subtree as-is (heading promoted by one level, =#+IMPORT:=
    preserved, plan files not inlined), stamping a =:ARCHIVED:= property.
  - Re-sorts archive entries by =CLOSED:= ascending (LOGBOOK fallback,
    =:ARCHIVED:= fallback, far-future fallback) so order matches pi.
  - Clears `#+SELECTED:' when the archived task is the selected one.
Both source files are saved."
  (interactive)
  (unless (tasks-org--at-task-heading-p)
    (user-error "Point is not on an actionable task heading"))
  (unless buffer-file-name
    (user-error "Current buffer is not visiting a file"))
  (save-excursion
    (org-back-to-heading t)
    (unless (= (org-outline-level) 2)
      (user-error
       "Only top-level tasks (level 2 under a category section) may be archived"))
    (let ((status (org-get-todo-state)))
      (unless (member status '("DONE" "CANCELLED"))
        (user-error "Cannot archive: status is %s, not DONE/CANCELLED"
                    (or status "unset")))))
  (let* ((tasks-file (tasks-org--tasks-file))
         (archive-file (tasks-org--archive-file))
         (current-abs (expand-file-name buffer-file-name)))
    (unless (string= current-abs (expand-file-name tasks-file))
      (user-error "Archive only operates on tasks in %s (publish local first)"
                  tasks-org-tasks-file-name))
    (let* ((id (org-entry-get nil "ID"))
           (summary (org-get-heading t t t t))
           ;; `org-entry-get' for CLOSED returns the value with surrounding
           ;; brackets included (e.g. "[2026-04-25 Sat 13:03]"); strip them
           ;; so we re-emit `:ARCHIVED: [TIMESTAMP]' with single brackets.
           (closed-raw (org-entry-get nil "CLOSED"))
           (closed (and closed-raw
                        (if (string-match "\\`\\[\\(.*\\)\\]\\'" closed-raw)
                            (match-string 1 closed-raw)
                          closed-raw)))
           (timestamp (or closed (tasks-org--org-timestamp))))
      (unless (yes-or-no-p
               (format "Archive '%s' to %s? " summary tasks-org-archive-file-name))
        (user-error "Cancelled"))
      ;; Capture + cut the subtree from TASKS.org.
      (let ((subtree (save-excursion
                       (org-back-to-heading t)
                       (let ((start (point))
                             (end (save-excursion
                                    (org-end-of-subtree t t)
                                    (point))))
                         (buffer-substring-no-properties start end)))))
        (org-cut-subtree)
        (save-buffer)
        ;; Build the archive entry: promote, stamp :ARCHIVED:, ensure newline.
        (let* ((promoted (tasks-org--promote-subtree-text subtree))
               (stamped (tasks-org--add-archived-property promoted timestamp))
               (entry (if (string-suffix-p "\n" stamped) stamped
                        (concat stamped "\n"))))
          (with-current-buffer (find-file-noselect archive-file)
            (let ((entries (tasks-org--collect-archive-entries)))
              (push (cons (tasks-org--archive-sort-key entry) entry) entries)
              ;; Ensure a blank line follows the preamble before any entries.
              (save-excursion
                (goto-char (point-min))
                (unless (re-search-forward "^\\* " nil t)
                  (goto-char (point-max))
                  (unless (bolp) (insert "\n"))))
              (tasks-org--rewrite-archive-sorted entries))
            (save-buffer)))
        ;; Clear #+SELECTED: when the archived task was the selected one.
        (when (and id (equal (tasks-org-selected-id) id))
          (tasks-org--write-local-selection nil))
        (message "Archived '%s' to %s" summary tasks-org-archive-file-name)))))

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
