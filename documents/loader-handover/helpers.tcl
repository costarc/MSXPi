proc scr {} { string trimright [join [lmap l [split [get_screen] "\n"] {string trimright $l}] "\n"] }
proc sendkeys {s} { type_via_keybuf $s; return ok }
