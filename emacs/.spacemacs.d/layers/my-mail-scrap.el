  ;; == MAIL / mu4e ==
  ;; (with-eval-after-load 'mu4e
  ;; ;;; Set up some common mu4e variables
  ;;   (setq mu4e-maildir "~/mail"
  ;;     mu4e-trash-folder "/Trash"
  ;;     mu4e-refile-folder "/Archive"
  ;;     mu4e-get-mail-command "mbsync -a"
  ;;     mu4e-update-interval nil
  ;;     mu4e-compose-signature-auto-include nil
  ;;     mu4e-view-show-images t
  ;;     mu4e-view-show-addresses t)

  ;; ;;; Mail directory shortcuts
  ;;   (setq mu4e-maildir-shortcuts
  ;;     '(("/gmail/INBOX" . ?g)
  ;;        ("/nmd/INBOX" . ?c)))

  ;; ;;; Bookmarks
  ;;   (setq mu4e-bookmarks
  ;;     `(("flag:unread AND NOT flag:trashed" "Unread messages" ?u)
  ;;        ("date:today..now" "Today's messages" ?t)
  ;;        ("date:7d..now" "Last 7 days" ?w)
  ;;        ("mime:image/*" "Messages with images" ?p)
  ;;        (,(mapconcat 'identity
  ;;            (mapcar
  ;;              (lambda (maildir)
  ;;                (concat "maildir:" (car maildir)))
  ;;              mu4e-maildir-shortcuts) " OR ")
  ;;          "All inboxes" ?i)))

  ;;   (setq mu4e-contexts
  ;;     `( ,(make-mu4e-context
  ;;           :name "gmail"
  ;;           :enter-func (lambda () (mu4e-message "Switch to the gmail context"))
  ;;           ;; leave-func not defined
  ;;           :match-func (lambda (msg)
  ;;                         (when msg
  ;;                           (string-prefix-p "/gmail" (mu4e-message-field msg :maildir))))
  ;;           :vars '(
  ;;                    ( user-mail-address      . "cormacc@gmail.com"  )
  ;;                    ( user-full-name     . "Cormac Cannon" )
  ;;                    ( mu4e-compose-signature .
  ;;                      (concat
  ;;                        "Cormac Cannon\n"
  ;;                        "\n"))))
  ;;        ,(make-mu4e-context
  ;;           :name "nmd"
  ;;           :enter-func (lambda () (mu4e-message "Switch to the nmd context"))
  ;;           ;; leave-fun not defined
  ;;           :match-func (lambda (msg)
  ;;                         (when msg
  ;;                           (string-prefix-p "/nmd" (mu4e-message-field msg :maildir))))
  ;;           :vars '( ( user-mail-address      . "cormac.cannon@neuromoddevices.com" )
  ;;                    ( user-full-name     . "Cormac Cannon" )
  ;;                    ( mu4e-compose-signature .
  ;;                      (concat
  ;;                        "Cormac Cannon Phd BEng - Software Architect\n"
  ;;                        "Neuromod\n"))))))
  ;;   )
  ;; (with-eval-after-load 'mu4e-alert
  ;;   ;; Enable Desktop notifications
  ;;   (mu4e-alert-set-default-style 'notifications)) ; For linux
  ;; ;; (mu4e-alert-set-default-style 'libnotify))  ; Alternative for linux
