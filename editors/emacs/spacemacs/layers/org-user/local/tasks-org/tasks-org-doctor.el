;;; tasks-org-doctor.el --- Health checks for the org-memory task graph -*- lexical-binding: t; -*-

;;; Commentary:

;; Mirrors the pi tasks extension's `/tasks doctor' health checks against the
;; in-Emacs task graph (see `tasks-org-graph.el').  The module is intentionally
;; UI-agnostic: pure functions return a list of FINDING plists, and a separate
;; renderer turns them into a transient report buffer with file/line jumps.
;;
;; Findings shape:
;;
;;   (:code SYMBOL  ;; e.g. 'duplicate-id, 'broken-import
;;    :severity SYMBOL ;; 'error or 'warn
;;    :message STRING
;;    :file STRING-OR-NIL
;;    :line INT-OR-NIL
;;    :heading STRING-OR-NIL)
;;
;; The codes mirror pi's `FindingCode' set:
;;
;;   duplicate-id, broken-import, selected-not-found,
;;   waiting-without-blocker, closed-without-timestamp,
;;   stale-parent-status, invalid-task-blocker

;;; Code:

(require 'cl-lib)
(require 'tasks-org)
(require 'tasks-org-graph)

(defconst tasks-org-doctor--closed-statuses '("DONE" "CANCELLED"))
(defconst tasks-org-doctor--active-child-statuses '("STARTED" "WAITING"))

(defun tasks-org-doctor--walk (tasks)
  "Pre-order walk over TASKS and their descendants, returning a flat list."
  (let (out)
    (cl-labels ((visit (lst)
                  (dolist (task lst)
                    (push task out)
                    (visit (plist-get task :children)))))
      (visit tasks))
    (nreverse out)))

(defun tasks-org-doctor--line-for-pos (file pos)
  "Return the 1-indexed line number of POS in FILE, or nil."
  (when (and file pos (file-readable-p file))
    (with-temp-buffer
      (insert-file-contents file)
      (goto-char (min pos (point-max)))
      (line-number-at-pos))))

(defun tasks-org-doctor--read-blockers (file pos)
  "Return =:BLOCKED-BY:= / =:BLOCKED-BY+:= values for the heading at POS in FILE.
Reads the source on disk so the doctor stays current with file edits even
when the graph cache pre-dates them.  Returns a list of strings (raw
values, e.g. =task:UUID=, =url:...=).  Looks only at the heading's own
property drawer region (between the heading line and the next heading
or end-of-buffer)."
  (when (and file pos (file-readable-p file))
    (with-temp-buffer
      (insert-file-contents file)
      (goto-char (min pos (point-max)))
      ;; Move past the current heading line so the next-heading search
      ;; doesn't snap back to it (when POS is at heading column 0).
      (forward-line 1)
      (let ((heading-end
             (save-excursion
               (if (re-search-forward "^\\*+ " nil t)
                   (line-beginning-position)
                 (point-max))))
            blockers)
        (save-excursion
          (while (re-search-forward
                  "^[ \t]*:BLOCKED-BY\\+?:[ \t]+\\(.*\\)$"
                  heading-end t)
            (push (string-trim (match-string-no-properties 1)) blockers)))
        (nreverse blockers)))))

(defun tasks-org-doctor--blocker-task-id (blocker)
  "Return the UUID referenced by BLOCKER when it is a `task:UUID' form."
  (and (stringp blocker)
       (string-match "\\`task:\\(.+\\)\\'" blocker)
       (string-trim (match-string 1 blocker))))

(defun tasks-org-doctor--build-id-index (tasks)
  "Return `(BY-ID . DUPLICATES)' over TASKS, where:
- BY-ID is a hash table id \u2192 first-seen task plist;
- DUPLICATES is a hash table id \u2192 list of *every* task plist sharing that id\n  (only populated for ids with >= 2 occurrences)."
  (let ((by-id (make-hash-table :test 'equal))
        (duplicates (make-hash-table :test 'equal)))
    (dolist (task (tasks-org-doctor--walk tasks))
      (when-let ((id (plist-get task :id)))
        (cond
         ((null (gethash id by-id))
          (puthash id task by-id))
         (t
          (let ((list (or (gethash id duplicates)
                          (list (gethash id by-id)))))
            (puthash id (append list (list task)) duplicates))))))
    (cons by-id duplicates)))

(defun tasks-org-doctor--child-statuses (task)
  "Return the set of statuses found anywhere under TASK (excluding TASK itself).
Returned as a list of distinct strings (string-equal comparison)."
  (let (seen)
    (cl-labels ((visit (lst)
                  (dolist (t1 lst)
                    (let ((s (plist-get t1 :status)))
                      (when (and s (not (member s seen)))
                        (push s seen)))
                    (visit (plist-get t1 :children)))))
      (visit (plist-get task :children)))
    (sort seen #'string<)))

(defun tasks-org-doctor--finding (code severity message task)
  "Build a finding plist for TASK with the supplied CODE/SEVERITY/MESSAGE."
  (let* ((file (and task (plist-get task :source-file)))
         (pos (and task (plist-get task :source-pos))))
    (list :code code
          :severity severity
          :message message
          :file file
          :line (tasks-org-doctor--line-for-pos file pos)
          :heading (and task (plist-get task :summary)))))

(defun tasks-org-doctor-run (graph)
  "Run all health checks against GRAPH; return a list of FINDING plists.
GRAPH is a graph plist as returned by `tasks-org-load-graph'."
  (let* ((tasks (plist-get graph :tasks))
         (selected-id (plist-get graph :selected-id))
         (index (tasks-org-doctor--build-id-index tasks))
         (by-id (car index))
         (duplicates (cdr index))
         findings)
    ;; duplicate-id (one finding per occurrence so each is jumpable)
    (maphash
     (lambda (id occurrences)
       (let ((n (length occurrences)))
         (dolist (occ occurrences)
           (push (tasks-org-doctor--finding
                  'duplicate-id 'error
                  (format "Duplicate :ID: %s (%d occurrences)" id n)
                  occ)
                 findings))))
     duplicates)
    ;; selected-not-found
    (when (and selected-id (not (gethash selected-id by-id)))
      (push (list :code 'selected-not-found
                  :severity 'error
                  :message
                  (format
                   "TASKS.local.org #+SELECTED: %s does not match any :ID: in the loaded task graph"
                   selected-id)
                  :file (ignore-errors (tasks-org--local-file))
                  :line nil
                  :heading nil)
            findings))
    ;; per-task checks
    (dolist (task (tasks-org-doctor--walk tasks))
      (let* ((status (plist-get task :status))
             (import-raw (plist-get task :import-raw))
             (import-path (plist-get task :import-path))
             (closed (plist-get task :closed))
             (file (plist-get task :source-file))
             (pos (plist-get task :source-pos)))
        ;; broken-import: graph parsed an #+IMPORT but did not resolve a
        ;; readable file underneath it.
        (when (and import-raw (not import-path))
          (push (tasks-org-doctor--finding
                 'broken-import 'error
                 (format "#+IMPORT: failed to resolve to a readable file: %s"
                         import-raw)
                 task)
                findings))
        ;; closed-without-timestamp
        (when (and (member status tasks-org-doctor--closed-statuses)
                   (or (null closed) (string-empty-p closed)))
          (push (tasks-org-doctor--finding
                 'closed-without-timestamp 'warn
                 (format
                  "%s task has no CLOSED: timestamp; the next status change repairs it"
                  status)
                 task)
                findings))
        ;; stale-parent-status: TODO with active/closed descendants
        (when (string= status "TODO")
          (let ((child-statuses (tasks-org-doctor--child-statuses task)))
            (when (cl-some
                   (lambda (s)
                     (or (member s tasks-org-doctor--closed-statuses)
                         (member s tasks-org-doctor--active-child-statuses)))
                   child-statuses)
              (push (tasks-org-doctor--finding
                     'stale-parent-status 'warn
                     (format
                      "Parent is TODO but has descendants in [%s] \u2014 promote to STARTED"
                      (mapconcat #'identity child-statuses ", "))
                     task)
                    findings))))
        ;; blocker checks (read source-on-disk for :BLOCKED-BY: / :BLOCKED-BY+:)
        (let ((blockers (tasks-org-doctor--read-blockers file pos)))
          (when (and (string= status "WAITING") (null blockers))
            (push (tasks-org-doctor--finding
                   'waiting-without-blocker 'warn
                   "WAITING task has no :BLOCKED-BY: entry \u2014 add one or move it back to TODO"
                   task)
                  findings))
          (dolist (blocker blockers)
            (when-let ((bid (tasks-org-doctor--blocker-task-id blocker)))
              (unless (gethash bid by-id)
                (push (tasks-org-doctor--finding
                       'invalid-task-blocker 'error
                       (format
                        ":BLOCKED-BY: references task:%s which is not in the loaded task graph"
                        bid)
                       task)
                      findings)))))))
    (nreverse findings)))

;;; Rendering

(defun tasks-org-doctor--severity-rank (sev)
  "Numeric rank for SEV: errors before warnings."
  (pcase sev (`error 0) (`warn 1) (_ 2)))

(defun tasks-org-doctor--format-line (finding)
  "Render FINDING as a single text line for the report buffer.
Format: =[SEV] code: message (file:line)= so the line parser in
`tasks-org-doctor-visit-at-point' can recover the location."
  (let* ((sev (plist-get finding :severity))
         (sev-tag (if (eq sev 'error) "ERROR" "WARN"))
         (code (plist-get finding :code))
         (msg (plist-get finding :message))
         (file (plist-get finding :file))
         (line (plist-get finding :line))
         (loc (cond
               ((and file line) (format " (%s:%d)" file line))
               (file (format " (%s)" file))
               (t ""))))
    (format "[%s] %s: %s%s" sev-tag code msg loc)))

(defun tasks-org-doctor-format-report (findings)
  "Render FINDINGS as a multi-line report string.
Empty input yields a single OK line.  Findings are grouped by code; within
each group, errors come before warnings."
  (if (null findings)
      "OK \u2014 no doctor findings.\n"
    (let ((sorted (sort (copy-sequence findings)
                        (lambda (a b)
                          (let ((ca (symbol-name (plist-get a :code)))
                                (cb (symbol-name (plist-get b :code))))
                            (or (string< ca cb)
                                (and (string= ca cb)
                                     (< (tasks-org-doctor--severity-rank
                                         (plist-get a :severity))
                                        (tasks-org-doctor--severity-rank
                                         (plist-get b :severity))))))))))
      (concat (format "%d finding%s:\n\n"
                      (length sorted) (if (= 1 (length sorted)) "" "s"))
              (mapconcat #'tasks-org-doctor--format-line sorted "\n")
              "\n"))))

(defvar tasks-org-doctor--line-location-re
  " (\\([^:()]+\\(?::[^:()]+\\)*?\\):\\([0-9]+\\))$"
  "Regex matching the trailing =(file:line)= location on a finding line.
The first capture group is the file path; the second is the 1-indexed line.")

(defun tasks-org-doctor-visit-at-point ()
  "Visit the source location referenced on the current report line, if any."
  (interactive)
  (let ((line (buffer-substring-no-properties
               (line-beginning-position) (line-end-position))))
    (if (string-match tasks-org-doctor--line-location-re line)
        (let* ((file (match-string 1 line))
               (line-num (string-to-number (match-string 2 line)))
               (buf (find-file-noselect file)))
          (pop-to-buffer buf)
          (goto-char (point-min))
          (forward-line (1- line-num))
          (when (fboundp 'org-fold-show-entry)
            (org-fold-show-entry)))
      (user-error "No source location on this line"))))

(defvar tasks-org-doctor-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "RET") #'tasks-org-doctor-visit-at-point)
    (define-key map (kbd "q") #'quit-window)
    map)
  "Keymap for `tasks-org-doctor-mode'.")

(define-derived-mode tasks-org-doctor-mode special-mode "Tasks-Org-Doctor"
  "Read-only buffer rendering `tasks-org-doctor-run' findings.
Press RET on a finding line to jump to its source.")

;;;###autoload
(defun tasks-org-doctor-show ()
  "Run health checks against the loaded task graph and display the report."
  (interactive)
  (let* ((graph (tasks-org-load-graph))
         (findings (tasks-org-doctor-run graph))
         (buf (get-buffer-create "*tasks-org-doctor*")))
    (with-current-buffer buf
      (tasks-org-doctor-mode)
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (tasks-org-doctor-format-report findings))
        (goto-char (point-min))))
    (pop-to-buffer buf)))

(provide 'tasks-org-doctor)
;;; tasks-org-doctor.el ends here
