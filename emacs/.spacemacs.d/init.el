;; -*- mode: emacs-lisp -*-
;; This file is loaded by Spacemacs at startup.
;; It must be stored in your home directory.

;; TODO: Look at this http://www.clauswitt.com/a-walkthrough-of-my-spacemacs-configuration-files.html

(defun dotspacemacs/layers ()
  "Layer configuration:
This function should only modify configuration layer settings."
  (setq-default
    ;; Base distribution to use. This is a layer contained in the directory
    ;; `+distribution'. For now available distributions are `spacemacs-base'
    ;; or `spacemacs'. (default 'spacemacs)
    dotspacemacs-distribution 'spacemacs
    ;; Lazy installation of layers (i.e. layers are installed only when a file
    ;; with a supported type is opened). Possible values are `all', `unused'
    ;; and `nil'. `unused' will lazy install only unused layers (i.e. layers
    ;; not listed in variable `dotspacemacs-configuration-layers'), `all' will
    ;; lazy install any layer that support lazy installation even the layers
    ;; listed in `dotspacemacs-configuration-layers'. `nil' disable the lazy
    ;; installation feature and you have to explicitly list a layer in the
    ;; variable `dotspacemacs-configuration-layers' to install it.
    ;; (default 'unused)
    dotspacemacs-enable-lazy-installation 'unused
    ;; If non-nil then Spacemacs will ask for confirmation before installing
    ;; a layer lazily. (default t)
    dotspacemacs-ask-for-lazy-installation t
    ;; If non-nil layers with lazy install support are lazy installed.
    ;; List of additional paths where to look for configuration layers.
    ;; Paths must have a trailing slash (i.e. `~/.mycontribs/')
    dotspacemacs-configuration-layer-path '()
    ;; List of configuration layers to load.
    dotspacemacs-configuration-layers
    '(
       ;;extra-langs
       ;;vimscript
       ;; ----------------------------------------------------------------
       ;; Example of useful layers you may want to use right away.
       ;; Uncomment some layer names and press `SPC f e R' (Vim style) or
       ;; `M-m f e R' (Emacs style) to install them.
       ;; ----------------------------------------------------------------
                                        ;asm
       (auto-completion :variables
         auto-completion-enable-snippets-in-popup t
         auto-completion-enable-help-tooltip t
         )
                                        ;better-defaults not relevant when using evil-mode key bindings
                                        ;better-defaults
       (c-c++ :variables
         c-c++-enable-clang-support t
         c-c++-enable-rtags-support t
         )
       (cmake :variables
         c-c++-enable-cmake-ide-support t
         )
                                        ;clojure
       (colors :variables
         colors-enable-nyan-cat-progress-bar t
         nyan-bar-length 8)
                                        ;Use OR cscope?
                                        ;cscope
       csv
       chrome
       dash
       deft
       emacs-lisp
       git
       (go :variables gofmt-command "goimports")
       html
       (ibuffer :variables ibuffer-group-buffers-by 'projects)
                                        ;Try helm instead, as counsel search replace appears broken
       ivy
       (javascript :variables node-add-modules-path t)
       (markdown :variables markdown-live-preview-engine 'vmd)
       ;; (mu4e :variables
       ;;   mu4e-enable-notifications t
       ;;   mu4e-enable-mode-line t
       ;;   )
       ;neotree
       notmuch
       octave
       ;;http://spacemacs.org/layers/+emacs/org/README.html
       (org :variables
         org-enable-hugo-support t
         org-enable-github-support t
         org-enable-reveal-js-support t)
       pandoc
       plantuml
       python
       racket
       (ranger :variables
         ranger-show-preview t
         ranger-cleanup-on-disable t
         ranger-show-dotfiles t)
       (ruby :variables
         ruby-test-runner 'rspec
         ;; ruby-version-manager 'rbenv
         ;; ruby-enable-enh-ruby-mode t
         )
                                        ;scheme
       rust
       search-engine
       ;;'semantic' used by cmode for refactoring support
       semantic
       (shell :variables
         shell-default-shell 'multi-term
         shell-default-term-shell "/bin/zsh"
         shell-default-height 30
         shell-default-position 'bottom)

       shell-scripts
       spell-checking
       syntax-checking
       systemd
       treemacs
       version-control
       windows-scripts
       ;; (version-control :variables
       ;;                  version-control-diff-tool 'git-gutter
       ;;                  version-control-global-margin t)
       yaml
       ;; YCMD is an auto-completion backend
                                        ycmd
       )
    ;; List of additional packages that will be installed without being
    ;; wrapped in a layer. If you need some configuration for these
    ;; packages, then consider creating a layer. You can also put the
    ;; configuration in `dotspacemacs/user-config'.
    dotspacemacs-additional-packages '()
    ;; A list of packages that cannot be updated.
    dotspacemacs-frozen-packages '()
    ;; A list of packages that will not be installed and loaded.
    dotspacemacs-excluded-packages '()
    ;; Defines the behaviour of Spacemacs when installing packages.
    ;; Possible values are `used-only', `used-but-keep-unused' and `all'.
    ;; `used-only' installs only explicitly used packages and deletes any unused
    ;; packages as well as their unused dependencies. `used-but-keep-unused'
    ;; installs only the used packages but won't delete unused ones. `all'
    ;; installs *all* packages supported by Spacemacs and never uninstalls them.
    ;; (default is `used-only')
    dotspacemacs-install-packages 'used-only))

(defun dotspacemacs/init ()
  "Initialization:
This function is called at the very beginning of Spacemacs startup,
before layer configuration.
It should only modify the values of Spacemacs settings."
  ;; This setq-default sexp is an exhaustive list of all the supported
  ;; spacemacs settings.
  (setq-default
    ;; If non-nil ELPA repositories are contacted via HTTPS whenever it's
    ;; possible. Set it to nil if you have no way to use HTTPS in your
    ;; environment, otherwise it is strongly recommended to let it set to t.
    ;; This variable has no effect if Emacs is launched with the parameter
    ;; `--insecure' which forces the value of this variable to nil.
    ;; (default t)
    dotspacemacs-elpa-https t
    ;; Maximum allowed time in seconds to contact an ELPA repository.
    ;; (default 5)
    dotspacemacs-elpa-timeout 70
    ;; If non-nil then verify the signature for downloaded Spacelpa archives.
    ;; (default nil)
    dotspacemacs-verify-spacelpa-archives nil
    ;; If non-nil then spacemacs will check for updates at startup
    ;; when the current branch is not `develop'. Note that checking for
    ;; new versions works via git commands, thus it calls GitHub services
    ;; whenever you start Emacs. (default nil)
    dotspacemacs-check-for-update t
    ;; If non-nil, a form that evaluates to a package directory. For example, to
    ;; use different package directories for different Emacs versions, set this
    ;; to `emacs-version'. (default 'emacs-version)
    dotspacemacs-elpa-subdirectory 'emacs-version
    ;; One of `vim', `emacs' or `hybrid'.
    ;; `hybrid' is like `vim' except that `insert state' is replaced by the
    ;; `hybrid state' with `emacs' key bindings. The value can also be a list
    ;; with `:variables' keyword (similar to layers). Check the editing styles
    ;; section of the documentation for details on available variables.
    ;; (default 'vim)
    dotspacemacs-editing-style 'vim
    ;; If non-nil output loading progress in `*Messages*' buffer. (default nil)
    dotspacemacs-verbose-loading nil
    ;; Specify the startup banner. Default value is `official', it displays
    ;; the official spacemacs logo. An integer value is the index of text
    ;; banner, `random' chooses a random text banner in `core/banners'
    ;; directory. A string value must be a path to an image format supported
    ;; by your Emacs build.
    ;; If the value is nil then no banner is displayed. (default 'official)
    dotspacemacs-startup-banner 'official
    ;; List of items to show in startup buffer or an association list of
    ;; the form `(list-type . list-size)`. If nil then it is disabled.
    ;; Possible values for list-type are:
    ;; `recents' `bookmarks' `projects' `agenda' `todos'.
    ;; List sizes may be nil, in which case
    ;; `spacemacs-buffer-startup-lists-length' takes effect.
    dotspacemacs-startup-lists '((recents . 5)
                        (projects . 7))
    ;; True if the home buffer should respond to resize events. (default t)
    dotspacemacs-startup-buffer-responsive t
    ;; Default major mode of the scratch buffer (default `text-mode')
    dotspacemacs-scratch-mode 'text-mode
    ;; List of themes, the first of the list is loaded when spacemacs starts.
    ;; Press `SPC T n' to cycle to the next theme in the list (works great
    ;; with 2 themes variants, one dark and one light)
    dotspacemacs-themes '(doom-one
                 spacemacs-dark
                 solarized-dark
                 misterioso
                 leuven
                 monokai
                 zenburn)
    ;; If non nil the cursor color matches the state color in GUI Emacs.
    dotspacemacs-colorize-cursor-according-to-state t
    ;; Default font, or prioritized list of fonts. `powerline-scale' allows to
    ;; quickly tweak the mode-line size to make separators look not too crappy.
    dotspacemacs-default-font '("Source Code Pro"
                       :size 22
                       :weight normal
                       :width normal
                       :powerline-scale 1.0)
    ;; The leader key
    dotspacemacs-leader-key "SPC"
    ;; The key used for Emacs commands `M-x' (after pressing on the leader key).
    ;; (default "SPC")
    dotspacemacs-emacs-command-key "SPC"
    ;; The key used for Vim Ex commands (default ":")
    dotspacemacs-ex-command-key ":"
    ;; The leader key accessible in `emacs state' and `insert state'
    ;; (default "M-m")
    dotspacemacs-emacs-leader-key "M-m"
    ;; Major mode leader key is a shortcut key which is the equivalent of
    ;; pressing `<leader> m`. Set it to `nil` to disable it. (default ",")
    dotspacemacs-major-mode-leader-key ","
    ;; Major mode leader key accessible in `emacs state' and `insert state'.
    ;; (default "C-M-m")
    dotspacemacs-major-mode-emacs-leader-key "C-M-m"
    ;; These variables control whether separate commands are bound in the GUI to
    ;; the key pairs `C-i', `TAB' and `C-m', `RET'.
    ;; Setting it to a non-nil value, allows for separate commands under `C-i'
    ;; and TAB or `C-m' and `RET'.
    ;; In the terminal, these pairs are generally indistinguishable, so this only
    ;; works in the GUI. (default nil)
    dotspacemacs-distinguish-gui-tab nil
    ;; If non-nil `Y' is remapped to `y$' in Evil states. (default nil)
    dotspacemacs-remap-Y-to-y$ nil
    ;; If non-nil, the shift mappings `<' and `>' retain visual state if used
    ;; there. (default t)
    dotspacemacs-retain-visual-state-on-shift t
    ;; If non-nil, `J' and `K' move lines up and down when in visual mode.
    ;; (default nil)
    dotspacemacs-visual-line-move-text t
    ;; If non nil, inverse the meaning of `g' in `:substitute' Evil ex-command.
    ;; (default nil)
    dotspacemacs-ex-substitute-global nil
    ;; Name of the default layout (default "Default")
    dotspacemacs-default-layout-name "Default"
    ;; If non-nil the default layout name is displayed in the mode-line.
    ;; (default nil)
    dotspacemacs-display-default-layout nil
    ;; If non-nil then the last auto saved layouts are resumed automatically upon
    ;; start. (default nil)
    dotspacemacs-auto-resume-layouts nil
    ;; If non-nil, auto-generate layout name when creating new layouts. Only has
    ;; effect when using the "jump to layout by number" commands. (default nil)
    dotspacemacs-auto-generate-layout-names nil
    ;; Size (in MB) above which spacemacs will prompt to open the large file
    ;; literally to avoid performance issues. Opening a file literally means that
    ;; no major mode or minor modes are active. (default is 1)
    dotspacemacs-large-file-size 1
    ;; Location where to auto-save files. Possible values are `original' to
    ;; auto-save the file in-place, `cache' to auto-save the file to another
    ;; file stored in the cache directory and `nil' to disable auto-saving.
    ;; (default 'cache)
    dotspacemacs-auto-save-file-location 'cache
    ;; Maximum number of rollback slots to keep in the cache. (default 5)
    dotspacemacs-max-rollback-slots 5
    ;; If non-nil, `helm' will try to minimize the space it uses. (default nil)
    dotspacemacs-helm-resize nil
    ;; if non-nil, the helm header is hidden when there is only one source.
    ;; (default nil)
    dotspacemacs-helm-no-header nil
    ;; define the position to display `helm', options are `bottom', `top',
    ;; `left', or `right'. (default 'bottom)
    dotspacemacs-helm-position 'bottom
    ;; Controls fuzzy matching in helm. If set to `always', force fuzzy matching
    ;; in all non-asynchronous sources. If set to `source', preserve individual
    ;; source settings. Else, disable fuzzy matching in all sources.
    ;; (default 'always)
    dotspacemacs-helm-use-fuzzy 'always
    ;; If non-nil, the paste transient-state is enabled. While enabled, pressing
    ;; `p' several times cycles through the elements in the `kill-ring'.
    ;; (default nil)
    dotspacemacs-enable-paste-transient-state nil
    ;; Which-key delay in seconds. The which-key buffer is the popup listing
    ;; the commands bound to the current keystroke sequence. (default 0.4)
    dotspacemacs-which-key-delay 0.4
    ;; Which-key frame position. Possible values are `right', `bottom' and
    ;; `right-then-bottom'. right-then-bottom tries to display the frame to the
    ;; right; if there is insufficient space it displays it at the bottom.
    ;; (default 'bottom)
    dotspacemacs-which-key-position 'bottom
    ;; Control where `switch-to-buffer' displays the buffer. If nil,
    ;; `switch-to-buffer' displays the buffer in the current window even if
    ;; another same-purpose window is available. If non-nil, `switch-to-buffer'
    ;; displays the buffer in a same-purpose window even if the buffer can be
    ;; displayed in the current window. (default nil)
    dotspacemacs-switch-to-buffer-prefers-purpose nil
    ;; If non-nil a progress bar is displayed when spacemacs is loading. This
    ;; may increase the boot time on some systems and emacs builds, set it to
    ;; nil to boost the loading time. (default t)
    dotspacemacs-loading-progress-bar t
    ;; If non-nil the frame is fullscreen when Emacs starts up. (default nil)
    ;; (Emacs 24.4+ only)
    dotspacemacs-fullscreen-at-startup nil
    ;; If non-nil `spacemacs/toggle-fullscreen' will not use native fullscreen.
    ;; Use to disable fullscreen animations in OSX. (default nil)
    dotspacemacs-fullscreen-use-non-native nil
    ;; If non-nil the frame is maximized when Emacs starts up.
    ;; Takes effect only if `dotspacemacs-fullscreen-at-startup' is nil.
    ;; (default nil) (Emacs 24.4+ only)
    dotspacemacs-maximized-at-startup nil
    ;; A value from the range (0..100), in increasing opacity, which describes
    ;; the transparency level of a frame when it's active or selected.
    ;; Transparency can be toggled through `toggle-transparency'. (default 90)
    dotspacemacs-active-transparency 90
    ;; A value from the range (0..100), in increasing opacity, which describes
    ;; the transparency level of a frame when it's inactive or deselected.
    ;; Transparency can be toggled through `toggle-transparency'. (default 90)
    dotspacemacs-inactive-transparency 90
    ;; If non-nil show the titles of transient states. (default t)
    dotspacemacs-show-transient-state-title t
    ;; If non-nil show the color guide hint for transient state keys. (default t)
    dotspacemacs-show-transient-state-color-guide t
    ;; If non-nil unicode symbols are displayed in the mode line. (default t)
    dotspacemacs-mode-line-unicode-symbols t
    ;; If non-nil smooth scrolling (native-scrolling) is enabled. Smooth
    ;; scrolling overrides the default behavior of Emacs which recenters point
    ;; when it reaches the top or bottom of the screen. (default t)
    dotspacemacs-smooth-scrolling t
    ;; Control line numbers activation.
    ;; If set to `t' or `relative' line numbers are turned on in all `prog-mode' and
    ;; `text-mode' derivatives. If set to `relative', line numbers are relative.
    ;; This variable can also be set to a property list for finer control:
    ;; '(:relative nil
    ;;   :disabled-for-modes dired-mode
    ;;                       doc-view-mode
    ;;                       markdown-mode
    ;;                       org-mode
    ;;                       pdf-view-mode
    ;;                       text-mode
    ;;   :size-limit-kb 1000)
    ;; (default nil)
    dotspacemacs-line-numbers nil
    ;; Code folding method. Possible values are `evil' and `origami'.
    ;; (default 'evil)
    dotspacemacs-folding-method 'evil
    ;; If non-nil `smartparens-strict-mode' will be enabled in programming modes.
    ;; (default nil)
    dotspacemacs-smartparens-strict-mode nil
    ;; If non-nil pressing the closing parenthesis `)' key in insert mode passes
    ;; over any automatically added closing parenthesis, bracket, quote, etc…
    ;; This can be temporary disabled by pressing `C-q' before `)'. (default nil)
    dotspacemacs-smart-closing-parenthesis nil
    ;; Select a scope to highlight delimiters. Possible values are `any',
    ;; `current', `all' or `nil'. Default is `all' (highlight any scope and
    ;; emphasis the current one). (default 'all)
    dotspacemacs-highlight-delimiters 'all
    ;; If non-nil, advise quit functions to keep server open when quitting.
    ;; (default nil)
    dotspacemacs-persistent-server nil
    ;; List of search tool executable names. Spacemacs uses the first installed
    ;; tool of the list. Supported tools are `rg', `ag', `pt', `ack' and `grep'.
    ;; (default '("rg" "ag" "pt" "ack" "grep"))
    dotspacemacs-search-tools '("rg" "ag" "pt" "ack" "grep")
    ;; The default package repository used if no explicit repository has been
    ;; specified with an installed package.
    ;; Not used for now. (default nil)
    dotspacemacs-default-package-repository nil
    ;; Format specification for setting the frame title.
    ;; %a - the `abbreviated-file-name', or `buffer-name'
    ;; %t - `projectile-project-name'
    ;; %I - `invocation-name'
    ;; %S - `system-name'
    ;; %U - contents of $USER
    ;; %b - buffer name
    ;; %f - visited file name
    ;; %F - frame name
    ;; %s - process status
    ;; %p - percent of buffer above top of window, or Top, Bot or All
    ;; %P - percent of buffer above bottom of window, perhaps plus Top, or Bot or All
    ;; %m - mode name
    ;; %n - Narrow if appropriate
    ;; %z - mnemonics of buffer, terminal, and keyboard coding systems
    ;; %Z - like %z, but including the end-of-line format
    ;; (default "%I@%S")
    dotspacemacs-frame-title-format "%I@%S"
    ;; Format specification for setting the icon title format
    ;; (default nil - same as frame-title-format)
    dotspacemacs-icon-title-format nil
    ;; Delete whitespace while saving buffer. Possible values are `all'
    ;; to aggressively delete empty line and long sequences of whitespace,
    ;; `trailing' to delete only the whitespace at end of lines, `changed' to
    ;; delete only whitespace for changed lines or `nil' to disable cleanup.
    ;; (default nil)
    dotspacemacs-whitespace-cleanup 'all
    ;; Either nil or a number of seconds. If non-nil zone out after the specified
    ;; number of seconds. (default nil)
    dotspacemacs-zone-out-when-idle nil
    ;; Run `spacemacs/prettify-org-buffer' when
    ;; visiting README.org files of Spacemacs.
    ;; (default nil)
    dotspacemacs-pretty-docs nil
    ))

(defun dotspacemacs/user-init ()
  "Initialization for user code:
This function is called immediately after `dotspacemacs/init', before layer
configuration.
It is mostly for variables that should be set before packages are loaded.
If you are unsure, try setting them in `dotspacemacs/user-config' first."

  ;; Disable Spacelpa (due to transient issue with cmake-ide package)
  (setq configuration-layer-elpa-archives '(("melpa" . "melpa.org/packages/")
                                            ("org" . "orgmode.org/elpa/")
                                            ("gnu" . "elpa.gnu.org/packages/")))

  (setq tramp-default-method "ssh")
  (setq tramp-password-prompt-regexp
    "^.*\\([pP]assword\\|[pP]assphrase\\|Verification code\\).*:? *")
  (setq tramp-ssh-controlmaster-options
    (concat
      "-o ControlPath=~/.ssh/%%r@%%h:%%p"))
  (push "/usr/share/emacs/site-lisp/rtags" load-path)
  )

(defun dotspacemacs/user-config ()
  "Configuration for user code:
This function is called at the very end of Spacemacs startup, after layer
configuration.
Put your configuration code here, except for variables that should be set
before packages are loaded."
  ;; (define-key global-map (kbd "C-+") 'text-scale-increase)
  ;; (define-key global-map (kbd "C--") 'text-scale-decrease)

  ;; C-mode stuff
  ;; This next line may be redundant with recent integration of cmake support into c/c++ layer
  ;; (add-to-list 'auto-mode-alist '("CMake.+\\.txt\\'" . cmake-mode))
  ;; (setq confirm-nonexistent-file-or-buffer nil)
  (c-add-style "cormacc"
    '((indent-tabs-mode . nil)
       (c-basic-offset . 2)
       (c-offsets-alist
         (substatement-open . 0)
         (inline-open . 0)
         (statement-cont . c-lineup-assignments)
         (inextern-lang . 0)
         (innamespace . 0))))
  (push '(other . "cormacc") c-default-style)
  (setq ycmd-server-command (list "python" (file-truename "~/dev/tools/ycmd/ycmd")))
  (setq cmake-ide-build-pool-dir (file-truename "~/.cmake_builds"))
  (setq cmake-ide-build-pool-use-persistent-naming t)
;  (setq ycmd-extra-conf-whitelist '("~/dev/*"
;                                     "~/nmd/*"
;                                     "~/nextcloud/*"))

  ;; Add a custom project type for embedded C projects using our state framework....
  (with-eval-after-load 'projectile
    (projectile-register-project-type 'nmd '("framework.project")
      :compile "make"
      :test "rake"
      :run "rake"
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
              (projectile-project-type))))))
    )

                                        ;MAIL / mu4e
  (with-eval-after-load 'mu4e
  ;;; Set up some common mu4e variables
    (setq mu4e-maildir "~/mail"
      mu4e-trash-folder "/Trash"
      mu4e-refile-folder "/Archive"
      mu4e-get-mail-command "mbsync -a"
      mu4e-update-interval nil
      mu4e-compose-signature-auto-include nil
      mu4e-view-show-images t
      mu4e-view-show-addresses t)

  ;;; Mail directory shortcuts
    (setq mu4e-maildir-shortcuts
      '(("/gmail/INBOX" . ?g)
         ("/nmd/INBOX" . ?c)))

  ;;; Bookmarks
    (setq mu4e-bookmarks
      `(("flag:unread AND NOT flag:trashed" "Unread messages" ?u)
         ("date:today..now" "Today's messages" ?t)
         ("date:7d..now" "Last 7 days" ?w)
         ("mime:image/*" "Messages with images" ?p)
         (,(mapconcat 'identity
             (mapcar
               (lambda (maildir)
                 (concat "maildir:" (car maildir)))
               mu4e-maildir-shortcuts) " OR ")
           "All inboxes" ?i)))

    (setq mu4e-contexts
      `( ,(make-mu4e-context
            :name "gmail"
            :enter-func (lambda () (mu4e-message "Switch to the gmail context"))
            ;; leave-func not defined
            :match-func (lambda (msg)
                          (when msg
                            (string-prefix-p "/gmail" (mu4e-message-field msg :maildir))))
            :vars '(
                     ( user-mail-address      . "cormacc@gmail.com"  )
                     ( user-full-name     . "Cormac Cannon" )
                     ( mu4e-compose-signature .
                       (concat
                         "Cormac Cannon\n"
                         "\n"))))
         ,(make-mu4e-context
            :name "nmd"
            :enter-func (lambda () (mu4e-message "Switch to the nmd context"))
            ;; leave-fun not defined
            :match-func (lambda (msg)
                          (when msg
                            (string-prefix-p "/nmd" (mu4e-message-field msg :maildir))))
            :vars '( ( user-mail-address      . "cormac.cannon@neuromoddevices.com" )
                     ( user-full-name     . "Cormac Cannon" )
                     ( mu4e-compose-signature .
                       (concat
                         "Cormac Cannon Phd BEng - Software Architect\n"
                         "Neuromod\n"))))))
    )
  (with-eval-after-load 'mu4e-alert
    ;; Enable Desktop notifications
    (mu4e-alert-set-default-style 'notifications)) ; For linux
  ;; (mu4e-alert-set-default-style 'libnotify))  ; Alternative for linux

  ;; This series is taken from this SO answer regarding automatic reload of dir-locals on save
  ;;https://emacs.stackexchange.com/questions/13080/reloading-directory-local-variables
  (defun dir-locals-reload-for-current-buffer ()
    "reload dir locals for the current buffer"
    (interactive)
    (let ((enable-local-variables :all))
      (hack-dir-local-variables-non-file-buffer)))
  (defun dir-locals-reload-for-all-buffers-in-this-directory ()
    "For every buffer with the same `default-directory` as the current buffer's, reload dir-locals."
    (interactive)
    (let ((dir default-directory))
      (dolist (buffer (buffer-list))
        (with-current-buffer buffer
          (when (equal default-directory dir))
          (dir-locals-reload-for-current-buffer)))))
  (add-hook 'emacs-lisp-mode-hook
    (defun dir-locals-enable-autoreload ()
      (when (and (buffer-file-name)
              (equal dir-locals-file
                (file-name-nondirectory (buffer-file-name))))
        (add-hook (make-variable-buffer-local 'after-save-hook)
          'dir-locals-reload-for-all-buffers-in-this-directory))))

  (setq deft-directory "~/notes")
  (setq deft-recursive t)

  ;;Org-babel
  (with-eval-after-load 'org
    (setq org-confirm-babel-evaluate nil
      org-src-fontify-natively t
      org-src-tab-acts-natively t
      org-startup-folded nil)
    (require 'ob-ruby)
    (org-babel-do-load-languages
      'org-babel-load-languages
      '((ruby . t)
         (shell . t)
         )
      )
    ;; todo keywords
    (setq org-todo-keywords
      (quote ((sequence "TODO(t)" "|" "DONE(d)")
               (sequence "TASK(t)" "MAYBE(m)" "NEXT(n)" "WAITING(w)" "|" "CANCELLED(c)" "FINISHED"))))
    (setq org-use-sub-superscripts "{}")
    (setq org-export-with-sub-superscripts "{}")
    (defun toggle-org-html-export-on-save ()
      (interactive)
      (if (memq 'org-html-export-to-html after-save-hook)
        (progn
          (remove-hook 'after-save-hook 'org-html-export-to-html t)
          (message "Disabled org html export on save for current buffer..."))
        (add-hook 'after-save-hook 'org-html-export-to-html nil t)
        (message "Enabled org html export on save for current buffer...")))
    )
  ;; (with-eval-after-load 'org-agenda
  ;;   (require 'org-projectile)
  ;;   ;;(org-projectile:per-repo)
  ;;   (push (org-projectile:todo-files) org-agenda-files))

  ;; PlantUML -- extension supports only .pum by default
  (setq plantuml-jar-path "/opt/plantuml/plantuml.jar")
  (add-to-list 'auto-mode-alist '(".+\\.puml\\'" . plantuml-mode))

  ;; Work around bug #7038
  ;; https://github.com/syl20bnr/spacemacs/issues/7038
  ;; (eval-after-load 'semantic
  ;;   (add-hook 'semantic-mode-hook
  ;;             (lambda ()
  ;;               (dolist (x (default-value 'completion-at-point-functions))
  ;;                 (when (string-prefix-p "semantic-" (symbol-name x))
  ;;                   (remove-hook 'completion-at-point-functions x))))))
  ;; Work around octave mod issue
  (eval-after-load 'octave
    (setq octave-mode-hook
      (lambda () (progn (setq octave-comment-char ?%)
                   (setq comment-start "%")
                   (setq indent-tabs-mode nil)
                   (setq comment-add 0)
                   (setq tab-width 2)
                   (setq tab-stop-list (number-sequence 2 200 2))
                   (setq octave-block-offset 2)

                   (defun octave-indent-comment ()
                     "A function for `smie-indent-functions' (which see)."
                     (save-excursion
                       (back-to-indentation)
                       (cond
                         ((octave-in-string-or-comment-p) nil)
                         ((looking-at-p "\\(\\s<\\)\\1\\{2,\\}") 0)))))))
    )
  )


;; Do not write anything past this comment. This is where Emacs will
;; auto-generate custom variable definitions.
(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(ansi-color-faces-vector
   [default default default italic underline success warning error])
 '(ansi-color-names-vector
   ["#d2ceda" "#f2241f" "#67b11d" "#b1951d" "#3a81c3" "#a31db1" "#21b8c7" "#655370"])
 '(compilation-message-face (quote default))
 '(cua-global-mark-cursor-color "#2aa198")
 '(cua-normal-cursor-color "#839496")
 '(cua-overwrite-cursor-color "#b58900")
 '(cua-read-only-cursor-color "#859900")
 '(evil-want-Y-yank-to-eol nil)
 '(highlight-changes-colors (quote ("#FD5FF0" "#AE81FF")))
 '(highlight-symbol-colors
   (--map
    (solarized-color-blend it "#002b36" 0.25)
    (quote
     ("#b58900" "#2aa198" "#dc322f" "#6c71c4" "#859900" "#cb4b16" "#268bd2"))))
 '(highlight-symbol-foreground-color "#93a1a1")
 '(highlight-tail-colors
   (quote
    (("#3C3D37" . 0)
     ("#679A01" . 20)
     ("#4BBEAE" . 30)
     ("#1DB4D0" . 50)
     ("#9A8F21" . 60)
     ("#A75B00" . 70)
     ("#F309DF" . 85)
     ("#3C3D37" . 100))))
 '(hl-bg-colors
   (quote
    ("#7B6000" "#8B2C02" "#990A1B" "#93115C" "#3F4D91" "#00629D" "#00736F" "#546E00")))
 '(hl-fg-colors
   (quote
    ("#002b36" "#002b36" "#002b36" "#002b36" "#002b36" "#002b36" "#002b36" "#002b36")))
 '(magit-diff-use-overlays nil)
 '(nrepl-message-colors
   (quote
    ("#dc322f" "#cb4b16" "#b58900" "#546E00" "#B4C342" "#00629D" "#2aa198" "#d33682" "#6c71c4")))
 '(package-selected-packages
   (quote
    (zeal-at-point systemd org-mime ibuffer-projectile gmail-message-mode ham-mode html-to-markdown flymd flycheck-ycmd ghub edit-server counsel-dash helm-dash company-ycmd ycmd request-deferred let-alist deferred doom-themes parent-mode gitignore-mode fringe-helper git-gutter+ pos-tip flx goto-chg diminish pkg-info epl popup org-category-capture racket-mode faceup toml-mode racer flycheck-rust cargo rust-mode csv-mode enh-ruby-mode gntp deft wolfram-mode thrift stan-mode scad-mode qml-mode matlab-mode julia-mode arduino-mode yapfify pyvenv pytest pyenv-mode py-isort pip-requirements live-py-mode hy-mode cython-mode company-anaconda anaconda-mode pythonic company-irony irony winum unfill fuzzy avy log4e powershell evil plantuml-mode clojure-snippets clj-refactor inflections edn paredit peg cider-eval-sexp-fu cider seq queue clojure-mode packed epresent web-beautify livid-mode skewer-mode simple-httpd json-mode json-snatcher json-reformat js2-refactor multiple-cursors js2-mode js-doc company-tern dash-functional tern coffee-mode alert ox-reveal pandoc-mode ox-pandoc ht helm-gtags helm-css-scss helm-cscope zenburn-theme monokai-theme solarized-theme powerline request spinner bind-key bind-map pcre2el vimrc-mode dactyl-mode ox-gfm xcscope x86-lookup stickyfunc-enhance srefactor rainbow-mode rainbow-identifiers quack nasm-mode key-chord ggtags geiser fiplr grizzl find-file-in-project engine-mode dired-subtree dired-narrow dired-hacks-utils color-identifiers-mode vmd-mode web-mode tagedit slim-mode scss-mode sass-mode pug-mode less-css-mode haml-mode emmet-mode company-web web-completion-data pcache git-gutter iedit go-mode yasnippet auto-complete inf-ruby company highlight anzu smartparens undo-tree flycheck projectile helm helm-core hydra markdown-mode magit magit-popup async dash s ranger go-guru git-commit with-editor org minitest insert-shebang hide-comnt fish-mode company-shell rtags cmake-ide levenshtein yaml-mode wgrep smex ivy-hydra flyspell-correct-ivy counsel-projectile counsel swiper ivy uuidgen rake org-projectile org-download mwim link-hint git-link flyspell-correct-helm flyspell-correct eyebrowse evil-visual-mark-mode evil-unimpaired evil-ediff eshell-z dumb-jump f column-enforce-mode xterm-color ws-butler window-numbering which-key volatile-highlights vi-tilde-fringe use-package toc-org spacemacs-theme spaceline smooth-scrolling smeargle shell-pop rvm ruby-tools ruby-test-mode rubocop rspec-mode robe restart-emacs rbenv rainbow-delimiters quelpa popwin persp-mode paradox page-break-lines orgit org-repo-todo org-present org-pomodoro org-plus-contrib org-bullets open-junk-file neotree multi-term move-text mmm-mode markdown-toc magit-gitflow macrostep lorem-ipsum linum-relative leuven-theme info+ indent-guide ido-vertical-mode hungry-delete htmlize hl-todo highlight-parentheses highlight-numbers highlight-indentation help-fns+ helm-themes helm-swoop helm-projectile helm-mode-manager helm-make helm-gitignore helm-flyspell helm-flx helm-descbinds helm-company helm-c-yasnippet helm-ag google-translate golden-ratio go-eldoc gnuplot gitconfig-mode gitattributes-mode git-timemachine git-messenger git-gutter-fringe git-gutter-fringe+ gh-md flycheck-pos-tip flx-ido fill-column-indicator fancy-battery expand-region exec-path-from-shell evil-visualstar evil-tutor evil-surround evil-search-highlight-persist evil-numbers evil-nerd-commenter evil-mc evil-matchit evil-magit evil-lisp-state evil-indent-plus evil-iedit-state evil-exchange evil-escape evil-args evil-anzu eval-sexp-fu eshell-prompt-extras esh-help elisp-slime-nav disaster diff-hl define-word company-statistics company-quickhelp company-go company-c-headers cmake-mode clean-aindent-mode clang-format chruby bundler buffer-move bracketed-paste auto-yasnippet auto-highlight-symbol auto-dictionary auto-compile aggressive-indent adaptive-wrap ace-window ace-link ace-jump-helm-line ac-ispell)))
 '(pos-tip-background-color "#A6E22E")
 '(pos-tip-foreground-color "#272822")
 '(smartrep-mode-line-active-bg (solarized-color-blend "#859900" "#073642" 0.2))
 '(term-default-bg-color "#002b36")
 '(term-default-fg-color "#839496")
 '(vc-annotate-background nil)
 '(vc-annotate-background-mode nil)
 '(vc-annotate-color-map
   (quote
    ((20 . "#F92672")
     (40 . "#CF4F1F")
     (60 . "#C26C0F")
     (80 . "#E6DB74")
     (100 . "#AB8C00")
     (120 . "#A18F00")
     (140 . "#989200")
     (160 . "#8E9500")
     (180 . "#A6E22E")
     (200 . "#729A1E")
     (220 . "#609C3C")
     (240 . "#4E9D5B")
     (260 . "#3C9F79")
     (280 . "#A1EFE4")
     (300 . "#299BA6")
     (320 . "#2896B5")
     (340 . "#2790C3")
     (360 . "#66D9EF"))))
 '(vc-annotate-very-old-color nil)
 '(weechat-color-list
   (unspecified "#272822" "#3C3D37" "#F70057" "#F92672" "#86C30D" "#A6E22E" "#BEB244" "#E6DB74" "#40CAE4" "#66D9EF" "#FB35EA" "#FD5FF0" "#74DBCD" "#A1EFE4" "#F8F8F2" "#F8F8F0"))
 '(xterm-color-names
   ["#073642" "#dc322f" "#859900" "#b58900" "#268bd2" "#d33682" "#2aa198" "#eee8d5"])
 '(xterm-color-names-bright
   ["#002b36" "#cb4b16" "#586e75" "#657b83" "#839496" "#6c71c4" "#93a1a1" "#fdf6e3"]))
(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 )
(defun dotspacemacs/emacs-custom-settings ()
  "Emacs custom settings.
This is an auto-generated function, do not modify its content directly, use
Emacs customize menu instead.
This function is called at the very end of Spacemacs initialization."
(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(ansi-color-faces-vector
   [default default default italic underline success warning error])
 '(ansi-color-names-vector
   ["#d2ceda" "#f2241f" "#67b11d" "#b1951d" "#3a81c3" "#a31db1" "#21b8c7" "#655370"])
 '(compilation-message-face (quote default))
 '(cua-global-mark-cursor-color "#2aa198")
 '(cua-normal-cursor-color "#839496")
 '(cua-overwrite-cursor-color "#b58900")
 '(cua-read-only-cursor-color "#859900")
 '(evil-want-Y-yank-to-eol nil)
 '(highlight-changes-colors (quote ("#FD5FF0" "#AE81FF")))
 '(highlight-symbol-colors
   (--map
    (solarized-color-blend it "#002b36" 0.25)
    (quote
     ("#b58900" "#2aa198" "#dc322f" "#6c71c4" "#859900" "#cb4b16" "#268bd2"))))
 '(highlight-symbol-foreground-color "#93a1a1")
 '(highlight-tail-colors
   (quote
    (("#3C3D37" . 0)
     ("#679A01" . 20)
     ("#4BBEAE" . 30)
     ("#1DB4D0" . 50)
     ("#9A8F21" . 60)
     ("#A75B00" . 70)
     ("#F309DF" . 85)
     ("#3C3D37" . 100))))
 '(hl-bg-colors
   (quote
    ("#7B6000" "#8B2C02" "#990A1B" "#93115C" "#3F4D91" "#00629D" "#00736F" "#546E00")))
 '(hl-fg-colors
   (quote
    ("#002b36" "#002b36" "#002b36" "#002b36" "#002b36" "#002b36" "#002b36" "#002b36")))
 '(magit-diff-use-overlays nil)
 '(nrepl-message-colors
   (quote
    ("#dc322f" "#cb4b16" "#b58900" "#546E00" "#B4C342" "#00629D" "#2aa198" "#d33682" "#6c71c4")))
 '(package-selected-packages
   (quote
    (all-the-icons font-lock+ zeal-at-point systemd org-mime ibuffer-projectile gmail-message-mode ham-mode html-to-markdown flymd flycheck-ycmd ghub edit-server counsel-dash helm-dash company-ycmd ycmd request-deferred let-alist deferred doom-themes parent-mode gitignore-mode fringe-helper git-gutter+ pos-tip flx goto-chg diminish pkg-info epl popup org-category-capture racket-mode faceup toml-mode racer flycheck-rust cargo rust-mode csv-mode enh-ruby-mode gntp deft wolfram-mode thrift stan-mode scad-mode qml-mode matlab-mode julia-mode arduino-mode yapfify pyvenv pytest pyenv-mode py-isort pip-requirements live-py-mode hy-mode cython-mode company-anaconda anaconda-mode pythonic company-irony irony winum unfill fuzzy avy log4e powershell evil plantuml-mode clojure-snippets clj-refactor inflections edn paredit peg cider-eval-sexp-fu cider seq queue clojure-mode packed epresent web-beautify livid-mode skewer-mode simple-httpd json-mode json-snatcher json-reformat js2-refactor multiple-cursors js2-mode js-doc company-tern dash-functional tern coffee-mode alert ox-reveal pandoc-mode ox-pandoc ht helm-gtags helm-css-scss helm-cscope zenburn-theme monokai-theme solarized-theme powerline request spinner bind-key bind-map pcre2el vimrc-mode dactyl-mode ox-gfm xcscope x86-lookup stickyfunc-enhance srefactor rainbow-mode rainbow-identifiers quack nasm-mode key-chord ggtags geiser fiplr grizzl find-file-in-project engine-mode dired-subtree dired-narrow dired-hacks-utils color-identifiers-mode vmd-mode web-mode tagedit slim-mode scss-mode sass-mode pug-mode less-css-mode haml-mode emmet-mode company-web web-completion-data pcache git-gutter iedit go-mode yasnippet auto-complete inf-ruby company highlight anzu smartparens undo-tree flycheck projectile helm helm-core hydra markdown-mode magit magit-popup async dash s ranger go-guru git-commit with-editor org minitest insert-shebang hide-comnt fish-mode company-shell rtags cmake-ide levenshtein yaml-mode wgrep smex ivy-hydra flyspell-correct-ivy counsel-projectile counsel swiper ivy uuidgen rake org-projectile org-download mwim link-hint git-link flyspell-correct-helm flyspell-correct eyebrowse evil-visual-mark-mode evil-unimpaired evil-ediff eshell-z dumb-jump f column-enforce-mode xterm-color ws-butler window-numbering which-key volatile-highlights vi-tilde-fringe use-package toc-org spacemacs-theme spaceline smooth-scrolling smeargle shell-pop rvm ruby-tools ruby-test-mode rubocop rspec-mode robe restart-emacs rbenv rainbow-delimiters quelpa popwin persp-mode paradox page-break-lines orgit org-repo-todo org-present org-pomodoro org-plus-contrib org-bullets open-junk-file neotree multi-term move-text mmm-mode markdown-toc magit-gitflow macrostep lorem-ipsum linum-relative leuven-theme info+ indent-guide ido-vertical-mode hungry-delete htmlize hl-todo highlight-parentheses highlight-numbers highlight-indentation help-fns+ helm-themes helm-swoop helm-projectile helm-mode-manager helm-make helm-gitignore helm-flyspell helm-flx helm-descbinds helm-company helm-c-yasnippet helm-ag google-translate golden-ratio go-eldoc gnuplot gitconfig-mode gitattributes-mode git-timemachine git-messenger git-gutter-fringe git-gutter-fringe+ gh-md flycheck-pos-tip flx-ido fill-column-indicator fancy-battery expand-region exec-path-from-shell evil-visualstar evil-tutor evil-surround evil-search-highlight-persist evil-numbers evil-nerd-commenter evil-mc evil-matchit evil-magit evil-lisp-state evil-indent-plus evil-iedit-state evil-exchange evil-escape evil-args evil-anzu eval-sexp-fu eshell-prompt-extras esh-help elisp-slime-nav disaster diff-hl define-word company-statistics company-quickhelp company-go company-c-headers cmake-mode clean-aindent-mode clang-format chruby bundler buffer-move bracketed-paste auto-yasnippet auto-highlight-symbol auto-dictionary auto-compile aggressive-indent adaptive-wrap ace-window ace-link ace-jump-helm-line ac-ispell)))
 '(pos-tip-background-color "#A6E22E")
 '(pos-tip-foreground-color "#272822")
 '(smartrep-mode-line-active-bg (solarized-color-blend "#859900" "#073642" 0.2))
 '(term-default-bg-color "#002b36")
 '(term-default-fg-color "#839496")
 '(vc-annotate-background nil)
 '(vc-annotate-background-mode nil)
 '(vc-annotate-color-map
   (quote
    ((20 . "#F92672")
     (40 . "#CF4F1F")
     (60 . "#C26C0F")
     (80 . "#E6DB74")
     (100 . "#AB8C00")
     (120 . "#A18F00")
     (140 . "#989200")
     (160 . "#8E9500")
     (180 . "#A6E22E")
     (200 . "#729A1E")
     (220 . "#609C3C")
     (240 . "#4E9D5B")
     (260 . "#3C9F79")
     (280 . "#A1EFE4")
     (300 . "#299BA6")
     (320 . "#2896B5")
     (340 . "#2790C3")
     (360 . "#66D9EF"))))
 '(vc-annotate-very-old-color nil)
 '(weechat-color-list
   (unspecified "#272822" "#3C3D37" "#F70057" "#F92672" "#86C30D" "#A6E22E" "#BEB244" "#E6DB74" "#40CAE4" "#66D9EF" "#FB35EA" "#FD5FF0" "#74DBCD" "#A1EFE4" "#F8F8F2" "#F8F8F0"))
 '(xterm-color-names
   ["#073642" "#dc322f" "#859900" "#b58900" "#268bd2" "#d33682" "#2aa198" "#eee8d5"])
 '(xterm-color-names-bright
   ["#002b36" "#cb4b16" "#586e75" "#657b83" "#839496" "#6c71c4" "#93a1a1" "#fdf6e3"]))
(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 )
)
