(defun ceedling//enable ()
  (dolist (mode c-c++-modes)
    (spacemacs/declare-prefix-for-mode mode "mt" "test")
    (spacemacs/set-leader-keys-for-major-mode mode
      "tt" #'ceedling-run-tests-this-file
      "tT" #'ceedling-clobber-tests-this-file
      "ta" #'ceedling-test-all
      "td" #'ceedling-test-delta
      "tp" #'ceedling-test-project
      "tf" #'ceedling-test-framework
      ;; "tC" #'ceedling-clobber
      )
    )
  )
