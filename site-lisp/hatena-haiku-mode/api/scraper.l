;;;; -*- mode: lisp; package: hatena-haiku.api -*-
;;;;
;;;; File: hatena-haiku-mode/api/scraper.l
;;;;
;;;; License:
;;;;
;;;;   Copyright (c) 2008 MIYAMUKO Katsuyuki.
;;;;
;;;;   hatena-haiku-mode is released under an MIT license.
;;;;   See hatena-haiku-mode/docs/MIT-LICENSE for full license.
;;;;

(eval-when (:compile-toplevel :load-toplevel :execute)
  (require "hatena-haiku-mode/api/package")
  )

(in-package :hatena-haiku.api)

(defparameter *scraper-keyword-regexp-alist*
  '((:sp . "[ \t\r\f\n]*")
    (:tag . "<[^<>]+>")
    (:tag* . "\\(?:<[^<>]+>\\)*")
    ))

(defun preprocess-regexp (regexp)
  (if (listp regexp)
      (let ((re (sublis *scraper-keyword-regexp-alist* regexp)))
        (awhen (remove-if #'stringp re)
          (error 'type-error
                 :datum _it_
                 :expected-type '(or string :sp)))
        (format nil "~{~A~}" re))
    regexp))


(defstruct scraper-spec-group
  index
  name
  filter
  strip-p)

(defstruct scraper-spec
  regexp
  group
  multiline-p)

(defmacro define-scraper (&body body)
  `(macrolet ((group (index name &key filter (strip t))
                `(make-scraper-spec-group :index ,index
                                          :name ,name
                                          :filter (or ,filter #'identity)
                                          :strip-p ,strip))
              (scrape ((regexp &key multiline) &rest body)
                `(make-scraper-spec :regexp ,regexp
                                    :multiline-p ,multiline
                                    :group (list ,@body))))
     (list ,@body)))


(defun scraper-spec-group->alist (g matched)
  (when matched
    (cons (scraper-spec-group-name g)
          (funcall (scraper-spec-group-filter g)
                   (strip-if (scraper-spec-group-strip-p g)
                             matched)))))


(defun html-cleanup-filter ()
  (delete-extra-alt-newline-buffer (selected-buffer))
  (goto-char (point-min))
  (alt-newline->newline-buffer (selected-buffer)))


(defun scrape-one (contents specs)
  (car (scrape contents specs :maxscan 1)))

(defun scrape (contents specs &key maxscan)
  (when contents
    (scrape0 contents specs :maxscan maxscan)))

(defun scrape0 (contents specs &key maxscan)
  (flet ((scan-spec (spec)
           (with-multiline-regexp-buffer-if ((scraper-spec-multiline-p spec) (selected-buffer))
             (goto-char (point-min))
             (map-scan-buffer ((preprocess-regexp (scraper-spec-regexp spec))
                               :regexp t :tail t :maxscan maxscan)
               (compact
                (mapcar #'(lambda (g)
                            (scraper-spec-group->alist
                             g (match-string (scraper-spec-group-index g))))
                        (scraper-spec-group spec))))))
         (merge-alist (lst)
           (when lst
             (apply 'mapcar 'append lst))))
    (with-temporary-buffer ((force contents) 'html-cleanup-filter)
      (merge-alist (compact (mapcar #'scan-spec specs))))))


(defun extract-one (contents open end &key (inner-text-only t) (strip t))
  (car (extract contents open end :inner-text-only inner-text-only :strip strip :maxscan 1)))

(defun extract (contents open end &key (inner-text-only t) (strip t) (maxscan -1))
  (when contents
    (extract0 contents open end :inner-text-only inner-text-only :strip strip :maxscan maxscan)))

(defun extract0 (contents open end &key inner-text-only strip maxscan)
  (setf open (preprocess-regexp open))
  (setf end (preprocess-regexp end))
  (with-temporary-buffer ((force contents) 'html-cleanup-filter)
    (let ((result))
      (while (scan-buffer open :regexp t :tail inner-text-only)
        (let ((start (point)))
          (goto-char (match-end 0))
          (when (and (scan-buffer end :regexp t :tail (not inner-text-only))
                     (not (= start (point))))
            (push (strip-if strip (buffer-substring start (point))) result)
            (when (zerop (decf maxscan))
              (return)))))
      (reverse result))))


(provide "hatena-haiku-mode/api/scraper")

;;;; End
