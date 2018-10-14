;;; ccls.el --- ccls client for lsp-mode     -*- lexical-binding: t; -*-

;; Copyright (C) 2017 Tobias Pisani
;; Copyright (C) 2018 Fangrui Song

;; Author: Tobias Pisani, Fangrui Song
;; Package-Version: 20180929.1
;; Version: 0.1
;; Homepage: https://github.com/MaskRay/emacs-ccls
;; Package-Requires: ((emacs "25.1") (lsp-mode "4.2") (dash "0.14") (projectile "1.0.0"))
;; Keywords: languages, lsp, c++

;; Permission is hereby granted, free of charge, to any person obtaining a copy
;; of this software and associated documentation files (the "Software"), to deal
;; in the Software without restriction, including without limitation the rights
;; to use, copy, modify, merge, publish, distribute, sublicense, and-or sell
;; copies of the Software, and to permit persons to whom the Software is
;; furnished to do so, subject to the following conditions:

;; The above copyright notice and this permission notice shall be included in
;; all copies or substantial portions of the Software.

;; THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
;; IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
;; FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
;; AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
;; LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
;; OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
;; SOFTWARE.
;;
;;; Commentary:

;;
;; To enable, call (lsp-ccls-enable) in your c++-mode hook.
;; See more at https://github.com/MaskRay/ccls/wiki/Emacs
;;

;;; Code:

(require 'ccls-common)
(require 'ccls-semantic-highlight)
(require 'ccls-code-lens)
(require 'ccls-tree)
(require 'ccls-call-hierarchy)
(require 'ccls-inheritance-hierarchy)
(require 'ccls-member-hierarchy)

(require 'seq)

;; ---------------------------------------------------------------------
;;   Customization
;; ---------------------------------------------------------------------

(defcustom ccls-executable
  "ccls"
  "Path of the ccls executable."
  :type 'file
  :group 'ccls)

(defcustom ccls-extra-args
  nil
  "Additional command line options passed to the ccls executable."
  :type '(repeat string)
  :group 'ccls)

(defalias 'ccls-additional-arguments 'ccls-extra-args)

(defcustom ccls-cache-dir
  ".ccls-cache/"
  "Directory in which ccls will store its index cache.
Relative to the project root directory."
  :type 'directory
  :group 'ccls)

(defcustom ccls-extra-init-params
  nil
  "Additional initializationOptions passed to ccls."
  :type '(repeat string)
  :group 'ccls)

(defcustom ccls-project-root-matchers
  '(".ccls-root" projectile-project-root)
  "List of matchers that are used to locate the ccls project roots.
Each matcher is run in order, and the first successful (non-nil) matcher
determines the project root.

A `string' entry defines a dominating file that exists in either the
current working directory or a parent directory. ccls will traverse
upwards through the project directory structure and return the first
matching file.

A `function' entry define a callable function that either returns workspace's
root location or `nil' if subsequent matchers should be used instead.
"
  :type '(repeat (choice (file) (function)))
  :group 'ccls)

;; ---------------------------------------------------------------------
;;   Other ccls-specific methods
;; ---------------------------------------------------------------------
;;
(defun ccls-info ()
  (lsp--cur-workspace-check)
  (lsp--send-request
   (lsp--make-request "$ccls/info")))

(defun ccls-file-info ()
  (lsp--cur-workspace-check)
  (lsp--send-request
   (lsp--make-request "$ccls/fileInfo"
                      `(:textDocument ,(lsp--text-document-identifier)))))

(defun ccls-preprocess-file (&optional output-buffer)
  "Preprocess selected buffer."
  (interactive)
  (lsp--cur-workspace-check)
  (-when-let* ((mode major-mode)
               (info (ccls-file-info))
               (args (seq-into (gethash "args" info) 'vector))
               (new-args (let ((i 0) ret)
                           (while (< i (length args))
                             (let ((arg (elt args i)))
                               (cond
                                ((string= arg "-o") (cl-incf i))
                                ((string-match-p "\\`-o.+" arg))
                                (t (push arg ret))))
                             (cl-incf i))
                           (nreverse ret))))
    (with-current-buffer (or output-buffer
                             (get-buffer-create
                              (format "*lsp-ccls preprocess %s*" (buffer-name))))
      (pop-to-buffer (current-buffer))
      (with-silent-modifications
        (erase-buffer)
        (insert (format "// Generated by: %s"
                        (combine-and-quote-strings new-args)))
        (insert (with-output-to-string
                  (with-current-buffer standard-output
                    (apply #'process-file (car new-args) nil t nil "-E" (cdr new-args)))))
        (delay-mode-hooks (funcall mode))
        (setq buffer-read-only t)))))

(defun ccls-reload ()
  "Reset database and reload cached index files."
  (interactive)
  (lsp--cur-workspace-check)
  (lsp--send-notification
   (lsp--make-notification "$ccls/reload" (list :whitelist []
                                                :blacklist []))))

(defun ccls-navigate (direction)
  "Navigate to a nearby outline symbol.
DIRECTION can be \"D\", \"L\", \"R\" or \"U\"."
  (lsp-find-custom "$ccls/navigate" `(:direction ,direction)))

;; ---------------------------------------------------------------------
;;  Register lsp client
;; ---------------------------------------------------------------------

(defun ccls--make-renderer (mode)
  `(lambda (str)
     (with-temp-buffer
       (delay-mode-hooks (,(intern (format "%s-mode" mode))))
       (insert str)
       (font-lock-ensure)
       (buffer-string))))

(defun ccls--initialize-client (client)
  (dolist (p ccls--handlers)
    (lsp-client-on-notification client (car p) (cdr p)))
  (lsp-provide-marked-string-renderer client "c" (ccls--make-renderer "c"))
  (lsp-provide-marked-string-renderer client "cpp" (ccls--make-renderer "c++"))
  (lsp-provide-marked-string-renderer client "objectivec" (ccls--make-renderer "objc")))

(defun ccls--get-init-params (workspace)
  `(:cacheDirectory ,(file-name-as-directory
                      (expand-file-name ccls-cache-dir (lsp--workspace-root workspace)))
                    ,@ccls-extra-init-params)) ; TODO: prog reports for modeline

;;;###autoload (autoload 'lsp-ccls-enable "ccls")
(lsp-define-stdio-client
 lsp-ccls "cpp" #'ccls--get-root
 `(,ccls-executable ,@ccls-extra-args)
 :initialize #'ccls--initialize-client
 :extra-init-params #'ccls--get-init-params)

(provide 'ccls)
;;; ccls.el ends here
