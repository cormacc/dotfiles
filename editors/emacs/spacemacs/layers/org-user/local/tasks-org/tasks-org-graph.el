;;; tasks-org-graph.el --- Task graph reader for org-memory protocol -*- lexical-binding: t; -*-

;; Author: Cormac Cannon
;; URL: https://github.com/cormacc/dotfiles
;; Keywords: org, tasks, productivity
;; Package-Requires: ((emacs "29.1") (org "9.4"))

;;; Commentary:

;; Pure-elisp reader that loads the project's task graph rooted at
;; `TASKS.org', following `#+IMPORT:' links into change-records and
;; ingesting `TASKS.local.org' for `#+SELECTED:' and local-only task
;; headings.  Used by both the minor mode (for project-wide
;; selection-clearing helpers) and the UI buffer (for tree
;; rendering).
;;
;; The graph reader does not mutate any source file.  Mutations go
;; through `tasks-org.el's protocol helpers, which take a graph
;; locator (file + position) returned by `tasks-org-locate-by-id'
;; or by walking `tasks-org-load-graph' results.
;;
;; Data shape (plists):
;;
;;   GRAPH ::= (:tasks       (TASK ...)        ;; top-level tasks
;;              :selected-id ID-OR-NIL         ;; from TASKS.local.org
;;              :files       (PATH ...))       ;; absolute paths loaded
;;
;;   TASK ::= (:id           UUID-OR-NIL
;;             :status       KEYWORD-OR-NIL    ;; e.g. "TODO" / "DONE"
;;             :priority     LETTER-OR-NIL     ;; e.g. "B"
;;             :summary      STRING            ;; heading text minus status/priority/tags
;;             :tags         (TAG ...)
;;             :created      RAW-OR-NIL        ;; "[2026-05-06 Wed 21:56]"
;;             :started      RAW-OR-NIL
;;             :closed       RAW-OR-NIL
;;             :linked-issues (TOKEN ...)
;;             :import-raw   STRING-OR-NIL     ;; verbatim #+IMPORT: value
;;             :import-path  ABS-PATH-OR-NIL   ;; resolved if file exists
;;             :source-file  ABS-PATH
;;             :source-pos   INTEGER           ;; buffer position of heading
;;             :origin       SYMBOL            ;; 'shared, 'local, or 'plan
;;             :level        INTEGER           ;; org outline level in source
;;             :children     (TASK ...))

;;; Code:

(require 'cl-lib)
(require 'org)
(require 'org-element)

(declare-function tasks-org--project-root "tasks-org" ())
(declare-function tasks-org--tasks-file "tasks-org" ())
(declare-function tasks-org--local-file "tasks-org" ())
(declare-function tasks-org--extract-import-path "tasks-org" (raw))
(declare-function tasks-org-selected-id "tasks-org" ())

(defconst tasks-org-graph--protocol-keywords
  '("TODO" "STARTED" "WAITING" "DONE" "CANCELLED")
  "TODO keywords the org-memory protocol recognises.
Used as the canonical lexicon when a buffer's `org-todo-keywords-1'
is narrower than the protocol (e.g. plan files without a `#+TODO:'
line).")

;;; Heading-line parsing

(defun tasks-org-graph--parse-heading-line (line)
  "Extract (STATUS PRIORITY SUMMARY TAGS) from heading LINE.
LINE is the raw heading line minus the leading stars and one space.
Returns a 4-element list; any element may be nil except SUMMARY (always
a string).

The keyword lexicon is the union of the buffer's
`org-todo-keywords-1' and the protocol's known keywords, so plan files
without an explicit `#+TODO:' header still surface STARTED / WAITING /
CANCELLED."
  (let* ((todo-keywords
          (delete-dups
           (append tasks-org-graph--protocol-keywords
                   (and (boundp 'org-todo-keywords-1)
                        org-todo-keywords-1))))
         (kw-regex (concat "\\`\\(" (regexp-opt todo-keywords) "\\)\\(?:[ \t]+\\|\\'\\)"))
         status priority tags summary)
    (when (string-match kw-regex line)
      (setq status (match-string 1 line))
      (setq line (substring line (match-end 0))))
    (when (string-match "\\`\\[#\\([A-Z]\\)\\][ \t]+" line)
      (setq priority (match-string 1 line))
      (setq line (substring line (match-end 0))))
    (when (string-match "[ \t]+\\(:\\([[:alnum:]_@#%]+:\\)+\\)\\s-*\\'" line)
      ;; Capture the cut position BEFORE calling `split-string', which
      ;; clobbers the global match data.
      (let ((cut (match-beginning 0))
            (chunk (match-string 1 line)))
        (setq tags (split-string chunk ":" t))
        (setq line (substring line 0 cut))))
    (setq summary (string-trim line))
    (list status priority summary tags)))

;;; Linked-issue extraction

(defconst tasks-org-graph--linked-issue-token-rx
  ;; org-link OR bare token (anything but whitespace and ])
  "\\(\\[\\[[^]]+\\(?:\\]\\[[^]]*\\)?\\]\\]\\|[^[:space:]]+\\)")

(defun tasks-org-graph--parse-linked-issues (raw)
  "Tokenise a `:LINKED_ISSUES:' RAW value into a list of strings.
Whitespace-separated tokens; org-link forms preserved as a single token."
  (when (and raw (not (string-empty-p (string-trim raw))))
    (let ((tokens nil)
          (pos 0))
      (while (string-match tasks-org-graph--linked-issue-token-rx raw pos)
        (push (match-string 1 raw) tokens)
        (setq pos (match-end 0)))
      (nreverse tokens))))

;;; Task subtree parsing

(defun tasks-org-graph--read-property (heading-end name)
  "Return the property NAME on the heading at point, scanning to HEADING-END."
  (save-excursion
    (let ((re (format "^[ \t]*:%s:[ \t]+\\(.*\\)$" (regexp-quote name))))
      (when (re-search-forward re heading-end t)
        (string-trim (match-string-no-properties 1))))))

(defun tasks-org-graph--read-closed (heading-end)
  "Return the heading's `CLOSED:' raw value or nil, scanning to HEADING-END."
  (save-excursion
    (when (re-search-forward "^[ \t]*CLOSED:[ \t]+\\(\\[[^]]+\\]\\)" heading-end t)
      (match-string-no-properties 1))))

(defun tasks-org-graph--read-import-raw (heading-end)
  "Return the heading's verbatim `#+IMPORT:' value or nil."
  (save-excursion
    (when (re-search-forward "^[ \t]*#\\+IMPORT:[ \t]*\\(.*\\)$" heading-end t)
      (let ((val (string-trim (match-string-no-properties 1))))
        (and (not (string-empty-p val)) val)))))

(defun tasks-org-graph--parse-task-at-point (source-file origin)
  "Parse the org task at point into a task plist.
Caller must position point on a heading line.  Does not recurse;
children are filled in by `tasks-org-graph--collect-subtree'."
  (save-excursion
    (org-back-to-heading t)
    (let* ((source-pos (point))
           (level (org-outline-level))
           (heading-line
            (buffer-substring-no-properties
             (progn (looking-at "^\\*+[ \t]+") (match-end 0))
             (line-end-position)))
           (parsed (tasks-org-graph--parse-heading-line heading-line))
           (status (nth 0 parsed))
           (priority (nth 1 parsed))
           (summary (nth 2 parsed))
           (tags (nth 3 parsed))
           (subtree-end
            (save-excursion (org-end-of-subtree t t) (point)))
           (heading-end
            (save-excursion (outline-next-heading) (or (point) subtree-end)))
           (id (tasks-org-graph--read-property heading-end "ID"))
           (created (tasks-org-graph--read-property heading-end "CREATED"))
           (started (tasks-org-graph--read-property heading-end "STARTED"))
           (closed (tasks-org-graph--read-closed heading-end))
           (linked-raw (tasks-org-graph--read-property heading-end "LINKED_ISSUES"))
           (linked-issues (tasks-org-graph--parse-linked-issues linked-raw))
           (import-raw (tasks-org-graph--read-import-raw heading-end))
           (import-path
            (when import-raw
              (let* ((rel (tasks-org--extract-import-path import-raw))
                     (abs (and rel (expand-file-name
                                    rel (file-name-directory source-file)))))
                (and abs (file-readable-p abs) abs)))))
      (list :id id
            :status status
            :priority priority
            :summary summary
            :tags tags
            :created created
            :started started
            :closed closed
            :linked-issues linked-issues
            :import-raw import-raw
            :import-path import-path
            :source-file source-file
            :source-pos source-pos
            :origin origin
            :level level
            :children nil))))

(defun tasks-org-graph--task-heading-p ()
  "Return non-nil when point's heading carries a known TODO keyword.
Recognises both the buffer-local TODO sequence and the protocol's
keyword set, so plan files without an explicit `#+TODO:' header still
expose STARTED/WAITING/CANCELLED as actionable statuses."
  ;; `org-get-todo-state' returns nil when the heading's first word is
  ;; outside `org-todo-keywords-1', so use a manual heading-line scrape
  ;; instead.
  (save-excursion
    (org-back-to-heading t)
    (when (looking-at "^\\*+[ \t]+\\([A-Z][A-Z]+\\)\\(?:[ \t]\\|$\\)")
      (let ((kw (match-string-no-properties 1)))
        (or (member kw tasks-org-graph--protocol-keywords)
            (and (boundp 'org-todo-keywords-1)
                 (member kw org-todo-keywords-1)))))))

(defun tasks-org-graph--collect-subtree (source-file origin parent-level)
  "Collect children of the heading at point, filtered to actionable tasks.
Recurses into deeper headings while their level > PARENT-LEVEL.
Stops when a sibling or shallower heading is reached."
  (let ((children nil)
        (subtree-end
         (save-excursion (org-back-to-heading t) (org-end-of-subtree t t) (point))))
    (save-excursion
      (org-back-to-heading t)
      (outline-next-heading)
      (while (and (< (point) subtree-end)
                  (looking-at org-heading-regexp))
        (let ((this-level (org-outline-level)))
          (cond
           ((<= this-level parent-level)
            ;; Sibling or shallower — stop.
            (goto-char subtree-end))
           ((= this-level (1+ parent-level))
            (when (tasks-org-graph--task-heading-p)
              (let ((task (tasks-org-graph--parse-task-at-point source-file origin)))
                (setq task (plist-put task :children
                                      (tasks-org-graph--collect-subtree
                                       source-file origin this-level)))
                (push task children)))
            (org-end-of-subtree t t))
           (t
            ;; Deeper than expected (skipped levels) — descend.
            (outline-next-heading))))))
    (nreverse children)))

(defun tasks-org-graph--collect-top-level (source-file origin)
  "Collect every actionable top-level task in the current buffer."
  (let ((tasks nil))
    (org-with-wide-buffer
     (goto-char (point-min))
     (while (re-search-forward "^\\* " nil t)
       (beginning-of-line)
       (when (tasks-org-graph--task-heading-p)
         (let ((task (tasks-org-graph--parse-task-at-point source-file origin)))
           (setq task (plist-put task :children
                                 (tasks-org-graph--collect-subtree
                                  source-file origin (org-outline-level))))
           (push task tasks)))
       (org-end-of-subtree t t)))
    (nreverse tasks)))

;;; Plan-file ingestion

(defun tasks-org-graph--collect-plan-file (file)
  "Parse the `* Plan' section of FILE (a change-record) into task plists.
Returns a flat list of plan-task plists, retaining their nested
children.  Returns nil when FILE is unreadable or has no actionable
plan tasks."
  (when (and file (file-readable-p file))
    (with-current-buffer (find-file-noselect file)
      (org-with-wide-buffer
       (goto-char (point-min))
       (let ((tasks nil))
         (when (re-search-forward "^\\* Plan[ \t]*$" nil t)
           (let ((section-end
                  (save-excursion
                    (if (re-search-forward "^\\* " nil t)
                        (match-beginning 0)
                      (point-max)))))
             (while (and (< (point) section-end)
                         (re-search-forward "^\\*\\* " section-end t))
               (beginning-of-line)
               (when (tasks-org-graph--task-heading-p)
                 (let ((task (tasks-org-graph--parse-task-at-point file 'plan)))
                   (setq task (plist-put task :children
                                         (tasks-org-graph--collect-subtree
                                          file 'plan (org-outline-level))))
                   (push task tasks)))
               (org-end-of-subtree t t))))
         (nreverse tasks))))))

(defun tasks-org-graph--attach-plans (tasks)
  "For every task in TASKS (recursively) with a resolvable :import-path,
attach the plan-file's plan tasks as children, preserving any existing
children.  Returns the updated TASKS list."
  (mapcar
   (lambda (task)
     (let* ((existing (plist-get task :children))
            (recursed (tasks-org-graph--attach-plans existing))
            (import-path (plist-get task :import-path))
            (plan-tasks (and import-path
                             (tasks-org-graph--collect-plan-file import-path))))
       (plist-put (copy-sequence task)
                  :children
                  (append recursed
                          (tasks-org-graph--attach-plans (or plan-tasks nil))))))
   tasks))

;;; Public entry

;;;###autoload
(defun tasks-org-load-graph (&optional opts)
  "Load the project task graph and return it as a plist.
OPTS is reserved for future extensibility (currently ignored).

The graph is rooted at `TASKS.org', extended with the contents of
imported change-records (`#+IMPORT:' under each task) and merged with
local-only tasks from `TASKS.local.org'.  See the file commentary for
the data shape."
  (ignore opts)
  (require 'tasks-org)
  (let* ((tasks-file (tasks-org--tasks-file))
         (local-file (tasks-org--local-file))
         (selected-id (and (file-readable-p local-file)
                           (tasks-org-selected-id)))
         (shared-tasks
          (when (file-readable-p tasks-file)
            (with-current-buffer (find-file-noselect tasks-file)
              (tasks-org-graph--collect-top-level tasks-file 'shared))))
         (local-tasks
          (when (file-readable-p local-file)
            (with-current-buffer (find-file-noselect local-file)
              (tasks-org-graph--collect-top-level local-file 'local))))
         (with-plans (tasks-org-graph--attach-plans shared-tasks))
         (all-tasks (append with-plans local-tasks))
         ;; Collect every loaded file path (TASKS.org, plan files, local).
         (files (delete-dups
                 (append (list tasks-file)
                         (and (file-readable-p local-file)
                              (list local-file))
                         (delq nil
                               (mapcar (lambda (task)
                                         (plist-get task :import-path))
                                       (tasks-org-graph--flatten with-plans)))))))
    (list :tasks all-tasks
          :selected-id selected-id
          :files files)))

(defun tasks-org-graph--flatten (tasks)
  "Return TASKS as a flat list (depth-first)."
  (cl-loop for task in tasks
           append (cons task
                        (tasks-org-graph--flatten
                         (plist-get task :children)))))

;;; Convenience accessors

(defun tasks-org-graph-find-by-id (graph id)
  "Return the task plist with :id ID in GRAPH, or nil."
  (cl-find-if (lambda (task) (equal (plist-get task :id) id))
              (tasks-org-graph--flatten (plist-get graph :tasks))))

(defun tasks-org-graph-tasks (graph)
  "Return the top-level task list from GRAPH."
  (plist-get graph :tasks))

(defun tasks-org-graph-selected-id (graph)
  "Return the selected-task UUID recorded in GRAPH, or nil."
  (plist-get graph :selected-id))

(defun tasks-org-graph-files (graph)
  "Return the list of source files contributing to GRAPH."
  (plist-get graph :files))

(provide 'tasks-org-graph)
;;; tasks-org-graph.el ends here
