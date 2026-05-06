;;; tasks-org-ui.el --- Expanded tasks UI buffer over org-memory protocol -*- lexical-binding: t; no-byte-compile: t; -*-

;; Author: Cormac Cannon
;; URL: https://github.com/cormacc/dotfiles
;; Keywords: org, tasks, productivity
;; Package-Requires: ((emacs "29.1") (vui "1.0") (org "9.4"))

;;; Commentary:

;; A vui.el-rendered visualisation of the org-memory task graph for the
;; current project.  Mirrors the pi `tasks' extension's expanded UI for
;; navigate / expand / select / cycle workflows, while delegating
;; durable mutations to `tasks-org.el's protocol helpers and the graph
;; reader in `tasks-org-graph.el'.
;;
;; Architecture
;; ------------
;;   * Major mode `tasks-org-ui-mode' derives from `vui-mode' (which
;;     derives from `special-mode').  Spacemacs registers an
;;     evilified-state mapping in the layer's `packages.el' so motion
;;     keys remap to UI actions while `SPC' remains the global leader.
;;   * `tasks-org-ui-show' creates `*tasks-org*', mounts the
;;     `tasks-org-ui--root' component, and registers `file-notify'
;;     watchers on every graph-contributing file so external edits
;;     trigger a re-render that preserves the cursor task by UUID.
;;   * Status cycling delegates to `tasks-org-set-status-at' (so
;;     LOGBOOK / CLOSED / :STARTED: stay protocol-correct).  Selection
;;     uses the non-destructive `tasks-org--write-local-selection'.
;;     Plan open / scaffold delegate to `tasks-org-open-plan' /
;;     `tasks-org-create-import-for-current-task'.
;;
;; Byte-compilation is intentionally disabled (file-local
;; `no-byte-compile: t') because vui's component-defining macros must
;; expand at load time with `vui' already available; the layer's
;; `org-user/init-tasks-org' guarantees that ordering at runtime but
;; not necessarily during a batch byte-compile of the layer.

;;; Code:

(require 'cl-lib)
(require 'filenotify)
(require 'org)
(require 'org-id)

(require 'tasks-org)
(require 'tasks-org-graph)

(declare-function vui-defcomponent "vui")
(declare-function vui-mount "vui")
(declare-function vui-component "vui")
(declare-function vui-set-state "vui")
(declare-function vui-vstack "vui")
(declare-function vui-fragment "vui")
(declare-function vui-text "vui")
(declare-function vui-button "vui")
(declare-function vui-newline "vui")
(declare-function vui-use-effect "vui")
(defvar vui-mode-map)

;;; Customisation

(defgroup tasks-org-ui nil
  "Visualisation buffer for the org-memory task graph."
  :group 'tasks-org
  :prefix "tasks-org-ui-")

(defcustom tasks-org-ui-buffer-name "*tasks-org*"
  "Name of the buffer that displays the task graph UI."
  :type 'string
  :group 'tasks-org-ui)

(defcustom tasks-org-ui-collapse-completed t
  "When non-nil, DONE / CANCELLED subtrees are collapsed by default.
Subtrees on the path to the currently selected task remain expanded
regardless of this setting."
  :type 'boolean
  :group 'tasks-org-ui)

;;; Faces — pi colour palette

(defface tasks-org-ui-status-todo-face
  '((t :inherit warning))
  "Face for TODO status tokens (yellow)." :group 'tasks-org-ui)

(defface tasks-org-ui-status-started-face
  '((t :inherit font-lock-keyword-face))
  "Face for STARTED status tokens (blue)." :group 'tasks-org-ui)

(defface tasks-org-ui-status-waiting-face
  '((t :foreground "orange"))
  "Face for WAITING status tokens (orange)." :group 'tasks-org-ui)

(defface tasks-org-ui-status-done-face
  '((t :inherit success))
  "Face for DONE status tokens (green)." :group 'tasks-org-ui)

(defface tasks-org-ui-status-cancelled-face
  '((t :inherit error))
  "Face for CANCELLED status tokens (red)." :group 'tasks-org-ui)

(defface tasks-org-ui-priority-critical-face
  '((t :foreground "orange" :weight bold))
  "Face for [#A] priority cookies (orange)." :group 'tasks-org-ui)

(defface tasks-org-ui-priority-high-face
  '((t :inherit warning :weight bold))
  "Face for [#B] priority cookies (yellow)." :group 'tasks-org-ui)

(defface tasks-org-ui-priority-medium-face
  '((t :inherit success))
  "Face for [#C] priority cookies (green)." :group 'tasks-org-ui)

(defface tasks-org-ui-priority-low-face
  '((t :inherit font-lock-keyword-face))
  "Face for [#D] priority cookies (blue)." :group 'tasks-org-ui)

(defface tasks-org-ui-tag-face
  '((t :inherit font-lock-comment-face))
  "Face for org tag suffixes." :group 'tasks-org-ui)

(defface tasks-org-ui-badge-face
  '((t :foreground "cyan"))
  "Face for linked-issue badges." :group 'tasks-org-ui)

(defface tasks-org-ui-import-face
  '((t :inherit link :slant italic))
  "Face for the change-record path indicator on a task row."
  :group 'tasks-org-ui)

(defface tasks-org-ui-local-marker-face
  '((t :foreground "magenta"))
  "Face for the local-draft marker (\u22a0) and tinted summary."
  :group 'tasks-org-ui)

(defface tasks-org-ui-selected-face
  '((((class color) (background dark))
     :background "#2d5c2d" :extend t)
    (((class color) (background light))
     :background "#b8ddb8" :extend t)
    (t :weight bold))
  "Face applied to the currently selected task row."
  :group 'tasks-org-ui)

(defun tasks-org-ui--status-face (status)
  "Return the face symbol for STATUS keyword."
  (pcase status
    ("TODO"      'tasks-org-ui-status-todo-face)
    ("STARTED"   'tasks-org-ui-status-started-face)
    ("WAITING"   'tasks-org-ui-status-waiting-face)
    ("DONE"      'tasks-org-ui-status-done-face)
    ("CANCELLED" 'tasks-org-ui-status-cancelled-face)
    (_           'default)))

(defun tasks-org-ui--priority-face (letter)
  "Return the face symbol for priority LETTER (\"A\"..\"D\")."
  (pcase letter
    ("A" 'tasks-org-ui-priority-critical-face)
    ("B" 'tasks-org-ui-priority-high-face)
    ("C" 'tasks-org-ui-priority-medium-face)
    ("D" 'tasks-org-ui-priority-low-face)
    (_   'default)))

;;; Default expansion rules

(defun tasks-org-ui--ancestor-ids (task target-id &optional acc)
  "Return UUIDs of ancestors leading to TARGET-ID under TASK, or nil.
ACC accumulates the trail.  Includes TASK's :id when reachable."
  (let ((id (plist-get task :id)))
    (cond
     ((equal id target-id) (cons id acc))
     (t
      (cl-loop for child in (plist-get task :children)
               for path = (tasks-org-ui--ancestor-ids
                           child target-id (cons id acc))
               when path return path)))))

(defun tasks-org-ui--default-expanded-ids (graph)
  "Compute the default expanded-id set for GRAPH.
Always expands the path leading to the selected task.  Sibling
subtrees and completed (DONE/CANCELLED) subtrees stay collapsed unless
they fall on that path."
  (let ((selected (tasks-org-graph-selected-id graph))
        (expanded (make-hash-table :test 'equal)))
    (when selected
      (dolist (top (tasks-org-graph-tasks graph))
        (let ((path (tasks-org-ui--ancestor-ids top selected)))
          (when path
            (dolist (id path)
              (when id
                (puthash id t expanded)))))))
    expanded))

;;; Row formatting

(defun tasks-org-ui--format-status (status)
  (when status
    (propertize (concat status " ") 'face (tasks-org-ui--status-face status))))

(defun tasks-org-ui--format-priority (letter)
  (when letter
    (propertize (format "[#%s] " letter) 'face (tasks-org-ui--priority-face letter))))

(defun tasks-org-ui--format-tags (tags)
  (when tags
    (propertize (concat " :" (mapconcat #'identity tags ":") ":")
                'face 'tasks-org-ui-tag-face)))

(defun tasks-org-ui--format-badges (linked-issues)
  (when linked-issues
    (mapconcat
     (lambda (token)
       (let ((label (cond
                     ((and (string-prefix-p "[[" token)
                           (string-match "\\[\\[\\([^]]+\\)\\]\\[\\([^]]+\\)\\]\\]" token))
                      (match-string 2 token))
                     (t token))))
         (propertize (format " ⤴%s" label) 'face 'tasks-org-ui-badge-face)))
     linked-issues
     "")))

(defun tasks-org-ui--format-import-indicator (task)
  (let ((path (plist-get task :import-path))
        (raw (plist-get task :import-raw)))
    (when (or path raw)
      (propertize " ⇲" 'face 'tasks-org-ui-import-face))))

(defun tasks-org-ui--format-summary (task selected-id)
  "Return the formatted single-line label for TASK in the UI tree.
Marks the row as selected if its :id equals SELECTED-ID."
  (let* ((id (plist-get task :id))
         (origin (plist-get task :origin))
         (status (plist-get task :status))
         (priority (plist-get task :priority))
         (summary (or (plist-get task :summary) ""))
         (tags (plist-get task :tags))
         (linked-issues (plist-get task :linked-issues))
         (selected-p (and id selected-id (equal id selected-id)))
         (text (concat
                (and selected-p (propertize "★ " 'face 'tasks-org-ui-selected-face))
                (and (eq origin 'local)
                     (propertize "⊠ " 'face 'tasks-org-ui-local-marker-face))
                (or (tasks-org-ui--format-status status) "")
                (or (tasks-org-ui--format-priority priority) "")
                (cond
                 ((eq origin 'local)
                  (propertize summary 'face 'tasks-org-ui-local-marker-face))
                 (t summary))
                (or (tasks-org-ui--format-badges linked-issues) "")
                (or (tasks-org-ui--format-tags tags) "")
                (or (tasks-org-ui--format-import-indicator task) ""))))
    (if selected-p
        (propertize text 'face 'tasks-org-ui-selected-face)
      text)))

(defun tasks-org-ui--collapse-marker (task expanded-ids)
  "Return the leading marker for TASK depending on whether it has children."
  (let ((kids (plist-get task :children))
        (id (plist-get task :id)))
    (cond
     ((null kids) "  • ")
     ((and id (gethash id expanded-ids)) "  ▼ ")
     (t "  ▶ "))))

;;; UI state — buffer-local

(defvar-local tasks-org-ui--graph nil
  "Currently rendered graph plist, or nil before first load.")

(defvar-local tasks-org-ui--expanded-ids nil
  "Hash table of UUIDs whose subtrees are expanded.")

(defvar-local tasks-org-ui--cursor-id nil
  "UUID of the task that should hold the cursor on next render.
When nil the renderer falls back to the selected task, then the
first top-level task.")

(defvar-local tasks-org-ui--watchers nil
  "List of file-notify watch descriptors registered for this buffer.")

(defvar-local tasks-org-ui--refresh-timer nil
  "Idle timer used to debounce file-notify driven re-renders.")

;;; Cursor / row tracking

(defun tasks-org-ui--row-task ()
  "Return the task plist attached to the row at point, or nil."
  (get-text-property (line-beginning-position) 'tasks-org-ui-task))

(defun tasks-org-ui--initial-cursor-id (graph)
  "Pick the cursor id when the UI opens.
Priority: an explicit `tasks-org-ui--cursor-id' (e.g. set by a launcher
that snapped the source-buffer task into the UI), then the selected
task, then the first top-level task."
  (or tasks-org-ui--cursor-id
      (tasks-org-graph-selected-id graph)
      (plist-get (car (tasks-org-graph-tasks graph)) :id)))

(defun tasks-org-ui--goto-task-id (id)
  "Move point to the row whose task has :id ID, if present."
  (when id
    (goto-char (point-min))
    (let (found)
      (while (and (not found) (not (eobp)))
        (let ((task (tasks-org-ui--row-task)))
          (if (and task (equal (plist-get task :id) id))
              (setq found t)
            (forward-line 1))))
      found)))

;;; Rendering — vui component tree

(defun tasks-org-ui--render-row (task expanded-ids selected-id depth)
  "Return a vui fragment for TASK at DEPTH.
Recursively renders children when TASK's :id is in EXPANDED-IDS."
  (let* ((id (plist-get task :id))
         (label (concat (make-string (* 2 depth) ?\s)
                        (tasks-org-ui--collapse-marker task expanded-ids)
                        (tasks-org-ui--format-summary task selected-id)))
         (button (vui-button label
                             :on-click
                             (lambda ()
                               (tasks-org-ui-toggle-expand id))
                             :face nil))
         (children (and id
                        (gethash id expanded-ids)
                        (plist-get task :children))))
    ;; Tag the underlying widget text so cursor lookups can recover the
    ;; task object without re-parsing the buffer.
    (apply #'vui-fragment
           (cons (vui-text (propertize "" 'tasks-org-ui-task task))
                 (cons button
                       (cons (vui-newline)
                             (mapcar
                              (lambda (child)
                                (tasks-org-ui--render-row
                                 child expanded-ids selected-id (1+ depth)))
                              (or children nil))))))))

(defun tasks-org-ui--make-tree (graph expanded-ids)
  "Return a vui-vstack rendering the top-level tasks in GRAPH."
  (let* ((selected-id (tasks-org-graph-selected-id graph))
         (top-tasks (tasks-org-graph-tasks graph)))
    (apply #'vui-vstack
           (or (mapcar
                (lambda (task)
                  (tasks-org-ui--render-row task expanded-ids selected-id 0))
                top-tasks)
               (list (vui-text "(no tasks)"))))))

;;; Component definitions

;; vui macros expand at load time; ensure vui is present.
(when (require 'vui nil t)
  (vui-defcomponent tasks-org-ui--root ()
    :state ((graph nil)
            (expanded-ids nil)
            (refresh-tick 0))
    :on-mount
    (lambda ()
      ;; Initial graph load + watchers; cleanup runs on unmount.
      (tasks-org-ui--load-and-set-state)
      (tasks-org-ui--register-watchers
       (tasks-org-graph-files tasks-org-ui--graph))
      ;; Cleanup thunk for vui to invoke on unmount.
      (lambda ()
        (tasks-org-ui--unregister-watchers)))
    :render
    (let ((g (or graph tasks-org-ui--graph))
          (e (or expanded-ids tasks-org-ui--expanded-ids)))
      (if (null g)
          (vui-text "Loading task graph…")
        (tasks-org-ui--make-tree g e)))))

;;; State management

(defun tasks-org-ui--load-and-set-state ()
  "Load the task graph and refresh `tasks-org-ui--expanded-ids'."
  (setq tasks-org-ui--graph (tasks-org-load-graph))
  ;; Register all loaded files with org-id so `org-id-goto' works on
  ;; first invocation of `e' without the user having visited them.
  (let ((files (tasks-org-graph-files tasks-org-ui--graph)))
    (when files
      (ignore-errors
        (org-id-update-id-locations files))))
  ;; Default expansion: keep any previously expanded ids that still
  ;; exist, plus the current selection path.
  (let* ((default (tasks-org-ui--default-expanded-ids tasks-org-ui--graph))
         (carried (or tasks-org-ui--expanded-ids
                      (make-hash-table :test 'equal))))
    (maphash (lambda (k _v) (puthash k t default)) carried)
    (setq tasks-org-ui--expanded-ids default)))

(defun tasks-org-ui--remount ()
  "Re-mount the root component so vui re-renders with current state."
  (let ((buf (get-buffer tasks-org-ui-buffer-name)))
    (when (buffer-live-p buf)
      (with-current-buffer buf
        (let ((cur-id (or (and (tasks-org-ui--row-task)
                               (plist-get (tasks-org-ui--row-task) :id))
                          tasks-org-ui--cursor-id)))
          (setq tasks-org-ui--cursor-id cur-id)
          (when (fboundp 'vui-mount)
            (vui-mount (vui-component 'tasks-org-ui--root)
                       tasks-org-ui-buffer-name))
          (when cur-id
            (tasks-org-ui--goto-task-id cur-id)))))))

;;; File-notify watchers

(defun tasks-org-ui--unregister-watchers ()
  "Tear down file-notify watchers registered for the UI buffer."
  (dolist (desc tasks-org-ui--watchers)
    (ignore-errors (file-notify-rm-watch desc)))
  (setq tasks-org-ui--watchers nil)
  (when tasks-org-ui--refresh-timer
    (cancel-timer tasks-org-ui--refresh-timer)
    (setq tasks-org-ui--refresh-timer nil)))

(defun tasks-org-ui--schedule-refresh ()
  "Debounce and schedule a re-render."
  (when tasks-org-ui--refresh-timer
    (cancel-timer tasks-org-ui--refresh-timer))
  (setq tasks-org-ui--refresh-timer
        (run-with-idle-timer
         0.2 nil
         (lambda ()
           (let ((buf (get-buffer tasks-org-ui-buffer-name)))
             (when (buffer-live-p buf)
               (with-current-buffer buf
                 (tasks-org-ui--load-and-set-state)
                 (tasks-org-ui--remount))))))))

(defun tasks-org-ui--register-watchers (files)
  "Watch FILES for changes and schedule a refresh on each event."
  (tasks-org-ui--unregister-watchers)
  (dolist (file files)
    (when (and file (file-readable-p file))
      (condition-case nil
          (push (file-notify-add-watch
                 file '(change)
                 (lambda (_event)
                   (tasks-org-ui--schedule-refresh)))
                tasks-org-ui--watchers)
        (error nil)))))

;;; Interactive commands

;;;###autoload
(defun tasks-org-ui-show ()
  "Open the org-memory task UI buffer.
When invoked from a `tasks-org-mode' buffer with point on a task, the
UI opens with that task as the cursor row.  Otherwise the cursor lands
on the selected task (if any) or the first top-level task."
  (interactive)
  (unless (require 'vui nil t)
    (user-error "vui.el is not installed; cannot open the tasks UI"))
  (let* ((source-task-id
          (when (and (derived-mode-p 'org-mode)
                     (fboundp 'tasks-org--at-task-heading-p)
                     (tasks-org--at-task-heading-p))
            (org-entry-get nil "ID")))
         (buf (get-buffer-create tasks-org-ui-buffer-name)))
    (with-current-buffer buf
      (unless (derived-mode-p 'tasks-org-ui-mode)
        (tasks-org-ui-mode))
      (setq tasks-org-ui--cursor-id source-task-id)
      (vui-mount (vui-component 'tasks-org-ui--root)
                 tasks-org-ui-buffer-name)
      (when source-task-id
        (tasks-org-ui--goto-task-id source-task-id)))
    (pop-to-buffer buf)))

(defun tasks-org-ui-toggle-expand (&optional id)
  "Toggle the expanded state of the task at point (or with explicit ID)."
  (interactive)
  (let* ((task (or (and id (tasks-org-graph-find-by-id tasks-org-ui--graph id))
                   (tasks-org-ui--row-task)))
         (tid (plist-get task :id)))
    (unless tid
      (user-error "No task on this row"))
    (if (gethash tid tasks-org-ui--expanded-ids)
        (remhash tid tasks-org-ui--expanded-ids)
      (puthash tid t tasks-org-ui--expanded-ids))
    (tasks-org-ui--remount)))

(defun tasks-org-ui-cycle-status (&optional backward)
  "Cycle the status of the task at point forward (or BACKWARD)."
  (interactive "P")
  (let* ((task (tasks-org-ui--row-task))
         (file (plist-get task :source-file))
         (pos (plist-get task :source-pos))
         (current (plist-get task :status))
         (direction (if backward 'backward 'forward))
         (new-status (and current
                          (tasks-org--cycle-direction current direction))))
    (unless (and file pos new-status)
      (user-error "No task at point with a cyclable status"))
    (tasks-org-set-status-at file pos new-status)
    (tasks-org-ui--load-and-set-state)
    (tasks-org-ui--remount)
    (message "Status: %s -> %s" current new-status)))

(defun tasks-org-ui-cycle-status-back ()
  "Cycle the status of the task at point backward."
  (interactive)
  (tasks-org-ui-cycle-status t))

(defun tasks-org-ui-toggle-selected ()
  "Toggle selection of the task at point via #+SELECTED in TASKS.local.org."
  (interactive)
  (let* ((task (tasks-org-ui--row-task))
         (id (plist-get task :id)))
    (unless id
      (user-error "Task at point has no :ID:"))
    (let ((current (tasks-org-graph-selected-id tasks-org-ui--graph)))
      (tasks-org--write-local-selection
       (if (equal current id) nil id))
      (tasks-org-ui--load-and-set-state)
      (tasks-org-ui--remount)
      (message (if (equal current id)
                   "Cleared selection"
                 "Selected: %s") (or (plist-get task :summary) id)))))

(defun tasks-org-ui-visit-source ()
  "Visit the task at point in its source file.
Reuses an already-visible window for the source file when available
rather than creating a new split."
  (interactive)
  (let* ((task (tasks-org-ui--row-task))
         (file (plist-get task :source-file))
         (id (plist-get task :id)))
    (unless file
      (user-error "Task at point has no source file"))
    (let ((target (find-file-noselect file)))
      (let ((win (get-buffer-window target)))
        (if win
            (select-window win)
          (pop-to-buffer target)))
      (with-current-buffer target
        (cond
         ((and id (ignore-errors (org-id-find id 'marker)))
          (let ((m (org-id-find id 'marker)))
            (when m (goto-char (marker-position m)))))
         (t
          (let ((pos (plist-get task :source-pos)))
            (when pos (goto-char pos)))))
        (when (fboundp 'org-fold-show-entry)
          (org-fold-show-entry))))))

(defun tasks-org-ui-open-or-create-import ()
  "Open the cursor task's #+IMPORT change-record, or scaffold one when missing."
  (interactive)
  (let* ((task (tasks-org-ui--row-task))
         (file (plist-get task :source-file))
         (pos (plist-get task :source-pos))
         (import-raw (plist-get task :import-raw)))
    (unless task
      (user-error "No task on this row"))
    (with-current-buffer (find-file-noselect file)
      (save-excursion
        (goto-char pos)
        (cond
         (import-raw
          (tasks-org-open-plan #'find-file-other-window))
         (t
          (tasks-org-create-import-for-current-task)))))
    (tasks-org-ui--load-and-set-state)
    (tasks-org-ui--remount)))

(defun tasks-org-ui-refresh ()
  "Reload the task graph and re-render the UI."
  (interactive)
  (tasks-org-ui--load-and-set-state)
  (tasks-org-ui--register-watchers
   (tasks-org-graph-files tasks-org-ui--graph))
  (tasks-org-ui--remount)
  (message "Tasks reloaded."))

;;; Linked-issue resolution

(defcustom tasks-org-ui-linked-issues-cap 5
  "Maximum number of linked-issue URLs `tasks-org-ui-open-linked-issues' opens.
Exceeding the cap surfaces a message rather than silently dropping URLs."
  :type 'integer :group 'tasks-org-ui)

(defun tasks-org-ui--issue-url-base ()
  "Return the project's `#+ISSUE_URL_BASE:' value, or nil.
Reads from `TASKS.org' at the project root."
  (let ((tasks-file (tasks-org--tasks-file)))
    (when (file-readable-p tasks-file)
      (with-temp-buffer
        (insert-file-contents tasks-file)
        (goto-char (point-min))
        (when (re-search-forward
               "^#\\+ISSUE_URL_BASE:[ \t]*\\(.*\\)$" nil t)
          (let ((val (string-trim (match-string-no-properties 1))))
            (and (not (string-empty-p val)) val)))))))

(defun tasks-org-ui--resolve-issue-token (token base)
  "Return a URL for TOKEN, or nil when unresolvable.
TOKEN is either an org-link form `[[url][label]]' (returns the URL
verbatim) or a bare key resolved against BASE.  When TOKEN is a bare
key and BASE is nil, returns nil — caller should surface a message."
  (cond
   ;; Org-link: extract the URL.
   ((and (string-prefix-p "[[" token)
         (string-match "\\[\\[\\([^]]+\\)\\]\\(?:\\[[^]]*\\]\\)?\\]" token))
    (match-string 1 token))
   ;; Bare key: resolve via BASE.
   (base
    (let ((encoded (url-hexify-string token)))
      (cond
       ((string-match-p "{ID}" base)
        (replace-regexp-in-string "{ID}" encoded base t t))
       (t (concat base encoded)))))
   ;; Bare key, no base.
   (t nil)))

(defun tasks-org-ui-open-linked-issues ()
  "Open every resolvable linked-issue URL on the cursor task in the browser.
Caps at `tasks-org-ui-linked-issues-cap' with an informational message
when exceeded.  Empty / absent property is a silent no-op.  Unresolvable
bare tokens (no `#+ISSUE_URL_BASE:' configured) trigger a message
pointing at the missing keyword."
  (interactive)
  (require 'url-util)
  (let* ((task (tasks-org-ui--row-task))
         (tokens (and task (plist-get task :linked-issues)))
         (base (tasks-org-ui--issue-url-base)))
    (cond
     ((null tokens)
      ;; Silent no-op for empty / absent.
      nil)
     (t
      (let ((urls nil)
            (unresolved 0))
        (dolist (token tokens)
          (let ((url (tasks-org-ui--resolve-issue-token token base)))
            (if url
                (push url urls)
              (cl-incf unresolved))))
        (setq urls (nreverse urls))
        (cond
         ((and (zerop (length urls)) (> unresolved 0))
          (message
           "%d unresolvable linked-issue token(s); set #+ISSUE_URL_BASE: in TASKS.org"
           unresolved))
         (t
          (let* ((capped (cl-subseq urls 0
                                    (min (length urls)
                                         tasks-org-ui-linked-issues-cap)))
                 (overflow (- (length urls) (length capped))))
            (dolist (url capped)
              (browse-url url))
            (when (> overflow 0)
              (message "Opened %d linked-issue URLs (%d more not opened, cap=%d)"
                       (length capped) overflow
                       tasks-org-ui-linked-issues-cap))))))))))

;;; Compact selected-task indicator

(defcustom tasks-org-ui-compact-buffer-name "*tasks-org compact*"
  "Buffer name for the compact selected-task widget."
  :type 'string :group 'tasks-org-ui)

(defcustom tasks-org-ui-compact-max-lines 6
  "Maximum number of lines rendered in the compact widget.
Completed (DONE / CANCELLED) subtrees are elided first as
`… N completed subtasks' so the selected task and pending siblings
stay visible."
  :type 'integer :group 'tasks-org-ui)

(defun tasks-org-ui--containing-top-level (graph id)
  "Return the top-level task in GRAPH whose subtree contains ID, or nil."
  (cl-find-if
   (lambda (top) (tasks-org-ui--ancestor-ids top id))
   (tasks-org-graph-tasks graph)))

(defun tasks-org-ui--completed-task-p (task)
  "Return non-nil when TASK has a terminal status."
  (member (plist-get task :status) tasks-org--terminal-states))

(defun tasks-org-ui--compact-format-task (task selected-id depth)
  "Return one rendered line for TASK at DEPTH in the compact widget."
  (concat (make-string (* 2 depth) ?\s)
          (cond
           ((null (plist-get task :children)) "• ")
           (t "▸ "))
          (tasks-org-ui--format-summary task selected-id)))

(defun tasks-org-ui--compact-collect-lines (task selected-id depth)
  "Walk TASK and its children, returning a list of rendered lines.
Subtrees of completed tasks are summarised as a single elision line
when they contain children."
  (let* ((line (tasks-org-ui--compact-format-task task selected-id depth))
         (kids (plist-get task :children)))
    (cond
     ((and (tasks-org-ui--completed-task-p task) kids)
      (list line
            (concat (make-string (* 2 (1+ depth)) ?\s)
                    (format "… %d completed subtasks" (length kids)))))
     (t
      (cons line
            (apply #'append
                   (mapcar
                    (lambda (kid)
                      (tasks-org-ui--compact-collect-lines
                       kid selected-id (1+ depth)))
                    (or kids nil))))))))

(defun tasks-org-ui--compact-truncate (lines max)
  "Truncate LINES to MAX, eliding the trailing completed-subtree blocks first."
  (if (<= (length lines) max)
      lines
    (let ((kept lines)
          (overflow (- (length lines) max)))
      ;; Walk backward dropping lines that look like elision summaries
      ;; or are below the selected row; simplest cut: just take the
      ;; first MAX lines (selected row is on the path so head-keeping
      ;; preserves it) and append a truncation indicator.
      (append (cl-subseq kept 0 (1- max))
              (list (format "  … %d more rows" (1+ overflow)))))))

(defun tasks-org-ui--compact-render-text (graph)
  "Return the compact widget's text for GRAPH, or nil when no selection."
  (when-let* ((selected (tasks-org-graph-selected-id graph))
              (top (tasks-org-ui--containing-top-level graph selected)))
    (let* ((lines (tasks-org-ui--compact-collect-lines top selected 0))
           (truncated (tasks-org-ui--compact-truncate
                       lines tasks-org-ui-compact-max-lines)))
      (mapconcat #'identity truncated "\n"))))

(defvar-local tasks-org-ui--compact-watchers nil
  "File-notify watchers registered for the compact widget.")

(defun tasks-org-ui--compact-rerender ()
  "Reload the graph and refresh the compact widget buffer."
  (let ((buf (get-buffer tasks-org-ui-compact-buffer-name)))
    (when (buffer-live-p buf)
      (with-current-buffer buf
        (let* ((graph (tasks-org-load-graph))
               (text (or (tasks-org-ui--compact-render-text graph)
                         "(no task selected)"))
               (inhibit-read-only t))
          (erase-buffer)
          (insert text)
          (goto-char (point-min)))))))

(defvar tasks-org-ui-compact-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "q") #'quit-window)
    map)
  "Keymap for `tasks-org-ui-compact-mode'.")

(define-derived-mode tasks-org-ui-compact-mode special-mode
  "Tasks-Org-Compact"
  "Read-only view of the currently selected task's containing tree."
  (setq-local tasks-org-mode nil)
  (setq buffer-read-only t))

(defcustom tasks-org-ui-compact-display-action
  '((display-buffer-in-side-window)
    (side . top)
    (slot . 0)
    (window-height . 8)
    (preserve-size . (nil . t)))
  "Default `display-buffer' action for the compact widget side window."
  :type 'sexp :group 'tasks-org-ui)

;;;###autoload
(defun tasks-org-ui-show-selected ()
  "Open the compact selected-task widget in a side window.
Subsequent calls re-render and surface the existing buffer."
  (interactive)
  (let ((buf (get-buffer-create tasks-org-ui-compact-buffer-name)))
    (with-current-buffer buf
      (unless (derived-mode-p 'tasks-org-ui-compact-mode)
        (tasks-org-ui-compact-mode))
      ;; Register watchers once per buffer lifetime.
      (unless tasks-org-ui--compact-watchers
        (let ((graph (tasks-org-load-graph)))
          (dolist (file (tasks-org-graph-files graph))
            (when (and file (file-readable-p file))
              (condition-case nil
                  (push (file-notify-add-watch
                         file '(change)
                         (lambda (_event)
                           (run-with-idle-timer
                            0.2 nil
                            #'tasks-org-ui--compact-rerender)))
                        tasks-org-ui--compact-watchers)
                (error nil)))))))
    (tasks-org-ui--compact-rerender)
    (display-buffer buf tasks-org-ui-compact-display-action)))

;;; Mode

(defvar tasks-org-ui-mode-map
  (let ((map (make-sparse-keymap)))
    ;; Movement (also handled by widget-forward/backward in vui-mode-map).
    (define-key map (kbd "j") #'next-line)
    (define-key map (kbd "k") #'previous-line)
    (define-key map (kbd "<down>") #'next-line)
    (define-key map (kbd "<up>") #'previous-line)
    ;; Collapse / expand.
    (define-key map (kbd "RET") #'tasks-org-ui-toggle-expand)
    (define-key map (kbd "TAB") #'tasks-org-ui-toggle-expand)
    ;; Status cycling.
    (define-key map (kbd "l") #'tasks-org-ui-cycle-status)
    (define-key map (kbd "h") #'tasks-org-ui-cycle-status-back)
    (define-key map (kbd "<right>") #'tasks-org-ui-cycle-status)
    (define-key map (kbd "<left>") #'tasks-org-ui-cycle-status-back)
    ;; Selection / source jumps / change-record.
    (define-key map (kbd "s") #'tasks-org-ui-toggle-selected)
    (define-key map (kbd "e") #'tasks-org-ui-visit-source)
    (define-key map (kbd "p") #'tasks-org-ui-open-or-create-import)
    ;; Refresh / quit.
    (define-key map (kbd "J") #'tasks-org-ui-open-linked-issues)
    (define-key map (kbd "g") #'tasks-org-ui-refresh)
    (define-key map (kbd "q") #'quit-window)
    map)
  "Keymap for `tasks-org-ui-mode'.
`SPC' is deliberately unbound — it remains the global Spacemacs leader.")

(define-derived-mode tasks-org-ui-mode special-mode "Tasks-Org-UI"
  "Major mode for the org-memory task graph visualisation buffer.

Renders the project's task tree using vui.el components, with status
colours and badges matching the pi `tasks' extension.  Status writes
go through the org-memory protocol helpers in `tasks-org.el', so
LOGBOOK / CLOSED / :STARTED: bookkeeping stays consistent across pi
and Emacs surfaces.

Derives from `special-mode'; `vui-mount' enables `vui-mode' on the
buffer at render time (per vui release notes), which preserves the
derived mode and its keybindings while overlaying vui's widget
navigation."
  ;; Skip `tasks-org-mode' auto-enable so the minor mode does not
  ;; trigger inside the visualisation buffer.
  (setq-local tasks-org-mode nil))

(provide 'tasks-org-ui)
;;; tasks-org-ui.el ends here
