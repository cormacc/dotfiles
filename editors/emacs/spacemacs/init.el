;; -*- mode: emacs-lisp; lexical-binding: t -*-
;; This file is loaded by Spacemacs at startup.
;; It must be stored in your home directory.

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

   ;; List of additional paths where to look for configuration layers.
   ;; Paths must have a trailing slash (i.e. `~/.mycontribs/')
   ;; N.B. It only became necessary to set this explicitly 25/07/2022 -- may be a transient upstream issue
   ;; dotspacemacs-configuration-layer-path '("~/.spacemacs.d/layers/")

   ;; List of configuration layers to load.
   dotspacemacs-configuration-layers
   '(
     ;; ----------------------------------------------------------------
     ;; Example of useful layers you may want to use right away.
     ;; Uncomment some layer names and press `SPC f e R' (Vim style) or
     ;; `M-m f e R' (Emacs style) to install them.
     ;; ----------------------------------------------------------------

     ;; ================================================================
     ;; Completion layers
     ;; ----------------------------------------------------------------
     ;; Helm layer is loaded automatically if ivy or compleseus layers not specified
     compleseus
     ;; ivy
     ;; ----------------------------------------------------------------
     ;; Completion layers
     ;; ================================================================

     ;; ================================================================
     ;; Editing layers
     ;; ----------------------------------------------------------------
     ;; (colors :variables
     ;;   colors-enable-nyan-cat-progress-bar t
     ;;   nyan-bar-length 8)
     copy-as-format
     dtrt-indent ;;Automatic indent detection...
     evil-snipe
     helpful
     (ibuffer :variables ibuffer-group-buffers-by 'projects)
     imenu-list
     (languagetool :variables
                   langtool-java-classpath "/usr/share/languagetool:/usr/share/java/languagetool/*"
                   langtool-default-language "en-GB")
     multiple-cursors
     ;; Prefer lsp-layer formatting?
     ;; prettier
     templates
     ;; see https://themegallery.robdor.com/
     ;; themes-megapack
     ;; ----------------------------------------------------------------
     ;; Editing layers
     ;; ================================================================

     ;; ================================================================
     ;; Utility layers
     ;; ----------------------------------------------------------------
     ;; chrome
     ;; confluence ;;This seems to use the old confluence xml-rpc api, rather than REST API provided by confluence cloud...
     (dash :variables
           dash-docs-docset-newpath "~/.local/share/Zeal/Zeal/docsets")
     ;; eaf is a nice idea, but doesn't play nice with i3wm
     ;; eaf
     git
     ;;TODO: Reinstate this...
     ;; mbt
     ;; (mu4e :variables
     ;;   mu4e-enable-notifications t
     ;;   mu4e-enable-mode-line t
     ;;   )
                                        ;neotree
     ;; nav-flash
     ;; notmuch
     (ranger :variables
             ranger-show-preview t
             ranger-cleanup-on-disable t
             ranger-show-dotfiles t)
     ;; search-engine
     ;;'semantic' used by cmode for refactoring support
     ;; semantic
     (shell :variables
            shell-default-shell 'vterm
            shell-default-term-shell "~/.nix-profile/bin/fish")
     spell-checking
     treemacs
     version-control
     ;; (version-control :variables
     ;;                  version-control-diff-tool 'git-gutter
     ;;                  version-control-global-margin t)
     ;; ----------------------------------------------------------------
     ;; Utility layers
     ;; ================================================================


     ;; ================================================================
     ;; AI/llm layers
     ;; ----------------------------------------------------------------
     ;; The llm-client layer supports multiple LLM backends
     ;; ... gptel provides a very simple/flexible/powerful interface
     ;; ... ellama provides a more granular interface with a range of useful discrete functions
     (llm-client :variables
                 llm-client-enable-gptel t
                 llm-client-enable-ellama t)
     ;; ... the openai layer provides functionality similar to llm-client/ellama, but for openai only
     openai
     ;; ----------------------------------------------------------------
     ;; AI/llm layers
     ;; ================================================================


     ;; ================================================================
     ;; Notes / GTD layers
     ;; ----------------------------------------------------------------
     ;; deft
     ;;http://spacemacs.org/layers/+emacs/org/README.html
     (org :variables
          jiralib-url "https://neuromod.atlassian.net:443"
          org-enable-appear-support t
          ;; org-enable-jira-support t
          org-enable-notifications t
          org-start-notification-daemon-on-startup t
          ;; org-modern screws with table alignment
          ;; org-enable-modern-support t
          org-enable-roam-protocol t
          org-enable-roam-support t
          org-enable-roam-ui t
          org-enable-sticky-header t
          org-enable-transclusion-support t
          org-enable-valign t
          org-want-todo-bindings t
          ;; Export-related...
          org-enable-bootstrap-support t
          org-enable-github-support t
          org-enable-hugo-support t
          org-enable-reveal-js-support t)
     (org-user :variables
               ;;Use your primary O365 e-mail address here, or set to t to load it from ~/.authinfo(.gpg)
               ;; Disabling for now, as can't get the new auth mechanism to work
               ;; org-user-o365 t
               org-user-roam-directory "~/notes/roam/")
     ;; outshine
     pandoc
     ;; ----------------------------------------------------------------
     ;; Notes / GTD layers
     ;; ================================================================

     ;; ================================================================
     ;; Markup / file format layers
     ;; ----------------------------------------------------------------
     csv
     (markdown :variables markdown-live-preview-engine 'vmd)
     pdf
     ;; Now setting PLANTUML_JAR_PATH in emacs.nix
     (plantuml :variables
               plantuml-jar-path (getenv "PLANTUML_JAR")
               org-plantuml-jar-path (getenv "PLANTUML_JAR")
               )
     ;;N.B. toml support provided by rust language layer
     yaml
     ;; ----------------------------------------------------------------
     ;; Markup / file format layers
     ;; ================================================================

     ;; ================================================================
     ;; Language support layers
     ;; ----------------------------------------------------------------
     (auto-completion :variables
                      auto-completion-enable-snippets-in-popup t
                      ;; Skip tooltip - use M-h instead
                      ;; auto-completion-enable-help-tooltip t
                      )
     (lsp :variables
          lsp-lens-enable t
          lsp-ui-remap-xref-keybindings t
          )
     tree-sitter
     (syntax-checking :variables
                      syntax-checking-enable-by-default nil)
     ;; ----------------------------------------------------------------
     ;; Language support layers
     ;; ================================================================

     ;; ================================================================
     ;; Language layers
     ;; ----------------------------------------------------------------
     ;;asm
     (c-c++ :variables
            ;; c-c++-backend 'lsp-ccls
            c-c++-backend 'lsp-clangd
            ;; c-c++-adopt-subprojects t
            c-c++-enable-semantic-highlight t
            gendoxy-header-copyright "(c) Neuromod Devices Ltd. 2024"
            ;; c-c++-enable-semantic-highlight 'rainbow
            )
     ceedling
     (clojure :variables
              clojure-enable-linters '(clj-kondo joker)
              )
     (cmake :variables
            ;; I was using this to generate compile_commands.json, but doing it via ceedling config now...
            ;; cmake-enable-cmake-ide-support t
            )
     docker
     emacs-lisp
     ;; (go :variables
     ;;   gofmt-command "goimports"
     ;;   go-use-gometalinter t
     ;;   godoc-at-point-function 'godoc-gogetdoc)
     ;; graphql
     ;; haskell
     html
     ;; This results in a json error rendering latex fragments in org buffers for some reason?
     ;; ipython-notebook
     ;; (javascript :variables node-add-modules-path t)
     (javascript :variables javascript-backend 'tide)
     ;; kivy
     nixos
     (node :variables node-add-modules-path t)
     ;; octave
     ;; parinfer ;;This may be screwing up my parens...
     (python :variables
             ;; python-backend 'anaconda
             python-backend 'lsp
             python-lsp-server 'pyright
             ;; python-lsp-server 'mspyls
             ;; python-pipenv-activate t
             python-formatter 'black
             python-format-on-save t
             ;; isort doesn't respect line length...
             ;; python-sort-imports-on-save t
             python-fill-column 120
             python-test-runner 'pytest)
     ;; racket
     ;; react
     (ruby :variables
           ;; ruby-backend 'robe ;defaults to lsp...
           ruby-test-runner 'rspec
           ;; ruby-version-manager 'rbenv
           ;; ruby-enable-enh-ruby-mode t
           )
     ;; (rust :variables
     ;;       rust-format-on-save t)
     ;; scheme
     shell-scripts
     sql
     ;; svelte

     ;; systemd
     (typescript :variables typescript-backend 'tide)

     windows-scripts
     )


   ;; List of additional packages that will be installed without being
   ;; wrapped in a layer. If you need some configuration for these
   ;; packages, then consider creating a layer. You can also put the
   ;; configuration in `dotspacemacs/user-config'.
   ;; dotspacemacs-additional-packages '(direnv)
   dotspacemacs-additional-packages '(envrc)


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
   ;; If non-nil then enable support for the portable dumper. You'll need
   ;; to compile Emacs 27 from source following the instructions in file
   ;; EXPERIMENTAL.org at to root of the git repository.
   ;;
   ;; WARNING: pdumper does not work with Native Compilation, so it's disabled
   ;; regardless of the following setting when native compilation is in effect.
   ;;
   ;; (default nil)
   dotspacemacs-enable-emacs-pdumper nil

   ;; Name of executable file pointing to emacs 27+. This executable must be
   ;; in your PATH.
   ;; (default "emacs")
   dotspacemacs-emacs-pdumper-executable-file "emacs"

   ;; Name of the Spacemacs dump file. This is the file will be created by the
   ;; portable dumper in the cache directory under dumps sub-directory.
   ;; To load it when starting Emacs add the parameter `--dump-file'
   ;; when invoking Emacs 27.1 executable on the command line, for instance:
   ;;   ./emacs --dump-file=$HOME/.emacs.d/.cache/dumps/spacemacs-27.1.pdmp
   ;; (default (format "spacemacs-%s.pdmp" emacs-version))
   dotspacemacs-emacs-dumper-dump-file (format "spacemacs-%s.pdmp" emacs-version)

   ;; If non-nil ELPA repositories are contacted via HTTPS whenever it's
   ;; possible. Set it to nil if you have no way to use HTTPS in your
   ;; environment, otherwise it is strongly recommended to let it set to t.
   ;; This variable has no effect if Emacs is launched with the parameter
   ;; `--insecure' which forces the value of this variable to nil.
   ;; (default t)
   dotspacemacs-elpa-https t

   ;; Maximum allowed time in seconds to contact an ELPA repository.
   ;; (default 5)
   dotspacemacs-elpa-timeout 10

   ;; Set `gc-cons-threshold' and `gc-cons-percentage' when startup finishes.
   ;; This is an advanced option and should not be changed unless you suspect
   ;; performance issues due to garbage collection operations.
   ;; (default '(100000000 0.1))
   dotspacemacs-gc-cons '(100000000 0.1)

   ;; Set `read-process-output-max' when startup finishes.
   ;; This defines how much data is read from a foreign process.
   ;; Setting this >= 1 MB should increase performance for lsp servers
   ;; in emacs 27.
   ;; (default (* 1024 1024))
   dotspacemacs-read-process-output-max (* 1024 1024)

   ;; If non-nil then Spacelpa repository is the primary source to install
   ;; a locked version of packages. If nil then Spacemacs will install the
   ;; latest version of packages from MELPA. Spacelpa is currently in
   ;; experimental state please use only for testing purposes.
   ;; (default nil)
   dotspacemacs-use-spacelpa nil

   ;; If non-nil then verify the signature for downloaded Spacelpa archives.
   ;; (default t)
   dotspacemacs-verify-spacelpa-archives t

   ;; If non-nil then spacemacs will check for updates at startup
   ;; when the current branch is not `develop'. Note that checking for
   ;; new versions works via git commands, thus it calls GitHub services
   ;; whenever you start Emacs. (default nil)
   dotspacemacs-check-for-update nil

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

   ;; If non-nil show the version string in the Spacemacs buffer. It will
   ;; appear as (spacemacs version)@(emacs version)
   ;; (default t)
   dotspacemacs-startup-buffer-show-version t

   ;; Specify the startup banner. Default value is `official', it displays
   ;; the official spacemacs logo. An integer value is the index of text
   ;; banner, `random' chooses a random text banner in `core/banners'
   ;; directory. A string value must be a path to an image format supported
   ;; by your Emacs build.
   ;; If the value is nil then no banner is displayed. (default 'official)
   dotspacemacs-startup-banner 'official

   ;; Scale factor controls the scaling (size) of the startup banner. Default
   ;; value is `auto' for scaling the logo automatically to fit all buffer
   ;; contents, to a maximum of the full image height and a minimum of 3 line
   ;; heights. If set to a number (int or float) it is used as a constant
   ;; scaling factor for the default logo size.
   dotspacemacs-startup-banner-scale 'auto

   ;; List of items to show in startup buffer or an association list of
   ;; the form `(list-type . list-size)`. If nil then it is disabled.
   ;; Possible values for list-type are:
   ;; `recents' `recents-by-project' `bookmarks' `projects' `agenda' `todos'.
   ;; List sizes may be nil, in which case
   ;; `spacemacs-buffer-startup-lists-length' takes effect.
   ;; The exceptional case is `recents-by-project', where list-type must be a
   ;; pair of numbers, e.g. `(recents-by-project . (7 .  5))', where the first
   ;; number is the project limit and the second the limit on the recent files
   ;; within a project.
   dotspacemacs-startup-lists '((recents . 5)
                                (projects . 7))

   ;; True if the home buffer should respond to resize events. (default t)
   dotspacemacs-startup-buffer-responsive t

   ;; Show numbers before the startup list lines. (default t)
   dotspacemacs-show-startup-list-numbers t

   ;; The minimum delay in seconds between number key presses. (default 0.4)
   dotspacemacs-startup-buffer-multi-digit-delay 0.4

   ;; If non-nil, show file icons for entries and headings on Spacemacs home buffer.
   ;; This has no effect in terminal or if "all-the-icons" package or the font
   ;; is not installed. (default nil)
   dotspacemacs-startup-buffer-show-icons nil

   ;; Default major mode for a new empty buffer. Possible values are mode
   ;; names such as `text-mode'; and `nil' to use Fundamental mode.
   ;; (default `text-mode')
   dotspacemacs-new-empty-buffer-major-mode 'text-mode

   ;; Default major mode of the scratch buffer (default `text-mode')
   dotspacemacs-scratch-mode 'text-mode

   ;; If non-nil, *scratch* buffer will be persistent. Things you write down in
   ;; *scratch* buffer will be saved and restored automatically.
   dotspacemacs-scratch-buffer-persistent t

   ;; If non-nil, `kill-buffer' on *scratch* buffer
   ;; will bury it instead of killing.
   dotspacemacs-scratch-buffer-unkillable t

   ;; Initial message in the scratch buffer, such as "Welcome to Spacemacs!"
   ;; (default nil)
   dotspacemacs-initial-scratch-message nil

   ;; List of themes, the first of the list is loaded when spacemacs starts.
   ;; Press `SPC T n' to cycle to the next theme in the list (works great
   ;; with 2 themes variants, one dark and one light)
   dotspacemacs-themes '(modus-operandi
                         modus-vivendi)

   ;; Set the theme for the Spaceline. Supported themes are `spacemacs',
   ;; `all-the-icons', `custom', `doom', `vim-powerline' and `vanilla'. The
   ;; first three are spaceline themes. `doom' is the doom-emacs mode-line.
   ;; `vanilla' is default Emacs mode-line. `custom' is a user defined themes,
   ;; refer to the DOCUMENTATION.org for more info on how to create your own
   ;; spaceline theme. Value can be a symbol or list with additional properties.
   ;; (default '(spacemacs :separator wave :separator-scale 1.5))
   dotspacemacs-mode-line-theme '(spacemacs :separator wave :separator-scale 1.5)

   ;; If non-nil the cursor color matches the state color in GUI Emacs.
   ;; (default t)
   dotspacemacs-colorize-cursor-according-to-state t

   ;; Default font or prioritized list of fonts. The `:size' can be specified as
   ;; a non-negative integer (pixel size), or a floating-point (point size).
   ;; Point size is recommended, because it's device independent. (default 10.0)
   ;; N.B. use 'fc-list' to list installed font names on linux
   dotspacemacs-default-font '(;;"FiraCode Nerd Font"
                               "Source Code Pro"
                               :size 10.0
                               :weight normal
                               :width normal)

   ;; The leader key (default "SPC")
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
   ;; (default "C-M-m" for terminal mode, "<M-return>" for GUI mode).
   ;; Thus M-RET should work as leader key in both GUI and terminal modes.
   ;; C-M-m also should work in terminal mode, but not in GUI mode.
   dotspacemacs-major-mode-emacs-leader-key (if window-system "<M-return>" "C-M-m")

   ;; These variables control whether separate commands are bound in the GUI to
   ;; the key pairs `C-i', `TAB' and `C-m', `RET'.
   ;; Setting it to a non-nil value, allows for separate commands under `C-i'
   ;; and TAB or `C-m' and `RET'.
   ;; In the terminal, these pairs are generally indistinguishable, so this only
   ;; works in the GUI. (default nil)
   dotspacemacs-distinguish-gui-tab nil

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

   ;; If non-nil, the paste transient-state is enabled. While enabled, after you
   ;; paste something, pressing `C-j' and `C-k' several times cycles through the
   ;; elements in the `kill-ring'. (default nil)
   dotspacemacs-enable-paste-transient-state t

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
   dotspacemacs-maximized-at-startup t

   ;; If non-nil the frame is undecorated when Emacs starts up. Combine this
   ;; variable with `dotspacemacs-maximized-at-startup' in OSX to obtain
   ;; borderless fullscreen. (default nil)
   dotspacemacs-undecorated-at-startup nil

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

   ;; If non-nil unicode symbols are displayed in the mode line.
   ;; If you use Emacs as a daemon and wants unicode characters only in GUI set
   ;; the value to quoted `display-graphic-p'. (default t)
   dotspacemacs-mode-line-unicode-symbols nil
   ;; [CC] Setting to nil to attempt to resolve short freezes

   ;; If non-nil smooth scrolling (native-scrolling) is enabled. Smooth
   ;; scrolling overrides the default behavior of Emacs which recenters point
   ;; when it reaches the top or bottom of the screen. (default t)
   dotspacemacs-smooth-scrolling t

   ;; Show the scroll bar while scrolling. The auto hide time can be configured
   ;; by setting this variable to a number. (default t)
   dotspacemacs-scroll-bar-while-scrolling t

   ;; Control line numbers activation.
   ;; If set to `t', `relative' or `visual' then line numbers are enabled in all
   ;; `prog-mode' and `text-mode' derivatives. If set to `relative', line
   ;; numbers are relative. If set to `visual', line numbers are also relative,
   ;; but only visual lines are counted. For example, folded lines will not be
   ;; counted and wrapped lines are counted as multiple lines.
   ;; This variable can also be set to a property list for finer control:
   ;; '(:relative nil
   ;;   :visual nil
   ;;   :disabled-for-modes dired-mode
   ;;                       doc-view-mode
   ;;                       markdown-mode
   ;;                       org-mode
   ;;                       pdf-view-mode
   ;;                       text-mode
   ;;   :size-limit-kb 1000)
   ;; When used in a plist, `visual' takes precedence over `relative'.
   ;; (default nil)
   dotspacemacs-line-numbers t

   ;; Code folding method. Possible values are `evil', `origami' and `vimish'.
   ;; (default 'evil)
   dotspacemacs-folding-method 'evil

   ;; If non-nil and `dotspacemacs-activate-smartparens-mode' is also non-nil,
   ;; `smartparens-strict-mode' will be enabled in programming modes.
   ;; (default nil)
   dotspacemacs-smartparens-strict-mode nil

   ;; If non-nil smartparens-mode will be enabled in programming modes.
   ;; (default t)
   dotspacemacs-activate-smartparens-mode t

   ;; If non-nil pressing the closing parenthesis `)' key in insert mode passes
   ;; over any automatically added closing parenthesis, bracket, quote, etc...
   ;; This can be temporary disabled by pressing `C-q' before `)'. (default nil)
   dotspacemacs-smart-closing-parenthesis nil

   ;; Select a scope to highlight delimiters. Possible values are `any',
   ;; `current', `all' or `nil'. Default is `all' (highlight any scope and
   ;; emphasis the current one). (default 'all)
   dotspacemacs-highlight-delimiters 'all

   ;; If non-nil, start an Emacs server if one is not already running.
   ;; (default nil)
   dotspacemacs-enable-server nil

   ;; Set the emacs server socket location.
   ;; If nil, uses whatever the Emacs default is, otherwise a directory path
   ;; like \"~/.emacs.d/server\". It has no effect if
   ;; `dotspacemacs-enable-server' is nil.
   ;; (default nil)
   dotspacemacs-server-socket-dir nil

   ;; If non-nil, advise quit functions to keep server open when quitting.
   ;; (default nil)
   dotspacemacs-persistent-server nil

   ;; List of search tool executable names. Spacemacs uses the first installed
   ;; tool of the list. Supported tools are `rg', `ag', `pt', `ack' and `grep'.
   ;; (default '("rg" "ag" "pt" "ack" "grep"))
   dotspacemacs-search-tools '("rg" "ag" "pt" "ack" "grep")

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
   ;; If nil then Spacemacs uses default `frame-title-format' to avoid
   ;; performance issues, instead of calculating the frame title by
   ;; `spacemacs/title-prepare' all the time.
   ;; (default "%I@%S")
   dotspacemacs-frame-title-format "%I@%S"

   ;; Format specification for setting the icon title format
   ;; (default nil - same as frame-title-format)
   dotspacemacs-icon-title-format nil

   ;; Show trailing whitespace (default t)
   ;; Color highlight trailing whitespace in all prog-mode and text-mode derived
   ;; modes such as c++-mode, python-mode, emacs-lisp, html-mode, rst-mode etc.
   ;; (default t)
   dotspacemacs-show-trailing-whitespace t

   ;; Delete whitespace while saving buffer. Possible values are `all'
   ;; to aggressively delete empty line and long sequences of whitespace,
   ;; `trailing' to delete only the whitespace at end of lines, `changed' to
   ;; delete only whitespace for changed lines or `nil' to disable cleanup.
   ;; (default nil)
   dotspacemacs-whitespace-cleanup 'trailing

   ;; If non-nil activate `clean-aindent-mode' which tries to correct
   ;; virtual indentation of simple modes. This can interfere with mode specific
   ;; indent handling like has been reported for `go-mode'.
   ;; If it does deactivate it here.
   ;; (default t)
   dotspacemacs-use-clean-aindent-mode t

   ;; Accept SPC as y for prompts if non-nil. (default nil)
   dotspacemacs-use-SPC-as-y nil

   ;; If non-nil shift your number row to match the entered keyboard layout
   ;; (only in insert state). Currently supported keyboard layouts are:
   ;; `qwerty-us', `qwertz-de' and `querty-ca-fr'.
   ;; New layouts can be added in `spacemacs-editing' layer.
   ;; (default nil)
   dotspacemacs-swap-number-row nil

   ;; Either nil or a number of seconds. If non-nil zone out after the specified
   ;; number of seconds. (default nil)
   dotspacemacs-zone-out-when-idle nil

   ;; Run `spacemacs/prettify-org-buffer' when
   ;; visiting README.org files of Spacemacs.
   ;; (default nil)
   dotspacemacs-pretty-docs nil

   ;; If nil the home buffer shows the full path of agenda items
   ;; and todos. If non-nil only the file name is shown.
   dotspacemacs-home-shorten-agenda-source nil

   ;; If non-nil then byte-compile some of Spacemacs files.
   dotspacemacs-byte-compile nil))

(defun dotspacemacs/user-env ()
  "Environment variables setup.
This function defines the environment variables for your Emacs session. By
default it calls `spacemacs/load-spacemacs-env' which loads the environment
variables declared in `~/.spacemacs.env' or `~/.spacemacs.d/.spacemacs.env'.
See the header of this file for more information."
  (spacemacs/load-spacemacs-env))

(defun dotspacemacs/user-init ()
  "Initialization for user code:
This function is called immediately after `dotspacemacs/init', before layer
configuration.
It is mostly for variables that should be set before packages are loaded.
If you are unsure, try setting them in `dotspacemacs/user-config' first."

  ;; setup package-user-dir to allow seamless switch between emacs versions
  ;; (setq package-user-dir (concat user-home-directory ".cache/emacs/elpa/" emacs-version))

  (setq tramp-default-method "ssh")
  (setq tramp-password-prompt-regexp
        "^.*\\([pP]assword\\|[pP]assphrase\\|Verification code\\).*:? *")
  (setq tramp-ssh-controlmaster-options
        (concat
         "-o ControlPath=~/.ssh/%%r@%%h:%%p"))

  (setq exec-path-from-shell-arguments (list "-i")))


(defun dotspacemacs/user-load ()
  "Library to load while dumping.
This function is called only while dumping Spacemacs configuration. You can
`require' or `load' the libraries of your choice that will be included in the
dump.")


(defun dotspacemacs/user-config ()
  "Configuration for user code:
This function is called at the very end of Spacemacs startup, after layer
configuration.
Put your configuration code here, except for variables that should be set
before packages are loaded."
  (define-key global-map (kbd "C-+") 'text-scale-increase)
  (define-key global-map (kbd "C-=") 'text-scale-decrease)
  ;; (direnv-mode)
  (envrc-global-mode)

  (setq-default evil-escape-key-sequence "xz")

  ;; Prevent remote files in recentf list causing a tramp error on startup
  (setq recentf-keep '(file-remote-p file-readable-p))

  ;; Place all '.#*' emacs backup files in a single directory rather than alongside your files
  (setq backup-directory-alist
        `(("." . ,(concat user-emacs-directory "backups"))))

  ;; ... similarly with the '.~undo-tree~' files cached by emacs 28+
  ;; DISABLING Experiencing undo-tree related freezing on save Oct 2022
  ;; (setq undo-tree-history-directory-alist
  ;;       `(("." . ,(concat user-emacs-directory "undo"))))


  (with-eval-after-load 'doom-themes
    (doom-themes-treemacs-config)
    ;; Corrects (and improves) org-mode's native fontification.
    (doom-themes-org-config))

  ;; C-mode stuff
  ;; Remember, .editorconfig can interact with spacing settings
  (c-add-style "cormacc"
               '((indent-tabs-mode . nil)
                 ;; (c-basic-offset . 2)
                 (c-offsets-alist
                  (substatement-open . 0)
                  (inline-open . 0)
                  (statement-cont . c-lineup-assignments)
                  (inextern-lang . 0)
                  (innamespace . 0))))
  (push '(other . "cormacc") c-default-style)
  (add-hook 'c-mode-hook (lambda () (setq fill-column 120)))

  ;; We want to open CMakeSources.txt in cmake mode (i.e. not just CMakeLists.txt)
  (add-to-list 'auto-mode-alist '("CMake.+\\.txt\\'" . cmake-mode))
  (setq cmake-ide-build-pool-dir (file-truename "~/.cmake_builds"))
  (setq cmake-ide-build-pool-use-persistent-naming t)



  ;; AI and LLM...


  ;; ... llm-client layer -- gptel backends
  ;; See https://github.com/karthink/gptel
  ;; This config assumes api keys are stored in ~/.authinfo.gpg, as illustrated below...
  ;;  machine api.openai.com login apikey password ****
  ;;  machine api.anthropic.com login apikey password ****
  (with-eval-after-load 'gptel
    (gptel-make-anthropic "Claude"
      :stream t
      :key (auth-source-pick-first-password :host "api.anthropic.com"))
    (setq
     ;; Backend defaults to ChatGPT/gpt-3.5-turbo. Overridding...
     gptel-backend (gptel-make-openai "ChatGPT" :stream t :key (auth-source-pick-first-password :host "api.openai.com"))
     gptel-model "gpt-4o"

     ;; gptel-backend (gptel-make-anthropic "Claude" :stream t :key (authinfo/get-password "api.anthropic.com"))

     ;; Use org mode syntax by default for buffers
     gptel-default-mode 'org-mode)
    (global-set-key (kbd "C-c RET") 'gptel-send))



  ;; ... llm-client layer -- ellama backends
  ;; See...
  ;; 1. https://github.com/s-kostyaev/ellama
  ;; 2. https://github.com/ahyatt/llm
  (with-eval-after-load 'ellama
    ;; TODO: Investigate setting up multiple providers, as we do with gptel...
    ;; OpenAI...
    (require 'llm-openai)
    (setopt ellama-provider (make-llm-openai
                             :key (auth-source-pick-first-password :host "api.openai.com")
                             :chat-model "gpt-4o")))

  ;; ... dedicated openai layer
  (with-eval-after-load 'openai
    (setq
     openai-key (auth-source-pick-first-password :host "api.openai.om")))

  ;; JS / React

  (setq-default
   ;; js2-mode
   js2-basic-offset 2
   ;; web-mode
   css-indent-offset 2
   web-mode-markup-indent-offset 2
   web-mode-css-indent-offset 2
   web-mode-code-indent-offset 2
   web-mode-attr-indent-offset 2)

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

  ;; (with-eval-after-load 'markdown-mode
  ;;   (add-hook 'markdown-mode-hook #'visual-line-mode))

  ;; == Add timestamps to message buffer
  ;; https://emacs.stackexchange.com/questions/32150/how-to-add-a-timestamp-to-each-entry-in-emacs-messages-buffer
  (defun my/add-timestamp-message (FORMAT-STRING &rest args)
    "Advice to run before `message' that prepends a timestamp to each message.
        Activate this advice with:
          (advice-add 'message :before 'my/ad-timestamp-message)
        Deactivate this advice with:
          (advice-remove 'message 'my/ad-timestamp-message)"
    (if message-log-max
        (let ((deactivate-mark nil)
              (inhibit-read-only t))
          (with-current-buffer "*Messages*"
            (goto-char (point-max))
            (if (not (bolp))
                (newline))
            (insert (format-time-string "[%F %T.%3N] "))))))
  (advice-add 'message :before 'my/add-timestamp-message)

  ;; == WORKAROUNDS -- REVISIT REGULARLY ==

  ;; Clipboard on wayland
  ;; See https://www.emacswiki.org/emacs/CopyAndPaste#h5o-4
  (setq wl-copy-process nil)
  (defun wl-copy (text)
    (setq wl-copy-process (make-process :name "wl-copy"
                                        :buffer nil
                                        :command '("wl-copy" "-f" "-n")
                                        :connection-type 'pipe
                                        :noquery t))
    (process-send-string wl-copy-process text)
    (process-send-eof wl-copy-process))
  (defun wl-paste ()
    (if (and wl-copy-process (process-live-p wl-copy-process))
        nil ; should return nil if we're the current paste owner
      (shell-command-to-string "wl-paste -n | tr -d \r")))
  (setq interprogram-cut-function 'wl-copy)
  (setq interprogram-paste-function 'wl-paste)

  ;; == END WORKAROUNDS
  )



;; Work around octave mod issue
;; (eval-after-load 'octave
;;   (setq octave-mode-hook
;;     (lambda () (progn (setq octave-comment-char ?%)
;;                  (setq comment-start "%")
;;                  (setq indent-tabs-mode nil)
;;                  (setq comment-add 0)
;;                  (setq tab-width 2)
;;                  (setq tab-stop-list (number-sequence 2 200 2))
;;                  (setq octave-block-offset 2)

;;                  (defun octave-indent-comment ()
;;                    "A function for `smie-indent-functions' (which see)."
;;                    (save-excursion
;;                      (back-to-indentation)
;;                      (cond
;;                        ((octave-in-string-or-comment-p) nil)
;;                        ((looking-at-p "\\(\\s<\\)\\1\\{2,\\}") 0)))))))


;; TODO: Look at this http://www.clauswitt.com/a-walkthrough-of-my-spacemacs-configuration-files.html


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
   '(compilation-message-face 'default)
   '(cua-global-mark-cursor-color "#2aa198")
   '(cua-normal-cursor-color "#839496")
   '(cua-overwrite-cursor-color "#b58900")
   '(cua-read-only-cursor-color "#859900")
   '(evil-want-Y-yank-to-eol nil)
   '(highlight-changes-colors '("#FD5FF0" "#AE81FF"))
   '(highlight-symbol-colors
     (--map
      (solarized-color-blend it "#002b36" 0.25)
      '("#b58900" "#2aa198" "#dc322f" "#6c71c4" "#859900" "#cb4b16" "#268bd2")))
   '(highlight-symbol-foreground-color "#93a1a1")
   '(highlight-tail-colors
     '(("#3C3D37" . 0)
       ("#679A01" . 20)
       ("#4BBEAE" . 30)
       ("#1DB4D0" . 50)
       ("#9A8F21" . 60)
       ("#A75B00" . 70)
       ("#F309DF" . 85)
       ("#3C3D37" . 100)))
   '(hl-bg-colors
     '("#7B6000" "#8B2C02" "#990A1B" "#93115C" "#3F4D91" "#00629D" "#00736F" "#546E00"))
   '(hl-fg-colors
     '("#002b36" "#002b36" "#002b36" "#002b36" "#002b36" "#002b36" "#002b36" "#002b36"))
   '(hl-todo-keyword-faces
     '(("TODO" . "#dc752f")
       ("NEXT" . "#dc752f")
       ("THEM" . "#2d9574")
       ("PROG" . "#4f97d7")
       ("OKAY" . "#4f97d7")
       ("DONT" . "#f2241f")
       ("FAIL" . "#f2241f")
       ("DONE" . "#86dc2f")
       ("NOTE" . "#b1951d")
       ("KLUDGE" . "#b1951d")
       ("HACK" . "#b1951d")
       ("TEMP" . "#b1951d")
       ("FIXME" . "#dc752f")
       ("XXX+" . "#dc752f")
       ("\\?\\?\\?+" . "#dc752f")))
   '(magit-diff-use-overlays nil)
   '(nrepl-message-colors
     '("#dc322f" "#cb4b16" "#b58900" "#546E00" "#B4C342" "#00629D" "#2aa198" "#d33682" "#6c71c4"))
   '(org-appear-trigger 'manual)
   '(org-safe-remote-resources
     '("\\`https://raw\\.githubusercontent\\.com/fniessen/org-html-themes/master/setup/theme-bigblow\\.setup\\'" "\\`https://raw\\.githubusercontent\\.com/fniessen/org-html-themes/master/org/theme-readtheorg\\.setup\\'" "\\`https://raw\\.githubusercontent\\.com/fniessen/org-html-themes/master/setup/theme-readtheorg\\.setup\\'"))
   '(package-selected-packages
     '(sql-indent sqlup-mode zeal-at-point systemd org-mime ibuffer-projectile gmail-message-mode ham-mode html-to-markdown flymd flycheck-ycmd ghub edit-server counsel-dash helm-dash company-ycmd ycmd request-deferred let-alist deferred doom-themes parent-mode gitignore-mode fringe-helper git-gutter+ pos-tip flx goto-chg diminish pkg-info epl popup org-category-capture racket-mode faceup toml-mode racer flycheck-rust cargo rust-mode csv-mode enh-ruby-mode gntp deft wolfram-mode thrift stan-mode scad-mode qml-mode matlab-mode julia-mode arduino-mode yapfify pyvenv pytest pyenv-mode py-isort pip-requirements live-py-mode hy-mode cython-mode company-anaconda anaconda-mode pythonic company-irony irony winum unfill fuzzy avy log4e powershell evil plantuml-mode clojure-snippets clj-refactor inflections edn paredit peg cider-eval-sexp-fu cider seq queue clojure-mode packed epresent web-beautify livid-mode skewer-mode simple-httpd json-mode json-snatcher json-reformat js2-refactor multiple-cursors js2-mode js-doc company-tern dash-functional tern coffee-mode alert ox-reveal pandoc-mode ox-pandoc ht helm-gtags helm-css-scss helm-cscope zenburn-theme monokai-theme solarized-theme powerline request spinner bind-key bind-map pcre2el vimrc-mode dactyl-mode ox-gfm xcscope x86-lookup stickyfunc-enhance srefactor rainbow-mode rainbow-identifiers quack nasm-mode key-chord ggtags geiser fiplr grizzl find-file-in-project engine-mode dired-subtree dired-narrow dired-hacks-utils color-identifiers-mode vmd-mode web-mode tagedit slim-mode scss-mode sass-mode pug-mode less-css-mode haml-mode emmet-mode company-web web-completion-data pcache git-gutter iedit go-mode yasnippet auto-complete inf-ruby company highlight anzu smartparens undo-tree flycheck projectile helm helm-core hydra markdown-mode magit magit-popup async dash s ranger go-guru git-commit with-editor org minitest insert-shebang hide-comnt fish-mode company-shell rtags cmake-ide levenshtein yaml-mode wgrep smex ivy-hydra flyspell-correct-ivy counsel-projectile counsel swiper ivy uuidgen rake org-projectile org-download mwim link-hint git-link flyspell-correct-helm flyspell-correct eyebrowse evil-visual-mark-mode evil-unimpaired evil-ediff eshell-z dumb-jump f column-enforce-mode xterm-color ws-butler window-numbering which-key volatile-highlights vi-tilde-fringe use-package toc-org spacemacs-theme spaceline smooth-scrolling smeargle shell-pop rvm ruby-tools ruby-test-mode rubocop rspec-mode robe restart-emacs rbenv rainbow-delimiters quelpa popwin persp-mode paradox page-break-lines orgit org-repo-todo org-present org-pomodoro org-plus-contrib org-bullets open-junk-file neotree multi-term move-text mmm-mode markdown-toc magit-gitflow macrostep lorem-ipsum linum-relative leuven-theme info+ indent-guide ido-vertical-mode hungry-delete htmlize hl-todo highlight-parentheses highlight-numbers highlight-indentation help-fns+ helm-themes helm-swoop helm-projectile helm-mode-manager helm-make helm-gitignore helm-flyspell helm-flx helm-descbinds helm-company helm-c-yasnippet helm-ag google-translate golden-ratio go-eldoc gnuplot gitconfig-mode gitattributes-mode git-timemachine git-messenger git-gutter-fringe git-gutter-fringe+ gh-md flycheck-pos-tip flx-ido fill-column-indicator fancy-battery expand-region exec-path-from-shell evil-visualstar evil-tutor evil-surround evil-search-highlight-persist evil-numbers evil-nerd-commenter evil-mc evil-matchit evil-magit evil-lisp-state evil-indent-plus evil-iedit-state evil-exchange evil-escape evil-args evil-anzu eval-sexp-fu eshell-prompt-extras esh-help elisp-slime-nav disaster diff-hl define-word company-statistics company-quickhelp company-go company-c-headers cmake-mode clean-aindent-mode clang-format chruby bundler buffer-move bracketed-paste auto-yasnippet auto-highlight-symbol auto-dictionary auto-compile aggressive-indent adaptive-wrap ace-window ace-link ace-jump-helm-line ac-ispell))
   '(pos-tip-background-color "#A6E22E")
   '(pos-tip-foreground-color "#272822")
   '(safe-local-variable-values
     '((cider-clojure-cli-aliases . ":dev:cljs")
       (cider-shadow-watched-builds ":app" ":portfolio" ":test")
       (cider-shadow-default-options . ":app")
       (cider-clojure-cli-aliases . ":dev")
       (cider-default-cljs-repl . custom)
       (cider-clojure-cli-aliases . "-M:dev")
       (cider-custom-cljs-repl-init-form . "(do (user/cljs-repl))")
       (eval progn
             (make-variable-buffer-local 'cider-jack-in-nrepl-middlewares)
             (add-to-list 'cider-jack-in-nrepl-middlewares "shadow.cljs.devtools.server.nrepl/middleware"))
       (cider-figwheel-main-default-options . ":dev")
       (cider-preferred-build-tool . clojure-cli)
       (cider-default-cljs-repl . figwheel-main)
       (cider-clojure-cli-global-options . "-A:dev")
       (cider-shadow-cljs-default-options . "app")
       (cider-default-cljs-repl . shadow)
       (magit-todos-exclude-globs "*.map")
       (javascript-backend . tern)
       (javascript-backend . lsp)
       (go-backend . go-mode)
       (go-backend . lsp)))
   '(smartrep-mode-line-active-bg (solarized-color-blend "#859900" "#073642" 0.2))
   '(term-default-bg-color "#002b36")
   '(term-default-fg-color "#839496")
   '(vc-annotate-background nil)
   '(vc-annotate-background-mode nil)
   '(vc-annotate-color-map
     '((20 . "#F92672")
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
       (360 . "#66D9EF")))
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
   '(highlight-parentheses-highlight ((nil (:weight ultra-bold))) t))
  )
