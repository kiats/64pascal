// This file is in the public domain: use it, change it, share it, sell it - do whatever you like with it.
// No permission, credit or payment needed. It comes as it is, with no warranty. Enjoy!
// Note: this has only been tested in the VICE emulator, never on real hardware.
// Runtime library. Assembled to run at the fixed address RT_BASE; the image is stored
// inline in the PRG and copied there at start-up. Compiled code calls these routines
// by absolute address.
//
// Execution model: result/left operand in 'ac'; 'rt_push' saves ac on the software stack;
// binary operators pop the left operand into 'tmp' and leave the result in ac.
// "Inline-argument" routines read their operand from the bytes following the JSR.

.encoding "ascii"

.macro FETCH() {
    pla                 // return address - 1
    sta rp
    pla
    sta rp+1
    ldy #1
    lda (rp),y
    sta wd              // inline word
    iny
    lda (rp),y
    sta wd+1
    clc
    lda rp              // rp = address after the inline word
    adc #3
    sta rp
    bcc !+
    inc rp+1
!:
}

.macro FETCH4() {      // two inline words: first -> wd, second -> wd2
    pla
    sta rp
    pla
    sta rp+1
    ldy #1
    lda (rp),y
    sta wd
    iny
    lda (rp),y
    sta wd+1
    iny
    lda (rp),y
    sta wd2
    iny
    lda (rp),y
    sta wd2+1
    clc
    lda rp              // rp = address after the inline words
    adc #5
    sta rp
    bcc !+
    inc rp+1
!:
}

.macro FETCH1() {      // like FETCH but the inline argument is a single byte (-> wd)
    pla
    sta rp
    pla
    sta rp+1
    ldy #1
    lda (rp),y
    sta wd
    clc
    lda rp              // rp = address after the inline byte
    adc #2
    sta rp
    bcc !+
    inc rp+1
!:
}

.macro NEG16(a) {
    sec
    lda #0
    sbc a
    sta a
    lda #0
    sbc a+1
    sta a+1
}

// Order in the program file: the extension chunks first, the runtime image (rt_image) LAST. Both images are only
// copied when the program starts (install_runtime: the runtime to RT_BASE, on the C64 the extension chunks to the RAM
// under the KERNAL ROM, HIDDEN_BASE); after that their bytes in the program file are dead and the text / source buffer
// may start inside them (SRC_BASE is computed from RECLAIM, see 64pascal.asm and 64ide.asm).

#if HAVEREAL
.label RECLAIM = ext_image      // C64: the extension chunks are copied to the RAM under the KERNAL at start-up too
#if NOSTORE
.label EXT_SRC = ext_image      // (64pascal on the Plus/4: the chunks stay where the program file put them)
#else
.label EXT_SRC = HIDDEN_BASE    // where the compiler finds the bytes of an extension chunk
#endif
#else
.label RECLAIM = rt_image
#if !NOEXT
.label EXT_SRC = ext_image
#endif
#endif
#if !NOEXT
// ---- extension chunks: assembled for EXT_BASE, copied there only when the program uses them -------
ext_image:
.pseudopc EXT_BASE {
ek0:
.import source "rt_heap.asm"
ek1:
#if HAVEREAL
.import source "rt_float.asm"
#endif
ek2:
.import source "rt_fmt.asm"
ek3:
}
.assert "extension chunks must fit their region", EXT_BASE + (ek3 - ek0) <= EXT_LIMIT, true
#endif
#if NOEXT
.label rt_wintw = 0             // (no extension chunks: write(x:width) is not available, the compiler does not use these)
.label rt_wstrw = 0
.label rt_wchw = 0
.label rt_wboolw = 0
.label rt_random = 0
.label rt_randomize = 0
.label rt_frandom = 0
.label rt_fstr = 0
.label rt_valreal = 0
#endif
#if !HAVEREAL
// No floating point on this machine (C128 in 128 mode, Plus/4: the extension region is too small): the compiler still
// refers to these routines, but the type name REAL is not defined, so they are never called.
.label rt_fpush = 0
.label rt_fpop = 0
.label rt_fpopi = 0
.label rt_i2f = 0
.label rt_fneg = 0
.label rt_fabs = 0
.label rt_fsqr = 0
.label rt_fldv = 0
.label rt_fstv = 0
.label rt_fldl = 0
.label rt_fstl = 0
.label rt_fldlp = 0
.label rt_fstlp = 0
.label rt_fldp = 0
.label rt_fstp = 0
.label rt_fli = 0
.label rt_flit = 0
.label rt_fsub = 0
.label rt_fadd = 0
.label rt_fmul = 0
.label rt_fdiv = 0
.label rt_feq = 0
.label rt_fne = 0
.label rt_flt = 0
.label rt_fgt = 0
.label rt_fle = 0
.label rt_fge = 0
.label rt_ftrunc = 0
.label rt_fround = 0
.label rt_fint = 0
.label rt_ffrac = 0
.label rt_fpi = 0
.label rt_fsqrt = 0
.label rt_fexp = 0
.label rt_fln = 0
.label rt_fsin = 0
.label rt_fcos = 0
.label rt_fatan = 0
.label rt_readreal = 0
.label rt_wreal = 0
#endif

rt_image:
.pseudopc RT_BASE {
rt_start:

// The runtime is built from CHUNKS (ck0 .. ck8). Each chunk is a group of routines that belong together.
// The compiler records which chunks a program calls (chunks.asm) and a standalone program file
// carries only those, each copied back to its own fixed address when the program starts.
//   ck0 core        stack, load/store, add/sub/neg, setbool, halt  (always present)
//   ck1 arrays      byte variables, array and record element addressing
//   ck2 frames      procedures, functions, local variables
//   ck3 muldiv      multiply, divide, mod
//   ck4 compare     logic operators and integer comparisons
//   ck5 output      printing, write, runtime errors
//   ck6 strings     string routines and comparisons
//   ck7 input       read, readln, Val
//   ck8 crt         Crt unit
ck0:
rt_savesp: .byte 0
rt_tnext:  .byte 0      // number of the string temporary used last
rt_havel:  .byte 0      // 1 while a keyboard line is held in RT_INBUF
rt_inlen:  .byte 0      // number of characters in that line
rt_inpos:  .byte 0      // index of the next unread character
rt_keyext: .byte 0      // second byte of an extended key waiting for ReadKey

// ---- stack ----------------------------------------------------------------
rt_push:                // push ac
    lda ssp
    sec
    sbc #2
    sta ssp
    bcs !+
    dec ssp+1
!:  ldy #0
    lda ac
    sta (ssp),y
    iny
    lda ac+1
    sta (ssp),y
    rts

popt:                   // tmp = pop
    ldy #0
    lda (ssp),y
    sta tmp
    iny
    lda (ssp),y
    sta tmp+1
    clc
    lda ssp
    adc #2
    sta ssp
    bcc !+
    inc ssp+1
!:  rts

// ---- load / store -----------------------------------------------------------
rt_ldi:                 // ac = inline word
    :FETCH()
    lda wd
    sta ac
    lda wd+1
    sta ac+1
    jmp (rp)

rt_ldv:                 // ac = [inline address]
    :FETCH()
    ldy #0
    lda (wd),y
    sta ac
    iny
    lda (wd),y
    sta ac+1
    jmp (rp)

rt_stv:                 // [inline address] = ac
    :FETCH()
    ldy #0
    lda ac
    sta (wd),y
    iny
    lda ac+1
    sta (wd),y
    jmp (rp)

rt_incv:                // [inline address] += 1
    :FETCH()
    ldy #0
    lda (wd),y
    clc
    adc #1
    sta (wd),y
    iny
    lda (wd),y
    adc #0
    sta (wd),y
    jmp (rp)

rt_decv:                // [inline address] -= 1
    :FETCH()
    ldy #0
    lda (wd),y
    sec
    sbc #1
    sta (wd),y
    iny
    lda (wd),y
    sbc #0
    sta (wd),y
    jmp (rp)

rt_jf:                  // jump to inline address if ac == 0
    :FETCH()
    lda ac
    ora ac+1
    bne !+
    lda wd
    sta rp
    lda wd+1
    sta rp+1
!:  jmp (rp)

// ---- arithmetic ---------------------------------------------------------------
rt_add:
    jsr popt
    clc
    lda tmp
    adc ac
    sta ac
    lda tmp+1
    adc ac+1
    sta ac+1
    rts

rt_sub:                 // ac = left - ac
    jsr popt
    sec
    lda tmp
    sbc ac
    sta ac
    lda tmp+1
    sbc ac+1
    sta ac+1
    rts

rt_neg:
    :NEG16(ac)
    rts

setbool:                // ac = carry
    lda #0
    rol
    sta ac
    lda #0
    sta ac+1
    rts

rt_halt:                // return to whoever started the program
    ldx rt_savesp
    txs
    rts

ck1:
// ---- one-byte globals (type byte, absolute variables) -----------------------------------
rt_ldvb:                // ac = zero-extended byte at inline address
    :FETCH()
    ldy #0
    lda (wd),y
    sta ac
    sty ac+1
    jmp (rp)

rt_stvb:                // byte at inline address = low byte of ac
    :FETCH()
    ldy #0
    lda ac
    sta (wd),y
    jmp (rp)

rt_incvb:               // byte at inline address += 1
    :FETCH()
    ldy #0
    lda (wd),y
    clc
    adc #1
    sta (wd),y
    jmp (rp)

rt_decvb:               // byte at inline address -= 1
    :FETCH()
    ldy #0
    lda (wd),y
    sec
    sbc #1
    sta (wd),y
    jmp (rp)

// ---- arrays: element addressing ------------------------------------------------------------
// Indexing leaves the base address on the software stack and the index in ac; the result is the
// element address in ac. The inline word is the array's lowest index.
rt_aidx1:               // element size 1: ac = base + (ac - lo)
    :FETCH()
    jsr popt
    sec
    lda ac
    sbc wd
    sta ac
    lda ac+1
    sbc wd+1
    sta ac+1
    clc
    lda ac
    adc tmp
    sta ac
    lda ac+1
    adc tmp+1
    sta ac+1
    jmp (rp)

rt_aidx2:               // element size 2: ac = base + (ac - lo) * 2
    :FETCH()
    jsr popt
    sec
    lda ac
    sbc wd
    sta ac
    lda ac+1
    sbc wd+1
    sta ac+1
    asl ac
    rol ac+1
    clc
    lda ac
    adc tmp
    sta ac
    lda ac+1
    adc tmp+1
    sta ac+1
    jmp (rp)

rt_aidx:                // any element size: inline words lo, size
    :FETCH4()
    jsr popt
    sec
    lda ac
    sbc wd
    sta ac
    lda ac+1
    sbc wd+1
    sta ac+1
    lda #0              // rem = ac * wd2 (shift and add)
    sta rem
    sta rem+1
    ldx #16
!:  lsr wd2+1
    ror wd2
    bcc !+
    clc
    lda rem
    adc ac
    sta rem
    lda rem+1
    adc ac+1
    sta rem+1
!:  asl ac
    rol ac+1
    dex
    bne !--
    clc
    lda rem
    adc tmp
    sta ac
    lda rem+1
    adc tmp+1
    sta ac+1
    jmp (rp)

rt_addi:                // ac += inline word (field offset inside a record)
    :FETCH()
    clc
    lda ac
    adc wd
    sta ac
    lda ac+1
    adc wd+1
    sta ac+1
    jmp (rp)

rt_ldpw:                // ac = word at address ac
    ldy #0
    lda (ac),y
    tax
    iny
    lda (ac),y
    sta ac+1
    stx ac
    rts

rt_ldpb:                // ac = byte at address ac (zero extended)
    ldy #0
    lda (ac),y
    sta ac
    sty ac+1
    rts

rt_stpw:                // word at the address popped from the stack = ac
    jsr popt
    ldy #0
    lda ac
    sta (tmp),y
    iny
    lda ac+1
    sta (tmp),y
    rts

rt_stpb:                // byte at the address popped from the stack = low byte of ac
    jsr popt
    ldy #0
    lda ac
    sta (tmp),y
    rts

rt_amove:               // copy inline-word bytes from address ac to the address popped from the stack
    :FETCH()
    jsr popt
    ldy #0
!:  lda wd              // finished when the count reaches zero
    ora wd+1
    beq !+
    lda (ac),y
    sta (tmp),y
    inc ac
    bne mv1
    inc ac+1
mv1:
    inc tmp
    bne mv2
    inc tmp+1
mv2:
    lda wd
    bne mv3
    dec wd+1
mv3:
    dec wd
    jmp !-
!:  jmp (rp)

ck2:
// ---- procedures and functions ---------------------------------------------------------
// Frame layout on the software stack (it grows downwards), highest address first:
//     argument 1 ... argument N     pushed by the caller (2 bytes each)
//     return address                pushed by rt_call
//     saved frame pointer           pushed by rt_enter
//     local variables (L bytes)     fp points to the lowest one
// Every local/parameter is addressed as fp + offset (offset is a compile-time constant).
// Return addresses live on the software stack, so recursion depth is limited only by memory.

rt_call:                // call the routine at the inline address
    :FETCH()            // wd = routine, rp = return address
    lda ssp             // push the return address on the software stack
    sec
    sbc #2
    sta ssp
    bcs !+
    dec ssp+1
!:  ldy #0
    lda rp
    sta (ssp),y
    iny
    lda rp+1
    sta (ssp),y
    jmp (wd)

rt_enter:               // procedure prologue, inline byte = L (bytes of locals)
    :FETCH1()
    lda ssp             // push the caller's frame pointer
    sec
    sbc #2
    sta ssp
    bcs !+
    dec ssp+1
!:  ldy #0
    lda fp
    sta (ssp),y
    iny
    lda fp+1
    sta (ssp),y
    sec                 // make room for the locals
    lda ssp
    sbc wd
    sta ssp
    bcs !+
    dec ssp+1
!:  lda ssp             // fp = lowest local
    sta fp
    lda ssp+1
    sta fp+1
    jmp (rp)

rt_leave:               // procedure epilogue, inline bytes = L (locals), A (argument bytes)
    :FETCH()            // wd = L, wd+1 = A
    clc                 // drop the locals: ssp = fp + L
    lda fp
    adc wd
    sta ssp
    lda fp+1
    adc #0
    sta ssp+1
    ldy #0              // restore the caller's frame pointer
    lda (ssp),y
    sta fp
    iny
    lda (ssp),y
    sta fp+1
    iny                 // fetch the return address
    lda (ssp),y
    sta rp
    iny
    lda (ssp),y
    sta rp+1
    lda wd+1            // drop saved fp, return address and arguments
    clc
    adc #4
    adc ssp
    sta ssp
    bcc !+
    inc ssp+1
!:  jmp (rp)

rt_ldl:                 // ac = local at fp + inline offset
    :FETCH1()
    ldy wd
    lda (fp),y
    sta ac
    iny
    lda (fp),y
    sta ac+1
    jmp (rp)

rt_stl:                 // local at fp + inline offset = ac
    :FETCH1()
    ldy wd
    lda ac
    sta (fp),y
    iny
    lda ac+1
    sta (fp),y
    jmp (rp)

rt_ldlp:                // ac = [pointer stored in local]   (read a var parameter)
    :FETCH1()
    ldy wd
    lda (fp),y
    sta tmp
    iny
    lda (fp),y
    sta tmp+1
    ldy #0
    lda (tmp),y
    sta ac
    iny
    lda (tmp),y
    sta ac+1
    jmp (rp)

rt_stlp:                // [pointer stored in local] = ac   (write a var parameter)
    :FETCH1()
    ldy wd
    lda (fp),y
    sta tmp
    iny
    lda (fp),y
    sta tmp+1
    ldy #0
    lda ac
    sta (tmp),y
    iny
    lda ac+1
    sta (tmp),y
    jmp (rp)

rt_lea:                 // ac = address of local (fp + inline offset)
    :FETCH1()
    clc
    lda fp
    adc wd
    sta ac
    lda fp+1
    adc #0
    sta ac+1
    jmp (rp)

rt_incl:                // local += 1
    :FETCH1()
    ldy wd
    lda (fp),y
    clc
    adc #1
    sta (fp),y
    iny
    lda (fp),y
    adc #0
    sta (fp),y
    jmp (rp)

rt_decl:                // local -= 1
    :FETCH1()
    ldy wd
    lda (fp),y
    sec
    sbc #1
    sta (fp),y
    iny
    lda (fp),y
    sbc #0
    sta (fp),y
    jmp (rp)

rt_peek1:               // ac = the top word of the software stack (not removed)
    ldy #0
    lda (ssp),y
    sta ac
    iny
    lda (ssp),y
    sta ac+1
    rts

rt_peek2:               // ac = second word on the software stack (the one below the top)
    ldy #2
    lda (ssp),y
    sta ac
    iny
    lda (ssp),y
    sta ac+1
    rts

rt_drop:                // discard the top word of the software stack
    clc
    lda ssp
    adc #2
    sta ssp
    bcc !+
    inc ssp+1
!:  rts

ck3:
rt_mul:                 // ac = left * ac (low 16 bits, valid for signed)
    jsr popt
    lda #0
    sta rem
    sta rem+1
    ldx #16
!:  lsr tmp+1
    ror tmp
    bcc !+
    clc
    lda rem
    adc ac
    sta rem
    lda rem+1
    adc ac+1
    sta rem+1
!:  asl ac
    rol ac+1
    dex
    bne !--
    lda rem
    sta ac
    lda rem+1
    sta ac+1
    rts

// signed divide core: tmp = |left| / |ac| quotient, rem = remainder; s1/s2 = sign flags
divcore:
    jsr popt
    lda ac
    ora ac+1
    bne !+
    lda #1              // division by zero
    jmp rt_err
!:  lda tmp+1
    and #$80
    sta s1
    beq !+
    :NEG16(tmp)
!:  lda ac+1
    and #$80
    sta s2
    beq !+
    :NEG16(ac)
!:  lda #0
    sta rem
    sta rem+1
    ldx #16
dvl1:
    asl tmp
    rol tmp+1
    rol rem
    rol rem+1
    sec
    lda rem
    sbc ac
    tay
    lda rem+1
    sbc ac+1
    bcc dvl2
    sta rem+1
    sty rem
    inc tmp
dvl2:
    dex
    bne dvl1
    rts

rt_div:
    jsr divcore
    lda tmp
    sta ac
    lda tmp+1
    sta ac+1
    lda s1
    eor s2
    beq !+
    :NEG16(ac)
!:  rts

rt_mod:
    jsr divcore
    lda rem
    sta ac
    lda rem+1
    sta ac+1
    lda s1
    beq !+
    :NEG16(ac)
!:  rts

ck4:
// ---- logic ----------------------------------------------------------------------
rt_and:
    jsr popt
    lda tmp
    and ac
    sta ac
    lda tmp+1
    and ac+1
    sta ac+1
    rts

rt_or:
    jsr popt
    lda tmp
    ora ac
    sta ac
    lda tmp+1
    ora ac+1
    sta ac+1
    rts

rt_xor:
    jsr popt
    lda tmp
    eor ac
    sta ac
    lda tmp+1
    eor ac+1
    sta ac+1
    rts

rt_not:                 // bitwise complement (integer)
    lda ac
    eor #$ff
    sta ac
    lda ac+1
    eor #$ff
    sta ac+1
    rts

rt_abs:                 // ac = |ac|
    lda ac+1
    bpl !+
    :NEG16(ac)
!:  rts

rt_bnot:                // boolean not
    lda ac
    ora ac+1
    beq !+
    lda #0
    sta ac
    sta ac+1
    rts
!:  lda #1
    sta ac
    lda #0
    sta ac+1
    rts

// ---- comparisons (tmp = left, ac = right) -----------------------------------------
slt:                    // carry set if tmp < ac (signed)
    lda tmp
    cmp ac
    lda tmp+1
    sbc ac+1
    bvc !+
    eor #$80
!:  asl
    rts

swapta:
    ldx #1
!:  lda tmp,x
    ldy ac,x
    sta ac,x
    sty tmp,x
    dex
    bpl !-
    rts

rt_lt:
    jsr popt
    jsr slt
    jmp setbool

rt_gt:
    jsr popt
    jsr swapta
    jsr slt
    jmp setbool

rt_ge:                  // not (left < right)
    jsr popt
    jsr slt
    bcs ltrue
    sec
    jmp setbool
ltrue:
    clc
    jmp setbool

rt_le:                  // not (left > right)
    jsr popt
    jsr swapta
    jsr slt
    bcs ltrue
    sec
    jmp setbool

rt_eq:
    jsr popt
    lda tmp
    cmp ac
    bne isne
    lda tmp+1
    cmp ac+1
    bne isne
    sec
    jmp setbool
isne:
    clc
    jmp setbool

rt_ne:
    jsr popt
    lda tmp
    cmp ac
    bne !+
    lda tmp+1
    cmp ac+1
    bne !+
    clc
    jmp setbool
!:  sec
    jmp setbool

ck5:
// ---- output -------------------------------------------------------------------------
putc:                   // print ASCII char in A (converted to PETSCII)
    cmp #$41
    bcc pc_out
    cmp #$5b
    bcc pc_up
    cmp #$61
    bcc pc_out
    cmp #$7b
    bcs pc_out
    sec
    sbc #$20            // a-z -> $41-$5A (lowercase in the mixed charset)
    jmp pc_out
pc_up:
    ora #$80            // A-Z -> $C1-$DA
pc_out:
    jmp $ffd2

rt_wch:
    lda ac
    jmp putc

rt_wln:
    lda #13
    jmp putc

div10:                  // ac = ac / 10, A = remainder
    lda #0
    sta rem
    ldy #16
!:  asl ac
    rol ac+1
    rol rem
    lda rem
    sec
    sbc #10
    bcc !+
    sta rem
    inc ac
!:  dey
    bne !--
    lda rem
    rts

rt_wint:                // print ac as signed decimal
    lda ac+1
    bpl !+
    lda #'-'
    jsr putc
    :NEG16(ac)
!:  ldx #0
!:  jsr div10
    pha
    inx
    lda ac
    ora ac+1
    bne !-
!:  pla
    ora #'0'
    jsr putc
    dex
    bne !-
    rts

rt_wbool:
    lda ac
    ora ac+1
    beq !+
    lda #<s_true
    ldx #>s_true
    jmp puts
!:  lda #<s_false
    ldx #>s_false
puts:                   // print 0-terminated string at X:A
    sta tmp
    stx tmp+1
    ldy #0
!:  lda (tmp),y
    beq !+
    jsr putc
    iny
    bne !-
!:  rts

rt_wlit:                // inline string: length byte + chars
    pla
    sta rp
    pla
    sta rp+1
    ldy #1
    lda (rp),y
    sta wd              // length
    tax
    beq wl_done
!:  iny
    lda (rp),y
    jsr putc
    dex
    bne !-
wl_done:
    lda wd
    clc
    adc #2
    adc rp
    sta rp
    bcc !+
    inc rp+1
!:  jmp (rp)

// ---- termination --------------------------------------------------------------------
rt_err:                 // A = error number
    pha
    lda #13
    jsr putc
    lda #<s_rterr
    ldx #>s_rterr
    jsr puts
    pla
    clc
    adc #'0'
    jsr putc
    lda #13
    jsr putc
    jmp rt_halt

s_true:  .text "TRUE"
         .byte 0
s_false: .text "FALSE"
         .byte 0
s_rterr: .text "RUNTIME ERROR "
         .byte 0

ck6:
// ---- strings (separate file) ---------------------------------------------------------
.import source "rt_strings.asm"

ck7:
// ---- keyboard input, read/readln/Val (separate file) --------------------------------
.import source "rt_input.asm"

ck8:
// ---- Crt unit (separate file) -----------------------------------------------------
.import source "rt_crt.asm"

ck9:
rt_end:
}
.label RT_SIZE = rt_end - rt_start
.assert "runtime must fit its 4 KB block", RT_SIZE <= $1000, true

