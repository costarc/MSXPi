/* arrowkeys.h - cursor-key debounce shared by PCHESS, PCHESS1 and PCHECKERS.
 *
 * The BIOS keeps typing arrows into its buffer while the board is being
 * redrawn, and a gate timed from before the redraw has already expired when the
 * next queued arrow is read, so one touch moved the cursor two squares. Here:
 *  - arrow_gate() lets one arrow through, then drops arrows for ARROW_GATE
 *    jiffies (8 = 133 ms at 60 Hz, 160 ms at 50 Hz);
 *  - arrow_done(), called after the redraw, empties the BIOS key buffer
 *    (GETPNT := PUTPNT) and starts that interval from the end of the redraw,
 *    so the time spent drawing is not counted against it.
 * A held key repeats at the gate rate; the first arrow is immediate. */
#ifndef ARROWKEYS_H
#define ARROWKEYS_H

#define ARROW_GATE 8
#define ARROW_JIFFY (*(volatile uint16_t *)0xFC9E)

static uint8_t arrow_seen,arrow_moved;
static uint16_t arrow_last;

static uint8_t arrow_gate(uint8_t key) {
    if(key<0x1c || key>0x1f) return key;
    if(arrow_seen && (uint16_t)(ARROW_JIFFY-arrow_last)<ARROW_GATE) return 0;
    arrow_seen=1; arrow_moved=1; arrow_last=ARROW_JIFFY;
    return key;
}

static void arrow_done(void) {
    if(!arrow_moved) return;
    arrow_moved=0;
    __critical { *(volatile uint16_t *)0xF3FA=*(volatile uint16_t *)0xF3F8; }
    arrow_last=ARROW_JIFFY;
}

#endif
