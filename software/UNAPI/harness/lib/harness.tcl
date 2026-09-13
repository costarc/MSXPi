# MSXPi Interface
# Version 1.6
# ------------------------------------------------------------------------------
# MIT License
#
# Copyright (c) 2015-2026 Ronivon Costa
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
# ------------------------------------------------------------------------------

# =============================================================================
# MSXPi UNAPI test harness - openMSX side
# =============================================================================
# Sourced by every test script.  Provides screen scraping, waiting, typing and
# assertions, and writes a machine-readable result file that run.sh parses.
#
# Screen text is read straight out of VRAM rather than via openMSX's optional
# save_msx_screen script: the debuggable "VRAM" and "VDP regs" are always
# present, need no auto-loading, and work identically in every openMSX build.
#
# All waiting is done on EMULATED time (`after time`), never wall-clock, so a
# test behaves the same on a fast and a slow host and cannot flake under load.
# =============================================================================

namespace eval harness {
    variable results   {}      ;# list of {name status detail}
    variable outfile   "harness_result.txt"
    variable failed    0
    variable testname  "unnamed"
}

# --- Configuration ----------------------------------------------------------

# The result file location comes from run.sh via MSXPI_HARNESS_OUT (an absolute
# path - openMSX's working directory is not the harness directory, so a relative
# name would land somewhere unhelpful).  Tests just call init with their name.
proc harness::init {name {out ""}} {
    variable testname
    variable outfile
    set testname $name
    if {$out ne ""} {
        set outfile $out
    } elseif {[info exists ::env(MSXPI_HARNESS_OUT)]} {
        set outfile $::env(MSXPI_HARNESS_OUT)
    }
}

# --- Screen scraping --------------------------------------------------------

# Returns the visible text screen as a list of lines.
# Handles both SCREEN 0 width 40 and width 80; the name table base comes from
# VDP R2 rather than being assumed, so a program that moves it still works.
# Decode the screen geometry from the VDP mode bits rather than guessing.
# The mode is spread across two registers:
#   M1 = R1 bit 4   M2 = R1 bit 3   M3 = R0 bit 1   M4 = R0 bit 2   M5 = R0 bit 3
#     M1 only            -> TEXT1    (SCREEN 0, 40 columns)
#     M1 + M4            -> TEXT2    (SCREEN 0 width 80, MSX2)
#     all clear          -> GRAPHIC1 (SCREEN 1, 32 columns)
# Returns {width rows nametable_base}.  Anything that is not a text-ish mode is
# reported as 32 columns, which at least keeps the reader from smearing.
proc harness::screen_geometry {} {
    set r0 [debug read "VDP regs" 0]
    set r1 [debug read "VDP regs" 1]
    set r2 [debug read "VDP regs" 2]

    set m1 [expr {($r1 & 0x10) != 0}]
    set m4 [expr {($r0 & 0x04) != 0}]

    if {$m1 && $m4} {
        # TEXT2 keeps the bottom two bits of R2 for the 80-column table.
        return [list 80 24 [expr {($r2 & 0x7c) * 0x400}]]
    } elseif {$m1} {
        return [list 40 24 [expr {($r2 & 0x7f) * 0x400}]]
    } else {
        return [list 32 24 [expr {($r2 & 0x7f) * 0x400}]]
    }
}

proc harness::screen_lines {} {
    lassign [harness::screen_geometry] w rows base
    set data [debug read_block "VRAM" $base [expr {$w * $rows}]]

    set out {}
    for {set y 0} {$y < $rows} {incr y} {
        set line ""
        for {set x 0} {$x < $w} {incr x} {
            set ch [string index $data [expr {$y * $w + $x}]]
            set c  [scan $ch %c]
            # MSX text VRAM holds raw character codes; anything outside
            # printable ASCII (graphics chars, padding) becomes a space so
            # that pattern matching stays predictable.
            if {$ch eq "" || $c eq "" || $c < 32 || $c > 126} { set c 32 }
            append line [format %c $c]
        }
        lappend out [string trimright $line]
    }
    return $out
}

# Whole screen as one string, lines joined with newlines.
proc harness::screen_text {} {
    return [join [harness::screen_lines] "\n"]
}

# --- Waiting ----------------------------------------------------------------

# Run $body once $pattern (a glob pattern) appears on screen, or run $onfail
# after $timeout emulated seconds.  Polls every 0.25 emulated seconds.
proc harness::wait_for {pattern timeout body {onfail {}}} {
    harness::_wait_tick $pattern $timeout 0.25 $body $onfail
}

proc harness::_wait_tick {pattern remaining step body onfail} {
    if {[string match "*$pattern*" [harness::screen_text]]} {
        uplevel #0 $body
        return
    }
    if {$remaining <= 0} {
        if {$onfail ne ""} {
            uplevel #0 $onfail
        } else {
            harness::fail "wait_for" "timed out waiting for '$pattern'"
            harness::done
        }
        return
    }
    after time $step [list harness::_wait_tick $pattern \
                          [expr {$remaining - $step}] $step $body $onfail]
}

# Plain delay in emulated seconds.
proc harness::wait {seconds body} {
    after time $seconds $body
}

# --- Input ------------------------------------------------------------------

# Type a line and press RETURN.  openMSX's `type` already paces the keystrokes
# through the key matrix, so no extra delay is needed between characters.
proc harness::type_line {text} {
    type "$text\r"
}

# Wait for the MSX-DOS prompt, then run $body.  With HW=msxpi the machine
# reaches "A:" at about 16 emulated seconds; the default timeout leaves plenty
# of margin without making a genuine hang take forever to report.
proc harness::at_dos_prompt {body {timeout 40}} {
    harness::wait_for "A:" $timeout $body
}

# Nextor boots through AUTOEXEC.BAT into MultiMente, a full-screen file
# manager, exactly as the real machine does.  ESC then RETURN leaves it for the
# DOS prompt.  The wait before it is a fixed settle on purpose: MM draws in a
# graphics mode, so there is no text on screen to wait for.
proc harness::at_nextor_prompt {body {boot 28} {timeout 30}} {
    # Nextor boots through AUTOEXEC.BAT into MultiMente, a full-screen file
    # manager - exactly what the real machine does.  ESC then RETURN leaves it
    # for the DOS prompt.  The wait before it is a fixed settle on purpose:
    # MM draws in a graphics mode, so there is no text on screen to wait for.
    #
    # Each step is deferred with [list ...] rather than a braced body: the
    # script an "after" runs is evaluated at global level, where this proc's
    # locals do not exist, so a braced body referring to $body silently fails.
    after time $boot [list harness::_mm_escape $timeout $body]
}

proc harness::_mm_escape {timeout body} {
    type [format %c 27]
    after time 2 [list harness::_mm_enter $timeout $body]
}

proc harness::_mm_enter {timeout body} {
    type [format %c 13]
    harness::wait_for "A:" $timeout $body
}

# Type a command at the DOS prompt, give it $settle emulated seconds to produce
# output, then run $body.
#
# PREFER run_until.  A fixed settle is only safe when you know how long the
# command takes, and that varies with how fast the server answers: the MSX
# spends emulated time waiting on the link, so a slower host makes a command
# take longer in EMULATED seconds too, not just wall-clock.  That is exactly
# how the WSL runs first failed - the next command got typed while the previous
# one was still running, and COMMAND.COM discarded it.
proc harness::run_command {cmd settle body} {
    harness::type_line $cmd
    after time $settle $body
}

# Type a command and wait until $pattern appears on screen before running $body.
#
# CAREFUL: $pattern must be text that cannot already be on screen, and that only
# appears once the command has FINISHED.  Both mistakes are easy to make and
# both produce the same symptom - the next command is typed while DOS is not
# reading the keyboard, COMMAND.COM discards it, and the test times out waiting
# for output that was never going to appear.  Prefer run_cmd.
proc harness::run_until {cmd pattern timeout body} {
    harness::type_line $cmd
    harness::wait_for $pattern $timeout $body
}

# True when the last non-empty line is a bare "A:" - i.e. DOS has finished
# whatever it was doing and is sitting at the prompt.  While a command is
# echoing or running, that line is "A:SOMETHING" or program output instead.
proc harness::at_idle_prompt {} {
    set lines [harness::screen_lines]
    for {set i [expr {[llength $lines] - 1}]} {$i >= 0} {incr i -1} {
        set l [string trim [lindex $lines $i]]
        if {$l eq ""} { continue }
        # MSX-DOS 1 with COMMAND.COM shows "A:".  Nextor / MSX-DOS 2 with
        # COMMAND2 and "set prompt on" shows a drive, a colon, a backslash and
        # ">".  Accept either, on any drive letter, so a test running from B:
        # is not silently reported as stuck.  The backslash is built with
        # format rather than written literally: it has to survive this file
        # being edited by tools that mangle escapes.
        set bs [format %c 92]
        set d [string index $l 0]
        return [expr {$l eq "${d}:" || $l eq "${d}:${bs}>"}]
    }
    return 0
}

# Type a command and run $body once DOS is back at an idle prompt.
#
# This is the one tests should use.  It does not care how long the command takes
# or what it prints, which matters because the MSX spends EMULATED time waiting
# on the link: a slower host makes a command take longer in emulated seconds
# too, so any fixed delay that works on one machine will race on another.
proc harness::run_cmd {cmd timeout body} {
    harness::type_line $cmd
    # Let the echo land first, so the prompt is genuinely non-idle before the
    # poll starts; otherwise this returns immediately on the prompt the command
    # was just typed at.
    after time 2 [list harness::_wait_idle $timeout 0.25 $body]
}

proc harness::_wait_idle {remaining step body} {
    if {[harness::at_idle_prompt]} {
        uplevel #0 $body
        return
    }
    if {$remaining <= 0} {
        harness::fail "run_cmd" "command did not return to an idle prompt"
        harness::done
        return
    }
    after time $step [list harness::_wait_idle [expr {$remaining - $step}] $step $body]
}

# --- Assertions -------------------------------------------------------------

proc harness::pass {name {detail ""}} {
    variable results
    lappend results [list $name PASS $detail]
}

proc harness::fail {name {detail ""}} {
    variable results
    variable failed
    lappend results [list $name FAIL $detail]
    set failed 1
}

proc harness::assert_screen_contains {name pattern} {
    if {[string match "*$pattern*" [harness::screen_text]]} {
        harness::pass $name
    } else {
        harness::fail $name "screen does not contain '$pattern'"
    }
}

proc harness::assert_screen_lacks {name pattern} {
    if {[string match "*$pattern*" [harness::screen_text]]} {
        harness::fail $name "screen unexpectedly contains '$pattern'"
    } else {
        harness::pass $name
    }
}

proc harness::assert_eq {name expected actual} {
    if {$expected eq $actual} {
        harness::pass $name
    } else {
        harness::fail $name "expected '$expected', got '$actual'"
    }
}

# --- Finish -----------------------------------------------------------------

# Write the result file and quit openMSX.  Always call this; a test that never
# reaches done() shows up in run.sh as NORESULT rather than silently passing.
proc harness::done {} {
    variable results
    variable outfile
    variable failed
    variable testname

    set fh [open $outfile w]
    puts $fh "TEST $testname"
    foreach r $results {
        lassign $r name status detail
        puts $fh "$status $name [expr {$detail ne "" ? "- $detail" : ""}]"
    }
    puts $fh [expr {$failed ? "RESULT FAIL" : "RESULT PASS"}]
    puts $fh "--- final screen ---"
    foreach line [harness::screen_lines] { puts $fh $line }
    close $fh
    exit
}
