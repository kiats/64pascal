// This file is in the public domain: use it, change it, share it, sell it - do whatever you like with it.
// No permission, credit or payment needed. It comes as it is, with no warranty. Enjoy!
// Note: this has only been tested in the VICE emulator, never on real hardware.
// =====================================================================================
// kfstubs.asm - calling the KERNAL while the ROMs are switched off (Plus/4, HIROM builds)
// =====================================================================================
//
// 64ide and 64pascal on the Plus/4 run with the ROMs off and interrupts disabled, so that the RAM under them
// ($8000-$FCFF: source text, compiler tables) can be read and written like any other. Writing any value to the TED
// register $FF3F switches the ROMs off, writing to $FF3E switches them on. A KF_ stub (the macro KBODY) does this around one call:
//
//     sta $ff3e   ROMs on          (the value written is irrelevant; A, X, Y and the flags are not changed)
//     cli         interrupts on, so that the keyboard is scanned and the jiffy clock runs
//     jsr <routine>
//     sei         off again, ROMs off
//     sta $ff3f
//     rts         the registers and flags are the ones the routine returned (carry, zero, A, X, Y)
//
// The stubs live in the low RAM (code of the program), so they stay visible when the ROMs go off. The routines they call
// that are not in the ROM (puts, rt_wint, ... of the runtime, run_program) run with the ROMs on as well.
// Memory the KERNAL reads must therefore be in the low RAM (file names, buffers); data it writes may be anywhere.

.macro KBODY(target) {
    sta $ff3e                   // ROMs on
    cli
    jsr target
    sei
    sta $ff3f                   // ROMs off
    rts
}

// rom_off_enter: first thing after start-up: disable interrupts and switch the ROMs off.
rom_off_enter:
    sei
    sta $ff3f
    rts

// rom_on_leave: switch the ROMs on and enable interrupts again (before returning to BASIC).
rom_on_leave:
    sta $ff3e
    cli
    rts

KF_SETLFS:
    :KBODY(K_SETLFS)
KF_SETNAM:
    :KBODY(K_SETNAM)
KF_OPEN:
    :KBODY(K_OPEN)
KF_CLOSE:
    :KBODY(K_CLOSE)
KF_CHKIN:
    :KBODY(K_CHKIN)
KF_CHKOUT:
    :KBODY(K_CHKOUT)
KF_CLRCHN:
    :KBODY(K_CLRCHN)
KF_CHRIN:
    :KBODY(K_CHRIN)
KF_CHROUT:
    :KBODY(K_CHROUT)
KF_READST:
    :KBODY(K_READST)
KF_GETIN:
    :KBODY(K_GETIN)
KF_PLOT:
    :KBODY(K_PLOT)
KF_puts:
    :KBODY(puts)
KF_rt_wint:
    :KBODY(rt_wint)
KF_rt_wln:
    :KBODY(rt_wln)
KF_print_errmsg:
    :KBODY(print_errmsg)
KF_run_program:
    :KBODY(run_program)
