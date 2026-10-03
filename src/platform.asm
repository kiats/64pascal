// This file is in the public domain: use it, change it, share it, sell it - do whatever you like with it.
// No permission, credit or payment needed. It comes as it is, with no warranty. Enjoy!
// Note: this has only been tested in the VICE emulator, never on real hardware.
// =====================================================================================
// platform.asm - start-up and exit code shared by the programs that contain the compiler
// =====================================================================================
//
// Import this file first (right after memmap.asm and zp.asm): it emits the BASIC line that
// starts the program, "10 SYS <start>", and defines the macros below. The importing file must
// define the label 'start' IMMEDIATELY after the import (that is where SYS jumps to), and import
// platcode.asm later for the routines.
//
//   PLAT_ENTER   macro: select the memory configuration (BASIC off, KERNAL + I/O on), clear the
//                screen and select the lowercase character set
//   PLAT_LEAVE   macro: undo the memory configuration so the program can return to BASIC

.encoding "ascii"
.import source "kernal.asm"      // K_* constants

#if PLUS4
* = $1001
    .word $1001+10              // link to the end of the BASIC program
    .word 10                    // line 10
    .byte $9e                   // SYS
    .text "4109"                // = address of 'start', checked below
    .byte 0
    .word 0
#elif C128
* = $1c01
    .word $1c01+10
    .word 10
    .byte $9e
    .text "7181"
    .byte 0
    .word 0
#else
:BasicUpstart2(start)           // BASIC stub at $0801
#endif

.macro PLAT_ENTER() {
    ldx #$27                    // save zero page $02-$29: BASIC keeps live pointers there (temporary
!:  lda $02,x                   // string stack, ...) and needs them back when we return
    sta zpsave,x
    dex
    bpl !-
#if C128
    lda #$0e                    // MMU: BASIC ROMs off, KERNAL + I/O on, RAM bank 0
    sta $ff00
#elif !PLUS4
    lda #$36                    // BASIC ROM off, KERNAL + I/O on
    sta $01
#endif
    lda #147                    // clear screen
    jsr $ffd2
    lda #14                     // lowercase character set
    jsr $ffd2
}

.macro PLAT_LEAVE() {
#if C128
    lda #$00                    // MMU back to the normal configuration (all ROMs on)
    sta $ff00
#elif !PLUS4
    lda #$37                    // BASIC ROM back on
    sta $01
#endif
    ldx #$27                    // restore zero page $02-$29
!:  lda zpsave,x
    sta $02,x
    dex
    bpl !-
}
