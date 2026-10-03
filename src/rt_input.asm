// This file is in the public domain: use it, change it, share it, sell it - do whatever you like with it.
// No permission, credit or payment needed. It comes as it is, with no warranty. Enjoy!
// Note: this has only been tested in the VICE emulator, never on real hardware.
// =====================================================================================
// rt_input.asm - runtime routines for read / readln / Val (included inside runtime.asm)
// =====================================================================================
//
// Keyboard input is line oriented. The first read of a line calls rt_getline, which lets the
// screen editor collect a whole line (the user types and presses RETURN; the KERNAL echoes it)
// and stores it as ASCII in the line buffer RT_INBUF. read(x) takes values from that buffer;
// when it is used up a new line is fetched. readln(x) additionally discards the rest of the line.
//   rt_havel   1 while a line is held in the buffer
//   rt_inlen   number of characters in the buffer
//   rt_inpos   index of the next unread character
// A prompt written on the same line (write('Name? '); readln(s)) is not returned: the screen editor
// remembers the cursor position where the input started and returns only what was typed after it.
// Zero page scratch (sa, sb, sn, sm, sc, sd) is shared with the string routines.


p2a:                    // PETSCII character in A -> ASCII (unshifted letters are lower case)
    cmp #$c1
    bcc !+
    cmp #$db
    bcs !+
    and #$7f            // shifted letters $C1-$DA -> $41-$5A
    rts
!:  cmp #$41
    bcc !+
    cmp #$5b
    bcs !+
    ora #$20            // $41-$5A -> $61-$7A
!:  rts

rt_getline:             // read one line from the keyboard into RT_INBUF
    ldx #0              // x = characters stored
gl_loop:
    stx sb              // (sb is not used by the readers that call rt_getline)
    jsr K_CHRIN         // the screen editor returns what was typed (not the prompt) at RETURN
    ldx sb
    cmp #13
    beq gl_end
    cpx #255
    bcs gl_loop         // line buffer full: ignore the rest
    jsr p2a
    sta RT_INBUF,x
    inx
    jmp gl_loop
gl_end:
    stx rt_inlen
    lda #13             // the KERNAL leaves the cursor after the line: move it to the next line
    jsr K_CHROUT
    lda #0
    sta rt_inpos
    lda #1
    sta rt_havel
    rts

rt_readchar:            // ac = next character of the input; carriage return (13) at the end of a line
    lda rt_havel
    bne !+
    jsr rt_getline
!:  ldx rt_inpos
    cpx rt_inlen
    bcs rc_eol
    lda RT_INBUF,x
    sta ac
    inc rt_inpos
    lda #0
    sta ac+1
    rts
rc_eol:
    lda #13
    sta ac
    lda #0
    sta ac+1
    sta rt_havel        // the end of the line has been delivered: the next read starts a new line
    rts

rt_readint:             // ac = next integer of the input (leading blanks and a sign allowed)
    lda #0
    sta sd              // sd = 1 for a negative number
ri_skip:
    lda rt_havel
    bne !+
    jsr rt_getline
!:  ldx rt_inpos
    cpx rt_inlen
    bcc ri_ch
    lda #0              // end of line before the number: continue on the next line
    sta rt_havel
    jmp ri_skip
ri_ch:
    lda RT_INBUF,x
    cmp #' '
    bne ri_sign
    inc rt_inpos
    jmp ri_skip
ri_sign:
    cmp #'-'
    bne !+
    lda #1
    sta sd
    inc rt_inpos
    jmp ri_digits
!:  cmp #'+'
    bne ri_digits
    inc rt_inpos
ri_digits:
    lda #0
    sta ac
    sta ac+1
ri_loop:
    ldx rt_inpos
    cpx rt_inlen
    bcs ri_done
    lda RT_INBUF,x
    sec
    sbc #'0'
    cmp #10
    bcs ri_done         // not a digit
    sta sm
    lda ac              // ac = ac * 10 + digit
    sta tmp
    lda ac+1
    sta tmp+1
    asl ac
    rol ac+1
    asl ac
    rol ac+1
    clc
    lda ac
    adc tmp
    sta ac
    lda ac+1
    adc tmp+1
    sta ac+1
    asl ac
    rol ac+1
    clc
    lda ac
    adc sm
    sta ac
    bcc !+
    inc ac+1
!:  inc rt_inpos
    jmp ri_loop
ri_done:
    lda sd
    beq !+
    :NEG16(ac)
!:  rts

rt_readstr:             // read(string): inline byte = maximum length; target address on the stack
    :FETCH1()
    jsr popt            // tmp = target
    lda rt_havel
    bne !+
    jsr rt_getline
!:  sec                 // characters left on the line
    lda rt_inlen
    sbc rt_inpos
    bcs !+
    lda #0
!:  cmp wd              // at most the maximum length
    bcc !+
    lda wd
!:  sta sc
    ldy #0
    sta (tmp),y
    ldx rt_inpos
    ldy #1
    lda sc
    beq rs_done
rs_copy:
    lda RT_INBUF,x
    sta (tmp),y
    inx
    iny
    dec sc
    bne rs_copy
rs_done:
    lda rt_inlen        // the whole rest of the line is used up (readln only has to discard it)
    sta rt_inpos
    jmp (rp)

rt_readln_end:          // end of readln: discard the rest of the line (waits for RETURN if no line was read)
    lda rt_havel
    bne !+
    jsr rt_getline
!:  lda #0
    sta rt_havel
    rts

rt_val:                 // Val(s, n, code): s and the address of n are on the stack, address of code in ac
    lda ac
    sta sb              // sb = address of code
    lda ac+1
    sta sb+1
    jsr popt
    lda tmp
    sta sa              // sa = address of n
    lda tmp+1
    sta sa+1
    jsr popt            // tmp = the string
    ldy #0
    lda (tmp),y
    sta sn              // sn = its length
    lda #0
    sta ac
    sta ac+1
    sta sd              // sd = negative flag
    ldx #1              // x = position of the character being examined
va_blank:
    cpx sn
    beq va_chk          // (the last character may still be a blank)
    bcc va_chk
    jmp va_nodigit
va_chk:
    txa
    tay
    lda (tmp),y
    cmp #' '
    bne va_sign
    inx
    jmp va_blank
va_sign:
    cmp #'-'
    bne !+
    inc sd
    inx
    jmp va_digits
!:  cmp #'+'
    bne va_digits
    inx
va_digits:
    stx sm              // position of the first digit
va_loop:
    cpx sn
    beq va_one
    bcs va_end          // past the end of the string
va_one:
    txa
    tay
    lda (tmp),y
    sec
    sbc #'0'
    cmp #10
    bcs va_end
    sta sc
    lda ac              // ac = ac * 10 + digit (as in readint)
    sta wd
    lda ac+1
    sta wd+1
    asl ac
    rol ac+1
    asl ac
    rol ac+1
    clc
    lda ac
    adc wd
    sta ac
    lda ac+1
    adc wd+1
    sta ac+1
    asl ac
    rol ac+1
    clc
    lda ac
    adc sc
    sta ac
    bcc !+
    inc ac+1
!:  inx
    jmp va_loop
va_end:                 // success only if every character up to the end was used (x = length + 1)
    stx sc
    lda sn
    clc
    adc #1
    cmp sc
    bne va_errj         // stopped early: x is the position of the offending character
    cpx sm
    beq va_errj         // no digit at all
    lda sd
    beq va_store
    :NEG16(ac)
va_store:
    ldy #0
    lda ac
    sta (sa),y
    iny
    lda ac+1
    sta (sa),y
    ldy #0              // code := 0
    tya
    sta (sb),y
    iny
    sta (sb),y
    rts
va_errj:
    jmp va_error
va_nodigit:
    ldx sn
    inx
va_error:
    ldy #0              // n := 0, code := position of the offending character
    tya
    sta (sa),y
    iny
    sta (sa),y
    ldy #0
    txa
    sta (sb),y
    iny
    lda #0
    sta (sb),y
    rts
