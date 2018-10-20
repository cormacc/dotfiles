;;; packages.el --- kivy layer packages file for Spacemacs.
;;
;; Copyright (c) 2012-2018 Sylvain Benner & Contributors
;;
;; Author: Cormac Cannon <cormacc@nmdburger>
;; URL: https://github.com/syl20bnr/spacemacs
;;
;; This file is not part of GNU Emacs.
;;
;;; License: GPLv3

;;; Code:

(defconst kivy-packages
  '(kivy-mode))

(defun kivy/init-kivy-mode ()
  "Initialize kivy-mode."
  (use-package kivy-mode
    :mode "\\.kv$"

    :config (when kivy-indent-on-enter
              (add-hook 'kivy-mode-hook
                '(lambda ()
                   (define-key kivy-mode-map "\C-m" 'newline-and-indent))))))

;;; packages.el ends here
