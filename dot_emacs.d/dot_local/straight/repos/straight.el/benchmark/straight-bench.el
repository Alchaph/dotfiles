;;; straight-bench.el --- How fast is straight.el? -*- lexical-binding: t -*-

(require 'cl-lib)

;; Not defined before Emacs 25.1
(eval-and-compile
  (unless (fboundp 'make-process)
    (defun make-process (&rest _)
      (error "Benchmarking suite does not support Emacs 24"))))

(defvar straight-bench-this-dir
  (file-name-directory
   (expand-file-name
    (or load-file-name buffer-file-name)))
  "Directory containing straight-bench.el.")

(defvar straight-bench-package-list
  '(eg
    fabric
    extmap
    ruby-end
    preseed-generic-mode
    crystal-mode
    ob-applescript
    esh-help
    dired-open
    grandshell-theme
    org-wild-notifier
    mpmc-queue
    elvish-mode
    all-the-icons-gnus
    dtrt-indent
    elisp-sandbox
    supergenpass
    prescient
    easy-kill
    eglot
    latex-pretty-symbols
    proc-net
    number
    bibliothek
    org-tfl
    ac-ispell
    verb
    switch-buffer-functions
    meta-presenter
    status
    vertica-snippets
    evil-iedit-state
    treemacs-projectile
    fstar-mode
    pipenv
    ob-nim
    hl-sentence
    gsettings
    helm-growthforecast
    rubocop
    flymake-vnu
    jinja2-mode
    flatfluc-theme
    calendar-norway
    julia-snail
    upbo
    ac-math
    git-backup-ivy
    markdownfmt
    shx
    ac-clang
    ac-js2
    markdown-mode+
    pyim
    helm-sly
    ac-geiser
    roy-mode
    berrys-theme
    neon-mode
    nix-env-install
    auto-read-only
    gntp
    nlinum-relative
    plain-theme
    sorcery-theme
    kakapo-mode
    lean-mode
    helm-R
    helm-directory
    lexbind-mode
    php-mode
    tramp-hdfs
    habamax-theme
    bbdb-
    russian-holidays
    mediawiki
    grayscale-theme
    helm-migemo
    cmd-to-echo
    realgud-byebug
    read-aloud
    simplenote
    vi-tilde-fringe
    multiple-cursors
    zotelo
    whitaker
    smart-shift
    connection
    web-mode-edit-element
    monokai-theme
    horizon-theme
    devdocs
    jaword
    flycheck-ocaml
    celery
    system-packages
    copy-file-on-save
    git
    xml+
    atcoder-tools)
  "List of packages to install in benchmark.
Generated by picking 100 random packages from MELPA (you can get
a listing from the URL
<https://melpa.org/packages/archive-contents>).")

(cl-defun straight-bench-time (callback &key init-form emacs-dir graphical)
  "Check how long it takes to run Emacs.
Asynchronous. Return the time (in seconds) as an argument to
CALLBACK.

INIT-FORM non-nil means to delete and re-create EMACS-DIR and
insert the contents of INIT-FORM into init.el in that directory,
before starting Emacs. EMACS-DIR is the `user-emacs-directory'.
GRAPHICAL non-nil means start a non-tty frame."
  (unless emacs-dir
    (error "No :emacs-dir given"))
  (let ((init-file (expand-file-name "init.el" emacs-dir)))
    (when init-form
      (delete-directory emacs-dir 'recursive)
      (make-directory emacs-dir 'parents)
      (with-temp-file init-file
        (print `(progn
                  (run-with-idle-timer
                   0 nil
                   (lambda ()
                     (when (fboundp #'straight--transaction-finalize)
                       (straight--transaction-finalize))
                     (kill-emacs)))
                  (setq user-emacs-directory ',emacs-dir)
                  ,init-form)
               (current-buffer))))
    (ignore-errors
      (kill-buffer "*straight-bench*"))
    (let* ((start-time (current-time))
           (sentinel-triggered nil)
           (process-environment
            (cons
             "TERM=eterm"
             process-environment)))
      (make-process
       :name "straight-bench"
       :command
       `("emacs" "-Q" "-l" ,init-file
         ,@(unless graphical
             '("-nw")))
       :noquery t
       :buffer "*straight-bench*"
       :connection-type 'pty
       :sentinel
       (lambda (proc _)
         (unless (or (process-live-p proc)
                     sentinel-triggered)
           (setq sentinel-triggered t)
           (funcall
            callback
            (float-time
             (time-subtract
              (current-time)
              start-time)))))))))

(defvar straight-bench-num-packages nil
  "Default number of packages to install.
Defaults to everything in `straight-bench-package-list'.")

(cl-defun straight-bench-run
    (callback &key package-manager install graphical
              inhibit-find shallow &allow-other-keys)
  "Run a single benchmark to see how fast a package manager is.
Asynchronous. CALLBACK is invoked with the time in seconds after
the operation finishes.

The benchmarking works differently depending on the keyword
arguments.

Firstly, PACKAGE-MANAGER is either `package' or `straight'.

INSTALL non-nil means to delete all downloaded packages, and
install from scratch. INSTALL nil, on the other hand, means to
assume packages are already downloaded, and just benchmark how
long startup takes.

GRAPHICAL non-nil means start a graphical Emacs frame. GRAPHICAL
nil means start a tty frame.

NUM-PACKAGES is the number of packages to install.

INHIBIT-FIND nil means do the find(1) command at straight.el
startup to check for package modifications (the default).
INHIBIT-FIND non-nil means disable it. (Normally you'd enable
live modification checking in this case, but that's irrelevant
here since there's no performance impact, so we don't bother.)

SHALLOW non-nil means tell straight.el to use shallow clones.
SHALLOW nil means use the default behavior of full clones."
  (let ((packages (cl-subseq straight-bench-package-list
                             0 straight-bench-num-packages)))
    (pcase package-manager
      (`package
       (straight-bench-time
        callback
        :init-form
        (when install
          `(progn
             (require 'package)
             (package-initialize)
             (add-to-list 'package-archives
                          '("melpa" . "https://melpa.org/packages/"))
             (let ((refreshed nil))
               (dolist (package ',packages)
                 (unless (package-installed-p package)
                   (unless refreshed
                     (package-refresh-contents)
                     (setq refreshed t))
                   (package-install package))))))
        :emacs-dir (expand-file-name "emacsd/package" straight-bench-this-dir)
        :graphical graphical))
      (`straight
       (straight-bench-time
        callback
        :init-form
        (when install
          `(progn
             (setq straight-repository-branch "develop")
             ,@(when inhibit-find
                 '((setq straight-check-for-modifications nil)))
             ,@(when shallow
                 '((setq straight-vc-git-default-clone-depth 1)))
             (defvar bootstrap-version)
             (let ((bootstrap-file
                    (expand-file-name
                     "straight/repos/straight.el/bootstrap.el"
                     (or (bound-and-true-p straight-base-dir)
                         user-emacs-directory)))
                   (bootstrap-version 7))
               (unless (file-exists-p bootstrap-file)
                 (with-current-buffer
                     (url-retrieve-synchronously
                      (concat
                       "https://raw.githubusercontent.com"
                       "/radian-software/straight.el/develop/install.el")
                      'silent 'inhibit-cookies)
                   (goto-char (point-max))
                   (eval-print-last-sexp)))
               (load bootstrap-file nil 'nomessage))
             (mapcar #'straight-use-package ',packages)))
        :emacs-dir (expand-file-name "emacsd/straight" straight-bench-this-dir)
        :graphical graphical))
      (`nil
       (straight-bench-time
        callback
        :init-form '(message "Hello world")
        :emacs-dir (expand-file-name "emacsd/base" straight-bench-this-dir)
        :graphical graphical)))))

(defvar straight-bench-install-reps 10
  "Number of times to install all packages from scratch.")

(defvar straight-bench-startup-reps 100
  "Number of times to start Emacs with packages already installed.")

(defvar straight-bench-test-plan
  '(("base Emacs startup")
    ("package.el"
     :package-manager package)
    ("straight.el"
     :package-manager straight)
    ("straight.el (no find)"
     :package-manager straight
     :inhibit-find t)
    ("straight.el (shallow, no find)"
     :package-manager straight
     :inhibit-find t
     :shallow t))
  "The sequence of tests that will be run by `straight-bench-run-plan'.")

(defun straight-bench-mapc-async (callback func items)
  "Invoke CALLBACK with no args after mapping FUNC over ITEMS.
FUNC is an asynchronous function taking a callback of no args and
one of ITEMS and performing some side effects."
  (cl-labels ((func-callback
               ()
               (if items
                   (funcall func #'func-callback (pop items))
                 (funcall callback))))
    (func-callback)))

(defun straight-bench-run-plan (callback)
  "Run all the tests in `straight-bench-test-plan'.
Asynchronous, returns the results as an argument to CALLBACK."
  (message "Running benchmark...")
  (let ((results nil))
    (straight-bench-mapc-async
     (lambda ()
       (funcall callback (nreverse results)))
     (lambda (callback elt)
       (let ((name (car elt))
             (props (cdr elt))
             (install-times nil)
             (startup-times nil))
         (straight-bench-mapc-async
          (lambda ()
            (straight-bench-mapc-async
             (lambda ()
               (push
                (cons
                 name
                 `(:install ,install-times :startup ,startup-times))
                results)
               (funcall callback))
             (lambda (callback _)
               (apply
                #'straight-bench-run
                (lambda (time)
                  (push time startup-times)
                  (funcall callback))
                props))
             (make-list straight-bench-startup-reps nil)))
          (lambda (callback _)
            (apply
             #'straight-bench-run
             (lambda (time)
               (push time install-times)
               (funcall callback))
             (cl-list* :install t props)))
          (make-list straight-bench-install-reps nil))))
     straight-bench-test-plan)))

(defun straight-bench-average (nums)
  "Calculate mean of NUMS."
  (/ (apply #'+ nums) (length nums)))

(defun straight-bench-stddev (nums)
  "Calculate sample standard deviation of NUMS."
  (let ((avg (straight-bench-average nums)))
    (sqrt (/ (apply #'+ (mapcar (lambda (num)
                                  (let ((dev (- num avg)))
                                    (* dev dev)))
                                nums))
             (1- (length nums))))))

(defun straight-bench-deviation (nums)
  "Calculate width of 95% confidence interval from sample NUMS."
  (* 1.960 (/ (straight-bench-stddev nums) (sqrt (length nums)))))

(defun straight-bench-format-results (results)
  "Format benchmarking results into Markdown.
RESULTS are as returned from `straight-bench-run-plan'."
  (let ((name-width
         (apply #'max (mapcar (lambda (result)
                                (length (car result)))
                              results))))
    (concat
     "| " (make-string name-width ? ) " "
     "| Install             | Startup             |\n"
     "|-" (make-string name-width ?-) "-"
     "|---------------------|---------------------|\n"
     (mapconcat
      (lambda (result)
        (let ((name (car result))
              (install-times (plist-get (cdr result) :install))
              (startup-times (plist-get (cdr result) :startup)))
          (format "| %s%s | %7.3fs ± %7.3fs | %7.3fs ± %7.3fs |"
                  name (make-string (- name-width (length name)) ? )
                  (straight-bench-average install-times)
                  (straight-bench-deviation install-times)
                  (straight-bench-average startup-times)
                  (straight-bench-deviation startup-times))))
      results
      "\n"))))

(defun straight-bench-batch ()
  (message "This function is not yet implemented"))

(provide 'straight-bench)

;;; straight-bench.el ends here
