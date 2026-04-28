;;; tasks-org-tests.el --- Tests for tasks-org -*- lexical-binding: t; -*-

;;; Commentary:

;; Run via:
;;   emacs -Q --batch -L . -l tasks-org-tests.el -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'tasks-org)

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

(provide 'tasks-org-tests)
;;; tasks-org-tests.el ends here
