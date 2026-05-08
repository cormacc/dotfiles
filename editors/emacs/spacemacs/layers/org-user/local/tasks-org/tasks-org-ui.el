;;; tasks-org-ui.el --- Treemacs task hierarchy over org-memory protocol -*- lexical-binding: t; no-byte-compile: t; -*-

;; Author: Cormac Cannon
;; URL: https://github.com/cormacc/dotfiles
;; Keywords: org, tasks, productivity
;; Package-Requires: ((emacs "29.1") (treemacs "3.1") (org "9.4"))

;;; Commentary:

;; A Treemacs/treelib-rendered visualisation of the org-memory task graph for
;; the current project.  Mirrors the pi `tasks' extension's expanded UI for
;; navigate / expand / select / cycle workflows, while delegating durable
;; mutations to `tasks-org.el's protocol helpers and the graph reader in
;; `tasks-org-graph.el'.
;;
;; Architecture
;; ------------
;;   * The expanded hierarchy uses Treemacs' treelib extension API in a
;;     dedicated `*tasks-org*' buffer.  It does not embed task nodes in the
;;     normal Treemacs project sidebar.
;;   * `tasks-org-ui-show' creates the buffer, renders top-level org-memory
;;     tasks as a variadic treelib root, and registers `file-notify' watchers
;;     on every graph-contributing file so external edits trigger a re-render
;;     that preserves the cursor task by UUID.
;;   * Status cycling delegates to `tasks-org-set-status-at' (so LOGBOOK /
;;     CLOSED / :STARTED: stay protocol-correct).  Selection uses the
;;     non-destructive `tasks-org--write-local-selection'.  Plan open /
;;     scaffold delegate to `tasks-org-open-plan' /
;;     `tasks-org-create-import-for-current-task'.
;;
;; Byte-compilation is intentionally disabled because Treemacs' extension
;; macros are only available when the Spacemacs treemacs layer/package is on
;; the load-path.  Batch tests still load this file without Treemacs present;
;; the treelib-specific node types are defined lazily at runtime.

;;; Code:

(require 'cl-lib)
(require 'filenotify)
(require 'org)
(require 'org-id)
(require 'subr-x)

(require 'tasks-org)
(require 'tasks-org-graph)

(declare-function treemacs-mode "treemacs-mode")
(declare-function treemacs--disable-fringe-indicator "treemacs-core-utils")
(declare-function treemacs--evade-image "treemacs-core-utils")
(declare-function treemacs--render-extension "treemacs-treelib" (ext &optional expand-depth))
(declare-function treemacs-button-get "treemacs-core-utils" (button prop))
(declare-function treemacs-button-start "treemacs-core-utils" (button))
(declare-function treemacs-current-button "treemacs-core-utils")
(declare-function treemacs-expand-extension-node "treemacs-treelib" (&optional arg))
(declare-function treemacs-find-node "treemacs-dom" (path))
(declare-function treemacs-is-node-collapsed? "treemacs-core-utils" (btn))
(declare-function treemacs-node-at-point "treemacs-core-utils")
(defvar treemacs-fringe-indicator-mode)
(defvar treemacs-mode-map)
(defvar treemacs-space-between-root-nodes)
(defvar treemacs--in-this-buffer)

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
  "Face for the local-draft marker (⊠) and tinted summary."
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
  "Return the face symbol for priority LETTER (A..D)."
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
  "Return a propertized STATUS token for a row."
  (when status
    (propertize (concat status " ") 'face (tasks-org-ui--status-face status))))

(defun tasks-org-ui--format-priority (letter)
  "Return a propertized priority cookie for LETTER."
  (when letter
    (propertize (format "[#%s] " letter) 'face (tasks-org-ui--priority-face letter))))

(defun tasks-org-ui--format-tags (tags)
  "Return a propertized org tag suffix for TAGS."
  (when tags
    (propertize (concat " :" (mapconcat #'identity tags ":") ":")
                'face 'tasks-org-ui-tag-face)))

(defun tasks-org-ui--format-badges (linked-issues)
  "Return propertized linked-issue badges for LINKED-ISSUES."
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
  "Return the change-record indicator for TASK when it has #+IMPORT."
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

(defun tasks-org-ui--task-has-children-p (task)
  "Return non-nil when TASK has child tasks."
  (and (plist-get task :children) t))

(defun tasks-org-ui--treemacs-key (task)
  "Return the semi-unique Treemacs key for TASK."
  (or (plist-get task :id)
      (format "%s:%s"
              (or (plist-get task :source-file) "unknown")
              (or (plist-get task :source-pos) 0))))

(defun tasks-org-ui--treemacs-label (task)
  "Return the Treemacs row label for TASK."
  (tasks-org-ui--format-summary
   task (and tasks-org-ui--graph
             (tasks-org-graph-selected-id tasks-org-ui--graph))))

(defun tasks-org-ui--treemacs-closed-icon (task)
  "Return the Treemacs closed/leaf icon for TASK."
  (if (tasks-org-ui--task-has-children-p task) "▸ " "• "))

(defun tasks-org-ui--treemacs-open-icon (_task)
  "Return the Treemacs open icon."
  "▾ ")

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

;;; Treemacs extension node types

(defconst tasks-org-ui--treemacs-root-key "tasks-org-root"
  "Hidden root key for the variadic Treemacs task extension.")

(defvar tasks-org-ui--treemacs-types-defined nil
  "Non-nil after the treelib node types have been defined.")

(defun tasks-org-ui--ensure-treemacs ()
  "Ensure Treemacs treelib is available and task node types are defined."
  (unless (require 'treemacs-treelib nil t)
    (user-error "Treemacs treelib is not installed; cannot open the tasks UI"))
  (unless tasks-org-ui--treemacs-types-defined
    ;; Use `eval' so this file remains loadable in batch tests where Treemacs is
    ;; not present on the load-path.  The macros are available after the require
    ;; above succeeds.
    (eval
     '(progn
        (treemacs-define-expandable-node-type tasks-org-task
          :closed-icon (tasks-org-ui--treemacs-closed-icon item)
          :open-icon (tasks-org-ui--treemacs-open-icon item)
          :label (tasks-org-ui--treemacs-label item)
          :key (tasks-org-ui--treemacs-key item)
          :children (plist-get item :children)
          :child-type 'tasks-org-task
          :more-properties (list :tasks-org-ui-task item
                                 :tasks-org-ui-task-id (plist-get item :id)
                                 :leaf (not (tasks-org-ui--task-has-children-p item)))
          :ret-action #'tasks-org-ui-toggle-expand
          :double-click-action #'tasks-org-ui-toggle-expand)
        (treemacs-define-variadic-entry-node-type tasks-org-root
          :key tasks-org-ui--treemacs-root-key
          :children (tasks-org-graph-tasks tasks-org-ui--graph)
          :child-type 'tasks-org-task)))
    (setq tasks-org-ui--treemacs-types-defined t)))

;;; Cursor / row tracking

(defun tasks-org-ui--treemacs-button-at-point ()
  "Return the Treemacs button on the current line, or nil."
  (when (fboundp 'treemacs-node-at-point)
    (ignore-errors (treemacs-node-at-point))))

(defun tasks-org-ui--row-task ()
  "Return the task plist attached to the row at point, or nil."
  (or (when-let* ((btn (tasks-org-ui--treemacs-button-at-point)))
        (or (ignore-errors (treemacs-button-get btn :tasks-org-ui-task))
            (ignore-errors (treemacs-button-get btn :item))))
      (get-text-property (line-beginning-position) 'tasks-org-ui-task)))

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

(defun tasks-org-ui--task-paths (tasks &optional prefix)
  "Return an alist mapping task ids/keys in TASKS to Treemacs paths.
PREFIX is the parent path, defaulting to the hidden root path."
  (let ((base (or prefix (list tasks-org-ui--treemacs-root-key)))
        paths)
    (dolist (task tasks)
      (let* ((key (tasks-org-ui--treemacs-key task))
             (path (append base (list key)))
             (id (plist-get task :id)))
        (push (cons (or id key) path) paths)
        (setq paths
              (append (nreverse (tasks-org-ui--task-paths
                                 (plist-get task :children) path))
                      paths))))
    (nreverse paths)))

(defun tasks-org-ui--apply-treemacs-expansion ()
  "Expand Treemacs nodes according to `tasks-org-ui--expanded-ids'."
  (when (and tasks-org-ui--graph tasks-org-ui--expanded-ids
             (fboundp 'treemacs-find-node))
    (dolist (cell (tasks-org-ui--task-paths
                   (tasks-org-graph-tasks tasks-org-ui--graph)))
      (let ((id (car cell))
            (path (cdr cell)))
        (when (gethash id tasks-org-ui--expanded-ids)
          (when-let* ((btn (ignore-errors (treemacs-find-node path))))
            (when (ignore-errors (treemacs-is-node-collapsed? btn))
              (goto-char (treemacs-button-start btn))
              (ignore-errors (treemacs-expand-extension-node)))))))))

;;; Rendering — Treemacs/treelib

(defun tasks-org-ui--load-and-set-state ()
  "Load the task graph and refresh `tasks-org-ui--expanded-ids'."
  (setq tasks-org-ui--graph (tasks-org-load-graph))
  ;; Register all loaded files with org-id so `org-id-goto' works on first
  ;; invocation of `e' without the user having visited them.
  (let ((files (tasks-org-graph-files tasks-org-ui--graph)))
    (when files
      (ignore-errors
        (org-id-update-id-locations files))))
  ;; Default expansion: keep any previously expanded ids that still exist, plus
  ;; the current selection path.
  (let* ((default (tasks-org-ui--default-expanded-ids tasks-org-ui--graph))
         (carried (or tasks-org-ui--expanded-ids
                      (make-hash-table :test 'equal))))
    (maphash (lambda (k _v) (puthash k t default)) carried)
    (setq tasks-org-ui--expanded-ids default)))

(defun tasks-org-ui--render-treemacs ()
  "Render `tasks-org-ui--graph' into the current buffer using treelib."
  (tasks-org-ui--ensure-treemacs)
  (let ((graph tasks-org-ui--graph)
        (expanded-ids tasks-org-ui--expanded-ids)
        (cursor-id (tasks-org-ui--initial-cursor-id tasks-org-ui--graph)))
    (treemacs--disable-fringe-indicator)
    (let ((treemacs-fringe-indicator-mode nil)
          (treemacs--in-this-buffer t)
          (inhibit-read-only t))
      (erase-buffer)
      (treemacs-mode))
    (setq-local treemacs-space-between-root-nodes nil)
    (setq-local treemacs--in-this-buffer :extension)
    (setq-local tasks-org-ui--graph graph)
    (setq-local tasks-org-ui--expanded-ids expanded-ids)
    (setq-local tasks-org-ui--cursor-id cursor-id)
    (setq-local tasks-org-mode nil)
    (tasks-org-ui-mode 1)
    (let ((inhibit-read-only t))
      (erase-buffer)
      (if (tasks-org-graph-tasks tasks-org-ui--graph)
          (progn
            (treemacs--render-extension 'tasks-org-root 0)
            (tasks-org-ui--apply-treemacs-expansion))
        (insert "(no tasks)\n")))
    (goto-char (point-min))
    (treemacs--evade-image)
    (or (tasks-org-ui--goto-task-id cursor-id)
        (tasks-org-ui--goto-task-id (tasks-org-ui--initial-cursor-id tasks-org-ui--graph)))))

(defun tasks-org-ui--rerender (&optional reload)
  "Re-render the UI, optionally RELOADing the graph first."
  (let ((cur-id (or (and (tasks-org-ui--row-task)
                         (plist-get (tasks-org-ui--row-task) :id))
                    tasks-org-ui--cursor-id)))
    (setq tasks-org-ui--cursor-id cur-id)
    (when reload
      (tasks-org-ui--load-and-set-state))
    (let ((files (and tasks-org-ui--graph
                      (tasks-org-graph-files tasks-org-ui--graph))))
      (tasks-org-ui--unregister-watchers)
      (tasks-org-ui--render-treemacs)
      (tasks-org-ui--register-watchers files)
      (when cur-id
        (tasks-org-ui--goto-task-id cur-id)))))

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
                 (tasks-org-ui--rerender t))))))))

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
When invoked from a `tasks-org-mode' buffer with point on a task, the UI opens
with that task as the cursor row.  Otherwise the cursor lands on the selected
task (if any) or the first top-level task."
  (interactive)
  (tasks-org-ui--ensure-treemacs)
  (let* ((source-task-id
          (when (and (derived-mode-p 'org-mode)
                     (fboundp 'tasks-org--at-task-heading-p)
                     (tasks-org--at-task-heading-p))
            (org-entry-get nil "ID")))
         (buf (get-buffer-create tasks-org-ui-buffer-name)))
    (with-current-buffer buf
      (setq tasks-org-ui--cursor-id source-task-id)
      (tasks-org-ui--load-and-set-state)
      (setq tasks-org-ui--cursor-id
            (or source-task-id (tasks-org-ui--initial-cursor-id tasks-org-ui--graph)))
      (tasks-org-ui--rerender nil))
    (pop-to-buffer buf)))

(defun tasks-org-ui-toggle-expand (&optional _arg)
  "Toggle the expanded state of the task at point."
  (interactive)
  (let* ((task (tasks-org-ui--row-task))
         (tid (plist-get task :id)))
    (unless tid
      (user-error "No task on this row"))
    (unless (tasks-org-ui--task-has-children-p task)
      (message "Task has no subtasks"))
    (if (gethash tid tasks-org-ui--expanded-ids)
        (remhash tid tasks-org-ui--expanded-ids)
      (puthash tid t tasks-org-ui--expanded-ids))
    (tasks-org-ui--rerender nil)))

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
    (tasks-org-ui--rerender t)
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
      (tasks-org-ui--rerender t)
      (message (if (equal current id)
                   "Cleared selection"
                 "Selected: %s") (or (plist-get task :summary) id)))))

(defun tasks-org-ui-visit-source ()
  "Visit the task at point in its source file.
Reuses an already-visible window for the source file when available rather than
creating a new split."
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
    (tasks-org-ui--rerender t)))

(defun tasks-org-ui--invoke-at-source (command)
  "Run COMMAND with point on the cursor task's source heading.
Resolves the cursor task's source file and position, visits the file in a
`find-file-noselect' buffer, navigates to the heading, and calls COMMAND there.
UI is re-rendered afterwards.  Used by mutation wrappers (publish, unpublish)
that delegate to `tasks-org' helpers operating at point."
  (let* ((task (tasks-org-ui--row-task))
         (file (plist-get task :source-file))
         (pos (plist-get task :source-pos)))
    (unless task
      (user-error "No task on this row"))
    (unless (and file pos)
      (user-error "Task at point has no source file/position"))
    (with-current-buffer (find-file-noselect file)
      (save-excursion
        (goto-char pos)
        (call-interactively command)))
    (tasks-org-ui--rerender t)))

(defun tasks-org-ui-publish-task ()
  "Publish the cursor task's subtree to TASKS.org.
Delegates to `tasks-org-publish-task' at the source heading; prompts for
confirmation, moves the subtree from its current file (typically
TASKS.local.org) into TASKS.org as a new top-level entry, and re-renders the
UI.  The cursor follows the task by ID across the move."
  (interactive)
  (tasks-org-ui--invoke-at-source #'tasks-org-publish-task))

(defun tasks-org-ui-unpublish-task ()
  "Unpublish the cursor top-level task from TASKS.org to TASKS.local.org.
Delegates to `tasks-org-unpublish-task' at the source heading; refuses for
non-top-level tasks, prompts for confirmation, and re-renders the UI."
  (interactive)
  (tasks-org-ui--invoke-at-source #'tasks-org-unpublish-task))

(defun tasks-org-ui-archive-task ()
  "Archive the cursor top-level task to `TASKS.archive.org'.
Delegates to `tasks-org-archive-task' at the source heading; refuses unless
the task is a level-2 DONE/CANCELLED entry in `TASKS.org' (publish local
tasks first).  Prompts for confirmation, transfers the subtree as-is
(promoted to level 1, =#+IMPORT:= preserved, =:ARCHIVED:= stamped), re-sorts
the archive by =CLOSED:= ascending, clears `#+SELECTED:' when archiving the
selected task, and re-renders the UI."
  (interactive)
  (tasks-org-ui--invoke-at-source #'tasks-org-archive-task))

(defun tasks-org-ui-doctor ()
  "Run org-memory health checks against the loaded task graph.
Thin wrapper around `tasks-org-doctor-show': opens a transient
`*tasks-org-doctor*' buffer with one line per finding (severity, code,
message, source location) and RET-to-visit on each line.  Mirrors
the pi tasks extension's =/tasks doctor= command."
  (interactive)
  (require 'tasks-org-doctor)
  (tasks-org-doctor-show))

(defun tasks-org-ui--read-task-summary (prompt)
  "Read a non-empty heading summary using PROMPT, or signal `user-error'."
  (let* ((raw (read-string prompt))
         (trimmed (and raw (string-trim raw))))
    (when (or (null trimmed) (string-empty-p trimmed))
      (user-error "Cancelled (empty summary)"))
    trimmed))

(defun tasks-org-ui--insert-new-task (file pos level summary)
  "Insert a new TODO task at LEVEL after the heading at POS in FILE.
SUMMARY is the heading text.  The task is appended at the end of the parent
heading's subtree (`org-end-of-subtree') with a leading blank line so siblings
stay readable.  Returns the new task's :ID:.  Buffer is saved."
  (let* ((id (org-id-new))
         (timestamp (tasks-org--org-timestamp))
         (block (tasks-org--build-task-block level summary id timestamp)))
    (with-current-buffer (find-file-noselect file)
      (save-excursion
        (goto-char pos)
        (org-back-to-heading t)
        (org-end-of-subtree t t)
        (unless (bolp) (insert "\n"))
        (unless (looking-back "\n\n" 2) (insert "\n"))
        (insert block))
      (save-buffer))
    id))

(defun tasks-org-ui-create-task ()
  "Create a new TODO task as a sibling of the cursor task.
The new task is inserted at the same outline level as the cursor task,
immediately after the cursor task's subtree, in the same source file (which is
`TASKS.local.org' for local-origin tasks and `TASKS.org' or the change-record
plan file otherwise).  Prompts for the heading summary; an empty summary
cancels.  The new task becomes the cursor row after re-render."
  (interactive)
  (let* ((task (tasks-org-ui--row-task))
         (file (plist-get task :source-file))
         (pos (plist-get task :source-pos))
         (level (plist-get task :level)))
    (unless task
      (user-error "No task on this row"))
    (unless (and file pos level)
      (user-error "Task at point has no source file/position/level"))
    (let* ((summary (tasks-org-ui--read-task-summary "New sibling task: "))
           (new-id (tasks-org-ui--insert-new-task file pos level summary)))
      (setq-local tasks-org-ui--cursor-id new-id)
      (tasks-org-ui--rerender t)
      (message "Created sibling task: %s" summary))))

(defun tasks-org-ui-create-subtask ()
  "Create a new TODO task as a child of the cursor task.
The new task is inserted one level deeper than the cursor task at the end of
its subtree, in the same source file.  Prompts for the heading summary; an
empty summary cancels.  The new subtask becomes the cursor row after
re-render."
  (interactive)
  (let* ((task (tasks-org-ui--row-task))
         (file (plist-get task :source-file))
         (pos (plist-get task :source-pos))
         (level (plist-get task :level)))
    (unless task
      (user-error "No task on this row"))
    (unless (and file pos level)
      (user-error "Task at point has no source file/position/level"))
    (let* ((summary (tasks-org-ui--read-task-summary "New subtask: "))
           (new-id (tasks-org-ui--insert-new-task file pos (1+ level) summary)))
      (setq-local tasks-org-ui--cursor-id new-id)
      (tasks-org-ui--rerender t)
      (message "Created subtask: %s" summary))))

(defun tasks-org-ui-refresh ()
  "Reload the task graph and re-render the UI."
  (interactive)
  (tasks-org-ui--rerender t)
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
TOKEN is either an org-link form `[[url][label]]' (returns the URL verbatim) or
a bare key resolved against BASE.  When TOKEN is a bare key and BASE is nil,
returns nil — caller should surface a message."
  (cond
   ;; Org-link: extract the URL.
   ((and (string-prefix-p "[[" token)
         (string-match "\\[\\[\\([^]]+\\)\\]\\(?:\\[[^]]*\\]\\)?\\]" token))
    (match-string 1 token))
   ;; Bare key: resolve via BASE.
   (base
    (require 'url-util)
    (let ((encoded (url-hexify-string token)))
      (cond
       ((string-match-p "{ID}" base)
        (replace-regexp-in-string "{ID}" encoded base t t))
       (t (concat base encoded)))))
   ;; Bare key, no base.
   (t nil)))

(defun tasks-org-ui-open-linked-issues ()
  "Open every resolvable linked-issue URL on the cursor task in the browser.
Caps at `tasks-org-ui-linked-issues-cap' with an informational message when
exceeded.  Empty / absent property is a silent no-op.  Unresolvable bare tokens
(no `#+ISSUE_URL_BASE:' configured) trigger a message pointing at the missing
keyword."
  (interactive)
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
Subtrees of completed tasks are summarised as a single elision line when they
contain children."
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
    (let ((overflow (- (length lines) max)))
      ;; Walk backward dropping lines that look like elision summaries or are
      ;; below the selected row; simplest cut: just take the first MAX lines
      ;; (selected row is on the path so head-keeping preserves it) and append a
      ;; truncation indicator.
      (append (cl-subseq lines 0 (1- max))
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

;;; Details pane
;;
;; The details pane is a read-only `org-mode' indirect buffer onto the cursor
;; task's source file, narrowed to the task's subtree.  Indirect buffers
;; share text with their base buffer (`find-file-noselect' on the source
;; file), so the pane stays in sync with file-watch reloads automatically and
;; gets native org fontification, folding, and link handling for free.  When
;; the cursor moves to a task in a *different* source file, the indirect
;; buffer is rebuilt against the new base; same-file moves only widen +
;; re-narrow.

(defcustom tasks-org-ui-details-buffer-name "*tasks-org details*"
  "Buffer name for the cursor task's details pane (an indirect org buffer)."
  :type 'string :group 'tasks-org-ui)

(defcustom tasks-org-ui-details-display-action
  '((display-buffer-in-side-window)
    (side . left)
    (slot . 1)
    (window-height . 0.4)
    (preserve-size . (nil . t)))
  "Default `display-buffer' action for the details pane.
Defaults to a side window in the same column (=left=) as the Treemacs tree,
occupying 40%% of the column's height in slot 1 (below the tree at slot 0).
Customise to relocate (e.g. =right= side, fixed line height)."
  :type 'sexp :group 'tasks-org-ui)

(defcustom tasks-org-ui-details-auto-update t
  "When non-nil, the details pane refreshes as the cursor row changes.
Driven by a `post-command-hook' installed in the tasks UI buffer; only fires
when the cursor task's :ID: actually changed."
  :type 'boolean :group 'tasks-org-ui)

(defvar-local tasks-org-ui--details-last-rendered-id nil
  "Buffer-local cache of the last :ID: rendered in the details pane.
Used by the auto-update hook to skip no-op refreshes.")

(defun tasks-org-ui--details-make-placeholder ()
  "Replace any existing details buffer with a plain placeholder buffer.
Used when there is no task at point; the previous buffer (which may be an
indirect buffer onto a source file) is killed so the next valid task gets
a fresh indirect buffer."
  (let ((existing (get-buffer tasks-org-ui-details-buffer-name)))
    (when existing (kill-buffer existing)))
  (let ((buf (get-buffer-create tasks-org-ui-details-buffer-name)))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert "(no task at point)\n"))
      (special-mode)
      (setq-local tasks-org-ui--details-last-rendered-id nil))
    buf))

(defun tasks-org-ui--details-prepare-buffer (task)
  "Return the details buffer narrowed to TASK's subtree.
The buffer is an indirect buffer of TASK's source file in `org-mode';
same-file cursor moves widen + re-narrow the existing indirect buffer,
different-file moves rebuild it.  Returns nil only when TASK is non-nil
but its source file is unreadable."
  (let* ((file (plist-get task :source-file))
         (pos (plist-get task :source-pos)))
    (cond
     ((or (null file) (null pos) (not (file-readable-p file)))
      (tasks-org-ui--details-make-placeholder))
     (t
      (let* ((base (find-file-noselect file))
             (existing (get-buffer tasks-org-ui-details-buffer-name))
             (recreate (or (null existing)
                           (not (buffer-live-p existing))
                           (not (eq (buffer-base-buffer existing) base))))
             (buf (cond
                   (recreate
                    (when existing (kill-buffer existing))
                    (make-indirect-buffer
                     base tasks-org-ui-details-buffer-name t))
                   (t existing))))
        (with-current-buffer buf
          ;; Indirect buffers inherit the base's major mode (`org-mode' for
          ;; .org files); make sure narrowing changes are unrestricted before
          ;; we re-narrow on each task change.
          (widen)
          (goto-char (min pos (point-max)))
          (when (fboundp 'org-back-to-heading)
            (ignore-errors (org-back-to-heading t)))
          (let ((start (point))
                (end (save-excursion (org-end-of-subtree t t) (point))))
            (narrow-to-region start end)
            (goto-char start))
          (when (fboundp 'org-fold-show-subtree)
            (ignore-errors (org-fold-show-subtree)))
          (setq buffer-read-only t)
          (setq-local tasks-org-ui--details-last-rendered-id
                      (plist-get task :id)))
        buf)))))

(defun tasks-org-ui--details-rerender-for (task)
  "Refresh / rebuild the details buffer to show TASK (or a placeholder)."
  (tasks-org-ui--details-prepare-buffer task))

(defun tasks-org-ui--details-track-cursor ()
  "Post-command hook: refresh details pane if the cursor row task changed.
No-op when the details buffer is not displayed in any window or when the
cursor task's :ID: has not changed since the last render."
  (when tasks-org-ui-details-auto-update
    (let ((buf (get-buffer tasks-org-ui-details-buffer-name)))
      (when (and (buffer-live-p buf) (get-buffer-window buf))
        (let* ((task (ignore-errors (tasks-org-ui--row-task)))
               (id (and task (plist-get task :id)))
               (last (with-current-buffer buf
                       tasks-org-ui--details-last-rendered-id)))
          (unless (equal id last)
            (tasks-org-ui--details-rerender-for task)))))))

;;;###autoload
(defun tasks-org-ui-show-details ()
  "Open the cursor task's details pane.
The pane is a read-only `org-mode' indirect buffer narrowed to the cursor
task's subtree, displayed in a side window beneath the Treemacs tree by
default.  Subsequent calls re-narrow to the current row; auto-tracking is
controlled by `tasks-org-ui-details-auto-update'."
  (interactive)
  (let* ((task (ignore-errors (tasks-org-ui--row-task)))
         (buf (tasks-org-ui--details-rerender-for task)))
    (display-buffer buf tasks-org-ui-details-display-action)))

;;; Mode

(defvar tasks-org-ui-mode-map
  (let ((map (make-sparse-keymap)))
    ;; Movement.  Treemacs also binds many of these; this minor-mode map keeps
    ;; the pi tasks-extension muscle memory active in the dedicated buffer.
    (define-key map (kbd "j") #'next-line)
    (define-key map (kbd "k") #'previous-line)
    (define-key map (kbd "<down>") #'next-line)
    (define-key map (kbd "<up>") #'previous-line)
    ;; Collapse / expand.
    (define-key map (kbd "RET") #'tasks-org-ui-toggle-expand)
    (define-key map (kbd "TAB") #'tasks-org-ui-toggle-expand)
    ;; Status cycling.  `S-<right>' / `S-<left>' mirror `org-shiftright' /
    ;; `org-shiftleft' so cycling here matches org buffers.  These are the
    ;; primary bindings because Treemacs claims `h' / `l' / `<right>' /
    ;; `<left>' for tree navigation in the Spacemacs build and shadows the
    ;; minor-mode entries below.  The plain bindings remain for
    ;; non-Spacemacs / non-evilified setups where they win.
    (define-key map (kbd "S-<right>") #'tasks-org-ui-cycle-status)
    (define-key map (kbd "S-<left>")  #'tasks-org-ui-cycle-status-back)
    (define-key map (kbd "l") #'tasks-org-ui-cycle-status)
    (define-key map (kbd "h") #'tasks-org-ui-cycle-status-back)
    (define-key map (kbd "<right>") #'tasks-org-ui-cycle-status)
    (define-key map (kbd "<left>") #'tasks-org-ui-cycle-status-back)
    ;; Selection / source jumps / change-record.
    (define-key map (kbd "s") #'tasks-org-ui-toggle-selected)
    (define-key map (kbd "e") #'tasks-org-ui-visit-source)
    (define-key map (kbd "p") #'tasks-org-ui-open-or-create-import)
    ;; Publish / unpublish (mirrors pi tasks extension's `P' / `U').
    (define-key map (kbd "P") #'tasks-org-ui-publish-task)
    (define-key map (kbd "U") #'tasks-org-ui-unpublish-task)
    ;; Archive (mirrors pi tasks extension's `A').
    (define-key map (kbd "A") #'tasks-org-ui-archive-task)
    ;; Doctor (mirrors pi tasks extension's `d', remapped to `D' so
    ;; Treemacs' lowercase `d' bindings remain available).
    (define-key map (kbd "D") #'tasks-org-ui-doctor)
    ;; Details pane.
    (define-key map (kbd "i") #'tasks-org-ui-show-details)
    ;; Task creation (mirrors pi tasks extension's `n' / `N').
    (define-key map (kbd "n") #'tasks-org-ui-create-task)
    (define-key map (kbd "N") #'tasks-org-ui-create-subtask)
    ;; Linked issues / refresh / quit.
    (define-key map (kbd "J") #'tasks-org-ui-open-linked-issues)
    (define-key map (kbd "g") #'tasks-org-ui-refresh)
    (define-key map (kbd "q") #'quit-window)
    map)
  "Keymap for `tasks-org-ui-mode'.
`SPC' is deliberately unbound — it remains the global Spacemacs leader.")

(define-minor-mode tasks-org-ui-mode
  "Minor mode for the org-memory task graph visualisation buffer.

The buffer's major mode is `treemacs-mode'; this minor mode overlays the
org-memory task actions and preserves the pi `tasks' extension's keybindings.
Status writes go through the org-memory protocol helpers in `tasks-org.el', so
LOGBOOK / CLOSED / :STARTED: bookkeeping stays consistent across pi and Emacs
surfaces."
  :init-value nil
  :lighter " TasksOrg"
  :keymap tasks-org-ui-mode-map
  (setq-local tasks-org-mode nil)
  (if tasks-org-ui-mode
      (add-hook 'post-command-hook
                #'tasks-org-ui--details-track-cursor nil t)
    (remove-hook 'post-command-hook
                 #'tasks-org-ui--details-track-cursor t)))

(provide 'tasks-org-ui)
;;; tasks-org-ui.el ends here
