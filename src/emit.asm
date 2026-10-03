// This file is in the public domain: use it, change it, share it, sell it - do whatever you like with it.
// No permission, credit or payment needed. It comes as it is, with no warranty. Enjoy!
// Note: this has only been tested in the VICE emulator, never on real hardware.
// =====================================================================================
// emit.asm - writing the generated program
// =====================================================================================
//
// Two addresses are tracked while generating code:
//   cout  physical address where the next byte is stored
//   cpc   logical address the byte will have when the program runs
// They are equal when the program runs where it was built (in-IDE run). They differ when
// building a standalone file for another load address.

// emit: append byte A to the program. Y is used, X is preserved.
emit:
    ldy #0
    sta (cout),y                // store at the physical address
    inc cout                    // advance physical pointer
    bne e1
    inc cout+1
    lda cout+1                  // crossed into a new page: check we are still inside CODE_LIMIT
    cmp codelimit+1
    bcc e1
    lda #E_MEM                  // generated code does not fit
    jmp error
e1: inc cpc                     // advance logical address
    bne !+
    inc cpc+1
!:  rts

// emit_word: append the 16-bit value A (low) / X (high), little endian.
emit_word:
    jsr emit
    txa
    jmp emit

// gen_jsr: emit "jsr <address>" where the address is A (low) / X (high).
// Used through the GCALL macro to call runtime routines.
gen_jsr:
    sta mk_lo                   // remember which chunk of the runtime the program uses (chunks.asm)
    stx mk_hi
    jsr mark_chunk
    lda mk_lo
    ldx mk_hi
    pha
    lda #$20                    // JSR opcode
    jsr emit
    pla
    jmp emit_word

// patch: store the current logical address into the 16-bit placeholder at (tmpc1).
// Resolves a forward jump emitted earlier with JPLACE.
patch:
    ldy #0
    lda cpc
    sta (tmpc1),y
    iny
    lda cpc+1
    sta (tmpc1),y
    rts
