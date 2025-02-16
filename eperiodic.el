;;; eperiodic.el --- periodic table for Emacs -*- lexical-binding: t -*-

;;; Copyright (C) 2002, 2003, 2004 Matthew P. Hodges

;; Author: Matthew P. Hodges <MPHodges@member.fsf.org>
;; Version: $Id: eperiodic.el,v 1.96 2023-03-22

;; eperiodic.el is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation; either version 2, or (at
;; your option) any later version.

;; eperiodic.el is distributed in the hope that it will be useful, but
;; WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
;; General Public License for more details.

;;; Commentary:

;; Package to display a periodic table in Emacs.

;; The data were mostly derived from the GPeriodic package, available
;; from <http://gperiodic.seul.org/>. Thanks are due to Kyle R. Burton
;; <mortis@voicenet.com> for making available the raw data needed for
;; this package.

;; Updated 2016-09-25 for GNU Emacs 24+ compatibility by Mark Oteiza
;; <mvoteiza@udel.edu>

;; Updated 2023-03-22 by Egor Maltsev <x0o1@ya.ru>
;; Add new elements, improve code.

;;; Code:

(defconst eperiodic-version "2.0.1"
  "Version number of this package.")

(eval-when-compile (require 'cl-lib))

;; Customizable variables

;; TODO set github link
(defgroup eperiodic nil
  "Periodic table for Emacs."
  :group 'tools
  :link '(url-link ""))

(defcustom eperiodic-display-type 'conventional
  "*Order the orbitals are shown in.
The symbol conventional leads to the lanthanides and actinides being
shown in separate rows. The symbol ordered leads to all the elements
being shown in order."
  :group 'eperiodic
  :type '(choice (const :tag "Separate lanthanides/actinides" conventional)
                 (const :tag "By atomic number" ordered))
  :set (lambda (sym val)
         (set-default sym val)
         (when (fboundp 'eperiodic-display)
           (mapcar (lambda (b)
                     (with-current-buffer b
                       (when (eq major-mode 'eperiodic-mode)
                         (setq eperiodic-display-type val)
                         (eperiodic-display)
                         (set-buffer-modified-p nil))))
                   (buffer-list)))))
(make-variable-buffer-local 'eperiodic-display-type)

(defcustom eperiodic-display-indentation 2
  "*Width of indentation at left-hand side of periodic table."
  :group 'eperiodic
  :type 'integer)

(defcustom eperiodic-element-display-width 2
  "*Width each element is displayed with.
Note that a minimum value of 3 is enforced."
  :group 'eperiodic
  :type 'integer)

(defcustom eperiodic-element-separation 1
  "*Width of whitespace each element is separated by."
  :group 'eperiodic
  :type 'integer)

(defcustom eperiodic-use-popup-help nil
  "*Choose whether or not to use help-echo property."
  :group 'eperiodic
  :type 'boolean)

(defcustom eperiodic-dict-program
  (if (file-executable-p "/usr/bin/dict")
      "/usr/bin/dict"
    nil)
  "*The command to use to run dict for eperiodic."
  :group 'eperiodic
  :type '(file :must match t))

(defcustom eperiodic-dict-dictionary
  (when eperiodic-dict-program
    (with-temp-buffer
      (call-process eperiodic-dict-program nil t nil "-D" "-P-")
      (goto-char (point-min))
      (cond
       ((re-search-forward "elements\\s-+The Elements" nil t)
        "elements")
       ((re-search-forward "wn\\s-+Wordnet" nil t)
        "wn")
       (t
        nil))))
  "*The dictionary for `eperiodic-dict-program' to use."
  :group 'eperiodic
  :type 'string)

(defcustom eperiodic-dict-dictionary-arg "-d"
  "*The flag to specify the dictionary for `eperiodic-dict-program'."
  :group 'eperiodic
  :type 'string)

(defcustom eperiodic-dict-nopager-arg "-P-"
  "*The flag to specify no paging for `eperiodic-dict-program'."
  :group 'eperiodic
  :type 'string)

(defcustom eperiodic-web-lookup-location nil
  "*Location to look up extra details about element of the Internet.
The token %s will be substituted by the atomic symbol and %n by the
atomic name."
  :group 'eperiodic
  :type '(choice (const :tag "WebElements"
                        "http://www.webelements.com/webelements/elements/text/%s/key.html")
                 ;; TODO https://webelements.com/_media/elements/element_pictures/Ce.jpg
                 (const :tag "WebElements (image)"
                        "http://www.webelements.com/webelements/elements/media/element-pics/%s.jpg")
                 (const :tag "Dict"
                        "http://www.dict.org/bin/Dict?Form=Dict2&Database=elements&Query=%n")
                 (const :tag "None" nil)))

(defcustom eperiodic-ignored-properties nil
  "List of properties not used by `eperiodic-update-element-info'."
  :group 'eperiodic
  :type '(repeat symbol))

(defvar eperiodic-colour-element-generic-functions
  '(eperiodic-colour-element-by-atomic-mass
    eperiodic-colour-element-by-density
    eperiodic-colour-element-by-atomic-radius
    eperiodic-colour-element-by-covalent-radius
    eperiodic-colour-element-by-ionic-radius
    eperiodic-colour-element-by-atomic-volume
    eperiodic-colour-element-by-specific-heat
    eperiodic-colour-element-by-fusion-heat
    eperiodic-colour-element-by-evaporation-heat
    eperiodic-colour-element-by-thermal-conductivity
    eperiodic-colour-element-by-debye-temperature
    eperiodic-colour-element-by-pauling-negativity-number
    eperiodic-colour-element-by-first-ionization-energy
    eperiodic-colour-element-by-lattice-constant
    eperiodic-colour-element-by-lattice-c/a-ratio)
  "List of functions that use `eperiodic-colour-element-generic'.")

(defvar eperiodic-colour-element-functions
  (nconc
   '(eperiodic-colour-element-by-group
     eperiodic-colour-element-by-state
     eperiodic-colour-element-by-discovery-date
     eperiodic-colour-element-by-oxidation-states)
   eperiodic-colour-element-generic-functions)
  "List of functions that can be used to colour elements.")

(defcustom eperiodic-colour-element-function
  'eperiodic-colour-element-by-group
  "Function used to colour elements.
One of `eperiodic-colour-element-functions'."
  :group 'eperiodic
  :type (let ((choices
               (mapcar (lambda (elt) (list 'const elt))
                       eperiodic-colour-element-functions)))
          (nconc '(choice) choices)))
(make-variable-buffer-local 'eperiodic-colour-element-function)

(defcustom eperiodic-precision 0.005
  "Precision used when incrementing and testing property values."
  :group 'eperiodic
  :type 'float)

;; Miscellaneous variables

(defvar eperiodic-element-end-marker nil
  "Marker for the end of the displayed elements.")
(make-variable-buffer-local 'eperiodic-element-end-marker)

(defvar eperiodic-last-displayed-element 1
  "The Z value for the element last displayed.
Used to avoid redisplaying the same information.")
(make-variable-buffer-local 'eperiodic-last-displayed-element)

(defvar eperiodic-post-display-hook nil
  "Hook run after display is updated.

For example:

  (add-hook 'eperiodic-post-display-hook
            'eperiodic-show-dictionary-entry)

will lead to dictionary information being updated automatically.")

(defvar eperiodic-current-temperature 298
  "Current temperature for EPeriodic (in Kelvin).
This is used by `eperiodic-colour-element-by-element'.")
(make-variable-buffer-local 'eperiodic-current-temperature)

(defvar eperiodic-current-year 1800
  "Current year for EPeriodic.
This is used by `eperiodic-colour-element-by-discovery-date'.")
(make-variable-buffer-local 'eperiodic-current-year)

(defvar eperiodic-current-property-values nil
  "Current property values used in `eperiodic-colour-element-generic'.
See `eperiodic-set-current-property-values' for details of their
initialization.")
(make-variable-buffer-local 'eperiodic-current-property-values)

;; Faces

(defface eperiodic-header-face
  '((((class color))
     (:bold t)))
  "Face used for the header."
  :group 'eperiodic)

(defface eperiodic-group-number-face
  '((((class color))
     (:inherit eperiodic-generic-block-face :bold t :foreground "orange red")))
  "Face used for group numbers."
  :group 'eperiodic)

(defface eperiodic-period-number-face
  '((((class color))
     (:bold t :foreground "orange red")))
  "Face used for group numbers."
  :group 'eperiodic)

;; We define this to make it convenient to change all the faces that
;; inherit its properties. Note that we go to the trouble of
;; defining/using such a face for the padding as some types of face
;; (e.g. boxed) can lead to text misalignments due to their additional
;; width.

(defface eperiodic-generic-block-face
  '((((class color))
     ;; (:box (:line-width 2 :style released-button))
     ))
  "Face used for all elements.
The properties of this face are inherited by others."
  :group 'eperiodic)

(defface eperiodic-padding-face
  '((((class color))
     (:inherit eperiodic-generic-block-face)))
  "Face used for padding between blocks."
  :group 'eperiodic)

(defface eperiodic-s-block-face
  '((((class color))
     (:inherit eperiodic-generic-block-face :background "red1" :foreground "black")))
  "Eperiodic face for s-block elements."
  :group 'eperiodic)

(defface eperiodic-p-block-face
  '((((class color))
     (:inherit eperiodic-generic-block-face :background "gold" :foreground "black")))
  "Eperiodic face for p-block elements."
  :group 'eperiodic)

(defface eperiodic-d-block-face
  '((((class color) (background light))
     (:inherit eperiodic-generic-block-face :background "dodger blue" :foreground "black"))
    (((class color) (background dark))
     (:inherit eperiodic-generic-block-face :background "dodger blue" :foreground "black")))
  "Eperiodic face for d-block elements."
  :group 'eperiodic)

(defface eperiodic-f-block-face
  '((((class color) (background light))
     (:inherit eperiodic-generic-block-face :background "lawn green" :foreground "black"))
    (((class color) (background dark))
     (:inherit eperiodic-generic-block-face :background "lawn green" :foreground "black")))
  "Eperiodic face for f-block elements."
  :group 'eperiodic)

(defface eperiodic-solid-face
  '((((class color))
     (:inherit eperiodic-generic-block-face :background "brown" :foreground "white")))
  "Eperiodic face for solid elements."
  :group 'eperiodic)

(defface eperiodic-liquid-face
  '((((class color))
     (:inherit eperiodic-generic-block-face :background "blue2" :foreground "white")))
  "Eperiodic face for liquid elements."
  :group 'eperiodic)

(defface eperiodic-gas-face
  '((((class color))
     (:inherit eperiodic-generic-block-face :background "yellow" :foreground "black")))
  "Eperiodic face for gas elements."
  :group 'eperiodic)

(defface eperiodic-discovered-before-face
  '((((class color) (background light))
     (:inherit eperiodic-generic-block-face :background "green" :foreground "black"))
    (((class color) (background dark))
     (:inherit eperiodic-generic-block-face :background "green2" :foreground "black")))
  "Eperiodic face for before elements."
  :group 'eperiodic)

(defface eperiodic-discovered-after-face
  '((((class color))
     (:inherit eperiodic-generic-block-face :background "yellow" :foreground "black")))
  "Eperiodic face for after elements."
  :group 'eperiodic)

(defface eperiodic-discovered-during-face
  '((((class color) (background light))
     (:inherit eperiodic-generic-block-face :background "red" :foreground "black"))
    (((class color) (background dark))
     (:inherit eperiodic-generic-block-face :background "red" :foreground "white")))
  "Eperiodic face for during elements."
  :group 'eperiodic)

(defface eperiodic-known-to-ancients-face
  '((((class color))
     (:inherit eperiodic-generic-block-face :background "blue2" :foreground "white")))
  "Eperiodic face for known to ancients elements."
  :group 'eperiodic)

(defface eperiodic-unknown-face
  '((((class color))
     (:inherit eperiodic-generic-block-face :foreground "grey")))
  "Eperiodic face for unknown elements."
  :group 'eperiodic)

(defface eperiodic-1-face
  '((((class color))
     (:inherit eperiodic-generic-block-face :background "blue2" :foreground "white")))
  "Eperiodic face for 1 elements.")

(defface eperiodic-2-face
  '((((class color))
     (:inherit eperiodic-generic-block-face :background "yellow" :foreground "black")))
  "Eperiodic face for 2 elements.")

(defface eperiodic-3-face
  '((((class color) (background light))
     (:inherit eperiodic-generic-block-face :background "red" :foreground "black"))
    (((class color) (background dark))
     (:inherit eperiodic-generic-block-face :background "red" :foreground "white")))
  "Eperiodic face for 3 elements.")

(defface eperiodic-4-face
  '((((class color) (background light))
     (:inherit eperiodic-generic-block-face :background "green" :foreground "black"))
    (((class color) (background dark))
     (:inherit eperiodic-generic-block-face :background "green2" :foreground "black")))
  "Eperiodic face for 4 elements.")

(defface eperiodic-5-face
  '((((class color))
     (:inherit eperiodic-generic-block-face :foreground "blue2" :background "white")))
  "Eperiodic face for 5 elements.")

(defface eperiodic-6-face
  '((((class color))
     (:inherit eperiodic-generic-block-face :foreground "yellow" :background "black")))
  "Eperiodic face for 6 elements.")

(defface eperiodic-7-face
  '((((class color) (background light))
     (:inherit eperiodic-generic-block-face :foreground "red" :background "black"))
    (((class color) (background dark))
     (:inherit eperiodic-generic-block-face :foreground "red" :background "white")))
  "Eperiodic face for 7 elements.")

(defface eperiodic-less-than-face
  '((((class color) (background light))
     (:inherit eperiodic-generic-block-face :background "green" :foreground "black"))
    (((class color) (background dark))
     (:inherit eperiodic-generic-block-face :background "green2" :foreground "black")))
  "Eperiodic face for less than elements."
  :group 'eperiodic)

(defface eperiodic-equal-to-face
  '((((class color) (background light))
     (:inherit eperiodic-generic-block-face :background "red" :foreground "black"))
    (((class color) (background dark))
     (:inherit eperiodic-generic-block-face :background "red" :foreground "white")))
  "Eperiodic face for equal to elements."
  :group 'eperiodic)

(defface eperiodic-greater-than-face
  '((((class color))
     (:inherit eperiodic-generic-block-face :background "yellow" :foreground "black")))
  "Eperiodic face for greater than elements."
  :group 'eperiodic)

;; Constants

(defconst eperiodic-orbital-order
  '(1s 2s 2p 3s 3p 4s 3d 4p 5s 4d 5p 6s 4f 5d 6p 7s 5f 6d 7p)
  "Order of atomic orbitals.
Filled according to the Aufbau principle (mostly).")

(defconst eperiodic-orbital-degeneracies
  '(("s" . 2)
    ("p" . 6)
    ("d" . 10)
    ("f" . 14))
  "Number of electrons that can populate each type of orbital.")

(defconst eperiodic-group-ranges
  '(("s" . (1 2))
    ("d" . (3 12))
    ("p" . (13 18))
    ("f" . (19 32)))
  "Group numbers spanned by each type of orbital.
Numbers aren't displayed for f orbitals.")

(defconst eperiodic-display-block-orders
  '((conventional (s d p))
    (ordered (s f d p)))
  "List of orders of displayed blocks of elements.
See also `eperiodic-display-lists'.")

(defconst eperiodic-orbital-faces
  '(("s" . eperiodic-s-block-face)
    ("p" . eperiodic-p-block-face)
    ("d" . eperiodic-d-block-face)
    ("f" . eperiodic-f-block-face))
  "Faces used for the different blocks of elements.")

(defconst eperiodic-orbital-z-value-map
  (let ((order eperiodic-orbital-order)
        (result)
        (z 0)
        degeneracy)
    (while order
      ;; Get the degeneracy for each orbital and work out range of Z
      (setq degeneracy (cdr (assoc (substring (symbol-name (car order)) 1 2)
                                   eperiodic-orbital-degeneracies)))
      (setq result (cons
                    (cons (car order) (cons (1+ z) (+ degeneracy z)))
                    result))
      (setq z (+ z degeneracy))
      (setq order (cdr order)))
    (setq result (reverse result))
    result)
  "Mapping of atomic orbitals to ranges of Z.")

(defconst eperiodic-elec-configs
  (let ((order eperiodic-orbital-order)
        (rare-gases '((2  . "He")
                      (10 . "Ne")
                      (18 . "Ar")
                      (36 . "Kr")
                      (54 . "Xe")
                      (86 . "Rn")))
        (so-far "")
        (z 1)
        label degeneracy orbital rare-gas result)
    (while order
      (setq orbital (symbol-name (car order)))
      ;; Work number of electrons for each orbital
      (setq degeneracy (cdr (assoc (substring (symbol-name (car order)) 1 2)
                                   eperiodic-orbital-degeneracies)))
      ;; Loop over z
      (cl-loop for i from z to (+ z degeneracy -1) by 1
            do
            (setq label (concat so-far orbital (format "-%d" (1+ (- i z))) " "))
            (setq result
                  (cons (cons i label) result)))
      ;; Substitute rare-gas configurations
      (setq rare-gas (cdr (assoc (+ z degeneracy -1) rare-gases)))
      (if rare-gas
          (setq so-far (format "[%s] " rare-gas))
        (setq so-far label))
      (setq order (cdr order)
            z (+ z degeneracy)))
    (setq result (reverse result))
    result)
  "Mapping of atomic numbers to electronic configurations.
These can be overridden by entries in
`eperiodic-aufbau-exceptions'.")

;; Taken from electronic configurations compiled in Cotton and
;; Wilkinson; should store configurations and build strings.

(defvar eperiodic-aufbau-exceptions
  '((24  . "[Ar] 4s-1 3d-5")
    (29  . "[Ar] 4s-1 3d-10")
    (41  . "[Kr] 5s-1 4d-4")
    (42  . "[Kr] 5s-1 4d-5")
    (43  . "[Kr] 5s-1 4d-6")
    (44  . "[Kr] 5s-1 4d-7")
    (45  . "[Kr] 5s-1 4d-8")
    (46  . "[Kr] 4d-10")
    (47  . "[Kr] 5s-1 4d-10")
    (57  . "[Xe] 6s-2 5d-1")
    (64  . "[Xe] 6s-2 4f-7 5d-1")
    (78  . "[Xe] 6s-1 4f-14 5d-9")
    (79  . "[Xe] 6s-1 4f-14 5d-10")
    (89  . "[Rn] 7s-2 6d-1")
    (90  . "[Rn] 7s-2 6d-2")
    (91  . "[Rn] 7s-2 5f-2 6d-1")
    (92  . "[Rn] 7s-2 5f-3 6d-1")
    (96  . "[Rn] 7s-2 5f-7 6d-1")
    (97  . "[Rn] 7s-2 5f-8 6d-1")
    ;;     (103 . "[Rn] 7s-2 5f-14 6d-1")
    )
  "Mapping of atomic numbers to electronic non-Aufbau configurations.")

(defvar eperiodic-display-lists
  '(
    ;; lanthanides/actinides below main table
    (conventional
     (1s)
     (2s 0d 2p)                         ; 0d for padding
     (3s 0d 3p)                         ; 0d for padding
     (4s 3d 4p)
     (5s 4d 5p)
     (6s 5d 6p)                         ; 4f removed (lanthanides)
     (7s 6d 7p)                         ; 5f removed (actinides)
     ()                            ; Blank line before the lanthanides
     (0s 4f 0s)                         ; 0s gives the padding we want
     (0s 5f 0s))                        ; 0s gives the padding we want
    ;; all elements in order of atomic number
    (ordered
     (1s)
     (2s 0f 0d 2p)                      ; 0f 0d for padding
     (3s 0f 0d 3p)                      ; 0f 0d for padding
     (4s 0f 3d 4p)                      ; 0f for padding
     (5s 0f 4d 5p)                      ; 0f for padding
     (6s 4f 5d 6p)
     (7s 5f 6d 7p)))
  "Mapping of display type to order of displayed orbitals.
Each entry in the display order corresponds to a line of atomic
orbitals. Padding for any an x-type orbital can be inserted using the
symbol 0x.")

;; Data taken from the GPeriodic package.

(defconst eperiodic-stored-properties
  '((symbol)
    (atomic-mass . "amu")
    (density . "g/cm^3")
    (melting-point . "K")
    (boiling-point . "K")
    (atomic-radius . "pm")
    (covalent-radius . "pm")
    (ionic-radius . "pm")
    (atomic-volume . "cm^3/mol")
    (specific-heat . "J/g mol (@20 deg C)")
    (fusion-heat . "kJ/mol")
    (evaporation-heat . "kJ/mol")
    (thermal-conductivity . "W/m K (@25 deg C)")
    (debye-temperature . "K")
    (pauling-negativity-number)
    (first-ionization-energy . "kJ/mol")
    (oxidation-states)
    (electronic-configuration)
    (lattice-structure)
    (lattice-constant . "Angstrom")
    (lattice-c/a-ratio)
    (appearance)
    (discovery-date)
    (discovered-by)
    (named-after))
  "List of properties for which eperiodic has data.
Units are also listed here.")

(defvar eperiodic-printed-properties
  (mapcar #'car eperiodic-stored-properties)
  "List of properties printed by `eperiodic-update-element-info'.")

(defconst eperiodic-element-properties
  '((1
     (name . "Hydrogen")
     (symbol . "H")
     (atomic-mass . "1.00794")
     (density . "0.0708 (@ -253 deg C)")
     (melting-point . "14.01")
     (boiling-point . "20.28")
     (atomic-radius . "79")
     (covalent-radius . "32")
     (ionic-radius . "154 (-1e)")
     (atomic-volume . "14.1")
     (specific-heat . "14.267 (H-H)")
     (fusion-heat . "0.117 (H-H)")
     (evaporation-heat . "0.904 (H-H)")
     (thermal-conductivity . "0.1815")
     (debye-temperature . "110.00")
     (pauling-negativity-number . "2.20")
     (first-ionization-energy . "1311.3")
     (oxidation-states . "1, -1")
     (lattice-structure . "HEX")
     (lattice-constant . "3.750")
     (lattice-c/a-ratio . "1.731")
     (appearance . "Colorless, odorless, tasteless gas")
     (discovery-date . "1766 (England)")
     (discovered-by . "Henry Cavendish")
     (named-after . "Greek: hydro (water) and genes (generate)"))

    (2
     (name . "Helium")
     (symbol . "He")
     (atomic-mass . "4.002602")
     (density . "0.147 (@ -270 deg C)")
     (melting-point . "0.95")
     (boiling-point . "4.216")
     (atomic-radius . "0.0")
     (covalent-radius . "n/a")
     (ionic-radius . "93")
     (atomic-volume . "31.8")
     (specific-heat . "5.188")
     (fusion-heat . "n/a")
     (evaporation-heat . "0.08")
     (thermal-conductivity . "0.152")
     (debye-temperature . "n/a")
     (pauling-negativity-number . "n/a")
     (first-ionization-energy . "2361.3")
     (oxidation-states . "n/a")
     (lattice-structure . "HEX")
     (lattice-constant . "3.570")
     (lattice-c/a-ratio . "1.633")
     (appearance . "Inert, colorless, odorless, tasteless gas")
     (discovery-date . "1895 (Scotland/Sweden)")
     (discovered-by . "Sir William Ramsey, Nils Langet, P.T.Cleve")
     (named-after . "Greek: helios (sun)."))

    (3
     (name . "Lithium")
     (symbol . "Li")
     (atomic-mass . "6.941")
     (density . "0.534")
     (melting-point . "553.69")
     (boiling-point . "1118.15")
     (atomic-radius . "155")
     (covalent-radius . "163")
     (ionic-radius . "68 (+1e)")
     (atomic-volume . "13.1")
     (specific-heat . "3.489")
     (fusion-heat . "2.89")
     (evaporation-heat . "148")
     (thermal-conductivity . "84.8")
     (debye-temperature . "400.00")
     (pauling-negativity-number . "0.98")
     (first-ionization-energy . "519.9")
     (oxidation-states . "1")
     (lattice-structure . "BCC")
     (lattice-constant . "3.490")
     (lattice-c/a-ratio . "n/a")
     (appearance . "Soft, silvery-white metal")
     (discovery-date . "1817 (Sweden)")
     (discovered-by . "Johann Arfwedson")
     (named-after . "Greek: lithos (stone)."))

    (4
     (name . "Beryllium")
     (symbol . "Be")
     (atomic-mass . "9.01218")
     (density . "1.848")
     (melting-point . "1551")
     (boiling-point . "3243")
     (atomic-radius . "112")
     (covalent-radius . "90")
     (ionic-radius . "35 (+2e)")
     (atomic-volume . "5.0")
     (specific-heat . "1.824")
     (fusion-heat . "12.21")
     (evaporation-heat . "309")
     (thermal-conductivity . "201")
     (debye-temperature . "1000.00")
     (pauling-negativity-number . "1.57")
     (first-ionization-energy . "898.8")
     (oxidation-states . "2")
     (lattice-structure . "HEX")
     (lattice-constant . "2.290")
     (lattice-c/a-ratio . "1.567")
     (appearance . "Hard, brittle, steel-gray metal")
     (discovery-date . "1798 (Germany/France)")
     (discovered-by . "Fredrich Wöhler, A.A.Bussy")
     (named-after . "Greek: beryllos, 'beryl' (a mineral)."))

    (5
     (name . "Boron")
     (symbol . "B")
     (atomic-mass . "10.811")
     (density . "2.34")
     (melting-point . "2573")
     (boiling-point . "3931")
     (atomic-radius . "98")
     (covalent-radius . "82")
     (ionic-radius . "23 (+3e)")
     (atomic-volume . "4.6")
     (specific-heat . "1.025")
     (fusion-heat . "23.60")
     (evaporation-heat . "504.5")
     (thermal-conductivity . "27.4")
     (debye-temperature . "1250.00")
     (pauling-negativity-number . "2.04")
     (first-ionization-energy . "800.2")
     (oxidation-states . "3")
     (lattice-structure . "TET")
     (lattice-constant . "8.730")
     (lattice-c/a-ratio . "0.576")
     (appearance . "Hard, brittle, lustrous black semimetal")
     (discovery-date . "1808 (England/France)")
     (discovered-by . "Sir H. Davy, J.L. Gay-Lussac, L.J. Thénard")
     (named-after . "The Arabic and Persian words for borax."))

    (6
     (name . "Carbon")
     (symbol . "C")
     (atomic-mass . "12.011")
     (density . "2.25 (graphite)")
     (melting-point . "3820")
     (boiling-point . "5100")
     (atomic-radius . "91")
     (covalent-radius . "77")
     (ionic-radius . "16 (+4e) 260 (-4e)")
     (atomic-volume . "5.3")
     (specific-heat . "0.711")
     (fusion-heat . "n/a")
     (evaporation-heat . "n/a")
     (thermal-conductivity . "1.59")
     (debye-temperature . "1860.00")
     (pauling-negativity-number . "2.55")
     (first-ionization-energy . "1085.7")
     (oxidation-states . "4, 2, -4")
     (lattice-structure . "DIA")
     (lattice-constant . "3.570")
     (lattice-c/a-ratio . "n/a")
     (appearance . "Dense, Black")
     (discovery-date . "n/a (Unknown)")
     (discovered-by . "Known to the ancients")
     (named-after . "Latin: carbo, (charcoal)."))

    (7
     (name . "Nitrogen")
     (symbol . "N")
     (atomic-mass . "14.00674")
     (density . "0.808 (@ -195.8 deg C)")
     (melting-point . "63.29")
     (boiling-point . "77.4")
     (atomic-radius . "92")
     (covalent-radius . "75")
     (ionic-radius . "13 (+5e) 171 (-3e)")
     (atomic-volume . "17.3")
     (specific-heat . "1.042 (N-N)")
     (fusion-heat . "n/a")
     (evaporation-heat . "n/a")
     (thermal-conductivity . "0.026")
     (debye-temperature . "n/a")
     (pauling-negativity-number . "3.04")
     (first-ionization-energy . "1401.5")
     (oxidation-states . "5, 4, 3, 2, -3")
     (lattice-structure . "HEX")
     (lattice-constant . "4.039")
     (lattice-c/a-ratio . "1.651")
     (appearance . "Colorless, odorless, tasteless, and generally inert gas")
     (discovery-date . "1772 (Scotland)")
     (discovered-by . "Daniel Rutherford")
     (named-after . "Greek: nitron and genes, (soda forming)."))

    (8
     (name . "Oxygen")
     (symbol . "O")
     (atomic-mass . "15.9994")
     (density . "1.149 (@ -183 deg C)")
     (melting-point . "54.8")
     (boiling-point . "90.19")
     (atomic-radius . "n/a")
     (covalent-radius . "73")
     (ionic-radius . "132 (-2e)")
     (atomic-volume . "14.0")
     (specific-heat . "0.916 (O-O)")
     (fusion-heat . "n/a")
     (evaporation-heat . "n/a")
     (thermal-conductivity . "0.027")
     (debye-temperature . "n/a")
     (pauling-negativity-number . "3.44")
     (first-ionization-energy . "1313.1")
     (oxidation-states . "-2, -1")
     (lattice-structure . "CUB")
     (lattice-constant . "6.830")
     (lattice-c/a-ratio . "n/a")
     (appearance . "Colorless, odorless, tasteless gas; pale blue liquid")
     (discovery-date . "1774 (England/Sweden)")
     (discovered-by . "Joseph Priestly, Carl Wilhelm Scheele")
     (named-after . "Greek: oxys and genes, (acid former)."))

    (9
     (name . "Fluorine")
     (symbol . "F")
     (atomic-mass . "18.998403")
     (density . "1.108 (@ -189 deg C)")
     (melting-point . "53.53")
     (boiling-point . "85.01")
     (atomic-radius . "n/a")
     (covalent-radius . "72")
     (ionic-radius . "133 (-1e)")
     (atomic-volume . "17.1")
     (specific-heat . "0.824 (F-F)")
     (fusion-heat . "0.51 (F-F)")
     (evaporation-heat . "6.54 (F-F)")
     (thermal-conductivity . "0.028")
     (debye-temperature . "n/a")
     (pauling-negativity-number . "3.98")
     (first-ionization-energy . "1680.0")
     (oxidation-states . "-1")
     (lattice-structure . "MCL")
     (lattice-constant . "n/a")
     (lattice-c/a-ratio . "n/a")
     (appearance . "Greenish-yellow, pungent, corrosive gas")
     (discovery-date . "1886 (France)")
     (discovered-by . "Henri Moissan")
     (named-after . "Latin: fluere (flow)."))

    (10
     (name . "Neon")
     (symbol . "Ne")
     (atomic-mass . "20.1797")
     (density . "1.204 (@ -246 deg C)")
     (melting-point . "48")
     (boiling-point . "27.1")
     (atomic-radius . "n/a")
     (covalent-radius . "71")
     (ionic-radius . "n/a")
     (atomic-volume . "16.8")
     (specific-heat . "1.029")
     (fusion-heat . "n/a")
     (evaporation-heat . "1.74")
     (thermal-conductivity . "(0.0493)")
     (debye-temperature . "63.00")
     (pauling-negativity-number . "0.0")
     (first-ionization-energy . "2079.4")
     (oxidation-states . "n/a")
     (lattice-structure . "FCC")
     (lattice-constant . "4.430")
     (lattice-c/a-ratio . "n/a")
     (appearance . "Colorless, odorless, tasteless gas")
     (discovery-date . "1898 (England)")
     (discovered-by . "Sir William Ramsey, M.W. Travers")
     (named-after . "Greek: neos (new)."))

    (11
     (name . "Sodium")
     (symbol . "Na")
     (atomic-mass . "22.989768")
     (density . "0.971")
     (melting-point . "370.96")
     (boiling-point . "1156.1")
     (atomic-radius . "190")
     (covalent-radius . "154")
     (ionic-radius . "97 (+1e)")
     (atomic-volume . "23.7")
     (specific-heat . "1.222")
     (fusion-heat . "2.64")
     (evaporation-heat . "97.9")
     (thermal-conductivity . "142.0")
     (debye-temperature . "150.00")
     (pauling-negativity-number . "0.93")
     (first-ionization-energy . "495.6")
     (oxidation-states . "1")
     (lattice-structure . "BCC")
     (lattice-constant . "4.230")
     (lattice-c/a-ratio . "n/a")
     (appearance . "Soft, silvery-white metal")
     (discovery-date . "1807 (England)")
     (discovered-by . "Sir Humphrey Davy")
     (named-after . "Medieval Latin: sodanum, (headache remedy); symbol from Latin natrium, (sodium carbonate)."))

    (12
     (name . "Magnesium")
     (symbol . "Mg")
     (atomic-mass . "24.305")
     (density . "1.738")
     (melting-point . "922")
     (boiling-point . "1363")
     (atomic-radius . "160")
     (covalent-radius . "136")
     (ionic-radius . "66 (+2e)")
     (atomic-volume . "14.0")
     (specific-heat . "1.025")
     (fusion-heat . "9.20")
     (evaporation-heat . "131.8")
     (thermal-conductivity . "156")
     (debye-temperature . "318.00")
     (pauling-negativity-number . "1.31")
     (first-ionization-energy . "737.3")
     (oxidation-states . "2")
     (lattice-structure . "HEX")
     (lattice-constant . "3.210")
     (lattice-c/a-ratio . "1.624")
     (appearance . "Lightweight, malleable, silvery-white metal")
     (discovery-date . "1808 (England)")
     (discovered-by . "Sir Humphrey Davy")
     (named-after . "Magnesia, ancient city in district of Thessaly, Greece."))

    (13
     (name . "Aluminum")
     (symbol . "Al")
     (atomic-mass . "26.981539")
     (density . "2.6989")
     (melting-point . "933.5")
     (boiling-point . "2740")
     (atomic-radius . "143")
     (covalent-radius . "118")
     (ionic-radius . "51 (+3e)")
     (atomic-volume . "10.0")
     (specific-heat . "0.900")
     (fusion-heat . "10.75")
     (evaporation-heat . "284.1")
     (thermal-conductivity . "237")
     (debye-temperature . "394.00")
     (pauling-negativity-number . "1.61")
     (first-ionization-energy . "577.2")
     (oxidation-states . "3")
     (lattice-structure . "FCC")
     (lattice-constant . "4.050")
     (lattice-c/a-ratio . "n/a")
     (appearance . "Soft, lightweight, silvery-white metal")
     (discovery-date . "1825 (Denmark)")
     (discovered-by . "Hans Christian Oersted")
     (named-after . "Latin: alumen, aluminis, (alum)."))

    (14
     (name . "Silicon")
     (symbol . "Si")
     (atomic-mass . "28.0855")
     (density . "2.33")
     (melting-point . "1683")
     (boiling-point . "2628")
     (atomic-radius . "132")
     (covalent-radius . "111")
     (ionic-radius . "42 (+4e) 271  (-4e)")
     (atomic-volume . "12.1")
     (specific-heat . "0.703")
     (fusion-heat . "50.6")
     (evaporation-heat . "383")
     (thermal-conductivity . "149")
     (debye-temperature . "625.00")
     (pauling-negativity-number . "1.90")
     (first-ionization-energy . "786.0")
     (oxidation-states . "4, -4")
     (lattice-structure . "DIA")
     (lattice-constant . "5.430")
     (lattice-c/a-ratio . "n/a")
     (appearance . "Amorphous form is brown powder; crystalline form has a gray")
     (discovery-date . "1824 (Sweden)")
     (discovered-by . "Jöns Berzelius")
     (named-after . "Latin: silex, silicus, (flint)."))

    (15
     (name . "Phosphorus")
     (symbol . "P")
     (atomic-mass . "30.973762")
     (density . "1.82 (white phosphorus)")
     (melting-point . "317.3")
     (boiling-point . "553")
     (atomic-radius . "128")
     (covalent-radius . "106")
     (ionic-radius . "35 (+5e) 212 (-3e)")
     (atomic-volume . "17.0")
     (specific-heat . "0.757")
     (fusion-heat . "2.51")
     (evaporation-heat . "49.8")
     (thermal-conductivity . "(0.236)")
     (debye-temperature . "n/a")
     (pauling-negativity-number . "2.19")
     (first-ionization-energy . "1011.2")
     (oxidation-states . "5, 3, -3")
     (lattice-structure . "CUB")
     (lattice-constant . "7.170")
     (lattice-c/a-ratio . "n/a")
     (appearance . "The most common white form is a waxy, phosphorescent solid")
     (discovery-date . "1669 (Germany)")
     (discovered-by . "Hennig Brand")
     (named-after . "Greek: phosphoros, (bringer of light)."))

    (16
     (name . "Sulfur")
     (symbol . "S")
     (atomic-mass . "32.066")
     (density . "2.070")
     (melting-point . "386")
     (boiling-point . "717.824")
     (atomic-radius . "127")
     (covalent-radius . "102")
     (ionic-radius . "30 (+6e) 184 (-2e)")
     (atomic-volume . "15.5")
     (specific-heat . "0.732")
     (fusion-heat . "1.23")
     (evaporation-heat . "10.5")
     (thermal-conductivity . "0.27")
     (debye-temperature . "n/a")
     (pauling-negativity-number . "2.58")
     (first-ionization-energy . "999.0")
     (oxidation-states . "6, 4, 2, -2")
     (lattice-structure . "ORC")
     (lattice-constant . "10.470")
     (lattice-c/a-ratio . "n/a")
     (appearance . "Tasteless, odorless, light-yellow, brittle solid")
     (discovery-date . "n/a (Unknown)")
     (discovered-by . "Known to the ancients.")
     (named-after . "Latin: sulphur (brimstone)."))

    (17
     (name . "Chlorine")
     (symbol . "Cl")
     (atomic-mass . "35.4527")
     (density . "1.56 (@ -33.6 deg C)")
     (melting-point . "172.2")
     (boiling-point . "238.6")
     (atomic-radius . "n/a")
     (covalent-radius . "99")
     (ionic-radius . "27 (+7e) 181 (-1e)")
     (atomic-volume . "18.7")
     (specific-heat . "0.477 (Cl-Cl)")
     (fusion-heat . "6.41 (Cl-Cl)")
     (evaporation-heat . "20.41 (Cl-Cl)")
     (thermal-conductivity . "0.009")
     (debye-temperature . "n/a")
     (pauling-negativity-number . "3.16")
     (first-ionization-energy . "1254.9")
     (oxidation-states . "7, 5, 3, 1, -1")
     (lattice-structure . "ORC")
     (lattice-constant . "6.240")
     (lattice-c/a-ratio . "n/a")
     (appearance . "Greenish-yellow, disagreeable gas")
     (discovery-date . "1774 (Sweden)")
     (discovered-by . "Carl Wilhelm Scheele")
     (named-after . "Greek: chlôros (greenish yellow)."))

    (18
     (name . "Argon")
     (symbol . "Ar")
     (atomic-mass . "39.948")
     (density . "1.40 (@ -186 deg C)")
     (melting-point . "83.8")
     (boiling-point . "87.3")
     (atomic-radius . "2-")
     (covalent-radius . "98")
     (ionic-radius . "n/a")
     (atomic-volume . "24.2")
     (specific-heat . "0.138")
     (fusion-heat . "n/a")
     (evaporation-heat . "6.52")
     (thermal-conductivity . "0.0177")
     (debye-temperature . "85.00")
     (pauling-negativity-number . "0.0")
     (first-ionization-energy . "1519.6")
     (oxidation-states . "n/a")
     (lattice-structure . "FCC")
     (lattice-constant . "5.260")
     (lattice-c/a-ratio . "n/a")
     (appearance . "Colorless, tasteless, odorless noble gas")
     (discovery-date . "1894 (Scotland)")
     (discovered-by . "Sir William Ramsey, Baron Rayleigh")
     (named-after . "Greek: argos (inactive)."))

    (19
     (name . "Potassium")
     (symbol . "K")
     (atomic-mass . "39.0983")
     (density . "0.856")
     (melting-point . "336.8")
     (boiling-point . "1047")
     (atomic-radius . "235")
     (covalent-radius . "203")
     (ionic-radius . "133 (+1e)")
     (atomic-volume . "45.3")
     (specific-heat . "0.753")
     (fusion-heat . "102.5")
     (evaporation-heat . "2.33")
     (thermal-conductivity . "79.0")
     (debye-temperature . "100.00")
     (pauling-negativity-number . "0.82")
     (first-ionization-energy . "418.5")
     (oxidation-states . "1")
     (lattice-structure . "BCC")
     (lattice-constant . "5.230")
     (lattice-c/a-ratio . "n/a")
     (appearance . "Soft, waxy, silvery-white metal")
     (discovery-date . "1807 (England)")
     (discovered-by . "Sir Humphrey Davy")
     (named-after . "English: pot ash; symbol from Latin: kalium, (alkali)."))

    (20
     (name . "Calcium")
     (symbol . "Ca")
     (atomic-mass . "40.078")
     (density . "1.55")
     (melting-point . "1112")
     (boiling-point . "1757")
     (atomic-radius . "197")
     (covalent-radius . "174")
     (ionic-radius . "99 (+2e)")
     (atomic-volume . "29.9")
     (specific-heat . "0.653")
     (fusion-heat . "9.20")
     (evaporation-heat . "153.6")
     (thermal-conductivity . "(201)")
     (debye-temperature . "230.00")
     (pauling-negativity-number . "1.00")
     (first-ionization-energy . "589.4")
     (oxidation-states . "2")
     (lattice-structure . "FCC")
     (lattice-constant . "5.580")
     (lattice-c/a-ratio . "n/a")
     (appearance . "Fairly hard, silvery-white metal")
     (discovery-date . "1808 (England)")
     (discovered-by . "Sir Humphrey Davy")
     (named-after . "Latin: calx, calcis (lime)."))

    (21
     (name . "Scandium")
     (symbol . "Sc")
     (atomic-mass . "44.95591")
     (density . "2.99")
     (melting-point . "1814")
     (boiling-point . "3104")
     (atomic-radius . "162")
     (covalent-radius . "144")
     (ionic-radius . "72.3 (+3e)")
     (atomic-volume . "15.0")
     (specific-heat . "0.556")
     (fusion-heat . "15.8")
     (evaporation-heat . "332.7")
     (thermal-conductivity . "15.8")
     (debye-temperature . "n/a")
     (pauling-negativity-number . "1.36")
     (first-ionization-energy . "630.8")
     (oxidation-states . "3")
     (lattice-structure . "HEX")
     (lattice-constant . "3.310")
     (lattice-c/a-ratio . "1.594")
     (appearance . "Fairly soft, silvery-white metal")
     (discovery-date . "1879 (Sweden)")
     (discovered-by . "Lars Nilson")
     (named-after . "Latin: Scandia, Scandinavia."))

    (22
     (name . "Titanium")
     (symbol . "Ti")
     (atomic-mass . "47.88")
     (density . "4.54")
     (melting-point . "1933")
     (boiling-point . "3560")
     (atomic-radius . "147")
     (covalent-radius . "132")
     (ionic-radius . "68 (+4e) 94 (+2e)")
     (atomic-volume . "10.6")
     (specific-heat . "0.523")
     (fusion-heat . "18.8")
     (evaporation-heat . "422.6")
     (thermal-conductivity . "21.9")
     (debye-temperature . "380.00")
     (pauling-negativity-number . "1.54")
     (first-ionization-energy . "657.8")
     (oxidation-states . "4, 3")
     (lattice-structure . "HEX")
     (lattice-constant . "2.950")
     (lattice-c/a-ratio . "n/a")
     (appearance . "Shiny, dark-gray metal")
     (discovery-date . "1791 (England)")
     (discovered-by . "William Gregor")
     (named-after . "Greek: titanos (Titans)."))

    (23
     (name . "Vanadium")
     (symbol . "V")
     (atomic-mass . "50.9415")
     (density . "6.11")
     (melting-point . "2160")
     (boiling-point . "3650")
     (atomic-radius . "134")
     (covalent-radius . "122")
     (ionic-radius . "59 (+5e) 74 (+3e)")
     (atomic-volume . "8.35")
     (specific-heat . "0.485")
     (fusion-heat . "17.5")
     (evaporation-heat . "460")
     (thermal-conductivity . "30.7")
     (debye-temperature . "390.00")
     (pauling-negativity-number . "1.63")
     (first-ionization-energy . "650.1")
     (oxidation-states . "5, 4, 3, 2, 0")
     (lattice-structure . "BCC")
     (lattice-constant . "3.020")
     (lattice-c/a-ratio . "n/a")
     (appearance . "Soft, ductile, silvery-white metal")
     (discovery-date . "1830 (Sweden)")
     (discovered-by . "Nils Sefström")
     (named-after . "The scandinavian goddess, Vanadis."))

    (24
     (name . "Chromium")
     (symbol . "Cr")
     (atomic-mass . "51.9961")
     (density . "7.18")
     (melting-point . "2130")
     (boiling-point . "2945")
     (atomic-radius . "130")
     (covalent-radius . "118")
     (ionic-radius . "52 (+6e) 63 (+3e)")
     (atomic-volume . "7.23")
     (specific-heat . "0.488")
     (fusion-heat . "21")
     (evaporation-heat . "342")
     (thermal-conductivity . "93.9")
     (debye-temperature . "460.00")
     (pauling-negativity-number . "1.66")
     (first-ionization-energy . "652.4")
     (oxidation-states . "6, 3, 2, 0")
     (lattice-structure . "BCC")
     (lattice-constant . "2.880")
     (lattice-c/a-ratio . "n/a")
     (appearance . "Very hard, crystalline, steel-gray metal")
     (discovery-date . "1797 (France)")
     (discovered-by . "Louis Vauquelin")
     (named-after . "Greek: chrôma (color)."))

    (25
     (name . "Manganese")
     (symbol . "Mn")
     (atomic-mass . "54.93805")
     (density . "7.21")
     (melting-point . "1517")
     (boiling-point . "2235")
     (atomic-radius . "135")
     (covalent-radius . "117")
     (ionic-radius . "46 (+7e) 80 (+2e)")
     (atomic-volume . "7.39")
     (specific-heat . "0.477")
     (fusion-heat . "(13.4)")
     (evaporation-heat . "221")
     (thermal-conductivity . "(7.8)")
     (debye-temperature . "400.00")
     (pauling-negativity-number . "1.55")
     (first-ionization-energy . "716.8")
     (oxidation-states . "7, 6, 4, 3, 2, 0, -1")
     (lattice-structure . "CUB")
     (lattice-constant . "8.890")
     (lattice-c/a-ratio . "n/a")
     (appearance . "Hard, brittle, gray-white metal")
     (discovery-date . "1774 (Sweden)")
     (discovered-by . "Johann Gahn")
     (named-after . "Latin: magnes (magnet); Italian: manganese."))

    (26
     (name . "Iron")
     (symbol . "Fe")
     (atomic-mass . "55.847")
     (density . "7.874")
     (melting-point . "1808")
     (boiling-point . "3023")
     (atomic-radius . "126")
     (covalent-radius . "117")
     (ionic-radius . "64 (+3e) 74 (+2e)")
     (atomic-volume . "7.1")
     (specific-heat . "0.443")
     (fusion-heat . "13.8")
     (evaporation-heat . "~340")
     (thermal-conductivity . "80.4")
     (debye-temperature . "460.00")
     (pauling-negativity-number . "1.83")
     (first-ionization-energy . "759.1")
     (oxidation-states . "6, 3, 2, 0, -2")
     (lattice-structure . "BCC")
     (lattice-constant . "2.870")
     (lattice-c/a-ratio . "n/a")
     (appearance . "Malleable, ductile, silvery-white metal")
     (discovery-date . "n/a (Unknown)")
     (discovered-by . "Known to the ancients.")
     (named-after . "Anglo-Saxon: iron; symbol from Latin: ferrum (iron)."))

    (27
     (name . "Cobalt")
     (symbol . "Co")
     (atomic-mass . "58.9332")
     (density . "8.9")
     (melting-point . "1768")
     (boiling-point . "3143")
     (atomic-radius . "125")
     (covalent-radius . "116")
     (ionic-radius . "63 (+3e) 72 (+2e)")
     (atomic-volume . "6.7")
     (specific-heat . "0.456")
     (fusion-heat . "15.48")
     (evaporation-heat . "389.1")
     (thermal-conductivity . "100")
     (debye-temperature . "385.00")
     (pauling-negativity-number . "1.88")
     (first-ionization-energy . "758.1")
     (oxidation-states . "3, 2, 0, -1")
     (lattice-structure . "HEX")
     (lattice-constant . "2.510")
     (lattice-c/a-ratio . "n/a")
     (appearance . "Hard, ductile, lustrous bluish-gray metal")
     (discovery-date . "1739 (Sweden)")
     (discovered-by . "George Brandt")
     (named-after . "German: kobold (goblin)."))

    (28
     (name . "Nickel")
     (symbol . "Ni")
     (atomic-mass . "58.6934")
     (density . "8.902")
     (melting-point . "1726")
     (boiling-point . "3005")
     (atomic-radius . "124")
     (covalent-radius . "115")
     (ionic-radius . "69 (+2e)")
     (atomic-volume . "6.6")
     (specific-heat . "0.443")
     (fusion-heat . "17.61")
     (evaporation-heat . "378.6")
     (thermal-conductivity . "90.9")
     (debye-temperature . "375.00")
     (pauling-negativity-number . "1.91")
     (first-ionization-energy . "736.2")
     (oxidation-states . "3, 2, 0")
     (lattice-structure . "FCC")
     (lattice-constant . "3.520")
     (lattice-c/a-ratio . "n/a")
     (appearance . "Hard, malleable, silvery-white metal")
     (discovery-date . "1751 (Sweden)")
     (discovered-by . "Axel Cronstedt")
     (named-after . "German: kupfernickel (false copper)."))

    (29
     (name . "Copper")
     (symbol . "Cu")
     (atomic-mass . "63.546")
     (density . "8.96")
     (melting-point . "1356.6")
     (boiling-point . "2840")
     (atomic-radius . "128")
     (covalent-radius . "117")
     (ionic-radius . "72 (+2e) 96 (+1e)")
     (atomic-volume . "7.1")
     (specific-heat . "0.385")
     (fusion-heat . "13.01")
     (evaporation-heat . "304.6")
     (thermal-conductivity . "401")
     (debye-temperature . "315.00")
     (pauling-negativity-number . "1.90")
     (first-ionization-energy . "745.0")
     (oxidation-states . "2, 1")
     (lattice-structure . "FCC")
     (lattice-constant . "3.610")
     (lattice-c/a-ratio . "n/a")
     (appearance . "Malleable, ductile, reddish-brown metal")
     (discovery-date . "n/a (Unknown)")
     (discovered-by . "Known to the ancients.")
     (named-after . "Symbol from Latin: cuprum (island of Cyprus famed for its copper mines)."))

    (30
     (name . "Zinc")
     (symbol . "Zn")
     (atomic-mass . "65.39")
     (density . "7.133")
     (melting-point . "692.73")
     (boiling-point . "1180")
     (atomic-radius . "138")
     (covalent-radius . "125")
     (ionic-radius . "74 (+2e)")
     (atomic-volume . "9.2")
     (specific-heat . "0.388")
     (fusion-heat . "7.28")
     (evaporation-heat . "114.8")
     (thermal-conductivity . "116")
     (debye-temperature . "234.00")
     (pauling-negativity-number . "1.65")
     (first-ionization-energy . "905.8")
     (oxidation-states . "2")
     (lattice-structure . "HEX")
     (lattice-constant . "2.660")
     (lattice-c/a-ratio . "n/a")
     (appearance . "Bluish-silver, ductile metal")
     (discovery-date . "n/a (Germany)")
     (discovered-by . "Known to the ancients.")
     (named-after . "German: zink (German for tin)."))

    (31
     (name . "Gallium")
     (symbol . "Ga")
     (atomic-mass . "69.723")
     (density . "5.91")
     (melting-point . "302.93")
     (boiling-point . "2676")
     (atomic-radius . "141")
     (covalent-radius . "126")
     (ionic-radius . "62 (+3e) 81 (+1e)")
     (atomic-volume . "11.8")
     (specific-heat . "0.372")
     (fusion-heat . "5.59")
     (evaporation-heat . "270.3")
     (thermal-conductivity . "28.1")
     (debye-temperature . "240.00")
     (pauling-negativity-number . "1.81")
     (first-ionization-energy . "578.7")
     (oxidation-states . "3")
     (lattice-structure . "ORC")
     (lattice-constant . "4.510")
     (lattice-c/a-ratio . "n/a")
     (appearance . "Soft, blue-white metal")
     (discovery-date . "1875 (France)")
     (discovered-by . "Paul Émile Lecoq de Boisbaudran")
     (named-after . "Latin: Gallia (France)."))

    (32
     (name . "Germanium")
     (symbol . "Ge")
     (atomic-mass . "72.61")
     (density . "5.323")
     (melting-point . "1210.6")
     (boiling-point . "3103")
     (atomic-radius . "137")
     (covalent-radius . "122")
     (ionic-radius . "53 (+4e) 73 (+2e)")
     (atomic-volume . "13.6")
     (specific-heat . "0.322")
     (fusion-heat . "36.8")
     (evaporation-heat . "328")
     (thermal-conductivity . "60.2")
     (debye-temperature . "360.00")
     (pauling-negativity-number . "2.01")
     (first-ionization-energy . "760.0")
     (oxidation-states . "4")
     (lattice-structure . "DIA")
     (lattice-constant . "5.660")
     (lattice-c/a-ratio . "n/a")
     (appearance . "Grayish-white metal")
     (discovery-date . "1886 (Germany)")
     (discovered-by . "Clemens Winkler")
     (named-after . "Latin: Germania (Germany)."))

    (33
     (name . "Arsenic")
     (symbol . "As")
     (atomic-mass . "74.92159")
     (density . "5.73 (grey arsenic)")
     (melting-point . "1090")
     (boiling-point . "876")
     (atomic-radius . "139")
     (covalent-radius . "120")
     (ionic-radius . "46 (+5e) 222 (-3e)")
     (atomic-volume . "13.1")
     (specific-heat . "0.328")
     (fusion-heat . "n/a")
     (evaporation-heat . "32.4")
     (thermal-conductivity . "(50.2)")
     (debye-temperature . "285.00")
     (pauling-negativity-number . "2.18")
     (first-ionization-energy . "946.2")
     (oxidation-states . "5, 3, -2")
     (lattice-structure . "RHL")
     (lattice-constant . "4.130")
     (lattice-c/a-ratio . "n/a")
     (appearance . "Steel gray, brittle semimetal")
     (discovery-date . "n/a (Unknown)")
     (discovered-by . "Known to the ancients.")
     (named-after . "Greek: arsenikon; Latin: arsenicum, (both names for yellow pigment)."))

    (34
     (name . "Selenium")
     (symbol . "Se")
     (atomic-mass . "78.96")
     (density . "4.79")
     (melting-point . "490")
     (boiling-point . "958.1")
     (atomic-radius . "140")
     (covalent-radius . "116")
     (ionic-radius . "42 (+6e) 191 (-2e)")
     (atomic-volume . "16.5")
     (specific-heat . "0.321 (Se-Se)")
     (fusion-heat . "5.23")
     (evaporation-heat . "59.7")
     (thermal-conductivity . "0.52")
     (debye-temperature . "n/a")
     (pauling-negativity-number . "2.55")
     (first-ionization-energy . "940.4")
     (oxidation-states . "6, 4, -2")
     (lattice-structure . "HEX")
     (lattice-constant . "4.360")
     (lattice-c/a-ratio . "n/a")
     (appearance . "A soft metalloid similar to sulfur")
     (discovery-date . "1818 (Sweden)")
     (discovered-by . "Jöns Berzelius")
     (named-after . "Greek: selene (moon)."))

    (35
     (name . "Bromine")
     (symbol . "Br")
     (atomic-mass . "79.904")
     (density . "3.12")
     (melting-point . "265.9")
     (boiling-point . "331.9")
     (atomic-radius . "n/a")
     (covalent-radius . "114")
     (ionic-radius . "47 (+5e) 196 (-1e)")
     (atomic-volume . "23.5")
     (specific-heat . "0.473 (Br-Br)")
     (fusion-heat . "10.57 (Br-Br)")
     (evaporation-heat . "29.56 (Br-Br)")
     (thermal-conductivity . "0.005")
     (debye-temperature . "n/a")
     (pauling-negativity-number . "2.96")
     (first-ionization-energy . "1142.0")
     (oxidation-states . "7, 5, 3, 1, -1")
     (lattice-structure . "ORC")
     (lattice-constant . "6.670")
     (lattice-c/a-ratio . "n/a")
     (appearance . "Reddish-brown liquid")
     (discovery-date . "1826 (France)")
     (discovered-by . "Antoine J. Balard")
     (named-after . "Greek: brômos (stench)."))

    (36
     (name . "Krypton")
     (symbol . "Kr")
     (atomic-mass . "83.8")
     (density . "2.155 (@ -153 deg C)")
     (melting-point . "116.6")
     (boiling-point . "120.85")
     (atomic-radius . "n/a")
     (covalent-radius . "112")
     (ionic-radius . "n/a")
     (atomic-volume . "32.2")
     (specific-heat . "0.247")
     (fusion-heat . "n/a")
     (evaporation-heat . "9.05")
     (thermal-conductivity . "0.0095")
     (debye-temperature . "n/a")
     (pauling-negativity-number . "0.0")
     (first-ionization-energy . "1350.0")
     (oxidation-states . "2")
     (lattice-structure . "FCC")
     (lattice-constant . "5.720")
     (lattice-c/a-ratio . "n/a")
     (appearance . "Dense, colorless, odorless, and tasteless gas")
     (discovery-date . "1898 (Great Britain)")
     (discovered-by . "Sir William Ramsey, M.W. Travers")
     (named-after . "Greek: kryptos (hidden)."))

    (37
     (name . "Rubidium")
     (symbol . "Rb")
     (atomic-mass . "85.4678")
     (density . "1.532")
     (melting-point . "312.2")
     (boiling-point . "961")
     (atomic-radius . "248")
     (covalent-radius . "216")
     (ionic-radius . "147 (+1e)")
     (atomic-volume . "55.9")
     (specific-heat . "0.360")
     (fusion-heat . "2.20")
     (evaporation-heat . "75.8")
     (thermal-conductivity . "58.2")
     (debye-temperature . "n/a")
     (pauling-negativity-number . "0.82")
     (first-ionization-energy . "402.8")
     (oxidation-states . "1")
     (lattice-structure . "BCC")
     (lattice-constant . "5.590")
     (lattice-c/a-ratio . "n/a")
     (appearance . "Soft, silvery-white, highly reactive metal")
     (discovery-date . "1861 (Germany)")
     (discovered-by . "R. Bunsen, G. Kirchoff")
     (named-after . "Latin: rubidus (deep red); the color its salts impart to flames."))

    (38
     (name . "Strontium")
     (symbol . "Sr")
     (atomic-mass . "87.62")
     (density . "2.54")
     (melting-point . "1042")
     (boiling-point . "1657")
     (atomic-radius . "215")
     (covalent-radius . "191")
     (ionic-radius . "112 (+2e)")
     (atomic-volume . "33.7")
     (specific-heat . "0.301")
     (fusion-heat . "9.20")
     (evaporation-heat . "144")
     (thermal-conductivity . "(35.4)")
     (debye-temperature . "n/a")
     (pauling-negativity-number . "0.95")
     (first-ionization-energy . "549.0")
     (oxidation-states . "2")
     (lattice-structure . "FCC")
     (lattice-constant . "6.080")
     (lattice-c/a-ratio . "n/a")
     (appearance . "Silvery, malleable metal")
     (discovery-date . "1790 (Scotland)")
     (discovered-by . "A. Crawford")
     (named-after . "The Scottish town, Strontian."))

    (39
     (name . "Yttrium")
     (symbol . "Y")
     (atomic-mass . "88.90585")
     (density . "4.47")
     (melting-point . "1795")
     (boiling-point . "3611")
     (atomic-radius . "178")
     (covalent-radius . "162")
     (ionic-radius . "89.3 (+3e)")
     (atomic-volume . "19.8")
     (specific-heat . "0.284")
     (fusion-heat . "11.5")
     (evaporation-heat . "367")
     (thermal-conductivity . "(17.2)")
     (debye-temperature . "n/a")
     (pauling-negativity-number . "1.22")
     (first-ionization-energy . "615.4")
     (oxidation-states . "3")
     (lattice-structure . "HEX")
     (lattice-constant . "3.650")
     (lattice-c/a-ratio . "1.571")
     (appearance . "Silvery, ductile, fairly reactive metal")
     (discovery-date . "1789 (Finland)")
     (discovered-by . "Johann Gadolin")
     (named-after . "The Swedish village, Ytterby, where one of its minerals was first found."))

    (40
     (name . "Zirconium")
     (symbol . "Zr")
     (atomic-mass . "91.224")
     (density . "6.506")
     (melting-point . "2125")
     (boiling-point . "4650")
     (atomic-radius . "160")
     (covalent-radius . "145")
     (ionic-radius . "79 (+4e)")
     (atomic-volume . "14.1")
     (specific-heat . "0.281")
     (fusion-heat . "19.2")
     (evaporation-heat . "567")
     (thermal-conductivity . "22.7")
     (debye-temperature . "250.00")
     (pauling-negativity-number . "1.33")
     (first-ionization-energy . "659.7")
     (oxidation-states . "4")
     (lattice-structure . "HEX")
     (lattice-constant . "3.230")
     (lattice-c/a-ratio . "1.593")
     (appearance . "Gray-white, lustrous, corrosion-resistant metal")
     (discovery-date . "1789 (Germany)")
     (discovered-by . "Martin Klaproth")
     (named-after . "The mineral, zircon."))

    (41
     (name . "Niobium")
     (symbol . "Nb")
     (atomic-mass . "92.90638")
     (density . "8.57")
     (melting-point . "2741")
     (boiling-point . "5015")
     (atomic-radius . "146")
     (covalent-radius . "134")
     (ionic-radius . "69 (+5e)")
     (atomic-volume . "10.8")
     (specific-heat . "0.268")
     (fusion-heat . "26.8")
     (evaporation-heat . "680")
     (thermal-conductivity . "53.7")
     (debye-temperature . "275.00")
     (pauling-negativity-number . "1.6")
     (first-ionization-energy . "663.6")
     (oxidation-states . "5, 3")
     (lattice-structure . "BCC")
     (lattice-constant . "3.300")
     (lattice-c/a-ratio . "n/a")
     (appearance . "Shiny white, soft, ductile metal")
     (discovery-date . "1801 (England)")
     (discovered-by . "Charles Hatchet")
     (named-after . "Niobe; daughter of the mythical Greek king Tantalus."))

    (42
     (name . "Molybdenum")
     (symbol . "Mo")
     (atomic-mass . "95.94")
     (density . "10.22")
     (melting-point . "2890")
     (boiling-point . "4885")
     (atomic-radius . "139")
     (covalent-radius . "130")
     (ionic-radius . "62 (+6e) 70 (+4e)")
     (atomic-volume . "9.4")
     (specific-heat . "0.251")
     (fusion-heat . "28")
     (evaporation-heat . "~590")
     (thermal-conductivity . "(138)")
     (debye-temperature . "380.00")
     (pauling-negativity-number . "2.16")
     (first-ionization-energy . "684.8")
     (oxidation-states . "6, 5, 4, 3, 2, 0")
     (lattice-structure . "BCC")
     (lattice-constant . "3.150")
     (lattice-c/a-ratio . "n/a")
     (appearance . "Silvery white, hard metal")
     (discovery-date . "1778 (Sweden)")
     (discovered-by . "Carl Wilhelm Scheele")
     (named-after . "Greek: molybdos (lead)."))

    (43
     (name . "Technetium")
     (symbol . "Tc")
     (atomic-mass . "97.9072")
     (density . "11.5")
     (melting-point . "2445")
     (boiling-point . "5150")
     (atomic-radius . "136")
     (covalent-radius . "127")
     (ionic-radius . "56 (+7e)")
     (atomic-volume . "8.5")
     (specific-heat . "0.243")
     (fusion-heat . "23.8")
     (evaporation-heat . "585")
     (thermal-conductivity . "50.6")
     (debye-temperature . "n/a")
     (pauling-negativity-number . "1.9")
     (first-ionization-energy . "702.2")
     (oxidation-states . "7")
     (lattice-structure . "HEX")
     (lattice-constant . "2.740")
     (lattice-c/a-ratio . "1.604")
     (appearance . "Silvery-gray metal")
     (discovery-date . "1937 (Italy)")
     (discovered-by . "Carlo Perrier, Émillo Segre")
     (named-after . "Greek: technetos (artificial)."))

    (44
     (name . "Ruthenium")
     (symbol . "Ru")
     (atomic-mass . "101.07")
     (density . "12.41")
     (melting-point . "2583")
     (boiling-point . "4173")
     (atomic-radius . "134")
     (covalent-radius . "125")
     (ionic-radius . "67 (+4e)")
     (atomic-volume . "8.3")
     (specific-heat . "0.238")
     (fusion-heat . "(25.5)")
     (evaporation-heat . "n/a")
     (thermal-conductivity . "117.0")
     (debye-temperature . "n/a")
     (pauling-negativity-number . "2.2")
     (first-ionization-energy . "710.3")
     (oxidation-states . "8, 6, 4, 3, 2, 0, -2")
     (lattice-structure . "HEX")
     (lattice-constant . "2.700")
     (lattice-c/a-ratio . "1.584")
     (appearance . "Rare, silver-gray, extremely brittle metal")
     (discovery-date . "1844 (Russia)")
     (discovered-by . "Karl Klaus")
     (named-after . "Latin: Ruthenia (Russia)."))

    (45
     (name . "Rhodium")
     (symbol . "Rh")
     (atomic-mass . "102.9055")
     (density . "12.41")
     (melting-point . "2239")
     (boiling-point . "4000")
     (atomic-radius . "134")
     (covalent-radius . "125")
     (ionic-radius . "68 (+3e)")
     (atomic-volume . "8.3")
     (specific-heat . "0.244")
     (fusion-heat . "21.8")
     (evaporation-heat . "494")
     (thermal-conductivity . "150")
     (debye-temperature . "n/a")
     (pauling-negativity-number . "2.28")
     (first-ionization-energy . "719.5")
     (oxidation-states . "5, 4, 3,  2, 1, 0")
     (lattice-structure . "FCC")
     (lattice-constant . "3.800")
     (lattice-c/a-ratio . "n/a")
     (appearance . "Silvery white, hard metal")
     (discovery-date . "1803 (England)")
     (discovered-by . "William Wollaston")
     (named-after . "Greek: rhodon (rose). Its salts give a rosy solution."))

    (46
     (name . "Palladium")
     (symbol . "Pd")
     (atomic-mass . "106.42")
     (density . "12.02")
     (melting-point . "1825")
     (boiling-point . "3413")
     (atomic-radius . "137")
     (covalent-radius . "128")
     (ionic-radius . "65 (+4e) 80 (+2e)")
     (atomic-volume . "8.9")
     (specific-heat . "0.244")
     (fusion-heat . "17.24")
     (evaporation-heat . "372.4")
     (thermal-conductivity . "71.8")
     (debye-temperature . "275.00")
     (pauling-negativity-number . "2.20")
     (first-ionization-energy . "803.5")
     (oxidation-states . "4,  2, 0")
     (lattice-structure . "FCC")
     (lattice-constant . "3.890")
     (lattice-c/a-ratio . "n/a")
     (appearance . "Silvery-white, soft, malleable and ductile metal")
     (discovery-date . "1803 (England)")
     (discovered-by . "William Wollaston")
     (named-after . "Named after the asteroid, Pallas, discovered in 1803."))

    (47
     (name . "Silver")
     (symbol . "Ag")
     (atomic-mass . "107.8682")
     (density . "10.5")
     (melting-point . "1235.1")
     (boiling-point . "2485")
     (atomic-radius . "144")
     (covalent-radius . "134")
     (ionic-radius . "89 (+2e) 126 (+1e)")
     (atomic-volume . "10.3")
     (specific-heat . "0.237")
     (fusion-heat . "11.95")
     (evaporation-heat . "254.1")
     (thermal-conductivity . "429")
     (debye-temperature . "215.00")
     (pauling-negativity-number . "1.93")
     (first-ionization-energy . "730.5")
     (oxidation-states . "2, 1")
     (lattice-structure . "FCC")
     (lattice-constant . "4.090")
     (lattice-c/a-ratio . "n/a")
     (appearance . "Silvery-ductile, and malleable metal")
     (discovery-date . "n/a (Unknown)")
     (discovered-by . "Known to the ancients.")
     (named-after . "Anglo-Saxon: siolful, (silver); symbol from Latin: argentium."))

    (48
     (name . "Cadmium")
     (symbol . "Cd")
     (atomic-mass . "112.411")
     (density . "8.65")
     (melting-point . "594.1")
     (boiling-point . "1038")
     (atomic-radius . "154")
     (covalent-radius . "148")
     (ionic-radius . "97 (+2e)")
     (atomic-volume . "13.1")
     (specific-heat . "0.232")
     (fusion-heat . "6.11")
     (evaporation-heat . "59.1")
     (thermal-conductivity . "96.9")
     (debye-temperature . "120.00")
     (pauling-negativity-number . "1.69")
     (first-ionization-energy . "867.2")
     (oxidation-states . "2")
     (lattice-structure . "HEX")
     (lattice-constant . "2.980")
     (lattice-c/a-ratio . "1.886")
     (appearance . "Soft, malleable, blue-white metal")
     (discovery-date . "1817 (Germany)")
     (discovered-by . "Fredrich Stromeyer")
     (named-after . "Greek: kadmeia (ancient name for calamine (zinc oxide))."))

    (49
     (name . "Indium")
     (symbol . "In")
     (atomic-mass . "114.818")
     (density . "7.31")
     (melting-point . "429.32")
     (boiling-point . "2353")
     (atomic-radius . "166")
     (covalent-radius . "144")
     (ionic-radius . "81 (+3e)")
     (atomic-volume . "15.7")
     (specific-heat . "0.234")
     (fusion-heat . "3.24")
     (evaporation-heat . "225.1")
     (thermal-conductivity . "81.8")
     (debye-temperature . "129.00")
     (pauling-negativity-number . "1.78")
     (first-ionization-energy . "558.0")
     (oxidation-states . "3")
     (lattice-structure . "TET")
     (lattice-constant . "4.590")
     (lattice-c/a-ratio . "n/a")
     (appearance . "Very soft, silvery-white metal")
     (discovery-date . "1863 (Germany)")
     (discovered-by . "Ferdinand Reich, T. Richter")
     (named-after . "Latin: indicum (color indigo), the color it shows in a spectroscope."))

    (50
     (name . "Tin")
     (symbol . "Sn")
     (atomic-mass . "118.71")
     (density . "7.31")
     (melting-point . "505.1")
     (boiling-point . "2543")
     (atomic-radius . "162")
     (covalent-radius . "141")
     (ionic-radius . "71 (+4e) 93 (+2)")
     (atomic-volume . "16.3")
     (specific-heat . "0.222")
     (fusion-heat . "7.07")
     (evaporation-heat . "296")
     (thermal-conductivity . "66.8")
     (debye-temperature . "170.00")
     (pauling-negativity-number . "1.96")
     (first-ionization-energy . "708.2")
     (oxidation-states . "4, 2")
     (lattice-structure . "TET")
     (lattice-constant . "5.820")
     (lattice-c/a-ratio . "n/a")
     (appearance . "Silvery-white, soft, malleable and ductile metal")
     (discovery-date . "n/a (Unknown)")
     (discovered-by . "Known to the ancients.")
     (named-after . "Named after Etruscan god, Tinia; symbol from Latin: stannum (tin)."))

    (51
     (name . "Antimony")
     (symbol . "Sb")
     (atomic-mass . "121.760")
     (density . "6.691")
     (melting-point . "903.9")
     (boiling-point . "1908")
     (atomic-radius . "159")
     (covalent-radius . "140")
     (ionic-radius . "62 (+6e) 245 (-3)")
     (atomic-volume . "18.4")
     (specific-heat . "0.205")
     (fusion-heat . "20.08")
     (evaporation-heat . "195.2")
     (thermal-conductivity . "24.43")
     (debye-temperature . "200.00")
     (pauling-negativity-number . "2.05")
     (first-ionization-energy . "833.3")
     (oxidation-states . "5, 3, -2")
     (lattice-structure . "RHL")
     (lattice-constant . "4.510")
     (lattice-c/a-ratio . "n/a")
     (appearance . "Hard, silvery-white, brittle semimetal")
     (discovery-date . "n/a (Unknown)")
     (discovered-by . "Known to the ancients.")
     (named-after . "Greek: anti and monos (not alone); symbol from mineral stibnite."))

    (52
     (name . "Tellurium")
     (symbol . "Te")
     (atomic-mass . "127.6")
     (density . "6.24")
     (melting-point . "722.7")
     (boiling-point . "1263")
     (atomic-radius . "160")
     (covalent-radius . "136")
     (ionic-radius . "56 (+6e) 211 (-2e)")
     (atomic-volume . "20.5")
     (specific-heat . "0.201")
     (fusion-heat . "17.91")
     (evaporation-heat . "49.8")
     (thermal-conductivity . "14.3")
     (debye-temperature . "n/a")
     (pauling-negativity-number . "2.1")
     (first-ionization-energy . "869.0")
     (oxidation-states . "6, 4, 2")
     (lattice-structure . "HEX")
     (lattice-constant . "4.450")
     (lattice-c/a-ratio . "1.330")
     (appearance . "Silvery-white, brittle semimetal")
     (discovery-date . "1782 (Romania)")
     (discovered-by . "Franz Müller von Reichenstein")
     (named-after . "Latin: tellus (earth)."))

    (53
     (name . "Iodine")
     (symbol . "I")
     (atomic-mass . "126.90447")
     (density . "4.93")
     (melting-point . "386.7")
     (boiling-point . "457.5")
     (atomic-radius . "n/a")
     (covalent-radius . "133")
     (ionic-radius . "50 (+7e) 220 (-1e)")
     (atomic-volume . "25.7")
     (specific-heat . "0.427 (I-I)")
     (fusion-heat . "15.52 (I-I)")
     (evaporation-heat . "41.95 (I-I)")
     (thermal-conductivity . "(0.45)")
     (debye-temperature . "n/a")
     (pauling-negativity-number . "2.66")
     (first-ionization-energy . "1008.3")
     (oxidation-states . "7, 5, 1, -1")
     (lattice-structure . "ORC")
     (lattice-constant . "7.720")
     (lattice-c/a-ratio . "n/a")
     (appearance . "Shiny, black nonmetallic solid")
     (discovery-date . "1811 (France)")
     (discovered-by . "Bernard Courtois")
     (named-after . "Greek: iôeides (violet colored)."))

    (54
     (name . "Xenon")
     (symbol . "Xe")
     (atomic-mass . "131.29")
     (density . "3.52 (@ -109 deg C)")
     (melting-point . "161.3")
     (boiling-point . "166.1")
     (atomic-radius . "n/a")
     (covalent-radius . "131")
     (ionic-radius . "n/a")
     (atomic-volume . "42.9")
     (specific-heat . "0.158")
     (fusion-heat . "n/a")
     (evaporation-heat . "12.65")
     (thermal-conductivity . "0.0057")
     (debye-temperature . "n/a")
     (pauling-negativity-number . "0.0")
     (first-ionization-energy . "1170.0")
     (oxidation-states . "7")
     (lattice-structure . "FCC")
     (lattice-constant . "6.200")
     (lattice-c/a-ratio . "n/a")
     (appearance . "Heavy, colorless, and odorless noble gas")
     (discovery-date . "1898 (England)")
     (discovered-by . "Sir William Ramsay; M. W. Travers")
     (named-after . "Greek: xenos (strange)."))

    (55
     (name . "Cesium")
     (symbol . "Cs")
     (atomic-mass . "132.90543")
     (density . "1.873")
     (melting-point . "301.6")
     (boiling-point . "951.6")
     (atomic-radius . "267")
     (covalent-radius . "235")
     (ionic-radius . "167 (+1e)")
     (atomic-volume . "70.0")
     (specific-heat . "0.241")
     (fusion-heat . "2.09")
     (evaporation-heat . "68.3")
     (thermal-conductivity . "35.9")
     (debye-temperature . "n/a")
     (pauling-negativity-number . "0.79")
     (first-ionization-energy . "375.5")
     (oxidation-states . "1")
     (lattice-structure . "BCC")
     (lattice-constant . "6.050")
     (lattice-c/a-ratio . "n/a")
     (appearance . "Very soft, ductile, light gray metal")
     (discovery-date . "1860 (Germany)")
     (discovered-by . "Gustov Kirchoff, Robert Bunsen")
     (named-after . "Latin: coesius (sky blue); for the blue lines of its spectrum."))

    (56
     (name . "Barium")
     (symbol . "Ba")
     (atomic-mass . "137.327")
     (density . "3.5")
     (melting-point . "1002")
     (boiling-point . "1910")
     (atomic-radius . "222")
     (covalent-radius . "198")
     (ionic-radius . "134 (+2e)")
     (atomic-volume . "39.0")
     (specific-heat . "0.192")
     (fusion-heat . "7.66")
     (evaporation-heat . "142.0")
     (thermal-conductivity . "(18.4)")
     (debye-temperature . "n/a")
     (pauling-negativity-number . "0.89")
     (first-ionization-energy . "502.5")
     (oxidation-states . "2")
     (lattice-structure . "BCC")
     (lattice-constant . "5.020")
     (lattice-c/a-ratio . "n/a")
     (appearance . "Soft, slightly malleable, silver-white metal")
     (discovery-date . "1808 (England)")
     (discovered-by . "Sir Humphrey Davy")
     (named-after . "Greek: barys (heavy or dense)."))

    (57
     (name . "Lanthanum")
     (symbol . "La")
     (atomic-mass . "138.9055")
     (density . "6.15")
     (melting-point . "1194")
     (boiling-point . "3730")
     (atomic-radius . "187")
     (covalent-radius . "169")
     (ionic-radius . "101.6 (+3e)")
     (atomic-volume . "22.5")
     (specific-heat . "0.197")
     (fusion-heat . "8.5")
     (evaporation-heat . "402")
     (thermal-conductivity . "13.4")
     (debye-temperature . "132.00")
     (pauling-negativity-number . "1.10")
     (first-ionization-energy . "541.1")
     (oxidation-states . "3")
     (lattice-structure . "HEX")
     (lattice-constant . "3.750")
     (lattice-c/a-ratio . "1.619")
     (appearance . "Silvery-white, soft, malleable, and ductile metal")
     (discovery-date . "1839 (Sweden)")
     (discovered-by . "Carl Mosander")
     (named-after . "Greek: lanthanein (to be hidden)."))

    (58
     (name . "Cerium")
     (symbol . "Ce")
     (atomic-mass . "140.115")
     (density . "6.757")
     (melting-point . "1072")
     (boiling-point . "3699")
     (atomic-radius . "181")
     (covalent-radius . "165")
     (ionic-radius . "92 (+4e) 103.4 (+3e)")
     (atomic-volume . "21.0")
     (specific-heat . "0.205")
     (fusion-heat . "5.2")
     (evaporation-heat . "398")
     (thermal-conductivity . "11.3")
     (debye-temperature . "n/a")
     (pauling-negativity-number . "1.12")
     (first-ionization-energy . "540.1")
     (oxidation-states . "4, 3")
     (lattice-structure . "FCC")
     (lattice-constant . "5.160")
     (lattice-c/a-ratio . "n/a")
     (appearance . "Malleable, ductile, iron-gray metal")
     (discovery-date . "1803 (Sweden/Germany)")
     (discovered-by . "W. von Hisinger, J. Berzelius, M. Klaproth")
     (named-after . "Named after the asteroid, Ceres, discovered two years before the element."))

    (59
     (name . "Praseodymium")
     (symbol . "Pr")
     (atomic-mass . "140.90765")
     (density . "6.773")
     (melting-point . "1204")
     (boiling-point . "3785")
     (atomic-radius . "182")
     (covalent-radius . "165")
     (ionic-radius . "90 (+4e) 101.3 (+3e)")
     (atomic-volume . "20.8")
     (specific-heat . "0.192")
     (fusion-heat . "11.3")
     (evaporation-heat . "331")
     (thermal-conductivity . "12.5")
     (debye-temperature . "n/a")
     (pauling-negativity-number . "1.13")
     (first-ionization-energy . "526.6")
     (oxidation-states . "4, 3")
     (lattice-structure . "HEX")
     (lattice-constant . "3.670")
     (lattice-c/a-ratio . "1.614")
     (appearance . "Silvery white, moderately soft, malleable, and ductile metal")
     (discovery-date . "1885 (Austria)")
     (discovered-by . "C.F. Aver von Welsbach")
     (named-after . "Greek: prasios and didymos (green twin); from its green salts."))

    (60
     (name . "Neodymium")
     (symbol . "Nd")
     (atomic-mass . "144.24")
     (density . "7.007")
     (melting-point . "1294")
     (boiling-point . "3341")
     (atomic-radius . "182")
     (covalent-radius . "184")
     (ionic-radius . "99.5 (+3e)")
     (atomic-volume . "20.6")
     (specific-heat . "0.205")
     (fusion-heat . "7.1")
     (evaporation-heat . "289")
     (thermal-conductivity . "(16.5)")
     (debye-temperature . "n/a")
     (pauling-negativity-number . "1.14")
     (first-ionization-energy . "531.5")
     (oxidation-states . "3")
     (lattice-structure . "HEX")
     (lattice-constant . "3.660")
     (lattice-c/a-ratio . "1.614")
     (appearance . "Silvery-white, rare-earth metal that oxidizes easily in air")
     (discovery-date . "1925 (Austria)")
     (discovered-by . "C.F. Aver von Welsbach")
     (named-after . "Greek: neos and didymos (new twin)."))

    (61
     (name . "Promethium")
     (symbol . "Pm")
     (atomic-mass . "144.9127")
     (density . "7.2")
     (melting-point . "1441")
     (boiling-point . "3000")
     (atomic-radius . "n/a")
     (covalent-radius . "163")
     (ionic-radius . "97.9 (+3e)")
     (atomic-volume . "n/a")
     (specific-heat . "0.185")
     (fusion-heat . "n/a")
     (evaporation-heat . "n/a")
     (thermal-conductivity . "17.9")
     (debye-temperature . "n/a")
     (pauling-negativity-number . "0.0")
     (first-ionization-energy . "536")
     (oxidation-states . "3")
     (lattice-structure . "n/a")
     (lattice-constant . "n/a")
     (lattice-c/a-ratio . "n/a")
     (appearance . "")
     (discovery-date . "1945 (United States)")
     (discovered-by . "J.A. Marinsky, L.E. Glendenin, C.D. Coryell")
     (named-after . "Named for the Greek god, Prometheus."))

    (62
     (name . "Samarium")
     (symbol . "Sm")
     (atomic-mass . "150.36")
     (density . "7.520")
     (melting-point . "1350")
     (boiling-point . "2064")
     (atomic-radius . "181")
     (covalent-radius . "162")
     (ionic-radius . "96.4 (+3e)")
     (atomic-volume . "19.9")
     (specific-heat . "0.180")
     (fusion-heat . "8.9")
     (evaporation-heat . "165")
     (thermal-conductivity . "(13.3)")
     (debye-temperature . "166.00")
     (pauling-negativity-number . "1.17")
     (first-ionization-energy . "540.1")
     (oxidation-states . "3, 2")
     (lattice-structure . "RHL")
     (lattice-constant . "9.000")
     (lattice-c/a-ratio . "n/a")
     (appearance . "Silvery rare-earth metal")
     (discovery-date . "1879 (France)")
     (discovered-by . "Paul Émile Lecoq de Boisbaudran")
     (named-after . "Named after the mineral samarskite."))

    (63
     (name . "Europium")
     (symbol . "Eu")
     (atomic-mass . "151.965")
     (density . "5.243")
     (melting-point . "1095")
     (boiling-point . "1870")
     (atomic-radius . "199")
     (covalent-radius . "185")
     (ionic-radius . "95 (+3e) 109 (+2e)")
     (atomic-volume . "28.9")
     (specific-heat . "0.176")
     (fusion-heat . "n/a")
     (evaporation-heat . "176")
     (thermal-conductivity . "13.9")
     (debye-temperature . "n/a")
     (pauling-negativity-number . "0.0")
     (first-ionization-energy . "546.9")
     (oxidation-states . "3, 2")
     (lattice-structure . "BCC")
     (lattice-constant . "4.610")
     (lattice-c/a-ratio . "n/a")
     (appearance . "Soft, silvery-white metal")
     (discovery-date . "1901 (France)")
     (discovered-by . "Eugene Demarçay")
     (named-after . "Named for the continent of Europe."))

    (64
     (name . "Gadolinium")
     (symbol . "Gd")
     (atomic-mass . "157.25")
     (density . "7.900")
     (melting-point . "1586")
     (boiling-point . "3539")
     (atomic-radius . "179")
     (covalent-radius . "161")
     (ionic-radius . "93.8 (+3e)")
     (atomic-volume . "19.9")
     (specific-heat . "0.230")
     (fusion-heat . "n/a")
     (evaporation-heat . "398")
     (thermal-conductivity . "(10.5)")
     (debye-temperature . "n/a")
     (pauling-negativity-number . "1.20")
     (first-ionization-energy . "594.2")
     (oxidation-states . "3")
     (lattice-structure . "HEX")
     (lattice-constant . "3.640")
     (lattice-c/a-ratio . "1.588")
     (appearance . "Soft, ductile, silvery-white metal")
     (discovery-date . "1880 (Switzerland)")
     (discovered-by . "Jean de Marignac")
     (named-after . "Named after the mineral gadolinite."))

    (65
     (name . "Terbium")
     (symbol . "Tb")
     (atomic-mass . "158.92534")
     (density . "8.229")
     (melting-point . "1629")
     (boiling-point . "3296")
     (atomic-radius . "180")
     (covalent-radius . "159")
     (ionic-radius . "84 (+4e) 92.3 (+3e)")
     (atomic-volume . "19.2")
     (specific-heat . "0.183")
     (fusion-heat . "n/a")
     (evaporation-heat . "389")
     (thermal-conductivity . "11.1")
     (debye-temperature . "n/a")
     (pauling-negativity-number . "1.2")
     (first-ionization-energy . "569")
     (oxidation-states . "4, 3")
     (lattice-structure . "HEX")
     (lattice-constant . "3.600")
     (lattice-c/a-ratio . "1.581")
     (appearance . "Soft, ductile, silvery-gray, rare-earth metal")
     (discovery-date . "1843 (Sweden)")
     (discovered-by . "Carl Mosander")
     (named-after . "Named after Ytterby, a village in Sweden."))

    (66
     (name . "Dysprosium")
     (symbol . "Dy")
     (atomic-mass . "162.50")
     (density . "8.55")
     (melting-point . "1685")
     (boiling-point . "2835")
     (atomic-radius . "180")
     (covalent-radius . "159")
     (ionic-radius . "90.8 (+3e)")
     (atomic-volume . "19.0")
     (specific-heat . "0.173")
     (fusion-heat . "n/a")
     (evaporation-heat . "291")
     (thermal-conductivity . "10.7")
     (debye-temperature . "n/a")
     (pauling-negativity-number . "n/a")
     (first-ionization-energy . "567")
     (oxidation-states . "3")
     (lattice-structure . "HEX")
     (lattice-constant . "3.590")
     (lattice-c/a-ratio . "1.573")
     (appearance . "Soft. lustrous, silvery metal")
     (discovery-date . "1886 (France)")
     (discovered-by . "Paul Émile Lecoq de Boisbaudran")
     (named-after . "Greek: dysprositos (hard to get at)."))

    (67
     (name . "Holmium")
     (symbol . "Ho")
     (atomic-mass . "164.93032")
     (density . "8.795")
     (melting-point . "1747")
     (boiling-point . "2968")
     (atomic-radius . "179")
     (covalent-radius . "158")
     (ionic-radius . "89.4 (+3e)")
     (atomic-volume . "18.7")
     (specific-heat . "0.164")
     (fusion-heat . "n/a")
     (evaporation-heat . "301")
     (thermal-conductivity . "(16.2)")
     (debye-temperature . "n/a")
     (pauling-negativity-number . "1.23")
     (first-ionization-energy . "574")
     (oxidation-states . "3")
     (lattice-structure . "HEX")
     (lattice-constant . "3.580")
     (lattice-c/a-ratio . "1.570")
     (appearance . "Fairly soft, malleable, lustrous, silvery metal")
     (discovery-date . "1878 (Switzerland)")
     (discovered-by . "J.L. Soret")
     (named-after . "Holmia, the Latinized name for Stockholm, Sweden."))

    (68
     (name . "Erbium")
     (symbol . "Er")
     (atomic-mass . "167.26")
     (density . "9.06")
     (melting-point . "1802")
     (boiling-point . "3136")
     (atomic-radius . "178")
     (covalent-radius . "157")
     (ionic-radius . "88.1 (+3e)")
     (atomic-volume . "18.4")
     (specific-heat . "0.168")
     (fusion-heat . "n/a")
     (evaporation-heat . "317")
     (thermal-conductivity . "(14.5)")
     (debye-temperature . "n/a")
     (pauling-negativity-number . "1.24")
     (first-ionization-energy . "581")
     (oxidation-states . "3")
     (lattice-structure . "HEX")
     (lattice-constant . "3.560")
     (lattice-c/a-ratio . "1.570")
     (appearance . "Soft, malleable, silvery metal")
     (discovery-date . "1843 (Sweden)")
     (discovered-by . "Carl Mosander")
     (named-after . "Named after the Swedish town, Ytterby."))

    (69
     (name . "Thulium")
     (symbol . "Tm")
     (atomic-mass . "168.93421")
     (density . "9.321")
     (melting-point . "1818")
     (boiling-point . "2220")
     (atomic-radius . "177")
     (covalent-radius . "156")
     (ionic-radius . "87 (+3e)")
     (atomic-volume . "18.1")
     (specific-heat . "0.160")
     (fusion-heat . "n/a")
     (evaporation-heat . "232")
     (thermal-conductivity . "(16.9)")
     (debye-temperature . "n/a")
     (pauling-negativity-number . "1.25")
     (first-ionization-energy . "589")
     (oxidation-states . "3, 2")
     (lattice-structure . "HEX")
     (lattice-constant . "3.540")
     (lattice-c/a-ratio . "1.570")
     (appearance . "Soft, malleable, ductile, silvery metal")
     (discovery-date . "1879 (Sweden)")
     (discovered-by . "Per Theodor Cleve")
     (named-after . "Thule, ancient name of Scandinavia."))

    (70
     (name . "Ytterbium")
     (symbol . "Yb")
     (atomic-mass . "173.04")
     (density . "6.9654")
     (melting-point . "1097")
     (boiling-point . "1466")
     (atomic-radius . "194")
     (covalent-radius . "n/a")
     (ionic-radius . "85.8 (+3e) 93 (+2e)")
     (atomic-volume . "24.8")
     (specific-heat . "0.145")
     (fusion-heat . "3.35")
     (evaporation-heat . "159")
     (thermal-conductivity . "(34.9)")
     (debye-temperature . "n/a")
     (pauling-negativity-number . "1.1")
     (first-ionization-energy . "603")
     (oxidation-states . "3, 2")
     (lattice-structure . "FCC")
     (lattice-constant . "5.490")
     (lattice-c/a-ratio . "n/a")
     (appearance . "Silvery, lustrous, malleable, and ductile metal")
     (discovery-date . "1878 (Switzerland)")
     (discovered-by . "Jean de Marignac")
     (named-after . "Named for the Swedish village of Ytterby."))

    (71
     (name . "Lutetium")
     (symbol . "Lu")
     (atomic-mass . "174.967")
     (density . "9.8404")
     (melting-point . "1936")
     (boiling-point . "3668")
     (atomic-radius . "175")
     (covalent-radius . "156")
     (ionic-radius . "85 (+3e)")
     (atomic-volume . "17.8")
     (specific-heat . "0.155")
     (fusion-heat . "n/a")
     (evaporation-heat . "414")
     (thermal-conductivity . "(16.4)")
     (debye-temperature . "n/a")
     (pauling-negativity-number . "1.27")
     (first-ionization-energy . "513")
     (oxidation-states . "3")
     (lattice-structure . "HEX")
     (lattice-constant . "3.510")
     (lattice-c/a-ratio . "1.585")
     (appearance . "Silvery-white, hard, dense, rare-earth metal")
     (discovery-date . "1907 (France)")
     (discovered-by . "Georges Urbain")
     (named-after . "Named for the ancient name of Paris, Lutecia."))

    (72
     (name . "Hafnium")
     (symbol . "Hf")
     (atomic-mass . "178.49")
     (density . "13.31")
     (melting-point . "2503")
     (boiling-point . "5470")
     (atomic-radius . "167")
     (covalent-radius . "144")
     (ionic-radius . "78 (+4e)")
     (atomic-volume . "13.6")
     (specific-heat . "0.146")
     (fusion-heat . "(25.1)")
     (evaporation-heat . "575")
     (thermal-conductivity . "23.0")
     (debye-temperature . "n/a")
     (pauling-negativity-number . "1.3")
     (first-ionization-energy . "575.2")
     (oxidation-states . "4")
     (lattice-structure . "HEX")
     (lattice-constant . "3.200")
     (lattice-c/a-ratio . "1.582")
     (appearance . "Silvery, ductile metal")
     (discovery-date . "1923 (Denmark)")
     (discovered-by . "Dirk Coster, Georg von Hevesy")
     (named-after . "Hafnia, the Latin name of Copenhagen."))

    (73
     (name . "Tantalum")
     (symbol . "Ta")
     (atomic-mass . "180.9479")
     (density . "16.654")
     (melting-point . "3269")
     (boiling-point . "5698")
     (atomic-radius . "149")
     (covalent-radius . "134")
     (ionic-radius . "68 (+5e)")
     (atomic-volume . "10.9")
     (specific-heat . "0.140")
     (fusion-heat . "24.7")
     (evaporation-heat . "758")
     (thermal-conductivity . "57.5")
     (debye-temperature . "225.00")
     (pauling-negativity-number . "1.5")
     (first-ionization-energy . "760.1")
     (oxidation-states . "5")
     (lattice-structure . "BCC")
     (lattice-constant . "3.310")
     (lattice-c/a-ratio . "n/a")
     (appearance . "Gray, heavy, hard metal")
     (discovery-date . "1802 (Sweden)")
     (discovered-by . "Anders Ekeberg")
     (named-after . "King Tantalus of Greek mythology, father of Niobe."))

    (74
     (name . "Tungsten")
     (symbol . "W")
     (atomic-mass . "183.84")
     (density . "19.3")
     (melting-point . "3680")
     (boiling-point . "5930")
     (atomic-radius . "141")
     (covalent-radius . "130")
     (ionic-radius . "62 (+6e) 70 (+4e)")
     (atomic-volume . "9.53")
     (specific-heat . "0.133")
     (fusion-heat . "(35)")
     (evaporation-heat . "824")
     (thermal-conductivity . "173")
     (debye-temperature . "310.00")
     (pauling-negativity-number . "1.7")
     (first-ionization-energy . "769.7")
     (oxidation-states . "6, 5, 4, 3, 2, 0")
     (lattice-structure . "BCC")
     (lattice-constant . "3.160")
     (lattice-c/a-ratio . "n/a")
     (appearance . "Tough, steel-gray to white metal")
     (discovery-date . "1783 (Spain)")
     (discovered-by . "Fausto and Juan José de Elhuyar")
     (named-after . "Swedish: tung sten (heavy stone): symbol from its German name wolfram."))

    (75
     (name . "Rhenium")
     (symbol . "Re")
     (atomic-mass . "186.207")
     (density . "21.02")
     (melting-point . "3453")
     (boiling-point . "5900")
     (atomic-radius . "137")
     (covalent-radius . "128")
     (ionic-radius . "53 (+7e) 72 (+4e)")
     (atomic-volume . "8.85")
     (specific-heat . "0.138")
     (fusion-heat . "34")
     (evaporation-heat . "704")
     (thermal-conductivity . "48.0")
     (debye-temperature . "416.00")
     (pauling-negativity-number . "1.9")
     (first-ionization-energy . "759.1")
     (oxidation-states . "5, 4, 3, 2, -1")
     (lattice-structure . "HEX")
     (lattice-constant . "2.760")
     (lattice-c/a-ratio . "1.615")
     (appearance . "Dense, silvery-white metal")
     (discovery-date . "1925 (Germany)")
     (discovered-by . "Walter Noddack, Ida Tacke, Otto Berg")
     (named-after . "Latin: Rhenus, the Rhine River."))

    (76
     (name . "Osmium")
     (symbol . "Os")
     (atomic-mass . "190.23")
     (density . "22.57")
     (melting-point . "3327")
     (boiling-point . "5300")
     (atomic-radius . "135")
     (covalent-radius . "126")
     (ionic-radius . "69 (+6e) 88 (+4e)")
     (atomic-volume . "8.43")
     (specific-heat . "0.131")
     (fusion-heat . "31.7")
     (evaporation-heat . "738")
     (thermal-conductivity . "(87.6)")
     (debye-temperature . "n/a")
     (pauling-negativity-number . "2.2")
     (first-ionization-energy . "819.8")
     (oxidation-states . "8, 6, 4, 3, 2, 0, -2")
     (lattice-structure . "HEX")
     (lattice-constant . "2.740")
     (lattice-c/a-ratio . "1.579")
     (appearance . "Blue-white, lustrous, hard metal")
     (discovery-date . "1804 (England)")
     (discovered-by . "Smithson Tenant")
     (named-after . "Greek: osme (odor)."))

    (77
     (name . "Iridium")
     (symbol . "Ir")
     (atomic-mass . "192.22")
     (density . "22.42")
     (melting-point . "2683")
     (boiling-point . "4403")
     (atomic-radius . "136")
     (covalent-radius . "127")
     (ionic-radius . "68 (+4e)")
     (atomic-volume . "8.54")
     (specific-heat . "0.133")
     (fusion-heat . "27.61")
     (evaporation-heat . "604")
     (thermal-conductivity . "147")
     (debye-temperature . "430.00")
     (pauling-negativity-number . "2.20")
     (first-ionization-energy . "868.1")
     (oxidation-states . "6, 4, 3, 2, 1, 0, -1")
     (lattice-structure . "FCC")
     (lattice-constant . "3.840")
     (lattice-c/a-ratio . "n/a")
     (appearance . "White, brittle metal")
     (discovery-date . "1804 (England/France)")
     (discovered-by . "S.Tenant, A.F.Fourcory, L.N.Vauquelin, H.V.Collet-Descoltils")
     (named-after . "Latin: iris (rainbow)."))

    (78
     (name . "Platinum")
     (symbol . "Pt")
     (atomic-mass . "195.08")
     (density . "21.45")
     (melting-point . "2045")
     (boiling-point . "4100")
     (atomic-radius . "139")
     (covalent-radius . "130")
     (ionic-radius . "65 (+4e) 80 (+2e)")
     (atomic-volume . "9.10")
     (specific-heat . "0.133")
     (fusion-heat . "21.76")
     (evaporation-heat . "~470")
     (thermal-conductivity . "71.6")
     (debye-temperature . "230.00")
     (pauling-negativity-number . "2.28")
     (first-ionization-energy . "868.1")
     (oxidation-states . "4, 2, 0")
     (lattice-structure . "FCC")
     (lattice-constant . "3.920")
     (lattice-c/a-ratio . "n/a")
     (appearance . "Very heavy, soft, silvery-white metal")
     (discovery-date . "1735 (Italy)")
     (discovered-by . "Julius Scaliger")
     (named-after . "Spanish: platina (little silver)."))

    (79
     (name . "Gold")
     (symbol . "Au")
     (atomic-mass . "196.96654")
     (density . "19.3")
     (melting-point . "1337.58")
     (boiling-point . "3080")
     (atomic-radius . "146")
     (covalent-radius . "134")
     (ionic-radius . "85 (+3e) 137 (+1e)")
     (atomic-volume . "10.2")
     (specific-heat . "0.129")
     (fusion-heat . "12.68")
     (evaporation-heat . "~340")
     (thermal-conductivity . "318")
     (debye-temperature . "170.00")
     (pauling-negativity-number . "2.54")
     (first-ionization-energy . "889.3")
     (oxidation-states . "3, 1")
     (lattice-structure . "FCC")
     (lattice-constant . "4.080")
     (lattice-c/a-ratio . "n/a")
     (appearance . "Soft, malleable, yellow metal")
     (discovery-date . "n/a (Unknown)")
     (discovered-by . "Known to the ancients.")
     (named-after . "Anglo-Saxon: geolo (yellow); symbol from Latin: aurum (shining dawn)."))

    (80
     (name . "Mercury")
     (symbol . "Hg")
     (atomic-mass . "200.59")
     (density . "13.546 (@ +20 deg C)")
     (melting-point . "234.28")
     (boiling-point . "629.73")
     (atomic-radius . "157")
     (covalent-radius . "149")
     (ionic-radius . "110 (+2e) 127 (+1e)")
     (atomic-volume . "14.8")
     (specific-heat . "0.138")
     (fusion-heat . "2.295")
     (evaporation-heat . "58.5")
     (thermal-conductivity . "8.3")
     (debye-temperature . "100.00")
     (pauling-negativity-number . "2.00")
     (first-ionization-energy . "1006.0")
     (oxidation-states . "2, 1")
     (lattice-structure . "RHL")
     (lattice-constant . "2.990")
     (lattice-c/a-ratio . "n/a")
     (appearance . "Heavy, silver-white metal that is in its liquid state at")
     (discovery-date . "n/a (Unknown)")
     (discovered-by . "Known to the ancients.")
     (named-after . "The Roman god Mercury; symbol from Latin: hydrargyrus (liquid silver)."))

    (81
     (name . "Thallium")
     (symbol . "Tl")
     (atomic-mass . "204.3833")
     (density . "11.85")
     (melting-point . "576.6")
     (boiling-point . "1730")
     (atomic-radius . "171")
     (covalent-radius . "148")
     (ionic-radius . "95 (+3e) 147 (+1e)")
     (atomic-volume . "17.2")
     (specific-heat . "0.128")
     (fusion-heat . "4.31")
     (evaporation-heat . "162.4")
     (thermal-conductivity . "46.1")
     (debye-temperature . "96.00")
     (pauling-negativity-number . "1.62")
     (first-ionization-energy . "588.9")
     (oxidation-states . "3, 1")
     (lattice-structure . "HEX")
     (lattice-constant . "3.460")
     (lattice-c/a-ratio . "1.599")
     (appearance . "Soft, gray metal")
     (discovery-date . "1861 (England)")
     (discovered-by . "Sir William Crookes")
     (named-after . "Greek: thallos (green twig), for a bright green line in its spectrum."))

    (82
     (name . "Lead")
     (symbol . "Pb")
     (atomic-mass . "207.2")
     (density . "11.35")
     (melting-point . "600.65")
     (boiling-point . "2013")
     (atomic-radius . "175")
     (covalent-radius . "147")
     (ionic-radius . "84 (+4e) 120 (+2e)")
     (atomic-volume . "18.3")
     (specific-heat . "0.159")
     (fusion-heat . "4.77")
     (evaporation-heat . "177.8")
     (thermal-conductivity . "35.3")
     (debye-temperature . "88.00")
     (pauling-negativity-number . "1.8")
     (first-ionization-energy . "715.2")
     (oxidation-states . "4, 2")
     (lattice-structure . "FCC")
     (lattice-constant . "4.950")
     (lattice-c/a-ratio . "n/a")
     (appearance . "Very soft, highly malleable and ductile, blue-white shiny metal")
     (discovery-date . "n/a (Unknown)")
     (discovered-by . "Known to the ancients.")
     (named-after . "Anglo-Saxon: lead; symbol from Latin: plumbum."))

    (83
     (name . "Bismuth")
     (symbol . "Bi")
     (atomic-mass . "208.98037")
     (density . "9.747")
     (melting-point . "544.5")
     (boiling-point . "1883")
     (atomic-radius . "170")
     (covalent-radius . "146")
     (ionic-radius . "74 (+5e) 96 (+3e)")
     (atomic-volume . "21.3")
     (specific-heat . "0.124")
     (fusion-heat . "11.00")
     (evaporation-heat . "172.0")
     (thermal-conductivity . "7.9")
     (debye-temperature . "120.00")
     (pauling-negativity-number . "2.02")
     (first-ionization-energy . "702.9")
     (oxidation-states . "5, 3")
     (lattice-structure . "RHL")
     (lattice-constant . "4.750")
     (lattice-c/a-ratio . "n/a")
     (appearance . "Hard, brittle, steel-gray metal with a pinkish tinge")
     (discovery-date . "n/a (Unknown)")
     (discovered-by . "Known to the ancients.")
     (named-after . "German: bisemutum, (white mass), Now spelled wismut."))

    (84
     (name . "Polonium")
     (symbol . "Po")
     (atomic-mass . "208.9824")
     (density . "9.32")
     (melting-point . "527")
     (boiling-point . "1235")
     (atomic-radius . "176")
     (covalent-radius . "146")
     (ionic-radius . "67 (+6e)")
     (atomic-volume . "22.7")
     (specific-heat . "0.125")
     (fusion-heat . "(10)")
     (evaporation-heat . "(102.9)")
     (thermal-conductivity . "n/a")
     (debye-temperature . "n/a")
     (pauling-negativity-number . "2.0")
     (first-ionization-energy . "813.1")
     (oxidation-states . "6, 4, 2")
     (lattice-structure . "SC")
     (lattice-constant . "3.350")
     (lattice-c/a-ratio . "n/a")
     (appearance . "Silvery-gray metal")
     (discovery-date . "1898 (France)")
     (discovered-by . "Pierre and Marie Curie")
     (named-after . "Named for Poland, native country of Marie Curie."))

    (85
     (name . "Astatine")
     (symbol . "At")
     (atomic-mass . "209.9871")
     (density . "n/a")
     (melting-point . "575")
     (boiling-point . "610")
     (atomic-radius . "n/a")
     (covalent-radius . "(145)")
     (ionic-radius . "62 (+7e)")
     (atomic-volume . "n/a")
     (specific-heat . "n/a")
     (fusion-heat . "n/a")
     (evaporation-heat . "n/a")
     (thermal-conductivity . "n/a")
     (debye-temperature . "n/a")
     (pauling-negativity-number . "2.2")
     (first-ionization-energy . "916.3")
     (oxidation-states . "7, 5, 3, 1, -1")
     (lattice-structure . "n/a")
     (lattice-constant . "n/a")
     (lattice-c/a-ratio . "n/a")
     (appearance . "Unstable, radioactive halogen")
     (discovery-date . "1940 (United States)")
     (discovered-by . "D.R.Corson, K.R.MacKenzie, E.Segré")
     (named-after . "Greek: astatos (unstable)."))

    (86
     (name . "Radon")
     (symbol . "Rn")
     (atomic-mass . "222.0176")
     (density . "4.4 (@ -62 deg C)")
     (melting-point . "202")
     (boiling-point . "211.4")
     (atomic-radius . "n/a")
     (covalent-radius . "n/a")
     (ionic-radius . "n/a")
     (atomic-volume . "n/a")
     (specific-heat . "0.094")
     (fusion-heat . "n/a")
     (evaporation-heat . "18.1")
     (thermal-conductivity . "0.0036")
     (debye-temperature . "n/a")
     (pauling-negativity-number . "n/a")
     (first-ionization-energy . "1036.5")
     (oxidation-states . "n/a")
     (lattice-structure . "FCC")
     (lattice-constant . "n/a")
     (lattice-c/a-ratio . "n/a")
     (appearance . "Heavy radioactive gas")
     (discovery-date . "1898 (Germany)")
     (discovered-by . "Fredrich Ernst Dorn")
     (named-after . "Variation of the name of another element, radium."))

    (87
     (name . "Francium")
     (symbol . "Fr")
     (atomic-mass . "223.0197")
     (density . "n/a")
     (melting-point . "300")
     (boiling-point . "950")
     (atomic-radius . "n/a")
     (covalent-radius . "n/a")
     (ionic-radius . "180 (+1e)")
     (atomic-volume . "n/a")
     (specific-heat . "n/a")
     (fusion-heat . "15")
     (evaporation-heat . "n/a")
     (thermal-conductivity . "n/a")
     (debye-temperature . "n/a")
     (pauling-negativity-number . "0.7")
     (first-ionization-energy . "~375")
     (oxidation-states . "2")
     (lattice-structure . "BCC")
     (lattice-constant . "n/a")
     (lattice-c/a-ratio . "n/a")
     (appearance . "n/a")
     (discovery-date . "1939 (France)")
     (discovered-by . "Marguerite Derey")
     (named-after . "Named for France, the nation of its discovery."))

    (88
     (name . "Radium")
     (symbol . "Ra")
     (atomic-mass . "226.0254")
     (density . "(5.5)")
     (melting-point . "973")
     (boiling-point . "1413")
     (atomic-radius . "n/a")
     (covalent-radius . "n/a")
     (ionic-radius . "143 (+2e)")
     (atomic-volume . "45.0")
     (specific-heat . "0.120")
     (fusion-heat . "(9.6)")
     (evaporation-heat . "(113)")
     (thermal-conductivity . "(18.6)")
     (debye-temperature . "n/a")
     (pauling-negativity-number . "0.9")
     (first-ionization-energy . "509.0")
     (oxidation-states . "2")
     (lattice-structure . "n/a")
     (lattice-constant . "n/a")
     (lattice-c/a-ratio . "n/a")
     (appearance . "Silvery white, radioactive element")
     (discovery-date . "1898 (France)")
     (discovered-by . "Pierre and Marie Curie")
     (named-after . "Latin: radius (ray)."))

    (89
     (name . "Actinium")
     (symbol . "Ac")
     (atomic-mass . "227.0278")
     (density . "n/a")
     (melting-point . "1320")
     (boiling-point . "3470")
     (atomic-radius . "188")
     (covalent-radius . "n/a")
     (ionic-radius . "118 (+3e)")
     (atomic-volume . "22.54")
     (specific-heat . "n/a")
     (fusion-heat . "(10.5)")
     (evaporation-heat . "(292.9)")
     (thermal-conductivity . "n/a")
     (debye-temperature . "n/a")
     (pauling-negativity-number . "1.1")
     (first-ionization-energy . "665.5")
     (oxidation-states . "3")
     (lattice-structure . "FCC")
     (lattice-constant . "5.310")
     (lattice-c/a-ratio . "n/a")
     (appearance . "Heavy, Silvery-white metal that is very radioactive")
     (discovery-date . "1899 (France)")
     (discovered-by . "André Debierne")
     (named-after . "Greek: akis, aktinos (ray)."))

    (90
     (name . "Thorium")
     (symbol . "Th")
     (atomic-mass . "232.0381")
     (density . "11.78")
     (melting-point . "2028")
     (boiling-point . "5060")
     (atomic-radius . "180")
     (covalent-radius . "165")
     (ionic-radius . "102 (+4e)")
     (atomic-volume . "19.8")
     (specific-heat . "0.113")
     (fusion-heat . "16.11")
     (evaporation-heat . "513.7")
     (thermal-conductivity . "(54.0)")
     (debye-temperature . "100.00")
     (pauling-negativity-number . "1.3")
     (first-ionization-energy . "670.4")
     (oxidation-states . "4")
     (lattice-structure . "FCC")
     (lattice-constant . "5.080")
     (lattice-c/a-ratio . "n/a")
     (appearance . "Gray, soft, malleable, ductile, radioactive metal")
     (discovery-date . "1828 (Sweden)")
     (discovered-by . "Jöns Berzelius")
     (named-after . "Named for Thor, Norse god of thunder."))

    (91
     (name . "Protactinium")
     (symbol . "Pa")
     (atomic-mass . "231.03588")
     (density . "15.37")
     (melting-point . "2113")
     (boiling-point . "4300")
     (atomic-radius . "161")
     (covalent-radius . "n/a")
     (ionic-radius . "89 (+5e) 113 (+3e)")
     (atomic-volume . "15.0")
     (specific-heat . "0.121")
     (fusion-heat . "16.7")
     (evaporation-heat . "481.2")
     (thermal-conductivity . "n/a")
     (debye-temperature . "n/a")
     (pauling-negativity-number . "1.5")
     (first-ionization-energy . "n/a")
     (oxidation-states . "5, 4")
     (lattice-structure . "TET")
     (lattice-constant . "3.920")
     (lattice-c/a-ratio . "n/a")
     (appearance . "Silvery-white, radioactive metal")
     (discovery-date . "1917 (England/France)")
     (discovered-by . "Fredrich Soddy, John Cranston, Otto Hahn, Lise Meitner")
     (named-after . "Greek: proto and actinium (parent of actinium); it forms actinium when it radioactively decays."))

    (92
     (name . "Uranium")
     (symbol . "U")
     (atomic-mass . "238.0289")
     (density . "19.05")
     (melting-point . "1405.5")
     (boiling-point . "4018")
     (atomic-radius . "138")
     (covalent-radius . "142")
     (ionic-radius . "80 (+6e) 97 (+4e)")
     (atomic-volume . "12.5")
     (specific-heat . "0.115")
     (fusion-heat . "12.6")
     (evaporation-heat . "417")
     (thermal-conductivity . "27.5")
     (debye-temperature . "n/a")
     (pauling-negativity-number . "1.38")
     (first-ionization-energy . "686.4")
     (oxidation-states . "6, 5, 4, 3")
     (lattice-structure . "ORC")
     (lattice-constant . "2.850")
     (lattice-c/a-ratio . "n/a")
     (appearance . "Silvery-white, dense, ductile and malleable, radioactive metal.")
     (discovery-date . "1789 (Germany)")
     (discovered-by . "Martin Klaproth")
     (named-after . "Named for the planet Uranus."))

    (93
     (name . "Neptunium")
     (symbol . "Np")
     (atomic-mass . "237.048")
     (density . "20.25")
     (melting-point . "913")
     (boiling-point . "4175")
     (atomic-radius . "130")
     (covalent-radius . "n/a")
     (ionic-radius . "95 (+4e) 110 (+3e)")
     (atomic-volume . "21.1")
     (specific-heat . "n/a")
     (fusion-heat . "(9.6)")
     (evaporation-heat . "336")
     (thermal-conductivity . "(6.3)")
     (debye-temperature . "n/a")
     (pauling-negativity-number . "1.36")
     (first-ionization-energy . "n/a")
     (oxidation-states . "6, 5, 4, 3")
     (lattice-structure . "ORC")
     (lattice-constant . "4.720")
     (lattice-c/a-ratio . "n/a")
     (appearance . "Silvery metal")
     (discovery-date . "1940 (United States)")
     (discovered-by . "E.M. McMillan, P.H. Abelson")
     (named-after . "Named for the planet Neptune."))

    (94
     (name . "Plutonium")
     (symbol . "Pu")
     (atomic-mass . "244.0642")
     (density . "19.84")
     (melting-point . "914")
     (boiling-point . "3505")
     (atomic-radius . "151")
     (covalent-radius . "n/a")
     (ionic-radius . "93 (+4e) 108 (+3e)")
     (atomic-volume . "n/a")
     (specific-heat . "n/a")
     (fusion-heat . "2.8")
     (evaporation-heat . "343.5")
     (thermal-conductivity . "(6.7)")
     (debye-temperature . "n/a")
     (pauling-negativity-number . "1.28")
     (first-ionization-energy . "491.9")
     (oxidation-states . "6, 5, 4, 3")
     (lattice-structure . "MCL")
     (lattice-constant . "n/a")
     (lattice-c/a-ratio . "n/a")
     (appearance . "Silvery-white, radioactive metal")
     (discovery-date . "1940 (United States)")
     (discovered-by . "G.T.Seaborg, J.W.Kennedy, E.M.McMillan, A.C.Wohl")
     (named-after . "Named for the planet Pluto."))

    (95
     (name . "Americium")
     (symbol . "Am")
     (atomic-mass . "243.0614")
     (density . "13.67")
     (melting-point . "1267")
     (boiling-point . "2880")
     (atomic-radius . "173")
     (covalent-radius . "n/a")
     (ionic-radius . "92 (+4e) 107 (+3e)")
     (atomic-volume . "20.8")
     (specific-heat . "n/a")
     (fusion-heat . "(10.0)")
     (evaporation-heat . "238.5")
     (thermal-conductivity . "n/a")
     (debye-temperature . "n/a")
     (pauling-negativity-number . "1.3")
     (first-ionization-energy . "n/a")
     (oxidation-states . "6, 5, 4, 3")
     (lattice-structure . "n/a")
     (lattice-constant . "n/a")
     (lattice-c/a-ratio . "n/a")
     (appearance . "Silvery-white, radioactive metal")
     (discovery-date . "1945 (United States)")
     (discovered-by . "G.T.Seaborg, R.A.James, L.O.Morgan, A.Ghiorso")
     (named-after . "Named for the American continent, by analogy with europium."))

    (96
     (name . "Curium")
     (symbol . "Cm")
     (atomic-mass . "247.0703")
     (density . "13.51")
     (melting-point . "1340")
     (boiling-point . "n/a")
     (atomic-radius . "299")
     (covalent-radius . "n/a")
     (ionic-radius . "n/a")
     (atomic-volume . "18.28")
     (specific-heat . "n/a")
     (fusion-heat . "n/a")
     (evaporation-heat . "n/a")
     (thermal-conductivity . "n/a")
     (debye-temperature . "n/a")
     (pauling-negativity-number . "1.3")
     (first-ionization-energy . "(580)")
     (oxidation-states . "4, 3")
     (lattice-structure . "n/a")
     (lattice-constant . "n/a")
     (lattice-c/a-ratio . "n/a")
     (appearance . "Silvery, malleable, synthetic radioactive metal")
     (discovery-date . "1944 (United States)")
     (discovered-by . "G.T.Seaborg, R.A.James, A.Ghiorso")
     (named-after . "Named in honor of Pierre and Marie Curie."))

    (97
     (name . "Berkelium")
     (symbol . "Bk")
     (atomic-mass . "247.0703")
     (density . "13.25")
     (melting-point . "n/a")
     (boiling-point . "n/a")
     (atomic-radius . "297")
     (covalent-radius . "n/a")
     (ionic-radius . "n/a")
     (atomic-volume . "n/a")
     (specific-heat . "n/a")
     (fusion-heat . "n/a")
     (evaporation-heat . "n/a")
     (thermal-conductivity . "n/a")
     (debye-temperature . "n/a")
     (pauling-negativity-number . "1.3")
     (first-ionization-energy . "(600)")
     (oxidation-states . "4, 3")
     (lattice-structure . "n/a")
     (lattice-constant . "n/a")
     (lattice-c/a-ratio . "n/a")
     (appearance . "Radionactive synthetic metal")
     (discovery-date . "1949 (United States)")
     (discovered-by . "G.T.Seaborg, S.G.Tompson, A.Ghiorso")
     (named-after . "Named after Berkeley, California the city of its discovery."))

    (98
     (name . "Californium")
     (symbol . "Cf")
     (atomic-mass . "251.0796")
     (density . "15.1")
     (melting-point . "900")
     (boiling-point . "n/a")
     (atomic-radius . "295")
     (covalent-radius . "n/a")
     (ionic-radius . "n/a")
     (atomic-volume . "n/a")
     (specific-heat . "n/a")
     (fusion-heat . "n/a")
     (evaporation-heat . "n/a")
     (thermal-conductivity . "n/a")
     (debye-temperature . "n/a")
     (pauling-negativity-number . "1.3")
     (first-ionization-energy . "(610)")
     (oxidation-states . "4, 3")
     (lattice-structure . "n/a")
     (lattice-constant . "n/a")
     (lattice-c/a-ratio . "n/a")
     (appearance . "Powerful neutron emitter")
     (discovery-date . "1950 (United States)")
     (discovered-by . "G.T.Seaborg, S.G.Tompson, A.Ghiorso, K.Street Jr.")
     (named-after . "Named after the state and University of California."))

    (99
     (name . "Einsteinium")
     (symbol . "Es")
     (atomic-mass . "252.083")
     (density . "n/a")
     (melting-point . "n/a")
     (boiling-point . "1130")
     (atomic-radius . "292")
     (covalent-radius . "n/a")
     (ionic-radius . "n/a")
     (atomic-volume . "n/a")
     (specific-heat . "n/a")
     (fusion-heat . "n/a")
     (evaporation-heat . "n/a")
     (thermal-conductivity . "n/a")
     (debye-temperature . "n/a")
     (pauling-negativity-number . "1.3")
     (first-ionization-energy . "(620)")
     (oxidation-states . "3")
     (lattice-structure . "n/a")
     (lattice-constant . "n/a")
     (lattice-c/a-ratio . "n/a")
     (appearance . "Radioactive, synthetic metal")
     (discovery-date . "1952 (United States)")
     (discovered-by . "Argonne, Los Alamos, U of Calif")
     (named-after . "Named in honor of the scientist Albert Einstein."))

    (100
     (name . "Fermium")
     (symbol . "Fm")
     (atomic-mass . "257.0951")
     (density . "n/a")
     (melting-point . "1800")
     (boiling-point . "n/a")
     (atomic-radius . "290")
     (covalent-radius . "n/a")
     (ionic-radius . "n/a")
     (atomic-volume . "n/a")
     (specific-heat . "n/a")
     (fusion-heat . "n/a")
     (evaporation-heat . "n/a")
     (thermal-conductivity . "n/a")
     (debye-temperature . "n/a")
     (pauling-negativity-number . "1.3")
     (first-ionization-energy . "(630)")
     (oxidation-states . "3")
     (lattice-structure . "n/a")
     (lattice-constant . "n/a")
     (lattice-c/a-ratio . "n/a")
     (appearance . "Radioactive, synthetic metal")
     (discovery-date . "1953 (United States)")
     (discovered-by . "Argonne, Los Alamos, U of Calif")
     (named-after . "Named in honor of the scientist Enrico Fermi."))

    (101
     (name . "Mendelevium")
     (symbol . "Md")
     (atomic-mass . "258.1")
     (density . "n/a")
     (melting-point . "1100")
     (boiling-point . "n/a")
     (atomic-radius . "287")
     (covalent-radius . "n/a")
     (ionic-radius . "n/a")
     (atomic-volume . "n/a")
     (specific-heat . "n/a")
     (fusion-heat . "n/a")
     (evaporation-heat . "n/a")
     (thermal-conductivity . "n/a")
     (debye-temperature . "n/a")
     (pauling-negativity-number . "1.3")
     (first-ionization-energy . "(635)")
     (oxidation-states . "3")
     (lattice-structure . "n/a")
     (lattice-constant . "n/a")
     (lattice-c/a-ratio . "n/a")
     (appearance . "Radioactive, synthetic metal")
     (discovery-date . "1955 (United States)")
     (discovered-by . "G.T.Seaborg, S.G.Tompson, A.Ghiorso, K.Street Jr.")
     (named-after . "Named in honor of the scientist Dmitri Ivanovitch Mendeleyev, who devised the periodic table."))

    (102
     (name . "Nobelium")
     (symbol . "No")
     (atomic-mass . "259.1009")
     (density . "n/a")
     (melting-point . "1100")
     (boiling-point . "n/a")
     (atomic-radius . "285")
     (covalent-radius . "n/a")
     (ionic-radius . "n/a")
     (atomic-volume . "n/a")
     (specific-heat . "n/a")
     (fusion-heat . "n/a")
     (evaporation-heat . "n/a")
     (thermal-conductivity . "n/a")
     (debye-temperature . "n/a")
     (pauling-negativity-number . "1.3")
     (first-ionization-energy . "(640)")
     (oxidation-states . "3, 2")
     (lattice-structure . "n/a")
     (lattice-constant . "n/a")
     (lattice-c/a-ratio . "n/a")
     (appearance . "Radioactive, synthetic metal.")
     (discovery-date . "1957 (Sweden)")
     (discovered-by . "Nobel Institute for Physics")
     (named-after . "Named in honor of Alfred Nobel, who invented dynamite and founded Nobel prize."))

    (103
     (name . "Lawrencium")
     (symbol . "Lr")
     (atomic-mass . "262.11")
     (density . "n/a")
     (melting-point . "n/a")
     (boiling-point . "n/a")
     (atomic-radius . "282")
     (covalent-radius . "n/a")
     (ionic-radius . "n/a")
     (atomic-volume . "n/a")
     (specific-heat . "n/a")
     (fusion-heat . "n/a")
     (evaporation-heat . "n/a")
     (thermal-conductivity . "n/a")
     (debye-temperature . "n/a")
     (pauling-negativity-number . "n/a")
     (first-ionization-energy . "n/a")
     (oxidation-states . "3")
     (lattice-structure . "n/a")
     (lattice-constant . "n/a")
     (lattice-c/a-ratio . "n/a")
     (appearance . "Radioactive, synthetic metal")
     (discovery-date . "1961 (United States)")
     (discovered-by . "A.Ghiorso, T.Sikkeland, A.E.Larsh, R.M.Latimer")
     (named-after . "Named in honor of Ernest O. Lawrence, inventor of the cyclotron."))

    (104
     (name . "Rutherfordium")
     (symbol . "Rf")
     (atomic-mass . "[261]")
     (density . "n/a")
     (melting-point . "n/a")
     (boiling-point . "n/a")
     (atomic-radius . "n/a")
     (covalent-radius . "n/a")
     (ionic-radius . "n/a")
     (atomic-volume . "n/a")
     (specific-heat . "n/a")
     (fusion-heat . "n/a")
     (evaporation-heat . "n/a")
     (thermal-conductivity . "n/a")
     (debye-temperature . "n/a")
     (pauling-negativity-number . "n/a")
     (first-ionization-energy . "n/a")
     (oxidation-states . "n/a")
     (lattice-structure . "n/a")
     (lattice-constant . "n/a")
     (lattice-c/a-ratio . "n/a")
     (appearance . "Radioactive, synthetic metal")
     (discovery-date . "1969 (United States)")
     (discovered-by . "A. Ghiorso, et al")
     (named-after . "Named in honor of Ernest Rutherford."))

    (105
     (name . "Dubnium")
     (symbol . "Db")
     (atomic-mass . "[262]")
     (density . "n/a")
     (melting-point . "n/a")
     (boiling-point . "n/a")
     (atomic-radius . "n/a")
     (covalent-radius . "n/a")
     (ionic-radius . "n/a")
     (atomic-volume . "n/a")
     (specific-heat . "n/a")
     (fusion-heat . "n/a")
     (evaporation-heat . "n/a")
     (thermal-conductivity . "n/a")
     (debye-temperature . "n/a")
     (pauling-negativity-number . "n/a")
     (first-ionization-energy . "n/a")
     (oxidation-states . "n/a")
     (lattice-structure . "n/a")
     (lattice-constant . "n/a")
     (lattice-c/a-ratio . "n/a")
     (appearance . "Radioactive, synthetic metal")
     (discovery-date . "1970 (United States)")
     (discovered-by . "A. Ghiorso, et al")
     (named-after . "The Joint Nuclear Institute at Dubna."))

    (106
     (name . "Seaborgium")
     (symbol . "Sg")
     (atomic-mass . "[266]")
     (density . "n/a")
     (melting-point . "n/a")
     (boiling-point . "n/a")
     (atomic-radius . "n/a")
     (covalent-radius . "n/a")
     (ionic-radius . "n/a")
     (atomic-volume . "n/a")
     (specific-heat . "n/a")
     (fusion-heat . "n/a")
     (evaporation-heat . "n/a")
     (thermal-conductivity . "n/a")
     (debye-temperature . "n/a")
     (pauling-negativity-number . "n/a")
     (first-ionization-energy . "n/a")
     (oxidation-states . "n/a")
     (lattice-structure . "n/a")
     (lattice-constant . "n/a")
     (lattice-c/a-ratio . "n/a")
     (appearance . "Radioactive, synthetic metal")
     (discovery-date . "1974 (USSR/United States)")
     (discovered-by . "Soviet Nuclear Research/ U. of Cal at Berkeley")
     (named-after . "Named in honor of Glenn Seaborg, American physical chemist known for research on transuranium elements."))

    (107
     (name . "Bohrium")
     (symbol . "Bh")
     (atomic-mass . "[264]")
     (density . "n/a")
     (melting-point . "n/a")
     (boiling-point . "n/a")
     (atomic-radius . "n/a")
     (covalent-radius . "n/a")
     (ionic-radius . "n/a")
     (atomic-volume . "n/a")
     (specific-heat . "n/a")
     (fusion-heat . "n/a")
     (evaporation-heat . "n/a")
     (thermal-conductivity . "n/a")
     (debye-temperature . "n/a")
     (pauling-negativity-number . "n/a")
     (first-ionization-energy . "n/a")
     (oxidation-states . "n/a")
     (lattice-structure . "n/a")
     (lattice-constant . "n/a")
     (lattice-c/a-ratio . "n/a")
     (appearance . "Radioactive, synthetic metal")
     (discovery-date . "1976 (Germany)")
     (discovered-by . "Heavy Ion Research Laboratory (HIRL)")
     (named-after . "Named in honor of Niels Bohr."))

    (108
     (name . "Hassium")
     (symbol . "Hs")
     (atomic-mass . "[269]")
     (density . "n/a")
     (melting-point . "n/a")
     (boiling-point . "n/a")
     (atomic-radius . "n/a")
     (covalent-radius . "n/a")
     (ionic-radius . "n/a")
     (atomic-volume . "n/a")
     (specific-heat . "n/a")
     (fusion-heat . "n/a")
     (evaporation-heat . "n/a")
     (thermal-conductivity . "n/a")
     (debye-temperature . "n/a")
     (pauling-negativity-number . "n/a")
     (first-ionization-energy . "n/a")
     (oxidation-states . "n/a")
     (lattice-structure . "n/a")
     (lattice-constant . "n/a")
     (lattice-c/a-ratio . "n/a")
     (appearance . "n/a")
     (discovery-date . "1984 (Germany)")
     (discovered-by . "Heavy Ion Research Laboratory (HIRL)")
     (named-after . "Named in honor of Henri Hess, Swiss born Russian chemist known for work in thermodydamics."))

    (109
     (name . "Meitnerium")
     (symbol . "Mt")
     (atomic-mass . "[268]")
     (density . "n/a")
     (melting-point . "n/a")
     (boiling-point . "n/a")
     (atomic-radius . "n/a")
     (covalent-radius . "n/a")
     (ionic-radius . "n/a")
     (atomic-volume . "n/a")
     (specific-heat . "n/a")
     (fusion-heat . "n/a")
     (evaporation-heat . "n/a")
     (thermal-conductivity . "n/a")
     (debye-temperature . "n/a")
     (pauling-negativity-number . "n/a")
     (first-ionization-energy . "n/a")
     (oxidation-states . "n/a")
     (lattice-structure . "n/a")
     (lattice-constant . "n/a")
     (lattice-c/a-ratio . "n/a")
     (appearance . "n/a")
     (discovery-date . "1982 (Germany)")
     (discovered-by . "Heavy Ion Research Laboratory (HIRL)")
     (named-after . "Named in honor of Lise Mietner."))

    (110
     (name . "Darmstadtium")
     (symbol . "Ds")
     (atomic-mass . "[269]")
     (density . "n/a")
     (melting-point . "n/a")
     (boiling-point . "n/a")
     (atomic-radius . "n/a")
     (covalent-radius . "n/a")
     (ionic-radius . "n/a")
     (atomic-volume . "n/a")
     (specific-heat . "n/a")
     (fusion-heat . "n/a")
     (evaporation-heat . "n/a")
     (thermal-conductivity . "n/a")
     (debye-temperature . "n/a")
     (pauling-negativity-number . "n/a")
     (first-ionization-energy . "n/a")
     (oxidation-states . "n/a")
     (lattice-structure . "n/a")
     (lattice-constant . "n/a")
     (lattice-c/a-ratio . "n/a")
     (appearance . "n/a")
     (discovery-date . "1994 (Germany)")
     (discovered-by . "GSI (Gesellschaft für Schwerionenforschung mbH, Darmstadt, Germany)")
     (named-after . "Named after Darmstadt, Germany the city of its discovery."))

    (111
     (name . "Roentgenium")
     (symbol . "Rg")
     (atomic-mass . "[272]")
     (density . "n/a")
     (melting-point . "n/a")
     (boiling-point . "n/a")
     (atomic-radius . "n/a")
     (covalent-radius . "n/a")
     (ionic-radius . "n/a")
     (atomic-volume . "n/a")
     (specific-heat . "n/a")
     (fusion-heat . "n/a")
     (evaporation-heat . "n/a")
     (thermal-conductivity . "n/a")
     (debye-temperature . "n/a")
     (pauling-negativity-number . "n/a")
     (first-ionization-energy . "n/a")
     (oxidation-states . "n/a")
     (lattice-structure . "n/a")
     (lattice-constant . "n/a")
     (lattice-c/a-ratio . "n/a")
     (appearance . "n/a")
     (discovery-date . "1994 (Germany)")
     (discovered-by . "Heavy Ion Research Laboratory (HIRL)")
     (named-after . "Wilhelm Conrad Roentgen discovered X-rays in 1895."))

    (112
     (name . "Copernicium")
     (symbol . "Cn")
     (atomic-mass . "[277]")
     (density . "n/a")
     (melting-point . "n/a")
     (boiling-point . "n/a")
     (atomic-radius . "n/a")
     (covalent-radius . "n/a")
     (ionic-radius . "n/a")
     (atomic-volume . "n/a")
     (specific-heat . "n/a")
     (fusion-heat . "n/a")
     (evaporation-heat . "n/a")
     (thermal-conductivity . "n/a")
     (debye-temperature . "n/a")
     (pauling-negativity-number . "n/a")
     (first-ionization-energy . "n/a")
     (oxidation-states . "n/a")
     (lattice-structure . "n/a")
     (lattice-constant . "n/a")
     (lattice-c/a-ratio . "n/a")
     (appearance . "n/a")
     (discovery-date . "1996 (Germany)")
     (discovered-by . "n/a")
     (named-after . "In honour of scientist and astronomer Nicolaus Copernicus (1473-1543)."))

    (113
     (name . "Nihonium")
     (symbol . "Nh")
     (atomic-mass . "n/a")
     (density . "n/a")
     (melting-point . "n/a")
     (boiling-point . "n/a")
     (atomic-radius . "n/a")
     (covalent-radius . "n/a")
     (ionic-radius . "n/a")
     (atomic-volume . "n/a")
     (specific-heat . "n/a")
     (fusion-heat . "n/a")
     (evaporation-heat . "n/a")
     (thermal-conductivity . "n/a")
     (debye-temperature . "n/a")
     (pauling-negativity-number . "n/a")
     (first-ionization-energy . "n/a")
     (oxidation-states . "n/a")
     (lattice-structure . "n/a")
     (lattice-constant . "n/a")
     (lattice-c/a-ratio . "n/a")
     (appearance . "n/a")
     (discovery-date . "2003")
     (discovered-by . "n/a")
     (named-after . "Nihon is one of the two ways to say «Japan» in Japanese."))

    (114
     (name . "Flerovium")
     (symbol . "Fl")
     (atomic-mass . "[289]")
     (density . "n/a")
     (melting-point . "n/a")
     (boiling-point . "n/a")
     (atomic-radius . "n/a")
     (covalent-radius . "n/a")
     (ionic-radius . "n/a")
     (atomic-volume . "n/a")
     (specific-heat . "n/a")
     (fusion-heat . "n/a")
     (evaporation-heat . "n/a")
     (thermal-conductivity . "n/a")
     (debye-temperature . "n/a")
     (pauling-negativity-number . "n/a")
     (first-ionization-energy . "n/a")
     (oxidation-states . "n/a")
     (lattice-structure . "n/a")
     (lattice-constant . "n/a")
     (lattice-c/a-ratio . "n/a")
     (appearance . "n/a")
     (discovery-date . "1999")
     (discovered-by . "n/a")
     (named-after . "Georgiy N. Flerov (1913-1990) was an eminent physicist who discovered the spontaneous fission of uranium."))

    (115
     (name . "Moscovium")
     (symbol . "Mc")
     (atomic-mass . "n/a")
     (density . "n/a")
     (melting-point . "n/a")
     (boiling-point . "n/a")
     (atomic-radius . "n/a")
     (covalent-radius . "n/a")
     (ionic-radius . "n/a")
     (atomic-volume . "n/a")
     (specific-heat . "n/a")
     (fusion-heat . "n/a")
     (evaporation-heat . "n/a")
     (thermal-conductivity . "n/a")
     (debye-temperature . "n/a")
     (pauling-negativity-number . "n/a")
     (first-ionization-energy . "n/a")
     (oxidation-states . "n/a")
     (lattice-structure . "n/a")
     (lattice-constant . "n/a")
     (lattice-c/a-ratio . "n/a")
     (appearance . "n/a")
     (discovery-date . "2003")
     (discovered-by . "n/a")
     (named-after . "Honoring Moscow region of Dubna, Russia."))

    (116
     (name . "Livermorium")
     (symbol . "Lv")
     (atomic-mass . "n/a")
     (density . "n/a")
     (melting-point . "n/a")
     (boiling-point . "n/a")
     (atomic-radius . "n/a")
     (covalent-radius . "n/a")
     (ionic-radius . "n/a")
     (atomic-volume . "n/a")
     (specific-heat . "n/a")
     (fusion-heat . "n/a")
     (evaporation-heat . "n/a")
     (thermal-conductivity . "n/a")
     (debye-temperature . "n/a")
     (pauling-negativity-number . "n/a")
     (first-ionization-energy . "n/a")
     (oxidation-states . "n/a")
     (lattice-structure . "n/a")
     (lattice-constant . "n/a")
     (lattice-c/a-ratio . "n/a")
     (appearance . "n/a")
     (discovery-date . "1999")
     (discovered-by . "n/a")
     (named-after . "The Lawrence Livermore National Laboratory, California, USA."))

    (117
     (name . "Tennessine")
     (symbol . "Ts")
     (atomic-mass . "n/a")
     (density . "n/a")
     (melting-point . "n/a")
     (boiling-point . "n/a")
     (atomic-radius . "n/a")
     (covalent-radius . "n/a")
     (ionic-radius . "n/a")
     (atomic-volume . "n/a")
     (specific-heat . "n/a")
     (fusion-heat . "n/a")
     (evaporation-heat . "n/a")
     (thermal-conductivity . "n/a")
     (debye-temperature . "n/a")
     (pauling-negativity-number . "n/a")
     (first-ionization-energy . "n/a")
     (oxidation-states . "n/a")
     (lattice-structure . "n/a")
     (lattice-constant . "n/a")
     (lattice-c/a-ratio . "n/a")
     (appearance . "n/a")
     (discovery-date . "2010")
     (discovered-by . "n/a")
     (named-after . "Tennessee, USA."))

    (118
     (name . "Oganesson")
     (symbol . "Og")
     (atomic-mass . "n/a")
     (density . "n/a")
     (melting-point . "n/a")
     (boiling-point . "n/a")
     (atomic-radius . "n/a")
     (covalent-radius . "n/a")
     (ionic-radius . "n/a")
     (atomic-volume . "n/a")
     (specific-heat . "n/a")
     (fusion-heat . "n/a")
     (evaporation-heat . "n/a")
     (thermal-conductivity . "n/a")
     (debye-temperature . "n/a")
     (pauling-negativity-number . "n/a")
     (first-ionization-energy . "n/a")
     (oxidation-states . "n/a")
     (lattice-structure . "n/a")
     (lattice-constant . "n/a")
     (lattice-c/a-ratio . "n/a")
     (appearance . "n/a")
     (discovery-date . "1999")
     (discovered-by . "n/a")
     (named-after . "Recognises Professor Yuri Oganessian (born 1933) for his pioneering contributions to transactinoid elements research.")))
  "Alist mapping elements and their properties.
Each car is an atomic number and each cdr a list of properties.")

;; Data from NIST:
;; <URL:http://physics.nist.gov/PhysRefData/Compositions/index.html>

(defconst eperiodic-isotope-properties
  '(mass-number relative-atomic-mass isotopic-composition)
  "List of properties stored in `eperiodic-isotope-data'.")

(defconst eperiodic-isotope-data
  '((1
     (1 "1.0078250321(4)" "99.9885(70)")
     (2 "2.0141017780(4)" "0.0115(70)")
     (3 "3.0160492675(11)"))
    (2
     (3 "3.0160293097(9)" "0.000137(3)")
     (4 "4.0026032497(10)" "99.999863(3)"))
    (3
     (6 "6.0151223(5)" "7.59(4)")
     (7 "7.0160040(5)" "92.41(4)"))
    (4
     (9 "9.0121821(4)" "100"))
    (5
     (10 "10.0129370(4)" "19.9(7)")
     (11 "11.0093055(5)" "80.1(7)"))
    (6
     (12 "12.0000000(0)" "98.93(8)")
     (13 "13.0033548378(10)" "1.07(8)")
     (14 "14.003241988(4)"))
    (7
     (14 "14.0030740052(9)" "99.632(7)")
     (15 "15.0001088984(9)" "0.368(7)"))
    (8
     (16 "15.9949146221(15)" "99.757(16)")
     (17 "16.99913150(22)" "0.038(1)")
     (18 "17.9991604(9)" "0.205(14)"))
    (9
     (19 "18.99840320(7)" "100"))
    (10
     (20 "19.9924401759(20)" "90.48(3)")
     (21 "20.99384674(4)" "0.27(1)")
     (22 "21.99138551(23)" "9.25(3)"))
    (11
     (23 "22.98976967(23)" "100"))
    (12
     (24 "23.98504190(20)" "78.99(4)")
     (25 "24.98583702(20)" "10.00(1)")
     (26 "25.98259304(21)" "11.01(3)"))
    (13
     (27 "26.98153844(14)" "100"))
    (14
     (28 "27.9769265327(20)" "92.2297(7)")
     (29 "28.97649472(3)" "4.6832(5)")
     (30 "29.97377022(5)" "3.0872(5)"))
    (15
     (31 "30.97376151(20)" "100"))
    (16
     (32 "31.97207069(12)" "94.93(31)")
     (33 "32.97145850(12)" "0.76(2)")
     (34 "33.96786683(11)" "4.29(28)")
     (36 "35.96708088(25)" "0.02(1)"))
    (17
     (35 "34.96885271(4)" "75.78(4)")
     (37 "36.96590260(5)" "24.22(4)"))
    (18
     (36 "35.96754628(27)" "0.3365(30)")
     (38 "37.9627322(5)" "0.0632(5)")
     (40 "39.962383123(3)" "99.6003(30)"))
    (19
     (39 "38.9637069(3)" "93.2581(44)")
     (40 "39.96399867(29)" "0.0117(1)")
     (41 "40.96182597(28)" "6.7302(44)"))
    (20
     (40 "39.9625912(3)" "96.941(156)")
     (42 "41.9586183(4)" "0.647(23)")
     (43 "42.9587668(5)" "0.135(10)")
     (44 "43.9554811(9)" "2.086(110)")
     (46 "45.9536928(25)" "0.004(3)")
     (48 "47.952534(4)" "0.187(21)"))
    (21
     (45 "44.9559102(12)" "100"))
    (22
     (46 "45.9526295(12)" "8.25(3)")
     (47 "46.9517638(10)" "7.44(2)")
     (48 "47.9479471(10)" "73.72(3)")
     (49 "48.9478708(10)" "5.41(2)")
     (50 "49.9447921(11)" "5.18(2)"))
    (23
     (50 "49.9471628(14)" "0.250(4)")
     (51 "50.9439637(14)" "99.750(4)"))
    (24
     (50 "49.9460496(14)" "4.345(13)")
     (52 "51.9405119(15)" "83.789(18)")
     (53 "52.9406538(15)" "9.501(17)")
     (54 "53.9388849(15)" "2.365(7)"))
    (25
     (55 "54.9380496(14)" "100"))
    (26
     (54 "53.9396148(14)" "5.845(35)")
     (56 "55.9349421(15)" "91.754(36)")
     (57 "56.9353987(15)" "2.119(10)")
     (58 "57.9332805(15)" "0.282(4)"))
    (27
     (59 "58.9332002(15)" "100"))
    (28
     (58 "57.9353479(15)" "68.0769(89)")
     (60 "59.9307906(15)" "26.2231(77)")
     (61 "60.9310604(15)" "1.1399(6)")
     (62 "61.9283488(15)" "3.6345(17)")
     (64 "63.9279696(16)" "0.9256(9)"))
    (29
     (63 "62.9296011(15)" "69.17(3)")
     (65 "64.9277937(19)" "30.83(3)"))
    (30
     (64 "63.9291466(18)" "48.63(60)")
     (66 "65.9260368(16)" "27.90(27)")
     (67 "66.9271309(17)" "4.10(13)")
     (68 "67.9248476(17)" "18.75(51)")
     (70 "69.925325(4)" "0.62(3)"))
    (31
     (69 "68.925581(3)" "60.108(9)")
     (71 "70.9247050(19)" "39.892(9)"))
    (32
     (70 "69.9242504(19)" "20.84(87)")
     (72 "71.9220762(16)" "27.54(34)")
     (73 "72.9234594(16)" "7.73(5)")
     (74 "73.9211782(16)" "36.28(73)")
     (76 "75.9214027(16)" "7.61(38)"))
    (33
     (75 "74.9215964(18)" "100"))
    (34
     (74 "73.9224766(16)" "0.89(4)")
     (76 "75.9192141(16)" "9.37(29)")
     (77 "76.9199146(16)" "7.63(16)")
     (78 "77.9173095(16)" "23.77(28)")
     (80 "79.9165218(20)" "49.61(41)")
     (82 "81.9167000(22)" "8.73(22)"))
    (35
     (79 "78.9183376(20)" "50.69(7)")
     (81 "80.916291(3)" "49.31(7)"))
    (36
     (78 "77.920386(7)" "0.35(1)")
     (80 "79.916378(4)" "2.28(6)")
     (82 "81.9134846(28)" "11.58(14)")
     (83 "82.914136(3)" "11.49(6)")
     (84 "83.911507(3)" "57.00(4)")
     (86 "85.9106103(12)" "17.30(22)"))
    (37
     (85 "84.9117893(25)" "72.17(2)")
     (87 "86.9091835(27)" "27.83(2)"))
    (38
     (84 "83.913425(4)" "0.56(1)")
     (86 "85.9092624(24)" "9.86(1)")
     (87 "86.9088793(24)" "7.00(1)")
     (88 "87.9056143(24)" "82.58(1)"))
    (39
     (89 "88.9058479(25)" "100"))
    (40
     (90 "89.9047037(23)" "51.45(40)")
     (91 "90.9056450(23)" "11.22(5)")
     (92 "91.9050401(23)" "17.15(8)")
     (94 "93.9063158(25)" "17.38(28)")
     (96 "95.908276(3)" "2.80(9)"))
    (41
     (93 "92.9063775(24)" "100"))
    (42
     (92 "91.906810(4)" "14.84(35)")
     (94 "93.9050876(20)" "9.25(12)")
     (95 "94.9058415(20)" "15.92(13)")
     (96 "95.9046789(20)" "16.68(2)")
     (97 "96.9060210(20)" "9.55(8)")
     (98 "97.9054078(20)" "24.13(31)")
     (100 "99.907477(6)" "9.63(23)"))
    (43
     (97 "96.906365(5)")
     (98 "97.907216(4)")
     (99 "98.9062546(21)"))
    (44
     (96 "95.907598(8)" "5.54(14)")
     (98 "97.905287(7)" "1.87(3)")
     (99 "98.9059393(21)" "12.76(14)")
     (100 "99.9042197(22)" "12.60(7)")
     (101 "100.9055822(22)" "17.06(2)")
     (102 "101.9043495(22)" "31.55(14)")
     (104 "103.905430(4)" "18.62(27)"))
    (45
     (103 "102.905504(3)" "100"))
    (46
     (102 "101.905608(3)" "1.02(1)")
     (104 "103.904035(5)" "11.14(8)")
     (105 "104.905084(5)" "22.33(8)")
     (106 "105.903483(5)" "27.33(3)")
     (108 "107.903894(4)" "26.46(9)")
     (110 "109.905152(12)" "11.72(9)"))
    (47
     (107 "106.905093(6)" "51.839(8)")
     (109 "108.904756(3)" "48.161(8)"))
    (48
     (106 "105.906458(6)" "1.25(6)")
     (108 "107.904183(6)" "0.89(3)")
     (110 "109.903006(3)" "12.49(18)")
     (111 "110.904182(3)" "12.80(12)")
     (112 "111.9027572(30)" "24.13(21)")
     (113 "112.9044009(30)" "12.22(12)")
     (114 "113.9033581(30)" "28.73(42)")
     (116 "115.904755(3)" "7.49(18)"))
    (49
     (113 "112.904061(4)" "4.29(5)")
     (115 "114.903878(5)" "95.71(5)"))
    (50
     (112 "111.904821(5)" "0.97(1)")
     (114 "113.902782(3)" "0.66(1)")
     (115 "114.903346(3)" "0.34(1)")
     (116 "115.901744(3)" "14.54(9)")
     (117 "116.902954(3)" "7.68(7)")
     (118 "117.901606(3)" "24.22(9)")
     (119 "118.903309(3)" "8.59(4)")
     (120 "119.9021966(27)" "32.58(9)")
     (122 "121.9034401(29)" "4.63(3)")
     (124 "123.9052746(15)" "5.79(5)"))
    (51
     (121 "120.9038180(24)" "57.21(5)")
     (123 "122.9042157(22)" "42.79(5)"))
    (52
     (120 "119.904020(11)" "0.09(1)")
     (122 "121.9030471(20)" "2.55(12)")
     (123 "122.9042730(19)" "0.89(3)")
     (124 "123.9028195(16)" "4.74(14)")
     (125 "124.9044247(20)" "7.07(15)")
     (126 "125.9033055(20)" "18.84(25)")
     (128 "127.9044614(19)" "31.74(8)")
     (130 "129.9062228(21)" "34.08(62)"))
    (53
     (127 "126.904468(4)" "100"))
    (54
     (124 "123.9058958(21)" "0.09(1)")
     (126 "125.904269(7)" "0.09(1)")
     (128 "127.9035304(15)" "1.92(3)")
     (129 "128.9047795(9)" "26.44(24)")
     (130 "129.9035079(10)" "4.08(2)")
     (131 "130.9050819(10)" "21.18(3)")
     (132 "131.9041545(12)" "26.89(6)")
     (134 "133.9053945(9)" "10.44(10)")
     (136 "135.907220(8)" "8.87(16)"))
    (55
     (133 "132.905447(3)" "100"))
    (56
     (130 "129.906310(7)" "0.106(1)")
     (132 "131.905056(3)" "0.101(1)")
     (134 "133.904503(3)" "2.417(18)")
     (135 "134.905683(3)" "6.592(12)")
     (136 "135.904570(3)" "7.854(24)")
     (137 "136.905821(3)" "11.232(24)")
     (138 "137.905241(3)" "71.698(42)"))
    (57
     (138 "137.907107(4)" "0.090(1)")
     (139 "138.906348(3)" "99.910(1)"))
    (58
     (136 "135.907140(50)" "0.185(2)")
     (138 "137.905986(11)" "0.251(2)")
     (140 "139.905434(3)" "88.450(51)")
     (142 "141.909240(4)" "11.114(51)"))
    (59
     (141 "140.907648(3)" "100"))
    (60
     (142 "141.907719(3)" "27.2(5)")
     (143 "142.909810(3)" "12.2(2)")
     (144 "143.910083(3)" "23.8(3)")
     (145 "144.912569(3)" "8.3(1)")
     (146 "145.913112(3)" "17.2(3)")
     (148 "147.916889(3)" "5.7(1)")
     (150 "149.920887(4)" "5.6(2)"))
    (61
     (145 "144.912744(4)")
     (147 "146.915134(3)"))
    (62
     (144 "143.911995(4)" "3.07(7)")
     (147 "146.914893(3)" "14.99(18)")
     (148 "147.914818(3)" "11.24(10)")
     (149 "148.917180(3)" "13.82(7)")
     (150 "149.917271(3)" "7.38(1)")
     (152 "151.919728(3)" "26.75(16)")
     (154 "153.922205(3)" "22.75(29)"))
    (63
     (151 "150.919846(3)" "47.81(3)")
     (153 "152.921226(3)" "52.19(3)"))
    (64
     (152 "151.919788(3)" "0.20(1)")
     (154 "153.920862(3)" "2.18(3)")
     (155 "154.922619(3)" "14.80(12)")
     (156 "155.922120(3)" "20.47(9)")
     (157 "156.923957(3)" "15.65(2)")
     (158 "157.924101(3)" "24.84(7)")
     (160 "159.927051(3)" "21.86(19)"))
    (65
     (159 "158.925343(3)" "100"))
    (66
     (156 "155.924278(7)" "0.06(1)")
     (158 "157.924405(4)" "0.10(1)")
     (160 "159.925194(3)" "2.34(8)")
     (161 "160.926930(3)" "18.91(24)")
     (162 "161.926795(3)" "25.51(26)")
     (163 "162.928728(3)" "24.90(16)")
     (164 "163.929171(3)" "28.18(37)"))
    (67
     (165 "164.930319(3)" "100"))
    (68
     (162 "161.928775(4)" "0.14(1)")
     (164 "163.929197(4)" "1.61(3)")
     (166 "165.930290(3)" "33.61(35)")
     (167 "166.932045(3)" "22.93(17)")
     (168 "167.932368(3)" "26.78(26)")
     (170 "169.935460(3)" "14.93(27)"))
    (69
     (169 "168.934211(3)" "100"))
    (70
     (168 "167.933894(5)" "0.13(1)")
     (170 "169.934759(3)" "3.04(15)")
     (171 "170.936322(3)" "14.28(57)")
     (172 "171.9363777(30)" "21.83(67)")
     (173 "172.9382068(30)" "16.13(27)")
     (174 "173.9388581(30)" "31.83(92)")
     (176 "175.942568(3)" "12.76(41)"))
    (71
     (175 "174.9407679(28)" "97.41(2)")
     (176 "175.9426824(28)" "2.59(2)"))
    (72
     (174 "173.940040(3)" "0.16(1)")
     (176 "175.9414018(29)" "5.26(7)")
     (177 "176.9432200(27)" "18.60(9)")
     (178 "177.9436977(27)" "27.28(7)")
     (179 "178.9458151(27)" "13.62(2)")
     (180 "179.9465488(27)" "35.08(16)"))
    (73
     (180 "179.947466(3)" "0.012(2)")
     (181 "180.947996(3)" "99.988(2)"))
    (74
     (180 "179.946706(5)" "0.12(1)")
     (182 "181.948206(3)" "26.50(16)")
     (183 "182.9502245(29)" "14.31(4)")
     (184 "183.9509326(29)" "30.64(2)")
     (186 "185.954362(3)" "28.43(19)"))
    (75
     (185 "184.9529557(30)" "37.40(2)")
     (187 "186.9557508(30)" "62.60(2)"))
    (76
     (184 "183.952491(3)" "0.02(1)")
     (186 "185.953838(3)" "1.59(3)")
     (187 "186.9557479(30)" "1.96(2)")
     (188 "187.9558360(30)" "13.24(8)")
     (189 "188.9581449(30)" "16.15(5)")
     (190 "189.958445(3)" "26.26(2)")
     (192 "191.961479(4)" "40.78(19)"))
    (77
     (191 "190.960591(3)" "37.3(2)")
     (193 "192.962924(3)" "62.7(2)"))
    (78
     (190 "189.959930(7)" "0.014(1)")
     (192 "191.961035(4)" "0.782(7)")
     (194 "193.962664(3)" "32.967(99)")
     (195 "194.964774(3)" "33.832(10)")
     (196 "195.964935(3)" "25.242(41)")
     (198 "197.967876(4)" "7.163(55)"))
    (79
     (197 "196.966552(3)" "100"))
    (80
     (196 "195.965815(4)" "0.15(1)")
     (198 "197.966752(3)" "9.97(20)")
     (199 "198.968262(3)" "16.87(22)")
     (200 "199.968309(3)" "23.10(19)")
     (201 "200.970285(3)" "13.18(9)")
     (202 "201.970626(3)" "29.86(26)")
     (204 "203.973476(3)" "6.87(15)"))
    (81
     (203 "202.972329(3)" "29.524(14)")
     (205 "204.974412(3)" "70.476(14)"))
    (82
     (204 "203.973029(3)" "1.4(1)")
     (206 "205.974449(3)" "24.1(1)")
     (207 "206.975881(3)" "22.1(1)")
     (208 "207.976636(3)" "52.4(1)"))
    (83
     (209 "208.980383(3)" "100"))
    (84
     (209 "208.982416(3)")
     (210 "209.982857(3)"))
    (85
     (210 "209.987131(9)")
     (211 "210.987481(4)"))
    (86
     (211 "210.990585(8)")
     (220 "220.0113841(29)")
     (222 "222.0175705(27)"))
    (87
     (223 "223.0197307(29)"))
    (88
     (223 "223.018497(3)")
     (224 "224.0202020(29)")
     (226 "226.0254026(27)")
     (228 "228.0310641(27)"))
    (89
     (227 "227.0277470(29)"))
    (90
     (230 "230.0331266(22)")
     (232 "232.0380504(22)" "100"))
    (91
     (231 "231.0358789(28)" "100"))
    (92
     (233 "233.039628(3)")
     (234 "234.0409456(21)" "0.0055(2)")
     (235 "235.0439231(21)" "0.7200(51)")
     (236 "236.0455619(21)")
     (238 "238.0507826(21)" "99.2745(106)"))
    (93
     (237 "237.0481673(21)")
     (239 "239.0529314(23)"))
    (94
     (238 "238.0495534(21)")
     (239 "239.0521565(21)")
     (240 "240.0538075(21)")
     (241 "241.0568453(21)")
     (242 "242.0587368(21)")
     (244 "244.064198(5)"))
    (95
     (241 "241.0568229(21)")
     (243 "243.0613727(23)"))
    (96
     (243 "243.0613822(24)")
     (244 "244.0627463(21)")
     (245 "245.0654856(29)")
     (246 "246.0672176(24)")
     (247 "247.070347(5)")
     (248 "248.072342(5)"))
    (97
     (247 "247.070299(6)")
     (249 "249.074980(3)"))
    (98
     (249 "249.074847(3)")
     (250 "250.0764000(24)")
     (251 "251.079580(5)")
     (252 "252.081620(5)"))
    (99
     (252 "252.082970(50)"))
    (100
     (257 "257.095099(7)"))
    (101
     (256 "256.094050(60)")
     (258 "258.098425(5)"))
    (102
     (259 "259.10102(11)"))
    (103
     (262 "262.10969(32)"))
    (104
     (261 "261.10875(11)"))
    (105
     (262 "262.11415(20)"))
    (106
     (266 "266.12193(31)"))
    (107
     (264 "264.12473(30)"))
    (108
     (269 "269.13411(46)"))
    (109
     (268 "268.13882(34)"))
    (110
     (271 "271.14608(20)"))
    (111
     (272 "272.15348(36)"))
    (112
     (277))
    (114
     (289))
    (116
     (292)))
  "Alist mapping elements to their isotopes.
Each car is an atomic number and each cdr a list of isotope properties
\(nucleons, nuclear mass and abundance).")

;; Other version-dependent configuration

(defalias 'eperiodic-line-beginning-position
  (cond
   ((fboundp 'line-beginning-position) 'line-beginning-position)
   ((fboundp 'point-at-bol) 'point-at-bol)))

(defalias 'eperiodic-line-end-position
  (cond
   ((fboundp 'line-end-position) 'line-end-position)
   ((fboundp 'point-at-eol) 'point-at-eol)))

(eval-and-compile
  (cond
   ;; Emacs 21
   ((fboundp 'replace-regexp-in-string)
    (defalias 'eperiodic-replace-regexp-in-string 'replace-regexp-in-string))
   ;; Emacs 20
   ((and (require 'dired)
         (fboundp 'dired-replace-in-string))
    (defalias 'eperiodic-replace-regexp-in-string 'dired-replace-in-string))
   ;; Bail out
   (t
    (error "No replace in string function found"))))

;; Entry points

;;;###autoload
(defun eperiodic ()
  "Display the periodic table of the elements in its own buffer.
If in periodic already then go back."
  (interactive)
  (if (string-equal (buffer-name) "*EPeriodic*")
      (switch-to-buffer (other-buffer))
    (progn
      (cond
       ((buffer-live-p (get-buffer "*EPeriodic*"))
        (set-buffer "*EPeriodic*"))
       (t
        (set-buffer (get-buffer-create "*EPeriodic*"))
        (eperiodic-mode)
        (setq buffer-read-only t)
        (setq truncate-lines t)))
      ;; Workhorse function
      (eperiodic-display)
      (set-buffer-modified-p nil)
      (select-window (display-buffer (current-buffer)))
      (delete-other-windows))))

;; Functions

(defun eperiodic-insert-table ()
  "Insert periodic table into the current buffer.
Any previous buffer contents are deleted."
  (let ((display-width (max eperiodic-element-display-width 2))
        (indentation (max eperiodic-display-indentation 0))
        (inhibit-read-only t)
        (max-width 0)
        (order (cdr (assoc eperiodic-display-type eperiodic-display-lists)))
        (separation (max eperiodic-element-separation 0)))
    (erase-buffer)
    ;; Insert group numbers
    (insert "\n" (make-string (+ indentation 2) ?\ ))
    (let ((list (cadr (assoc eperiodic-display-type
                             eperiodic-display-block-orders)))
          end start)
      (dolist (elt list)
        (setq start (nth 1 (assoc (symbol-name elt) eperiodic-group-ranges))
              end (nth 2 (assoc (symbol-name elt) eperiodic-group-ranges)))
        (cl-loop for i from start to end
              do
              (if (equal elt 'f)
                  (insert (make-string display-width ?\ ))
                (insert (format (format "%%-%dd" display-width) i)))
              (add-text-properties (point)
                                   (- (point) display-width)
                                   '(face eperiodic-group-number-face))
              (insert (make-string separation ?\ ))))
      (insert "\n\n"))
    ;; Loop over display order
    (while order
      (insert (make-string indentation ?\ ))
      (let ((orbital-list (car order))
            face max-z min-z orbital period)
        ;; Period number
        (setq period (if (car orbital-list)
                         (substring (symbol-name (car orbital-list)) 0 1)))
        (if (and period
                 (not (string-equal period "0")))
            (progn
              (insert period " ")
              (add-text-properties (- (point) 1) (- (point) 2)
                                   '(face eperiodic-period-number-face)))
          (insert "  "))
        (while orbital-list
          (setq orbital (car orbital-list))
          (setq min-z (cadr (assoc orbital eperiodic-orbital-z-value-map)))
          (setq max-z (cddr (assoc orbital eperiodic-orbital-z-value-map)))
          ;; Print the range of Z for this orbital
          (cond
           (min-z
            (cl-loop for z from min-z to max-z by 1
                  do
                  (let ((help (if eperiodic-use-popup-help
                                  (eperiodic-get-help-string z)
                                nil))
                        (start (point)))
                    (insert (format (format "%%-%ds" (+ separation
                                                        display-width))
                                    (eperiodic-get-element-property z 'symbol)))
                    ;; Get face for element
                    (when (fboundp eperiodic-colour-element-function)
                      (setq face (funcall eperiodic-colour-element-function z)))
                    (add-text-properties start (- (point) separation)
                                         `(face ,face
                                                eperiodic-at-number ,z
                                                help-echo ,help)))))
           ;; Must be a 0x type orbital, i.e. padding
           (t
            (let ((string (make-string (+ separation display-width) ?\ )))
              (add-text-properties 0 display-width
                                   '(face eperiodic-padding-face)
                                   string)
              (cl-loop for z from 1 to
                    (cdr (assoc (substring (symbol-name orbital) 1 2)
                                eperiodic-orbital-degeneracies)) by 1
                    do
                    (insert string)))))
          (setq orbital-list (cdr orbital-list)))
        ;; Keep track of maximum width
        (when (> (current-column) max-width)
            (setq max-width (current-column)))
        (insert "\n"))
      (setq order (cdr order)))
    ;; Insert header
    (let* ((header "PERIODIC CHART OF THE ELEMENTS")
           (padding (/ (- max-width (length header)) 2)))
      (goto-char (point-min))
      (setq padding (make-string padding ?\ ))
      (add-text-properties 0 (length header) `(face eperiodic-header-face)
                           header)
      (if (boundp 'header-line-format)
          (progn
            (setq header-line-format (concat
                                      (propertize " " 'display
                                                  `(space :align-to ,(length padding)))
                                      header)))
        (insert padding header "\n")))
    ;; Align He above Ne if both are shown
    (let ((he-posn
           (text-property-any (point-min) (point-max) 'eperiodic-at-number 2))
          (ne-posn
           (text-property-any (point-min) (point-max) 'eperiodic-at-number 10)))
      (when (and ne-posn he-posn)
        ;; Convert positions to columns
        (goto-char ne-posn)
        (setq ne-posn (current-column))
        (goto-char he-posn)
        (let ((string (make-string (+ separation display-width) ?\ )))
          (add-text-properties 0 display-width
                               '(face eperiodic-padding-face)
                               string)
          (cl-loop for i from 1 to (/ (- ne-posn (current-column))
                                   (+ display-width separation))
                do
                (insert string)))))
    (goto-char (point-max))
    (eperiodic-insert-key))
  ;; Keep track of end of elements
  (setq eperiodic-element-end-marker (point-max-marker))
  ;; Move to point after first element
  (goto-char (text-property-any (point-min) (point-max)
                                'eperiodic-at-number
                                eperiodic-last-displayed-element)))

(defun eperiodic-update-element-info (&optional force)
  "Display data for the element with atomic number Z.
Try not to do unnecessary updates, but always update if FORCE is
non-null."
  (let ((z (eperiodic-element-at)))
    (when (or force
              (and z (not (equal z eperiodic-last-displayed-element))))
      (save-excursion
        (let ((inhibit-read-only t))
          (goto-char (marker-position eperiodic-element-end-marker))
          (delete-region (point) (point-max))
          (eperiodic-insert-element-info z)
          (eperiodic-insert-isotope-info z)
          (set-buffer-modified-p nil)))
      (setq eperiodic-last-displayed-element z)
      (run-hooks 'eperiodic-post-display-hook))))

(defun eperiodic-display ()
  "Display periodic table in the current buffer."
  (eperiodic-insert-table)
  (eperiodic-update-element-info t))

(defun eperiodic-display-preserve-point ()
  "Display periodic table in the current buffer; preserve point."
  (let ((posn (point)))
    (eperiodic-display)
    (goto-char posn)))

(defun eperiodic-insert-element-info (z)
  "Insert data for the element with atomic number Z.
The data (taken from `eperiodic-element-properties') are inserted into
the current buffer. Properties specified in
`eperiodic-ignored-properties' are ignored."
  ;; Header
  (insert "\n")
  (insert (format "%s Properties:"
                  (eperiodic-get-element-property z 'name)))
  ;; Propertize is not portable :-( ...)
  (put-text-property (eperiodic-line-beginning-position)
                     (eperiodic-line-end-position)
                     'face 'eperiodic-header-face)
  (insert "\n\n")
  (insert (format " %-25s %-25s\n"
                  "Atomic Number"
                  z))
  ;; Insert other properties
  (let ((properties (copy-alist eperiodic-printed-properties)))
    ;; Remove unwanted properties
    (dolist (elt eperiodic-ignored-properties)
      (setq properties (delete elt properties)))
    (dolist (property properties)
      (insert
       (format " %-25s %-25s %-s\n"
               (eperiodic-format-symbol property)
               (eperiodic-get-element-property z property)
               (eperiodic-get-property-unit property))))))

(defun eperiodic-insert-isotope-info (z)
  "Insert isotope data for the element with atomic number Z.
The data (taken from `eperiodic-isotope-data') are inserted into the
current buffer."
  ;; Header
  (insert "\n")
  (insert (format "%s Isotopes:"
                  (eperiodic-get-element-property z 'name)))
  ;; Propertize is not portable :-( ...)
  (put-text-property (eperiodic-line-beginning-position)
                     (eperiodic-line-end-position)
                     'face 'eperiodic-header-face)
  (insert "\n\n")
  (dolist (property eperiodic-isotope-properties)
    (insert
     (format " %-25s"
             (eperiodic-format-symbol property))))
  (insert "\n\n")
  ;; Data
  (let ((data (cdr (assoc z eperiodic-isotope-data))))
    ;; Loop over isotopes
    (while data
      (let ((isotope-data (car data)))
        (while isotope-data
          (insert
           (format " %-25s"
                   (car isotope-data)))
          (setq isotope-data (cdr isotope-data)))
        (insert "\n"))
      (setq data (cdr data)))))

(defun eperiodic-get-help-string (z)
  "Build help string for element with atomic number Z."
  (let ((name (eperiodic-get-element-property z 'name)))
    (format "%s: Z = %d" name z)))

(defun eperiodic-bury-buffer ()
  "Bury the *EPeriodic* buffer."
  (interactive)
  (when (eq major-mode 'eperiodic-mode)
    (if (fboundp 'quit-window)
        (quit-window)
      (bury-buffer))))

(defun eperiodic-kill-buffer ()
  "Kill this `eperiodic-mode' buffer."
  (interactive)
  (unless (equal major-mode 'eperiodic-mode)
    (error "Not in *EPeriodic* buffer"))
  (kill-buffer (current-buffer)))

(defvar eperiodic-completion-table
  (let ((table
         (mapcar (lambda (w)
                   (cons (cdr (assoc 'name (cdr w)))
                         (car w)))
                 eperiodic-element-properties)))
    ;; Add element symbols to list
    (setq table (append table
                        (mapcar (lambda (w)
                                  (cons (cdr (assoc 'symbol (cdr w)))
                                        (car w)))
                                eperiodic-element-properties)))
    ;; Add atomic numbers
    (setq table (append table
                        (mapcar (lambda (w)
                                  (cons (number-to-string (car w))
                                        (car w)))
                                eperiodic-element-properties)))
    table)
  "Completion table mapping element names to atomic numbers.
Atomic numbers, as strings, are also mapped. Used in
`eperiodic-find-element'")

(defun eperiodic-find-element ()
  "Find a named element in the *EPeriodic* buffer.
The element name, symbol, or atomic number can be used."
  (interactive)
  (unless (eq major-mode 'eperiodic-mode)
    (error "Not in an *EPeriodic* buffer"))
  (let ((completion-ignore-case t)
        element)
    (setq element (completing-read
                   "Choose element: " eperiodic-completion-table nil t))
    (when (> (length element) 0)
      (goto-char
       (text-property-any (point-min)
                          (point-max)
                          'eperiodic-at-number
                          (cdr (assoc (capitalize element)
                                      eperiodic-completion-table)))))))

(defun eperiodic-get-element-property (z prop)
  "For element with atomic number Z, get property PROP."
  (cond ((equal prop 'electronic-configuration)
         (let ((exception
                (cdr (assoc z eperiodic-aufbau-exceptions))))
           (if exception
               (concat exception " (non-Aufbau)")
             (cdr (assoc z eperiodic-elec-configs)))))
        (t
         (cdr (assoc prop (cdr (assoc z eperiodic-element-properties)))))))

(defun eperiodic-get-property-unit (prop)
  "Get the unit (if any) for property PROP."
  (or (cdr (assoc prop eperiodic-stored-properties))
      ""))

(defvar eperiodic-use-property-change
  (fboundp 'next-single-char-property-change)
  "If non-nil, use single character property change functions.")

;; Adapted from widget-move

(defun eperiodic-next-element (arg)
  "Move point to the ARG next element.
ARG may be negative to move backward."
  (interactive "p")
  (let ((old (eperiodic-element-at)))
    ;; Forward.
    (while (> arg 0)
      (cond ((eobp)
	     (goto-char (point-min)))
	    (eperiodic-use-property-change
	     (goto-char (next-single-char-property-change (point) 'eperiodic-at-number)))
            (t
             (forward-char 1)))
      (let ((new (eperiodic-element-at)))
	(when new
	  (unless (eq new old)
	    (setq arg (1- arg))
	    (setq old new)))))
    ;; Backward.
    (while (< arg 0)
      (cond ((bobp)
	     (goto-char (point-max)))
	    (eperiodic-use-property-change
	     (goto-char (previous-single-char-property-change (point) 'eperiodic-at-number)))
            (t
             (backward-char 1)))
      (let ((new (eperiodic-element-at)))
	(when new
	  (unless (eq new old)
	    (setq arg (1+ arg))))))
    ;; Go to beginning of field.
    (let ((new (eperiodic-element-at)))
      (while (eq (eperiodic-element-at) new)
	(backward-char)))
    (forward-char)))

(defun eperiodic-previous-element (arg)
  "Move point to the ARG previous element.
ARG may be negative to move forward."
  (interactive "p")
  (eperiodic-next-element (- arg)))

(defun eperiodic-element-at (&optional posn)
  "Get atomic number text property at point, or POSN if specified."
  (get-text-property (or posn (point)) 'eperiodic-at-number))

(defun eperiodic-format-symbol (symbol)
  "Format `symbol-name' of SYMBOL.
Remove hyphens and capitalize using relevant functions if available."
  (let (name)
    (setq name (symbol-name symbol))
    (setq name (eperiodic-replace-regexp-in-string "-" " " name))
    (capitalize name)))

;; Dictionary support

(defun eperiodic-show-dictionary-entry ()
  "Show dictionary entry for element at point.
Uses `eperiodic-dict-program' and `eperiodic-dict-dictionary'."
  (interactive)
  (let ((element (eperiodic-get-element-property
                  (eperiodic-element-at) 'name)))
    (cond
     ((not element)
      (message "No element at point"))
     ((or (not (stringp eperiodic-dict-program))
          (not (file-executable-p eperiodic-dict-program)))
      (message "Cannot run eperiodic-dict-program"))
     ((not (stringp eperiodic-dict-dictionary))
      (message "Cannot run eperiodic-dict-program"))
     (t
      (with-output-to-temp-buffer "*Eperiodic dictionary entry*"
        (call-process eperiodic-dict-program nil "*Eperiodic dictionary entry*" nil
                      eperiodic-dict-dictionary-arg eperiodic-dict-dictionary
                      eperiodic-dict-nopager-arg element))))))

;; Internet support

(defun eperiodic-web-lookup ()
  "Look up extra details on The Web about element at point."
  (interactive)
  (let ((z (eperiodic-element-at))
        (url (or eperiodic-web-lookup-location ""))
        string token)
    (cond
     ((not z)
      (error "No element at point"))
     ((string-match "%s" url)
      (setq token "%s"
            string (eperiodic-get-element-property z 'symbol)))
     ((string-match "%n" url)
      (setq token "%n"
            string (eperiodic-get-element-property z 'name)))
     ((or (not (stringp eperiodic-web-lookup-location))
          (not token))
      (error "Variable eperiodic-web-lookup-location not set correctly"))
     ((not (fboundp 'browse-url))
      (error "Cannot run browse-url")))
    ;; Construct URL
    (setq url
          (eperiodic-replace-regexp-in-string token string url))
    (if url
        (browse-url url)
      (message "Could not construct URL to look up element"))))

;; Miscellaneous

(defun eperiodic-show-element-properties (&optional arg)
  "Show information for a chosen property of all elements.
With a prefix ARG, sort the entries numerically (where possible).
If ARG is the result of `negative-argument', the sorting is
reversed."
  (interactive "P")
  (let ((completion-ignore-case t)
        (list (mapcar
               (lambda (elt)
                 (cons (eperiodic-format-symbol elt) elt))
               eperiodic-printed-properties))
        (default (intern
                  (eperiodic-replace-regexp-in-string
                   "eperiodic-colour-element-by-" ""
                   (symbol-name eperiodic-colour-element-function))))
        name prop string value unit z)
    (setq prop (cdr (assoc (completing-read
                            "Choose property: " list nil t
                            (when (member default eperiodic-printed-properties)
                              (eperiodic-format-symbol default)))
                           list)))
    (when prop
      (setq list nil)
      (setq list
            (mapcar (lambda (elt)
                      (setq z (car elt)
                            name (eperiodic-get-element-property z 'name)
                            value (eperiodic-get-element-property z prop)
                            string (format "%-15s [Z = %3d] -> %s" name z value))
                      (if arg
                          (cons
                           (if (string-match "^n/a" value)
                               (if (eq arg '-)
                                   most-negative-fixnum
                                 most-positive-fixnum)
                             (string-to-number
                              (eperiodic-extract-number-from-string value)))
                           string)
                        string))
                    eperiodic-element-properties))
      ;; Sort if required
      (cond
       ((eq arg '-)
        (setq list (sort list (lambda (a b)
                                (>= (car a) (car b))))))
       (arg
        (setq list (sort list (lambda (a b)
                                      (<= (car a) (car b)))))))
      (with-output-to-temp-buffer "*Eperiodic element properties*"
        (princ (format "%s" (eperiodic-format-symbol prop)))
        (if (setq unit (cdr (assoc prop eperiodic-stored-properties)))
            (princ (format " (%s):\n\n" unit))
          (princ ":\n\n"))
        (princ (mapconcat (if arg #'cdr #'identity) list "\n"))
        (princ "\n\n")))))

(defun eperiodic-jump-to-properties ()
  "Move point to start of properties."
  (interactive)
  (goto-char eperiodic-element-end-marker)
  (forward-line 1))

;; Colouring functions

(defun eperiodic-colour-element-by-group (arg)
  "Colour elements by their group.
Return face for element with atomic number ARG, unless ARG equals the
symbol 'key', in which case insert key elements."
  (cond
   ((eq arg 'key)
    (insert " Electronic Configuration\n    ")
    (eperiodic-insert-key-elements '(eperiodic-s-block-face
                                     eperiodic-p-block-face
                                     eperiodic-d-block-face
                                     eperiodic-f-block-face)))
   (t
    (cdr (assoc (substring
                            (symbol-name
                             (eperiodic-get-orbital-from-z arg)) 1 2)
                           eperiodic-orbital-faces)))))

(defun eperiodic-colour-element-by-state (arg)
  "Colour elements by their state.
Return face for element with atomic number ARG, unless ARG equals the
symbol 'key', in which case insert key elements."
  (cond
   ((eq arg 'key)
    (insert (format " State [%6.2f K]\n    " eperiodic-current-temperature))
    (eperiodic-insert-key-elements '(eperiodic-solid-face
                                     eperiodic-liquid-face
                                     eperiodic-gas-face
                                     eperiodic-unknown-face)))
   (t
    (let ((boiling-point (string-to-number (eperiodic-get-element-property
                                            arg 'boiling-point)))
          (melting-point (string-to-number (eperiodic-get-element-property
                                            arg 'melting-point))))
      (cond
       ((or (= boiling-point 0)
            (= melting-point 0))
        'eperiodic-unknown-face)
       ((< eperiodic-current-temperature melting-point)
        'eperiodic-solid-face)
       ((< eperiodic-current-temperature boiling-point)
        'eperiodic-liquid-face)
       (t
        'eperiodic-gas-face))))))

(defun eperiodic-colour-element-by-discovery-date (arg)
  "Colour elements by their discovery date.
Return face for element with atomic number ARG, unless ARG equals the
symbol 'key', in which case insert key elements."
  (cond
   ((eq arg 'key)
    (insert (format " Discovery Relative to %4d\n    " eperiodic-current-year))
    (eperiodic-insert-key-elements '(eperiodic-discovered-before-face
                                     eperiodic-discovered-during-face
                                     eperiodic-discovered-after-face
                                     eperiodic-known-to-ancients-face
                                     eperiodic-unknown-face)))
   (t
    (let ((year (eperiodic-get-element-property arg 'discovery-date)))
      (cond
       ((string-match "\\(^[0-9]+\\) " year)
        (setq year (string-to-number (match-string 1 year)))
        (cond
         ((= year eperiodic-current-year)
          'eperiodic-discovered-during-face)
         ((< year eperiodic-current-year)
          'eperiodic-discovered-before-face)
         (t
          'eperiodic-discovered-after-face)))
       ((string-match "Known to the ancients"
                      (eperiodic-get-element-property arg 'discovered-by))
        'eperiodic-known-to-ancients-face)
       (t
        'eperiodic-unknown-face))))))

(defun eperiodic-colour-element-by-oxidation-states (arg)
  "Colour elements by their number of oxidation states.
Return face for element with atomic number ARG, unless ARG equals the
symbol 'key', in which case insert key elements."
  (cond
   ((eq arg 'key)
    (insert " Number of Oxidation States\n    ")
    (eperiodic-insert-key-elements
     (nconc (mapcar (lambda (n)
                      (intern (format "eperiodic-%d-face" n)))
                    '(1 2 3 4 5 6 7))
            '(eperiodic-unknown-face))))
   (t
    (let ((states (eperiodic-get-element-property arg 'oxidation-states)))
      (cond
       ((string-equal states "n/a")
        'eperiodic-unknown-face)
       (t
        (intern (format "eperiodic-%d-face"
                        (length (split-string states ", *"))))))))))

(defun eperiodic-colour-element-generic (arg)
  "Colour elements by their number of oxidation states.
Return face for element with atomic number ARG, unless ARG equals the
symbol 'key', in which case insert key elements."
  (let ((symbol (symbol-name eperiodic-colour-element-function))
        current string unit value)
    (or eperiodic-current-property-values
        (eperiodic-set-current-property-values))
    (setq symbol
          (eperiodic-replace-regexp-in-string
           "eperiodic-colour-element-by-" "" symbol)
          current (cdr (assoc (intern symbol)
                              eperiodic-current-property-values)))
    (cond
     ((eq arg 'key)
      (setq string
            (eperiodic-replace-regexp-in-string "-" " " symbol)
            unit (eperiodic-get-property-unit (intern symbol)))
      (insert (format " %s [%.2f%s]\n    "
                      (capitalize string) current
                      (if (string-equal unit "")
                          ""
                        (concat " " unit))))
      (eperiodic-insert-key-elements '(eperiodic-less-than-face
                                       eperiodic-equal-to-face
                                       eperiodic-greater-than-face
                                       eperiodic-unknown-face)))
     (t
      (setq value (eperiodic-get-element-property arg
                                                  (intern symbol)))
      ;; Cope with mass values written as [261] or (600) or ~340
      (setq value (eperiodic-extract-number-from-string value))
      (if (string-equal value "n/a")
          'eperiodic-unknown-face
        (setq value (string-to-number value))
        (cond
         ((< (abs (- value current)) eperiodic-precision)
          'eperiodic-equal-to-face)
         ((< value current)
          'eperiodic-less-than-face)
         ((> value current)
          'eperiodic-greater-than-face)))))))

(defalias 'eperiodic-colour-element-by-atomic-mass 'eperiodic-colour-element-generic)
(defalias 'eperiodic-colour-element-by-density 'eperiodic-colour-element-generic)
(defalias 'eperiodic-colour-element-by-atomic-radius 'eperiodic-colour-element-generic)
(defalias 'eperiodic-colour-element-by-covalent-radius 'eperiodic-colour-element-generic)
(defalias 'eperiodic-colour-element-by-ionic-radius 'eperiodic-colour-element-generic)
(defalias 'eperiodic-colour-element-by-atomic-volume 'eperiodic-colour-element-generic)
(defalias 'eperiodic-colour-element-by-specific-heat 'eperiodic-colour-element-generic)
(defalias 'eperiodic-colour-element-by-fusion-heat 'eperiodic-colour-element-generic)
(defalias 'eperiodic-colour-element-by-evaporation-heat 'eperiodic-colour-element-generic)
(defalias 'eperiodic-colour-element-by-thermal-conductivity 'eperiodic-colour-element-generic)
(defalias 'eperiodic-colour-element-by-debye-temperature 'eperiodic-colour-element-generic)
(defalias 'eperiodic-colour-element-by-pauling-negativity-number 'eperiodic-colour-element-generic)
(defalias 'eperiodic-colour-element-by-first-ionization-energy 'eperiodic-colour-element-generic)
(defalias 'eperiodic-colour-element-by-lattice-structure 'eperiodic-colour-element-generic)
(defalias 'eperiodic-colour-element-by-lattice-constant 'eperiodic-colour-element-generic)
(defalias 'eperiodic-colour-element-by-lattice-c/a-ratio 'eperiodic-colour-element-generic)

(defun eperiodic-insert-key-elements (faces)
  "Insert string for each of FACES."
  (let ((separator " ") posn)
    (mapcar (lambda (face)
              (setq posn (+ (point) (length separator)))
              (when (string-match
                     "Eperiodic face for \\(.*\\) elements."
                     (face-doc-string face))
                (insert separator (match-string 1 (face-doc-string face))))
              (add-text-properties posn
                                   (point)
                                   `(face ,face)))
            faces)))

(defun eperiodic-get-orbital-from-z (z)
  "Get orbital for element with atomic number Z."
  (let (min max)
    (catch 'orbital
      (mapcar (lambda (orb)
                (setq min (cadr orb)
                      max (cddr orb)
                      orb (car orb))
                (when (and (>= z min) (<= z max))
                  (throw 'orbital orb)))
            eperiodic-orbital-z-value-map))))

(defun eperiodic-insert-key ()
  "Insert key for the current *Eperiodic* buffer."
  (when (fboundp eperiodic-colour-element-function)
    (insert "\nKey:")
    (add-text-properties (eperiodic-line-beginning-position)
                         (point)
                         `(face eperiodic-header-face))
    (funcall eperiodic-colour-element-function 'key)
    (insert "\n")))

(defun eperiodic-increase-property-value (arg &optional factor)
  "Increase some property by ARG multiplied by FACTOR.
The properties are associated with entries in
`eperiodic-colour-element-functions'."
  (interactive "p")
  (setq factor (or factor 1.0))
  (cond
   ((eq eperiodic-colour-element-function
        'eperiodic-colour-element-by-state)
    (setq eperiodic-current-temperature
          (eperiodic-property-increment eperiodic-current-temperature
                                        (* factor arg) 0.01 0)))
   ((eq eperiodic-colour-element-function
        'eperiodic-colour-element-by-discovery-date)
    (setq eperiodic-current-year
          (eperiodic-property-increment eperiodic-current-year
                                        (* factor arg) 1.0 0)))
   (t
    ;; Generic colouring function
    (let ((symbol
           (intern (eperiodic-replace-regexp-in-string
                    "eperiodic-colour-element-by-" ""
                    (symbol-name eperiodic-colour-element-function))))
          current)
      (setq current (cdr (assoc symbol eperiodic-current-property-values)))
      (if current
          (setcdr (assoc symbol eperiodic-current-property-values)
                  (eperiodic-property-increment current
                                                (* factor arg) 0.01 0))
        (message "No property value for colouring by %s"
                 (eperiodic-format-symbol symbol))))))
  (eperiodic-display-preserve-point))

(defun eperiodic-decrease-property-value (arg)
  "Decrease some property by ARG.
The properties are associated with entries in
`eperiodic-colour-element-functions'. If no argument given,
`eperiodic-property-increment' is used."
  (interactive "p")
  (eperiodic-increase-property-value arg -1))

(defun eperiodic-property-increment (current factor minimum-increment minimum-value)
  "Increment property value CURRENT.
Multiply by FACTOR (should be +/-1); constraints are the minimum
increment (MINIMUM-INCREMENT) and the minimum
value (MINIMUM-VALUE)"
  ;; Clean the current value
  (setq current (/ (floor (+ (/ current eperiodic-precision ) 0.5))
                   (/ 1.0 eperiodic-precision)))
  (let (increment)
    ;; Determine heuristic increment
    (setq increment (expt 10.0 (1- (floor (log (max minimum-increment current) 10.0)))))
    (when (and (< factor 0) (= current increment))
      (setq increment (/ increment 10.0)))
    (setq increment (max increment minimum-increment))
    ;; Return the new value
    (max (+ current (* factor increment)) minimum-value)))

(defun eperiodic-set-property-value (num)
  "Set property value for current colouring scheme."
  (interactive "nSet current property value to: ")
  (cond
   ((eq eperiodic-colour-element-function
        'eperiodic-colour-element-by-state)
    (setq eperiodic-current-temperature (max num 0)))
   ((eq eperiodic-colour-element-function
        'eperiodic-colour-element-by-discovery-date)
    (setq eperiodic-current-year (floor (max num 0))))
   (t
    ;; Generic colouring function
    (let ((symbol
           (intern (eperiodic-replace-regexp-in-string
                    "eperiodic-colour-element-by-" ""
                    (symbol-name eperiodic-colour-element-function))))
          current)
      (setq current (cdr (assoc symbol eperiodic-current-property-values)))
      (if current
          (setcdr (assoc symbol eperiodic-current-property-values)
                  (max num 0))
        (message "No property value for colouring by %s"
                 (eperiodic-format-symbol symbol))))))
  (eperiodic-display-preserve-point))

(defun eperiodic-reset-property-values ()
  "Reset all current property values."
  (interactive)
  (eperiodic-set-current-property-values)
  (setq eperiodic-current-temperature (default-value 'eperiodic-current-temperature)
        eperiodic-current-year (default-value 'eperiodic-current-year))
  (eperiodic-display-preserve-point))

(defun eperiodic-next-colour-scheme ()
  "Cycle forward through elements of `eperiodic-colour-element-functions'."
  (interactive)
  (setq eperiodic-colour-element-function
        (or (nth 1 (member eperiodic-colour-element-function
                           eperiodic-colour-element-functions))
            (car eperiodic-colour-element-functions)))
  (eperiodic-display))

(defun eperiodic-previous-colour-scheme ()
  "Cycle backward through elements of `eperiodic-colour-element-functions'."
  (interactive)
  (setq eperiodic-colour-element-function
        (or (nth 1 (member eperiodic-colour-element-function
                           (reverse eperiodic-colour-element-functions)))
            (car (reverse eperiodic-colour-element-functions))))
  (eperiodic-display))

(defun eperiodic-choose-colour-scheme ()
  "Choose colour function for the periodic table.
See `eperiodic-colour-element-functions'."
  (interactive)
  (let ((completion-ignore-case t)
        choice string table)
    (setq table
          (mapcar (lambda (elt)
                    (setq string
                          (eperiodic-replace-regexp-in-string
                           "eperiodic-colour-element-by-" "" (symbol-name elt)))
                    (setq string
                          (eperiodic-format-symbol (intern string)))
                    (cons string elt))
                 eperiodic-colour-element-functions))
    (setq choice
          (cdr (assoc
                (completing-read "Colour elements according to: "
                                 table nil t nil)
                table)))
    (when (and choice
               (not (equal choice eperiodic-colour-element-function)))
      (setq eperiodic-colour-element-function choice)
      (eperiodic-display))))

(defun eperiodic-choose-display-type ()
  "Choose display type for the periodic table.
See `eperiodic-display-lists'."
  (interactive)
  (let ((completion-ignore-case t)
        (table '(("Separate lanthanides/actinides" . conventional)
                 ("By atomic number" . ordered)))
        choice)
    (setq choice
          (cdr (assoc
                (completing-read "Choose display type: " table nil t nil)
                table)))
    (when (and choice
               (not (equal choice eperiodic-display-type)))
      (setq eperiodic-display-type choice)
      (eperiodic-display))))

(defun eperiodic-set-current-property-values ()
  "Set `eperiodic-current-property-values'.
Starting values are the median values calculated for each
property (though for even length lists, use the lower value). See
also `eperiodic-colour-element-functions'."
  (setq eperiodic-current-property-values
        (let (symbol list value)
          (mapcar (lambda (elt)
                    (setq symbol (intern
                                  (eperiodic-replace-regexp-in-string
                                   "eperiodic-colour-element-by-" ""
                                   (symbol-name elt))))
                    (setq list nil)
                    (cl-loop for z from 1 to 118
                          do
                          (setq value
                                (eperiodic-extract-number-from-string
                                 (eperiodic-get-element-property z symbol)))
                          (when (not (string-match "n/a" value))
                            (setq list (nconc (list (string-to-number value))
                                              list))))
                    (setq value (nth (/ (1- (length list)) 2) (sort list #'<)))
                    ;; Round
                    (setq value (* (floor (/ value eperiodic-precision))
                                   eperiodic-precision))
                    (cons symbol value))
                  eperiodic-colour-element-generic-functions))))

(defun eperiodic-extract-number-from-string (string)
  "Extract a number from string STRING.
Remove various extraneous characters and return a string that
will be meaningful to `string-to-number'."
  (eperiodic-replace-regexp-in-string "[][()~]" "" string))

;; Mode settings

(defvar eperiodic-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "1")   'delete-other-windows)
    (define-key map (kbd "c")   'eperiodic-choose-colour-scheme)
    (define-key map (kbd "d")   'eperiodic-show-dictionary-entry)
    (define-key map (kbd "f")   'eperiodic-find-element)
    (define-key map (kbd "j")   'eperiodic-jump-to-properties)
    (define-key map (kbd "n")   'next-line)
    (define-key map (kbd "p")   'previous-line)
    (define-key map (kbd "q")   'eperiodic-bury-buffer)
    (define-key map (kbd "Q")   'eperiodic-kill-buffer)
    (define-key map (kbd "s")   'eperiodic-show-element-properties)
    (define-key map (kbd "t")   'eperiodic-choose-display-type)
    (define-key map (kbd "w")   'eperiodic-web-lookup)
    (define-key map (kbd "+")   'eperiodic-increase-property-value)
    (define-key map (kbd "-")   'eperiodic-decrease-property-value)
    (define-key map (kbd "=")   'eperiodic-set-property-value)
    (define-key map (kbd ">")   'eperiodic-next-colour-scheme)
    (define-key map (kbd "<")   'eperiodic-previous-colour-scheme)
    (define-key map (kbd "?")   'describe-mode)
    (define-key map (kbd "TAB")   'eperiodic-next-element)
    (define-key map (kbd "M-TAB") 'eperiodic-previous-element)
    (define-key map (kbd "M-=")   'eperiodic-reset-property-values)
    (define-key map [(shift tab)]         'eperiodic-previous-element)
    (define-key map [(shift iso-lefttab)] 'eperiodic-previous-element)
    map)
  "Keymap for eperiodic mode.")

;; Menus

(defvar eperiodic-menu nil
  "Menu to use for `eperiodic-mode'.")

(when (fboundp 'easy-menu-define)
  (easy-menu-define eperiodic-menu eperiodic-mode-map "Eperiodic Menu"
    '("Eperiodic"
      ["Next Element"             eperiodic-next-element t]
      ["Previous Element"         eperiodic-previous-element t]
      ["Find Element"             eperiodic-find-element t]
      "---"
      ["Show Element Properties"  eperiodic-show-element-properties t]
      ["Show Dictionary Entry"    eperiodic-show-dictionary-entry t]
      ["Web Lookup"               eperiodic-web-lookup t]
      "---"
      ["Choose Colour Scheme"     eperiodic-choose-colour-scheme t]
      ["Choose Display Type"      eperiodic-choose-display-type t]
      "---"
      ["Next Colour Scheme"       eperiodic-next-colour-scheme t]
      ["Previous Colour Scheme"   eperiodic-previous-colour-scheme t]
      ["Increase Property Value"  eperiodic-increase-property-value t]
      ["Decrease Property Value"  eperiodic-decrease-property-value t]
      "---"
      ["Quit"                     eperiodic-bury-buffer t]
      ["Kill Buffer"              eperiodic-kill-buffer t])))

(defun eperiodic-mode ()
  "Major mode for controlling the *EPeriodic* buffer.

This buffer contains a representation of the periodic table of the
elements. Elemental and isotopic data is displayed for the element at
the cursor position.

\\{eperiodic-mode-map}"
  (kill-all-local-variables)
  (use-local-map eperiodic-mode-map)
  (setq major-mode 'eperiodic-mode)
  (setq mode-name "EPeriodic")
  (setq buffer-undo-list t)
  (when (fboundp 'make-local-hook)
    (make-local-hook 'post-command-hook))
  (add-hook 'post-command-hook 'eperiodic-update-element-info t t)
  (run-hooks 'eperiodic-mode-hook))

(provide 'eperiodic)

;;; eperiodic.el ends here
