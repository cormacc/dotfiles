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
  )
