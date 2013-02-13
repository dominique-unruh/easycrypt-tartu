(require 'proof)
(require 'easycrypt-syntax)

(defpgdefault  menu-entries
  '(
    ["Use Three Panes" proof-three-window-toggle
      :style toggle
      :active (not proof-multiple-frames-enable)
      :selected proof-three-window-enable
      :help "Use three panes"]
    ""
    ["Index Menu" proof-imenu-toggle
      :active (stringp (locate-library "imenu"))
      :style toggle
      :selected proof-imenu-enable
      :help "Generate an index menu of definitions, display which function in modeline"]

    ["Hide/Show" hs-minor-mode
      :active (stringp (locate-library "hideshow"))
      :style toggle
      :selected (and (boundp 'hs-minor-mode) hs-minor-mode)
      :help "Hide/Show mode for folding"]

    ["Speedbar" speedbar
      :active (stringp (locate-library "speedbar"))
      :style toggle
      :selected (and (boundp 'speedbar-frame) speedbar-frame)
      :help "Speedbar navigation window"]
))



(provide 'easycrypt-abbrev)