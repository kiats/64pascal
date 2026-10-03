// This file is in the public domain: use it, change it, share it, sell it - do whatever you like with it.
// No permission, credit or payment needed. It comes as it is, with no warranty. Enjoy!
// Note: this has only been tested in the VICE emulator, never on real hardware.
// =====================================================================================
// standalone.asm - building a program file that runs without the compiler
// =====================================================================================
//
// With cmode = 1 the compiler produces a complete .prg file image in the code buffer
// (starting at CODE_BASE) instead of a program that is run in place:
//
//    load address (STAND_BASE)    $0801 on the C64, $1C01 on the C128, $1001 on the Plus/4
//    BASIC line   10 SYS <start>   so that RUN starts the program
//    start-up code                set up memory, copy the runtime, run the program, return to BASIC
//    runtime image                the same runtime that the compiler uses (RT_SIZE bytes)
//    program code                 compiled as if it were loaded at its real address
//
// The compiler keeps two addresses (see emit.asm): the physical address where bytes are stored
// (the code buffer) and the logical address they will have when the file is loaded. All
// addresses inside the code are logical, so the file works wherever it is loaded.
// Variables live in the data area (DATA_BASE...) which is not part of the file.
//
// The runtime is always copied in full (about 3.5 KB); linking only the needed routines is a
// possible later optimisation.

// (On the Plus/4 the image is built in the RAM under the ROMs, behind the source text: see HIROM in memmap.asm.)

#if C128
.const SYS_TEXT_ADDR = 7181
#elif PLUS4
.const SYS_TEXT_ADDR = 4109
#else
.const SYS_TEXT_ADDR = 2061
#endif

// The template: BASIC line + start-up code, assembled for its load address.
sa_image:
.pseudopc STAND_BASE {
sa_template:
    .word STAND_BASE+10         // link to the end of the BASIC program
    .word 10                    // line number 10
    .byte $9e                   // SYS
    .text toIntString(SYS_TEXT_ADDR)
    .byte 0                     // end of line
    .word 0                     // end of program
sa_code:
.assert "BASIC SYS address must match the start-up code", sa_code == SYS_TEXT_ADDR, true
    ldx #$27                    // save zero page $02-$29: BASIC keeps live pointers there
!:  lda $02,x
    sta sa_zpsave,x
    dex
    bpl !-
#if C128
    lda #$0e                    // MMU: BASIC ROMs off, KERNAL + I/O on
    sta $ff00
#elif !PLUS4
    lda #$36                    // BASIC ROM off, KERNAL + I/O on
    sta $01
#endif
    lda sa_dirptr               // copy the runtime chunks used by the program to their fixed
    sta rp                      // addresses: the directory lists (destination, source, length)
    lda sa_dirptr+1
    sta rp+1
sx_ent:
    ldy #1
    lda (rp),y
    beq sx_done                 // destination 0 ends the directory
    sta wd+1
    dey
    lda (rp),y
    sta wd
    ldy #2
    lda (rp),y
    sta tmp
    iny
    lda (rp),y
    sta tmp+1
    iny
    lda (rp),y
    sta rem
    iny
    lda (rp),y
    sta rem+1
    ldy #0
sx_cp:
    lda rem
    ora rem+1
    beq sx_next
    lda (tmp),y
    sta (wd),y
    inc tmp
    bne !+
    inc tmp+1
!:  inc wd
    bne !+
    inc wd+1
!:  lda rem
    bne !+
    dec rem+1
!:  dec rem
    jmp sx_cp
sx_next:
    clc
    lda rp
    adc #6
    sta rp
    bcc sx_ent
    inc rp+1
    jmp sx_ent
sx_done:
    lda #14                     // lowercase / uppercase character set (the runtime prints that way);
                                // it stays selected when the program ends, so the output stays readable
    jsr $ffd2
    jsr sx_go                   // run the program; rt_halt returns here
#if C128
    lda #$00                    // normal configuration, all ROMs on
    sta $ff00
#elif !PLUS4
    lda #$37                    // BASIC ROM back on
    sta $01
#endif
    ldx #$27                    // restore zero page $02-$29
!:  lda sa_zpsave,x
    sta $02,x
    dex
    bpl !-
    rts                         // back to BASIC
sx_go:
    tsx                         // rt_halt will restore this stack level and return to our caller
    stx rt_savesp
    lda #<STK_TOP               // software stack and frame pointer
    sta ssp
    sta fp
    lda #>STK_TOP
    sta ssp+1
    sta fp+1
    jmp PROG_START
sa_zpsave:
    .fill 40, 0
sa_dirptr:
    .word 0                     // address of the chunk directory (filled in at the end of the compilation)
}
.label SA_SIZE = * - sa_image            // size of the template
.label PROG_START = STAND_BASE + SA_SIZE // the program code follows the template

// emit_block: emit tmpc2 bytes starting at address tmpc1 (destroys tmpc1, tmpc2).
emit_block:
    lda tmpc2
    ora tmpc2+1
    beq eb_done
    ldy #0
    lda (tmpc1),y
    jsr emit
    inc tmpc1
    bne !+
    inc tmpc1+1
!:  lda tmpc2
    bne !+
    dec tmpc2+1
!:  dec tmpc2
    jmp emit_block
eb_done:
    rts

// emit_standalone_header: emit the BASIC line and the start-up code at the start of the file.
// Afterwards the logical address is PROG_START, where the program code begins. (The runtime chunks
// are appended after the program, see chunks.asm.)
emit_standalone_header:
    lda #<sa_image
    sta tmpc1
    lda #>sa_image
    sta tmpc1+1
    lda #<SA_SIZE
    sta tmpc2
    lda #>SA_SIZE
    sta tmpc2+1
    jmp emit_block
