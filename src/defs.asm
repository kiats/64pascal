// This file is in the public domain: use it, change it, share it, sell it - do whatever you like with it.
// No permission, credit or payment needed. It comes as it is, with no warranty. Enjoy!
// Note: this has only been tested in the VICE emulator, never on real hardware.
// =====================================================================================
// defs.asm - constants and macros shared by all compiler source files
// =====================================================================================
// (the constants are in tokens.asm)

.import source "tokens.asm"

// ---- macros -------------------------------------------------------------------------------

// GCALL(routine): emit "jsr routine" into the generated program.
.macro GCALL(a) {
    lda #<a
    ldx #>a
    jsr gen_jsr
}

// JPLACE(): emit a 16-bit placeholder word (a forward jump target not yet known) and
// remember where it lives (its physical address) on the hardware stack so that PATCH()
// can fill it in later. Stack effect: pushes 2 bytes.
.macro JPLACE() {
    lda cout+1
    pha
    lda cout
    pha
    lda #0
    tax
    jsr emit_word
}

// PATCH(): pop a placeholder address pushed by JPLACE() and store the current code
// address (cpc) into it, i.e. "the forward jump lands here". Stack effect: pops 2 bytes.
.macro PATCH() {
    pla
    sta tmpc1
    pla
    sta tmpc1+1
    jsr patch
}

// WOP(plain, wide): emit the call that prints a value of the current type: 'plain' normally, 'wide' followed by the
// field width (fmt_w) if the item was written with :width (not on the Plus/4: it has no extension chunks)
.macro WOP(plain, wide) {
#if NOEXT
    :GCALL(plain)
#else
    lda fmt_w
    beq !p+
    :GCALL(wide)
    lda fmt_w
    jsr emit
    jmp !d+
!p:
    :GCALL(plain)
!d:
#endif
}
