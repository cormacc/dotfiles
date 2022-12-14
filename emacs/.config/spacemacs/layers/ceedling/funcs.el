(defun ceedling//enable ()
  (dolist (mode c-c++-modes)
    (spacemacs/declare-prefix-for-mode mode "mt" "test")
    (spacemacs/set-leader-keys-for-major-mode mode
      "tb" #'ceedling-test-this-file
      "tc" #'ceedling-clobber-and-test-this-file
      "ta" #'ceedling-test-all
      "td" #'ceedling-test-delta
      "tC" #'ceedling-clobber
      )
    )
  (with-eval-after-load 'projectile
    (projectile-register-project-type 'ceedling '("project.yml")
      :compile "make"
      :test "ceedling"
      :run "ceedling"
      :test-prefix "test_")
    (defun projectile-find-test (file-name)
      "Given a test OR implementation FILE-NAME return the matching test filename.
  Does not create missing test files -- intended for use in test runner command."
      (unless file-name (error "The current buffer is not visiting a file"))
      (if (projectile-test-file-p file-name)
        (projectile-expand-root file-name)
        ;; find the matching test file
        (let ((test-file (projectile-find-matching-test file-name)))
          (if test-file
            (projectile-expand-root test-file)
            (error "No matching test file found for project type `%s'"
              (projectile-project-type)))))))
  )
