// This file is in the public domain: use it, change it, share it, sell it - do whatever you like with it.
// No permission, credit or payment needed. It comes as it is, with no warranty. Enjoy!
// Note: this has only been tested in the VICE emulator, never on real hardware.
// =====================================================================================
// rt_fmt.asm - write(x:width) for integers, characters, booleans and strings; random numbers (extension chunk, inside runtime.asm)
// =====================================================================================
//
// The value is printed right-justified in a field of the given width (it is printed in full if it needs more room).
// The width is an inline byte after the call; the value is in ac like for rt_wint / rt_wch / rt_wbool / rt_wstr.
// (For reals the width is part of rt_wreal, see rt_float.asm.)

fmt_pad:                        // print spaces so that A characters fill the width in wd
    sta s1
    sec
    lda wd
    sbc s1
    bcc fp_ret
    beq fp_ret
    sta fp_cnt                  // (not in X: the Plus/4 KERNAL's CHROUT does not preserve X and Y)
!:  lda #' '
    jsr putc
    dec fp_cnt
    bne !-
fp_ret:
    rts
fp_cnt: .byte 0

rt_wintw:                       // integer in ac
    :FETCH1()
    lda ac                      // count the characters of the number (sign + digits) on a copy
    pha
    lda ac+1
    pha
    ldx #1
    lda ac+1
    bpl fi_pos
    inx
    :NEG16(ac)
fi_pos:
    jsr div10
    lda ac
    ora ac+1
    beq fi_cnt
    inx
    jmp fi_pos
fi_cnt:
    pla
    sta ac+1
    pla
    sta ac
    txa
    jsr fmt_pad
    jsr rt_wint
    jmp (rp)

rt_wstrw:                       // string at the address in ac
    :FETCH1()
    ldy #0
    lda (ac),y
    jsr fmt_pad
    jsr rt_wstr
    jmp (rp)

rt_wchw:                        // character in ac
    :FETCH1()
    lda #1
    jsr fmt_pad
    jsr rt_wch
    jmp (rp)

rt_wboolw:                      // boolean in ac
    :FETCH1()
    lda #4
    ldx ac
    bne !+
    lda #5
!:  jsr fmt_pad
    jsr rt_wbool
    jmp (rp)

// ---- random numbers (16 bit xorshift generator) -------------------------------------------------------------------
rnd_x:   .word $ace1            // the generator state (never 0): the same sequence at every start until Randomize
rnd_t:   .word 0
rnd_h:   .word 0
rnd_l:   .word 0

rnd_step:                       // x = next number of the sequence
    lda rnd_x
    sta rnd_t
    lda rnd_x+1
    sta rnd_t+1
    ldx #7
!:  asl rnd_t                   // x ^= x << 7
    rol rnd_t+1
    dex
    bne !-
    lda rnd_x
    eor rnd_t
    sta rnd_x
    lda rnd_x+1
    eor rnd_t+1
    sta rnd_x+1
    lsr                         // x ^= x >> 9
    eor rnd_x
    sta rnd_x
    eor rnd_x+1                 // x ^= x << 8
    sta rnd_x+1
    rts

rt_random:                      // ac = a random integer 0 .. ac-1 (the high half of ac * a random 16 bit number)
    jsr rnd_step
    lda #0
    sta rnd_h
    sta rnd_h+1
    lda rnd_x
    sta rnd_l
    lda rnd_x+1
    sta rnd_l+1
    ldx #16
rr_loop:
    lda rnd_l
    lsr
    bcc rr_shift
    clc
    lda rnd_h
    adc ac
    sta rnd_h
    lda rnd_h+1
    adc ac+1
    sta rnd_h+1
rr_shift:
    ror rnd_h+1
    ror rnd_h
    ror rnd_l+1
    ror rnd_l
    dex
    bne rr_loop
    lda rnd_h
    sta ac
    lda rnd_h+1
    sta ac+1
    rts

rt_randomize:                   // start the sequence at a point that depends on the clock
    jsr K_RDTIM
    sta rnd_x
    stx rnd_x+1
    tya
    eor rnd_x
    sta rnd_x
    lda rnd_x
    ora rnd_x+1
    bne !+
    lda #$e1
    sta rnd_x
    lda #$ac
    sta rnd_x+1
!:  rts
