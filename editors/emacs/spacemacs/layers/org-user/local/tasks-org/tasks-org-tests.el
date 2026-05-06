;;; tasks-org-tests.el --- Tests for tasks-org -*- lexical-binding: t; -*-

;;; Commentary:

;; Run via:
;;   emacs -Q --batch -L . -l tasks-org-tests.el -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'tasks-org)
(require 'tasks-org-graph)

;; tasks-org-ui.el is intentionally `no-byte-compile' because vui.el is
;; the runtime renderer.  Load it interpreted for the pure-elisp
;; helpers we test here; vui-using forms are guarded with
;; `(when (require 'vui nil t) ...)' so this load succeeds in batch
;; without vui present.
(load (expand-file-name "tasks-org-ui.el" (file-name-directory load-file-name))
      nil t)

(ert-deftest tasks-org-org-timestamp-format ()
  "Timestamp helper produces the expected pattern."
  (let ((ts (tasks-org--org-timestamp)))
    (should (string-match-p
             "^[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\} [A-Z][a-z]\\{2\\} [0-9]\\{2\\}:[0-9]\\{2\\}$"
             ts))))

(ert-deftest tasks-org-effective-plans-directory-fallback ()
  "Falls back to `tasks-org-plans-directory' when TASKS.org is absent."
  (let ((default-directory (make-temp-file "tasks-org-test" t))
        (tasks-org-plans-directory "design/log"))
    (unwind-protect
        (cl-letf (((symbol-function 'tasks-org--project-root)
                   (lambda () default-directory)))
          (should (equal (tasks-org--effective-plans-directory) "design/log")))
      (delete-directory default-directory t))))

(ert-deftest tasks-org-effective-plans-directory-from-keyword ()
  "Reads `#+DEFAULT_PLAN_DIR:' from TASKS.org when present."
  (let* ((tmp (make-temp-file "tasks-org-test" t))
         (tasks-file (expand-file-name "TASKS.org" tmp)))
    (unwind-protect
        (progn
          (with-temp-file tasks-file
            (insert "#+TITLE: T\n"
                    "#+DEFAULT_PLAN_DIR: [[file:./change-records]]\n"
                    "* TODO Task\n"))
          (cl-letf (((symbol-function 'tasks-org--project-root)
                     (lambda () tmp)))
            (should (equal (tasks-org--effective-plans-directory)
                           "change-records"))))
      (delete-directory tmp t))))

(ert-deftest tasks-org-effective-plans-directory-bare-path ()
  "Accepts a bare path value for `#+DEFAULT_PLAN_DIR:'."
  (let* ((tmp (make-temp-file "tasks-org-test" t))
         (tasks-file (expand-file-name "TASKS.org" tmp)))
    (unwind-protect
        (progn
          (with-temp-file tasks-file
            (insert "#+DEFAULT_PLAN_DIR: plans/\n"))
          (cl-letf (((symbol-function 'tasks-org--project-root)
                     (lambda () tmp)))
            (should (equal (tasks-org--effective-plans-directory) "plans/"))))
      (delete-directory tmp t))))

(ert-deftest tasks-org-extract-import-path-bare ()
  "Bare path values are returned unchanged."
  (should (equal (tasks-org--extract-import-path "design/log/plan.org")
                 "design/log/plan.org")))

(ert-deftest tasks-org-extract-import-path-link ()
  "Org-link forms (with and without label) yield the path."
  (should (equal (tasks-org--extract-import-path "[[file:design/log/plan.org]]")
                 "design/log/plan.org"))
  (should (equal (tasks-org--extract-import-path
                  "[[file:design/log/plan.org][Plan]]")
                 "design/log/plan.org")))

;;; Selection writer preservation

(ert-deftest tasks-org-write-local-selection-preserves-existing-content ()
  "Writing a new selection must preserve local task headings and #+IMPORT keywords."
  (let* ((tmp (make-temp-file "tasks-org-test" t))
         (local-file (expand-file-name "TASKS.local.org" tmp)))
    (unwind-protect
        (cl-letf (((symbol-function 'tasks-org--project-root)
                   (lambda () tmp)))
          ;; Seed the local file with a mix of selection + drafts + import.
          (with-temp-file local-file
            (insert "#+SELECTED: old-uuid\n"
                    "#+IMPORT: [[file:./scratch.org]]\n"
                    "* TODO Local draft\n"
                    ":PROPERTIES:\n"
                    ":ID: draft-1\n"
                    ":END:\n"
                    "Draft body.\n"))
          (tasks-org--write-local-selection "new-uuid")
          (let ((content (with-temp-buffer
                           (insert-file-contents local-file)
                           (buffer-string))))
            (should (string-match-p "^#\\+SELECTED: new-uuid$" content))
            (should-not (string-match-p "^#\\+SELECTED: old-uuid" content))
            (should (string-match-p "^#\\+IMPORT: " content))
            (should (string-match-p "^\\* TODO Local draft$" content))
            (should (string-match-p ":ID: draft-1" content))
            (should (string-match-p "Draft body\\." content))))
      (delete-directory tmp t))))

(ert-deftest tasks-org-write-local-selection-clears-without-deleting-content ()
  "Clearing selection (nil) keeps non-selection content intact."
  (let* ((tmp (make-temp-file "tasks-org-test" t))
         (local-file (expand-file-name "TASKS.local.org" tmp)))
    (unwind-protect
        (cl-letf (((symbol-function 'tasks-org--project-root)
                   (lambda () tmp)))
          (with-temp-file local-file
            (insert "#+SELECTED: keep-me\n"
                    "* TODO Local draft\n"))
          (tasks-org--write-local-selection nil)
          (let ((content (with-temp-buffer
                           (insert-file-contents local-file)
                           (buffer-string))))
            (should (string-match-p "^#\\+SELECTED:[ \t]*$" content))
            (should (string-match-p "^\\* TODO Local draft$" content))))
      (delete-directory tmp t))))

(ert-deftest tasks-org-write-local-selection-prepends-when-keyword-absent ()
  "Existing local content without #+SELECTED: gets the keyword prepended."
  (let* ((tmp (make-temp-file "tasks-org-test" t))
         (local-file (expand-file-name "TASKS.local.org" tmp)))
    (unwind-protect
        (cl-letf (((symbol-function 'tasks-org--project-root)
                   (lambda () tmp)))
          (with-temp-file local-file
            (insert "* TODO Existing draft\n"
                    ":PROPERTIES:\n"
                    ":ID: draft-x\n"
                    ":END:\n"))
          (tasks-org--write-local-selection "fresh-uuid")
          (let ((content (with-temp-buffer
                           (insert-file-contents local-file)
                           (buffer-string))))
            (should (string-prefix-p "#+SELECTED: fresh-uuid\n" content))
            (should (string-match-p "^\\* TODO Existing draft$" content))))
      (delete-directory tmp t))))

(ert-deftest tasks-org-write-local-selection-creates-file-when-absent ()
  "Writing into a missing local file creates it with just the keyword."
  (let* ((tmp (make-temp-file "tasks-org-test" t))
         (local-file (expand-file-name "TASKS.local.org" tmp)))
    (unwind-protect
        (cl-letf (((symbol-function 'tasks-org--project-root)
                   (lambda () tmp)))
          (should-not (file-exists-p local-file))
          (tasks-org--write-local-selection "first-uuid")
          (let ((content (with-temp-buffer
                           (insert-file-contents local-file)
                           (buffer-string))))
            (should (equal content "#+SELECTED: first-uuid\n"))))
      (delete-directory tmp t))))

;;; Status transitions

(defun tasks-org-tests--with-task-buffer (initial body)
  "Run BODY in an org buffer initialised with INITIAL content.
BODY is a function called with the buffer as current; its return value
is returned.  The buffer is killed afterwards."
  (with-temp-buffer
    (insert initial)
    (org-mode)
    (goto-char (point-min))
    (re-search-forward "^\\* " nil t)
    (beginning-of-line)
    (funcall body)))

(ert-deftest tasks-org-cycle-direction-wraps ()
  "Cycle direction wraps modulo the configured TODO sequence."
  (cl-letf (((symbol-function 'tasks-org--todo-sequence)
             (lambda () '("TODO" "STARTED" "WAITING" "DONE" "CANCELLED"))))
    (should (equal (tasks-org--cycle-direction "TODO" 'forward) "STARTED"))
    (should (equal (tasks-org--cycle-direction "STARTED" 'forward) "WAITING"))
    (should (equal (tasks-org--cycle-direction "CANCELLED" 'forward) "TODO"))
    (should (equal (tasks-org--cycle-direction "TODO" 'backward) "CANCELLED"))
    (should (equal (tasks-org--cycle-direction nil 'forward) "TODO"))))

(ert-deftest tasks-org-apply-status-transition-todo-to-started ()
  "TODO -> STARTED writes :STARTED: and a LOGBOOK transition entry."
  (tasks-org-tests--with-task-buffer
   "#+TODO: TODO(t) STARTED(s) WAITING(w) | DONE(d) CANCELLED(c)\n* TODO Task\n:PROPERTIES:\n:ID: t1\n:END:\n"
   (lambda ()
     (tasks-org--apply-status-transition "STARTED")
     (let ((content (buffer-substring-no-properties (point-min) (point-max))))
       (should (string-match-p "^\\* STARTED Task$" content))
       (should (string-match-p ":STARTED:[ \t]+\\[" content))
       (should (string-match-p
                "- State \"STARTED\"      from \"TODO\"      \\[" content))
       (should-not (string-match-p "^CLOSED:" content))))))

(ert-deftest tasks-org-apply-status-transition-started-to-done ()
  "STARTED -> DONE writes CLOSED:, preserves :STARTED:, appends LOGBOOK."
  (tasks-org-tests--with-task-buffer
   "#+TODO: TODO(t) STARTED(s) WAITING(w) | DONE(d) CANCELLED(c)\n* STARTED Task\n:PROPERTIES:\n:ID: t1\n:STARTED: [2026-01-01 Thu 09:00]\n:END:\n"
   (lambda ()
     (tasks-org--apply-status-transition "DONE")
     (let ((content (buffer-substring-no-properties (point-min) (point-max))))
       (should (string-match-p "^\\* DONE Task$" content))
       (should (string-match-p "^CLOSED:[ \t]+\\[" content))
       (should (string-match-p ":STARTED:[ \t]+\\[2026-01-01 Thu 09:00\\]" content))
       (should (string-match-p
                "- State \"DONE\"      from \"STARTED\"      \\[" content))))))

(ert-deftest tasks-org-apply-status-transition-reopen-clears-closed ()
  "Reopening DONE -> STARTED clears CLOSED: but preserves :STARTED:."
  (tasks-org-tests--with-task-buffer
   "#+TODO: TODO(t) STARTED(s) WAITING(w) | DONE(d) CANCELLED(c)\n* DONE Task\nCLOSED: [2026-01-02 Fri 10:00]\n:PROPERTIES:\n:ID: t1\n:STARTED: [2026-01-01 Thu 09:00]\n:END:\n"
   (lambda ()
     (tasks-org--apply-status-transition "STARTED")
     (let ((content (buffer-substring-no-properties (point-min) (point-max))))
       (should (string-match-p "^\\* STARTED Task$" content))
       (should-not (string-match-p "^CLOSED:" content))
       (should (string-match-p ":STARTED:[ \t]+\\[2026-01-01 Thu 09:00\\]" content))
       (should (string-match-p
                "- State \"STARTED\"      from \"DONE\"      \\[" content))))))

(ert-deftest tasks-org-apply-status-transition-logbook-appends ()
  "Multiple transitions append; the drawer is not rewritten."
  (tasks-org-tests--with-task-buffer
   "#+TODO: TODO(t) STARTED(s) WAITING(w) | DONE(d) CANCELLED(c)\n* TODO Task\n:PROPERTIES:\n:ID: t1\n:END:\n:LOGBOOK:\n- Created [2026-01-01 Thu 08:00]\n:END:\n"
   (lambda ()
     (tasks-org--apply-status-transition "STARTED")
     (tasks-org--apply-status-transition "DONE")
     (let ((content (buffer-substring-no-properties (point-min) (point-max))))
       (should (string-match-p "- Created \\[2026-01-01 Thu 08:00\\]" content))
       (should (string-match-p
                "- State \"STARTED\"      from \"TODO\"      \\[" content))
       (should (string-match-p
                "- State \"DONE\"      from \"STARTED\"      \\[" content))))))

;;; Change-record scaffold

(ert-deftest tasks-org-scaffold-change-record-skeleton ()
  "Scaffold writes the org-plan minimal skeleton with the supplied parent ID."
  (let* ((tmp (make-temp-file "tasks-org-test" t))
         (cr (expand-file-name "design/log/2026-05-06-x.org" tmp)))
    (unwind-protect
        (progn
          (tasks-org--scaffold-change-record cr "parent-uuid" "Demo title")
          (let ((content (with-temp-buffer
                           (insert-file-contents cr)
                           (buffer-string))))
            (should (string-match-p "^#\\+TITLE: Demo title$" content))
            (should (string-match-p "^#\\+DATE: " content))
            (should (string-match-p "^#\\+PARENT_ID: parent-uuid$" content))
            (should (string-match-p "^#\\+STATUS: Draft$" content))
            (should (string-match-p
                     "^#\\+TODO: TODO(t) STARTED(s) WAITING(w) | DONE(d) CANCELLED(c)$"
                     content))
            (should (string-match-p "^\\* Context$" content))
            (should (string-match-p "^\\*\\* Design decisions$" content))
            (should (string-match-p "^\\* Plan$" content))
            (should (string-match-p "^\\* Implementation$" content))
            (should (string-match-p "^\\* Open questions$" content))))
      (delete-directory tmp t))))

(ert-deftest tasks-org-scaffold-change-record-refuses-overwrite ()
  "Scaffold refuses to overwrite an existing file."
  (let* ((tmp (make-temp-file "tasks-org-test" t))
         (cr (expand-file-name "design/log/existing.org" tmp)))
    (unwind-protect
        (progn
          (make-directory (file-name-directory cr) t)
          (write-region "pre-existing" nil cr)
          (should-error
           (tasks-org--scaffold-change-record cr "parent-uuid" "Title")
           :type 'user-error))
      (delete-directory tmp t))))

;;; Graph reader

(defun tasks-org-tests--with-fixture-project (fn &rest files-and-content)
  "Materialise a temporary project with FILES-AND-CONTENT pairs, then run FN.
FILES-AND-CONTENT is a flat plist of (relpath content ...).
FN is called with the project root path and must return its result."
  (let ((tmp (make-temp-file "tasks-org-graph-test" t)))
    (unwind-protect
        (progn
          (cl-loop for (rel content) on files-and-content by #'cddr
                   do (let ((path (expand-file-name rel tmp)))
                        (make-directory (file-name-directory path) t)
                        (with-temp-file path (insert content))))
          (cl-letf (((symbol-function 'tasks-org--project-root)
                     (lambda () tmp)))
            (funcall fn tmp)))
      ;; Kill any buffers we visited from the fixture so the next test runs clean.
      (dolist (buf (buffer-list))
        (when (and (buffer-file-name buf)
                   (string-prefix-p tmp (buffer-file-name buf)))
          (kill-buffer buf)))
      (delete-directory tmp t))))

(ert-deftest tasks-org-graph-parses-heading-line ()
  "Heading-line parser splits status / priority / summary / tags."
  (should (equal (tasks-org-graph--parse-heading-line "TODO [#B] Hello :foo:bar:")
                 '("TODO" "B" "Hello" ("foo" "bar"))))
  (should (equal (tasks-org-graph--parse-heading-line "DONE Hello world")
                 '("DONE" nil "Hello world" nil)))
  (should (equal (tasks-org-graph--parse-heading-line "Just a header")
                 '(nil nil "Just a header" nil))))

(ert-deftest tasks-org-graph-parses-linked-issues ()
  "Linked-issues tokeniser splits whitespace tokens, preserves org-link forms."
  (should (equal (tasks-org-graph--parse-linked-issues "MBE-1  MBE-2")
                 '("MBE-1" "MBE-2")))
  (should (equal (tasks-org-graph--parse-linked-issues
                  "MBE-1 [[https://example.com/x][gh#42]]")
                 '("MBE-1" "[[https://example.com/x][gh#42]]")))
  (should (null (tasks-org-graph--parse-linked-issues nil)))
  (should (null (tasks-org-graph--parse-linked-issues "   "))))

(ert-deftest tasks-org-graph-loads-tasks-with-import ()
  "Loading the graph follows #+IMPORT links into change-records."
  (tasks-org-tests--with-fixture-project
   (lambda (root)
     (let* ((graph (tasks-org-load-graph))
            (tasks (tasks-org-graph-tasks graph))
            (parent (car tasks)))
       (should (= (length tasks) 1))
       (should (equal (plist-get parent :id) "parent-1"))
       (should (equal (plist-get parent :status) "TODO"))
       (should (equal (plist-get parent :priority) "B"))
       (should (equal (plist-get parent :origin) 'shared))
       (should (member "demo" (plist-get parent :tags)))
       (should (equal (plist-get parent :import-raw)
                      "[[file:design/log/plan.org]]"))
       (should (string-suffix-p "design/log/plan.org"
                                (plist-get parent :import-path)))
       (let ((children (plist-get parent :children)))
         (should (= (length children) 1))
         (should (equal (plist-get (car children) :id) "plan-1"))
         (should (equal (plist-get (car children) :origin) 'plan)))
       (should (equal (tasks-org-graph-selected-id graph) "parent-1"))))
   "TASKS.org"
   (concat "#+TITLE: t\n"
           "* TODO [#B] Demo :demo:\n"
           ":PROPERTIES:\n"
           ":ID: parent-1\n"
           ":END:\n"
           "#+IMPORT: [[file:design/log/plan.org]]\n")
   "design/log/plan.org"
   (concat "#+TITLE: plan\n"
           "* Plan\n"
           "** TODO Plan task\n"
           ":PROPERTIES:\n"
           ":ID: plan-1\n"
           ":END:\n")
   "TASKS.local.org"
   "#+SELECTED: parent-1\n"))

(ert-deftest tasks-org-graph-ingests-local-tasks ()
  "Local task headings in TASKS.local.org are surfaced with origin 'local."
  (tasks-org-tests--with-fixture-project
   (lambda (root)
     (let* ((graph (tasks-org-load-graph))
            (tasks (tasks-org-graph-tasks graph))
            (origins (mapcar (lambda (t) (plist-get t :origin)) tasks))
            (ids (mapcar (lambda (t) (plist-get t :id)) tasks)))
       (should (= (length tasks) 2))
       (should (member 'shared origins))
       (should (member 'local origins))
       (should (member "shared-1" ids))
       (should (member "local-1" ids))
       (should (equal (tasks-org-graph-selected-id graph) "local-1"))))
   "TASKS.org"
   (concat "* TODO Shared\n"
           ":PROPERTIES:\n"
           ":ID: shared-1\n"
           ":END:\n")
   "TASKS.local.org"
   (concat "#+SELECTED: local-1\n"
           "* TODO Local draft\n"
           ":PROPERTIES:\n"
           ":ID: local-1\n"
           ":END:\n")))

(ert-deftest tasks-org-graph-extracts-linked-issues ()
  "LINKED_ISSUES property is parsed into a list."
  (tasks-org-tests--with-fixture-project
   (lambda (root)
     (let* ((graph (tasks-org-load-graph))
            (parent (car (tasks-org-graph-tasks graph))))
       (should (equal (plist-get parent :linked-issues)
                      '("MBE-1" "MBE-2")))))
   "TASKS.org"
   (concat "* TODO Demo\n"
           ":PROPERTIES:\n"
           ":ID: demo-1\n"
           ":LINKED_ISSUES: MBE-1 MBE-2\n"
           ":END:\n")))

(ert-deftest tasks-org-graph-find-by-id ()
  "find-by-id locates plan tasks under the parent's import."
  (tasks-org-tests--with-fixture-project
   (lambda (root)
     (let* ((graph (tasks-org-load-graph))
            (plan-task (tasks-org-graph-find-by-id graph "plan-1")))
       (should plan-task)
       (should (equal (plist-get plan-task :status) "STARTED"))
       (should (equal (plist-get plan-task :origin) 'plan))))
   "TASKS.org"
   (concat "* TODO Demo\n"
           ":PROPERTIES:\n"
           ":ID: parent\n"
           ":END:\n"
           "#+IMPORT: [[file:design/log/plan.org]]\n")
   "design/log/plan.org"
   (concat "* Plan\n"
           "** STARTED Plan task\n"
           ":PROPERTIES:\n"
           ":ID: plan-1\n"
           ":END:\n")))

(ert-deftest tasks-org-graph-does-not-mutate-source ()
  "Graph reader is read-only — drawer properties remain unchanged."
  (let* ((tmp (make-temp-file "tasks-org-graph-test" t))
         (tasks-file (expand-file-name "TASKS.org" tmp))
         (initial (concat "* TODO Demo\n"
                          ":PROPERTIES:\n"
                          ":ID: demo-id\n"
                          ":CUSTOM_KEY: keep-me\n"
                          ":END:\n")))
    (unwind-protect
        (progn
          (with-temp-file tasks-file (insert initial))
          (cl-letf (((symbol-function 'tasks-org--project-root)
                     (lambda () tmp)))
            (tasks-org-load-graph))
          (let ((after (with-temp-buffer
                         (insert-file-contents tasks-file)
                         (buffer-string))))
            (should (equal after initial))))
      (dolist (buf (buffer-list))
        (when (and (buffer-file-name buf)
                   (string-prefix-p tmp (buffer-file-name buf)))
          (kill-buffer buf)))
      (delete-directory tmp t))))

;;; tasks-org-ui pure-logic tests

(ert-deftest tasks-org-ui-default-expanded-ids-empty-without-selection ()
  "With no #+SELECTED, no subtrees are pre-expanded."
  (let* ((graph (list :tasks (list (list :id "t1"
                                         :children (list (list :id "c1"))))
                      :selected-id nil
                      :files nil))
         (expanded (tasks-org-ui--default-expanded-ids graph)))
    (should (= (hash-table-count expanded) 0))))

(ert-deftest tasks-org-ui-default-expanded-ids-expands-selected-path ()
  "Selected task's full ancestor path is expanded."
  (let* ((graph (list :tasks (list (list :id "root"
                                         :children
                                         (list (list :id "mid"
                                                     :children
                                                     (list (list :id "leaf"))))))
                      :selected-id "leaf"
                      :files nil))
         (expanded (tasks-org-ui--default-expanded-ids graph)))
    (should (gethash "root" expanded))
    (should (gethash "mid" expanded))
    (should (gethash "leaf" expanded))))

(ert-deftest tasks-org-ui-default-expanded-ids-leaves-siblings-collapsed ()
  "Sibling subtrees of the selected path remain collapsed."
  (let* ((graph (list :tasks (list (list :id "root"
                                         :children
                                         (list (list :id "selected-branch"
                                                     :children
                                                     (list (list :id "leaf")))
                                               (list :id "other-branch"
                                                     :children
                                                     (list (list :id "other-leaf"))))))
                      :selected-id "leaf"
                      :files nil))
         (expanded (tasks-org-ui--default-expanded-ids graph)))
    (should (gethash "selected-branch" expanded))
    (should-not (gethash "other-branch" expanded))
    (should-not (gethash "other-leaf" expanded))))

(ert-deftest tasks-org-ui-format-summary-marks-selected ()
  "Summary formatter prefixes the selected task with the star marker."
  (let* ((task (list :id "x" :status "TODO" :summary "Demo"))
         (out (tasks-org-ui--format-summary task "x")))
    (should (string-match-p "^★ " (substring-no-properties out)))))

(ert-deftest tasks-org-ui-format-summary-tints-local-origin ()
  "Local-origin tasks get the magenta marker."
  (let* ((task (list :id "x" :origin 'local :status "TODO" :summary "Local draft"))
         (out (tasks-org-ui--format-summary task nil))
         (plain (substring-no-properties out)))
    (should (string-match-p "^⊠ " plain))))

(ert-deftest tasks-org-ui-format-summary-includes-import-indicator ()
  "Tasks with #+IMPORT show the change-record indicator."
  (let* ((task (list :id "x" :status "TODO" :summary "Demo"
                     :import-raw "[[file:plan.org]]"
                     :import-path "/abs/plan.org"))
         (out (tasks-org-ui--format-summary task nil)))
    (should (string-match-p "⇲" (substring-no-properties out)))))

(ert-deftest tasks-org-ui-format-summary-renders-badges ()
  "Linked-issue tokens render as ⤴ badges."
  (let* ((task (list :id "x" :status "TODO" :summary "Demo"
                     :linked-issues '("MBE-1" "[[https://x/y][gh#1]]")))
         (out (tasks-org-ui--format-summary task nil))
         (plain (substring-no-properties out)))
    (should (string-match-p "⤴MBE-1" plain))
    (should (string-match-p "⤴gh#1" plain))))

;;; Compact widget

(ert-deftest tasks-org-ui-compact-finds-containing-top-level ()
  "Compact widget locates the top-level task containing the selection."
  (let* ((graph (list :tasks
                      (list
                       (list :id "top-a"
                             :children (list (list :id "leaf-a")))
                       (list :id "top-b"
                             :children (list (list :id "leaf-b"))))
                      :selected-id "leaf-b"
                      :files nil))
         (top (tasks-org-ui--containing-top-level graph "leaf-b")))
    (should top)
    (should (equal (plist-get top :id) "top-b"))))

(ert-deftest tasks-org-ui-compact-elides-completed-subtree ()
  "Completed subtrees are summarised as `… N completed subtasks'."
  (let* ((task (list :id "p" :status "DONE" :summary "Done parent"
                     :children (list (list :id "c1" :status "DONE" :summary "x")
                                     (list :id "c2" :status "DONE" :summary "y")
                                     (list :id "c3" :status "DONE" :summary "z"))))
         (lines (tasks-org-ui--compact-collect-lines task nil 0)))
    (should (= (length lines) 2))
    (should (string-match-p "… 3 completed subtasks" (nth 1 lines)))))

(ert-deftest tasks-org-ui-compact-render-shows-no-selection-text ()
  "render-text returns nil when no selection, callers display fallback."
  (let ((graph (list :tasks (list (list :id "x")) :selected-id nil :files nil)))
    (should-not (tasks-org-ui--compact-render-text graph))))

;;; Linked-issue resolution

(ert-deftest tasks-org-ui-resolve-issue-token-org-link ()
  "Org-link tokens return the URL verbatim regardless of base."
  (should (equal (tasks-org-ui--resolve-issue-token
                  "[[https://example.com/x][label]]" nil)
                 "https://example.com/x"))
  (should (equal (tasks-org-ui--resolve-issue-token
                  "[[https://example.com/x]]" "https://anything/")
                 "https://example.com/x")))

(ert-deftest tasks-org-ui-resolve-issue-token-template ()
  "Bare keys resolve against {ID} placeholder (URL-encoded)."
  (should (equal (tasks-org-ui--resolve-issue-token
                  "MBE-1" "https://your-org.atlassian.net/browse/{ID}")
                 "https://your-org.atlassian.net/browse/MBE-1")))

(ert-deftest tasks-org-ui-resolve-issue-token-prefix ()
  "Bare keys append to a prefix-style base."
  (should (equal (tasks-org-ui--resolve-issue-token
                  "MBE-1" "https://your-org.atlassian.net/browse/")
                 "https://your-org.atlassian.net/browse/MBE-1")))

(ert-deftest tasks-org-ui-resolve-issue-token-unresolvable ()
  "Bare key with no base is unresolvable."
  (should-not (tasks-org-ui--resolve-issue-token "MBE-1" nil)))

(ert-deftest tasks-org-ui-resolve-issue-token-encodes-key ()
  "Non-URL-safe characters in keys are percent-encoded."
  (should (equal (tasks-org-ui--resolve-issue-token
                  "key with space" "https://x/{ID}")
                 "https://x/key%20with%20space")))

(ert-deftest tasks-org-ui-compact-render-truncates-overflow ()
  "Long trees are truncated at the configured max line count."
  (let* ((long-task (list :id "p" :status "TODO" :summary "Parent"
                          :children
                          (cl-loop for i from 1 to 12
                                   collect (list :id (format "c%d" i)
                                                 :status "TODO"
                                                 :summary (format "child %d" i)))))
         (graph (list :tasks (list long-task)
                      :selected-id "p"
                      :files nil))
         (tasks-org-ui-compact-max-lines 4)
         (text (tasks-org-ui--compact-render-text graph)))
    (should text)
    (should (string-match-p "more rows" text))
    (should (= (length (split-string text "\n")) 4))))

(provide 'tasks-org-tests)
;;; tasks-org-tests.el ends here
