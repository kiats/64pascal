// This file is in the public domain: use it, change it, share it, sell it - do whatever you like with it.
// No permission, credit or payment needed. It comes as it is, with no warranty. Enjoy!
// Note: this has only been tested in the VICE emulator, never on real hardware.
// =====================================================================================
// rt_strings.asm - runtime routines for strings (included inside runtime.asm)
// =====================================================================================
//
// A string is a length byte followed by that many characters. Expressions that create strings
// (concatenation, Copy, Chr, ...) build them in one of four 256-byte temporaries (RT_TEMPS) that
// are used in rotation, so one expression may have up to four pending temporaries. In all
// routines a string "value" is the ADDRESS of its length byte, held in ac.
// Zero page scratch (sa, sb, sn, sm, sc, sd) reuses compiler locations, see zp.asm.

newtemp:                // sa = address of the next temporary string
    lda rt_tnext
    clc
    adc #1
    and #3
    sta rt_tnext
    clc
    adc #>RT_TEMPS
    sta sa+1
    lda #0
    sta sa
    rts

rt_slit:                // inline string literal (length + characters): ac = its address, skip it
    pla
    sta rp
    pla
    sta rp+1
    clc
    lda rp              // ac = address of the length byte = rp + 1
    adc #1
    sta ac
    lda rp+1
    adc #0
    sta ac+1
    ldy #1
    lda (rp),y          // length
    clc
    adc #2              // next instruction = rp + 2 + length
    adc rp
    sta rp
    bcc !+
    inc rp+1
!:  jmp (rp)

rt_c2s:                 // ac = character -> ac = address of a temporary string holding it
    jsr newtemp
    ldy #0
    lda #1
    sta (sa),y
    iny
    lda ac
    sta (sa),y
    lda sa
    sta ac
    lda sa+1
    sta ac+1
    rts

rt_scat:                // ac = left + ac (left address popped from the stack) -> temporary
    jsr popt            // tmp = left
    jsr newtemp         // sa = result
    ldy #0
    lda (tmp),y
    sta sn              // left length
    lda (ac),y
    sta sm              // right length
    clc
    lda sn
    adc sm
    bcc !+
    lda #255            // the result is limited to 255 characters
!:  sta sc              // total length
    sta (sa),y
    ldx sn              // copy the left part
    beq cat_r
    ldy #1
!:  lda (tmp),y
    sta (sa),y
    iny
    dex
    bne !-
cat_r:
    clc                 // sb = sa + left length: the right part goes to sb[1..]
    lda sa
    adc sn
    sta sb
    lda sa+1
    adc #0
    sta sb+1
    sec
    lda sc
    sbc sn              // characters of the right part that fit
    tax
    beq cat_done
    ldy #1
!:  lda (ac),y
    sta (sb),y
    iny
    dex
    bne !-
cat_done:
    lda sa
    sta ac
    lda sa+1
    sta ac+1
    rts

rt_sset:                // string assignment, inline byte = maximum length of the target
    :FETCH1()           // wd = maximum length
    jsr popt            // tmp = target address, ac = source address
sset_do:                // (also used by Str) copy at most wd characters from ac to tmp
    ldy #0
    lda (ac),y
    cmp wd
    bcc !+
    lda wd
!:  sta (tmp),y
    tax
    beq sset_done
    ldy #1
!:  lda (ac),y
    sta (tmp),y
    iny
    dex
    bne !-
sset_done:
    jmp (rp)

scmp:                   // compare string tmp (left) with string ac (right): A = $ff, 0 or 1
    ldy #0
    lda (tmp),y
    sta sn
    lda (ac),y
    sta sm
    lda sn
    cmp sm
    bcc !+
    lda sm
!:  sta sc              // the shorter length
    beq sc_len
    ldy #1
!:  lda (tmp),y
    cmp (ac),y
    bne sc_diff
    iny
    dec sc
    bne !-
sc_len:                 // common part equal: the shorter string is smaller
    lda sn
    cmp sm
    beq sc_eq
    bcc sc_lt
    bcs sc_gt
sc_diff:
    bcc sc_lt
sc_gt:
    lda #1
    rts
sc_lt:
    lda #$ff
    rts
sc_eq:
    lda #0
    rts

rt_seq:                 // string comparisons: ac = (left op right) as a boolean
    jsr popt
    jsr scmp
    cmp #0
    beq sb_yes
    bne sb_no
rt_sne:
    jsr popt
    jsr scmp
    cmp #0
    bne sb_yes
    beq sb_no
rt_slt:
    jsr popt
    jsr scmp
    cmp #$ff
    beq sb_yes
    bne sb_no
rt_sgt:
    jsr popt
    jsr scmp
    cmp #1
    beq sb_yes
    bne sb_no
rt_sle:
    jsr popt
    jsr scmp
    cmp #1
    bne sb_yes
    beq sb_no
rt_sge:
    jsr popt
    jsr scmp
    cmp #$ff
    bne sb_yes
    beq sb_no
sb_no:
    clc
    jmp setbool
sb_yes:
    sec
    jmp setbool

rt_wstr:                // print the string at ac
    ldy #0
    lda (ac),y
    beq !+
    tax
    ldy #1
!:  lda (ac),y
    jsr putc
    iny
    dex
    bne !-
!:  rts

rt_slen:                // ac = length of the string at ac
    ldy #0
    lda (ac),y
    sta ac
    sty ac+1
    rts

rt_upcase:              // ac = upper case of the character in ac
    lda ac
    cmp #'a'
    bcc !+
    cmp #'{'
    bcs !+
    and #$df
    sta ac
!:  rts

clampcnt:               // sc = ac limited to 0..255 (negative counts become 0)
    lda ac+1
    bmi cl_0
    beq cl_lo
    lda #255
    bne cl_set
cl_0:
    lda #0
    beq cl_set
cl_lo:
    lda ac
cl_set:
    sta sc
    rts

rt_copy:                // Copy(s, index, count): s and index on the stack, count in ac
    jsr clampcnt
    jsr popt            // index
    lda tmp+1
    sta sd              // sd <> 0: index out of range
    lda tmp
    sta sn
    jsr popt            // tmp = s
    jsr newtemp
    ldy #0
    lda #0
    sta (sa),y          // result := ''
    lda sd
    bne copy_fin
    lda (tmp),y
    sta sm              // length of s
    lda sn
    bne !+
    lda #1              // index 0 counts as 1
    sta sn
!:  lda sm
    cmp sn
    bcc copy_fin        // index beyond the end
    sec                 // available = length - index + 1
    lda sm
    sbc sn
    clc
    adc #1
    cmp sc
    bcc !+
    lda sc
!:  sta sd              // number of characters to copy
    ldy #0
    sta (sa),y
    clc                 // sb = tmp + index - 1, so that sb[1] is the first character
    lda tmp
    adc sn
    sta sb
    lda tmp+1
    adc #0
    sta sb+1
    sec
    lda sb
    sbc #1
    sta sb
    lda sb+1
    sbc #0
    sta sb+1
    ldx sd
    beq copy_fin
    ldy #1
!:  lda (sb),y
    sta (sa),y
    iny
    dex
    bne !-
copy_fin:
    lda sa
    sta ac
    lda sa+1
    sta ac+1
    rts

rt_pos:                 // Pos(sub, s): sub on the stack, s in ac -> index of first match, 0 if none
    jsr popt            // tmp = sub
    ldy #0
    lda (tmp),y
    sta sn              // length of sub
    lda (ac),y
    sta sm              // length of s
    lda sn
    beq pos_none
    sec
    lda sm
    sbc sn
    bcc pos_none
    clc
    adc #1
    sta sc              // number of start positions to try
    lda #1
    sta sd              // current start position
pos_try:
    clc                 // sb = ac + start - 1
    lda ac
    adc sd
    sta sb
    lda ac+1
    adc #0
    sta sb+1
    sec
    lda sb
    sbc #1
    sta sb
    lda sb+1
    sbc #0
    sta sb+1
    ldx sn
    ldy #1
!:  lda (tmp),y
    cmp (sb),y
    bne pos_next
    iny
    dex
    bne !-
    lda sd              // found
    sta ac
    lda #0
    sta ac+1
    rts
pos_next:
    inc sd
    dec sc
    bne pos_try
pos_none:
    lda #0
    sta ac
    sta ac+1
    rts

rt_delete:              // Delete(var s, index, count): address of s and index on the stack, count in ac
    jsr clampcnt
    jsr popt
    lda tmp+1
    sta sd
    lda tmp
    sta sn              // index
    jsr popt
    lda tmp
    sta sb              // sb = s
    lda tmp+1
    sta sb+1
    lda sd
    bne del_done        // index out of range
    ldy #0
    lda (sb),y
    sta sm              // current length
    lda sn
    beq del_done
    lda sm
    cmp sn
    bcc del_done        // index beyond the end
    sec
    lda sm
    sbc sn
    clc
    adc #1              // available = length - index + 1
    sta sd
    cmp sc
    bcc !+
    lda sc
!:  sta sc              // characters to delete
    beq del_done
    sec                 // new length
    lda sm
    sbc sc
    sta (sb),y
    sec                 // tail = available - deleted characters, moved down
    lda sd
    sbc sc
    tax
    beq del_done
    clc                 // sa = sb + index (destination), tmp = sa + count (source)
    lda sb
    adc sn
    sta sa
    lda sb+1
    adc #0
    sta sa+1
    clc
    lda sa
    adc sc
    sta tmp
    lda sa+1
    adc #0
    sta tmp+1
    ldy #0
!:  lda (tmp),y
    sta (sa),y
    iny
    dex
    bne !-
del_done:
    rts

rt_insert:              // Insert(src, var s, index): src and address of s on the stack, index in ac;
    :FETCH1()           // inline byte = maximum length of s (wd)
    lda ac
    sta sn              // index (clamped below)
    lda ac+1
    sta sd
    jsr popt
    lda tmp
    sta sb              // sb = s
    lda tmp+1
    sta sb+1
    jsr popt
    lda tmp
    sta sa              // sa = src
    lda tmp+1
    sta sa+1
    ldy #0
    lda (sb),y
    sta sm              // length of s
    lda sd              // index < 1 -> 1, index > length + 1 -> length + 1
    bmi ins_one
    bne ins_end
    lda sn
    bne !+
ins_one:
    lda #1
    sta sn
!:  lda sm
    cmp sn
    bcs ins_idx_ok
ins_end:
    lda sm
    clc
    adc #1
    sta sn
ins_idx_ok:
    sec                 // room = maximum - length
    lda wd
    sbc sm
    bcc ins_done
    ldy #0
    cmp (sa),y          // n = min(room, length of src)
    bcc !+
    lda (sa),y
!:  sta sc              // n characters are inserted
    beq ins_done
    sec                 // tail length = length - index + 1 (characters moved up by n)
    lda sm
    sbc sn
    clc
    adc #1
    beq ins_copy        // index = length + 1: nothing to move
    tax
    clc                 // tmp = sb + index: the tail starts at tmp[0]
    lda sb
    adc sn
    sta tmp
    lda sb+1
    adc #0
    sta tmp+1
    txa
    tay
    dey
mv_tail:                // move the tail backwards: tmp[y] -> tmp[y + n]
    lda (tmp),y
    sty sd
    pha
    tya
    clc
    adc sc
    tay
    pla
    sta (tmp),y
    ldy sd
    dey
    bpl mv_tail
ins_copy:
    clc                 // tmp = sb + index - 1: the j-th inserted character goes to tmp[j]
    lda sb
    adc sn
    sta tmp
    lda sb+1
    adc #0
    sta tmp+1
    sec
    lda tmp
    sbc #1
    sta tmp
    lda tmp+1
    sbc #0
    sta tmp+1
    ldx sc
    ldy #1
!:  lda (sa),y
    sta (tmp),y
    iny
    dex
    bne !-
    clc                 // new length
    lda sm
    adc sc
    ldy #0
    sta (sb),y
ins_done:
    jmp (rp)

rt_str:                 // Str(n, var s): n on the stack, address of s in ac, inline byte = maximum length
    :FETCH1()
    lda ac
    sta sb              // sb = destination string
    lda ac+1
    sta sb+1
    jsr popt
    lda tmp
    sta ac              // ac = n
    lda tmp+1
    sta ac+1
    jsr newtemp         // build the text in a temporary
    lda #0
    sta sc              // sc = characters so far
    lda ac+1
    bpl !+
    :NEG16(ac)
    lda #'-'
    ldy #1
    sta (sa),y
    inc sc
!:  ldx #0              // digits come out last first: push them, then pop
!:  jsr div10
    pha
    inx
    lda ac
    ora ac+1
    bne !-
!:  pla
    ora #'0'
    inc sc
    ldy sc
    sta (sa),y
    dex
    bne !-
    ldy #0
    lda sc
    sta (sa),y
    lda sa              // copy to the destination, limited to the maximum length
    sta ac
    lda sa+1
    sta ac+1
    lda sb
    sta tmp
    lda sb+1
    sta tmp+1
    jmp sset_do
