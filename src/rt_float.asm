// This file is in the public domain: use it, change it, share it, sell it - do whatever you like with it.
// No permission, credit or payment needed. It comes as it is, with no warranty. Enjoy!
// Note: this has only been tested in the VICE emulator, never on real hardware.
// =====================================================================================
// rt_float.asm - floating point: the type real (extension chunk 10, included inside runtime.asm)
// =====================================================================================
//
// A real is a 4 byte number, the same format in memory and on the software stack:
//     byte 0     exponent, biased by 128 (0 = the value zero)
//     byte 1     bit 7 = sign, bits 6..0 = the top bits of the mantissa (the leading 1 is not stored)
//     byte 2, 3  the rest of the 24 bit mantissa
//   value = (-1)^sign * 0.1mmmm... (binary) * 2^(exponent - 128)        about 7 decimal digits, 1E-38 .. 1E38
// While it is calculated with, a number is UNPACKED (the leading 1 is explicit) in a register:
//     FAC  (facx, facs, fm0..fm2)   the float accumulator: result of every real expression
//     ARG  (arx,  ars,  am0..am2)   the second operand: the left operand of a binary operator is popped into it
//   facx/arx = exponent (0 = zero), facs/ars = $00 or $80, fm0..fm2 = mantissa, bit 7 of fm0 set unless zero.
//   Zero always has sign 0 and mantissa 0.
// Binary operators compute FAC = ARG <op> FAC, so  a - b  is: a in ARG, b in FAC.
//
// Generated code (compiler: expr.asm, realop.asm):
//     left operand ... rt_fpush (real) or rt_push (integer)       right operand ... (in FAC, or ac)
//     [rt_i2f]  rt_fpop / rt_fpopi   rt_fadd / rt_fsub / rt_fmul / rt_fdiv / rt_feq ... rt_fge
// Integers are converted with rt_i2f (ac -> FAC) wherever a real is needed.
//
// Every result goes through f_pack: the result is a 32 bit number N (fn3 = most significant byte), a 16 bit
// exponent fex and a sign fsg, meaning  value = N / 2^32 * 2^(fex - 128).  f_pack normalises it (the top
// bit of N becomes 1), rounds to 24 bits and stores it in FAC; underflow gives zero, overflow runtime error 5.

.macro FLT(v) {                 // assembles the packed 4 byte representation of the number v
    .var a = abs(v)
    .if (a == 0) {
        .byte 0, 0, 0, 0
    } else {
        .var e = floor(log(a) / log(2)) + 1
        .var m = a / pow(2, e)
        .if (m >= 1) {
            .eval m = m / 2
            .eval e = e + 1
        }
        .if (m < 0.5) {
            .eval m = m * 2
            .eval e = e - 1
        }
        .var mi = round(m * 16777216)
        .if (mi >= 16777216) {
            .eval mi = 8388608
            .eval e = e + 1
        }
        .byte e + 128
        .byte ((mi >> 16) & $7f) | (v < 0 ? $80 : 0)
        .byte (mi >> 8) & $ff
        .byte mi & $ff
    }
}

.macro WFLT(v) {                // 5 bytes: exponent (biased 128) and a 32 bit mantissa (top bit set), most significant first
    .var a = abs(v)
    .var e = floor(log(a) / log(2)) + 1
    .var m = a / pow(2, e)
    .if (m >= 1) {
        .eval m = m / 2
        .eval e = e + 1
    }
    .if (m < 0.5) {
        .eval m = m * 2
        .eval e = e - 1
    }
    .var mi = round(m * 4294967296)
    .if (mi >= 4294967296) {
        .eval mi = 2147483648
        .eval e = e + 1
    }
    .byte e + 128
    .byte (mi >> 24) & $ff
    .byte (mi >> 16) & $ff
    .byte (mi >> 8) & $ff
    .byte mi & $ff
}

.macro LDPTR(a) {               // tmp = address of a float constant / variable
    lda #<a
    sta tmp
    lda #>a
    sta tmp+1
}

.macro LDARGC(a) {              // ARG = the float at address a
    :LDPTR(a)
    jsr f_ldarg
}

.macro FHORN(a, n) {            // FAC = polynomial in f_t3 with the n coefficients at a (highest power first)
    lda #<a
    sta fhp
    lda #>a
    sta fhp+1
    lda #n
    sta fhn
    jsr f_horner
}

// ---- registers ------------------------------------------------------------------------------------
facx:   .byte 0                 // FAC and ARG must stay in this order (f_swap, f_arg2fac index them together)
facs:   .byte 0
fm0:    .byte 0
fm1:    .byte 0
fm2:    .byte 0
arx:    .byte 0
ars:    .byte 0
am0:    .byte 0
am1:    .byte 0
am2:    .byte 0
fn0:    .byte 0                 // the 32 bit number f_pack works on (fn3 = most significant)
fn1:    .byte 0
fn2:    .byte 0
fn3:    .byte 0
fex:    .word 0                 // its exponent
fsg:    .byte 0                 // its sign
ft0:    .byte 0                 // scratch (second 32 bit number, product)
ft1:    .byte 0
ft2:    .byte 0
ft3:    .byte 0
ph0:    .byte 0                 // product: ph0..ph2 high half, pl0..pl2 low half (ph0 most significant)
ph1:    .byte 0
ph2:    .byte 0
pl0:    .byte 0
pl1:    .byte 0
pl2:    .byte 0
dr0:    .byte 0                 // remainder of the division (3 bytes) and its carry
dr1:    .byte 0
dr2:    .byte 0
fcy:    .byte 0
fdiff:  .byte 0                 // exponent difference of an addition
f_t1:   .fill 4, 0              // temporaries (packed floats) of the maths routines
f_t2:   .fill 4, 0
f_t3:   .fill 4, 0
fhp:    .word 0                 // polynomial coefficients being read
fhn:    .byte 0                 // coefficients left
fit:    .byte 0                 // iteration counter
fn_n:   .word 0                 // integer part of x/ln2 or x/(pi/2)
fq_off: .byte 0
fq_q:   .byte 0
fln_e:  .word 0                 // binary exponent of the argument of Ln
fat_s:  .byte 0                 // Arctan: sign, reciprocal used, reduced by pi/4
fat_inv: .byte 0
fat_add: .byte 0
flen:   .byte 0                 // length of the text being converted to a number
fused:  .byte 0                 // characters used by it
fi0:    .byte 0                 // integer of the decimal digits read
fi1:    .byte 0
fi2:    .byte 0
fi3:    .byte 0
fdot:   .byte 0                 // a decimal point has been seen
fdp:    .byte 0                 // decimal exponent correction (signed)
fexv:   .byte 0                 // exponent after E
fexn:   .byte 0                 // ... is negative
fdg:    .byte 0                 // digit
ftmp:   .byte 0
fti:    .byte 0                 // index into the powers of ten
fkabs:  .byte 0
fkneg:  .byte 0
fwid:   .byte 0                 // output: field width, decimals ($ff = none), sign, ...
fdec:   .byte 0
fneg:   .byte 0
fsc:    .byte 0
fnz:    .byte 0
ftot:   .byte 0
fix:    .byte 0
fnd:    .byte 0                 // number of digits in fdbuf
fd10:   .byte 0                 // decimal exponent of the number being printed
fv:     .word 0
fpl:    .word 0
fdbuf:   .fill 12, 0             // decimal digits, least significant first
frm:    .byte 0
wcx:    .byte 0                 // constant being multiplied in f_wmul: exponent, mantissa (wc3 = most significant)
wc3:    .byte 0
wc2:    .byte 0
wc1:    .byte 0
wc0:    .byte 0
rh3:    .byte 0                 // 64 bit product of f_wmul: rh = high half, rl = low half
rh2:    .byte 0
rh1:    .byte 0
rh0:    .byte 0
rl3:    .byte 0
rl2:    .byte 0
rl1:    .byte 0
rl0:    .byte 0
fsl:    .word 0                 // shift count of f_wto32
fsmode: .byte 0                 // 1: f_put appends to a string (Str) instead of printing
fsmax:  .byte 0                 // maximum length of that string

// ---- constants ------------------------------------------------------------------------------------
c_log2e: :FLT(1.4426950408889634)
c_ln2:   :FLT(0.6931471805599453)
c_2opi:  :FLT(0.6366197723675814)
c_pio2:  :FLT(1.5707963267948966)
c_pio4:  :FLT(0.7853981633974483)
c_pi:    :FLT(3.141592653589793)
c_tan8:  :FLT(0.41421356237309503)
// powers of ten with 32 bit mantissas, for scaling numbers with more precision than a real has (f_wscale):
// 10^1, 10^2, 10^4, 10^8, 10^16, 10^32, then 10^-1 ... 10^-32 (5 bytes each)
f_wpos:  :WFLT(10)
         :WFLT(100)
         :WFLT(10000)
         :WFLT(100000000)
         :WFLT(pow(10,16))
         :WFLT(pow(10,32))
f_wneg:  :WFLT(pow(10,-1))
         :WFLT(pow(10,-2))
         :WFLT(pow(10,-4))
         :WFLT(pow(10,-8))
         :WFLT(pow(10,-16))
         :WFLT(pow(10,-32))
c_exp:   :FLT(1/40320)          // e^r = sum r^k / k!   (highest power first)
         :FLT(1/5040)
         :FLT(1/720)
         :FLT(1/120)
         :FLT(1/24)
         :FLT(1/6)
         :FLT(1/2)
         :FLT(1)
         :FLT(1)
c_ln:    :FLT(1/9)              // ln m = 2 z (1 + z^2/3 + z^4/5 + ...),  z = (m-1)/(m+1)
         :FLT(1/7)
         :FLT(1/5)
         :FLT(1/3)
         :FLT(1)
c_sin:   :FLT(1/362880)         // sin r = r (1 - w/6 + w^2/120 ...),  w = r^2
         :FLT(-1/5040)
         :FLT(1/120)
         :FLT(-1/6)
         :FLT(1)
c_cos:   :FLT(1/40320)          // cos r = 1 - w/2 + w^2/24 ...
         :FLT(-1/720)
         :FLT(1/24)
         :FLT(-1/2)
         :FLT(1)
c_atan:  :FLT(1/17)             // atan t = t (1 - w/3 + w^2/5 ...),  w = t^2
         :FLT(-1/15)
         :FLT(1/13)
         :FLT(-1/11)
         :FLT(1/9)
         :FLT(-1/7)
         :FLT(1/5)
         :FLT(-1/3)
         :FLT(1)

// ---- packing, loading and storing ---------------------------------------------------------------------
// f_pack: fn3..fn0, fex, fsg -> FAC (see the header)
f_pack:
    lda fn3
    ora fn2
    ora fn1
    ora fn0
    bne fp_nz
    jmp f_zero
fp_nz:
fp_bytes:                       // the top byte is empty: shift by whole bytes
    lda fn3
    bne fp_bits
    lda fn2
    sta fn3
    lda fn1
    sta fn2
    lda fn0
    sta fn1
    lda #0
    sta fn0
    sec
    lda fex
    sbc #8
    sta fex
    lda fex+1
    sbc #0
    sta fex+1
    jmp fp_bytes
fp_bits:
    lda fn3
    bmi fp_round                // bit 7 set: normalised
    asl fn0
    rol fn1
    rol fn2
    rol fn3
    lda fex
    bne !+
    dec fex+1
!:  dec fex
    jmp fp_bits
fp_round:
    lda fn0                     // round to nearest with the next bit
    bpl fp_range
    inc fn1
    bne fp_range
    inc fn2
    bne fp_range
    inc fn3
    bne fp_range
    lda #$80                    // the mantissa overflowed: 1.0 * 2^1
    sta fn3
    inc fex
    bne fp_range
    inc fex+1
fp_range:
    lda fex+1
    bmi f_zero                  // exponent below 0: underflow
    bne f_overflow              // 256 or more
    lda fex
    beq f_zero
    sta facx
    lda fsg
    sta facs
    lda fn3
    sta fm0
    lda fn2
    sta fm1
    lda fn1
    sta fm2
    rts
f_zero:                         // FAC = 0
    lda #0
    sta facx
    sta facs
    sta fm0
    sta fm1
    sta fm2
    rts
f_overflow:
    lda #5                      // runtime error 5: floating point overflow
    jmp rt_err

f_ldfac:                        // FAC = the float at (tmp)
    ldy #0
    lda (tmp),y
    sta facx
    beq f_zero
    iny
    lda (tmp),y
    tax
    and #$80
    sta facs
    txa
    ora #$80
    sta fm0
    iny
    lda (tmp),y
    sta fm1
    iny
    lda (tmp),y
    sta fm2
    rts

f_ldarg:                        // ARG = the float at (tmp)
    ldy #0
    lda (tmp),y
    sta arx
    bne !+
    sta ars
    sta am0
    sta am1
    sta am2
    rts
!:  iny
    lda (tmp),y
    tax
    and #$80
    sta ars
    txa
    ora #$80
    sta am0
    iny
    lda (tmp),y
    sta am1
    iny
    lda (tmp),y
    sta am2
    rts

f_stfac:                        // the float at (tmp) = FAC
    ldy #0
    lda facx
    sta (tmp),y
    iny
    lda fm0
    and #$7f
    ora facs
    sta (tmp),y
    iny
    lda fm1
    sta (tmp),y
    iny
    lda fm2
    sta (tmp),y
    rts

f_swap:                         // FAC <-> ARG
    ldx #4
!:  lda facx,x
    pha
    lda arx,x
    sta facx,x
    pla
    sta arx,x
    dex
    bpl !-
    rts

f_arg2fac:                      // FAC = ARG
    ldx #4
!:  lda arx,x
    sta facx,x
    dex
    bpl !-
    rts

f_fac2arg:                      // ARG = FAC
    ldx #4
!:  lda facx,x
    sta arx,x
    dex
    bpl !-
    rts

f_one:                          // FAC = 1
    lda #129
    sta facx
    lda #$80
    sta fm0
    lda #0
    sta facs
    sta fm1
    sta fm2
    rts

// ---- the interface of the generated code --------------------------------------------------------------
rt_fpush:                       // push FAC (4 bytes) on the software stack
    lda ssp
    sec
    sbc #4
    sta ssp
    bcs !+
    dec ssp+1
!:  lda ssp
    sta tmp
    lda ssp+1
    sta tmp+1
    jmp f_stfac

rt_fpop:                        // ARG = the real on the software stack (removed)
    lda ssp
    sta tmp
    lda ssp+1
    sta tmp+1
    jsr f_ldarg
    clc
    lda ssp
    adc #4
    sta ssp
    bcc !+
    inc ssp+1
!:  rts

rt_fpopi:                       // ARG = the INTEGER on the software stack (removed), converted; FAC is kept
    jsr popt
    jsr f_swap                  // FAC -> ARG for a moment
    lda tmp
    sta ac
    lda tmp+1
    sta ac+1
    jsr rt_i2f                  // FAC = the integer
    jmp f_swap                  // ARG = the integer, FAC = the right operand again

rt_i2f:                         // FAC = the integer in ac
    lda #0
    sta fsg
    sta fn0
    sta fn1
    lda ac
    sta fn2
    lda ac+1
    sta fn3
    bpl !+
    lda #$80
    sta fsg
    sec                         // magnitude
    lda #0
    sbc fn2
    sta fn2
    lda #0
    sbc fn3
    sta fn3
!:  lda #144                    // |n| * 2^16 / 2^32 * 2^(144-128) = |n|
    sta fex
    lda #0
    sta fex+1
    jmp f_pack

rt_fneg:
    lda facx
    beq !+
    lda facs
    eor #$80
    sta facs
!:  rts

rt_fabs:
    lda #0
    sta facs
    rts

rt_fsqr:                        // FAC = FAC * FAC
    jsr f_fac2arg
    jmp rt_fmul

// ---- load and store ----------------------------------------------------------------------------------------
rt_fldv:                        // FAC = the real at the inline address
    :FETCH()
    lda wd
    sta tmp
    lda wd+1
    sta tmp+1
    jsr f_ldfac
    jmp (rp)

rt_fstv:                        // the real at the inline address = FAC
    :FETCH()
    lda wd
    sta tmp
    lda wd+1
    sta tmp+1
    jsr f_stfac
    jmp (rp)

rt_fldl:                        // FAC = the real in the frame at fp + inline offset
    :FETCH1()
    clc
    lda fp
    adc wd
    sta tmp
    lda fp+1
    adc #0
    sta tmp+1
    jsr f_ldfac
    jmp (rp)

rt_fstl:                        // the real in the frame = FAC
    :FETCH1()
    clc
    lda fp
    adc wd
    sta tmp
    lda fp+1
    adc #0
    sta tmp+1
    jsr f_stfac
    jmp (rp)

rt_fldlp:                       // FAC = the real that the pointer in the frame cell points to (var parameter)
    :FETCH1()
    ldy wd
    lda (fp),y
    sta tmp
    iny
    lda (fp),y
    sta tmp+1
    jsr f_ldfac
    jmp (rp)

rt_fstlp:                       // that real = FAC
    :FETCH1()
    ldy wd
    lda (fp),y
    sta tmp
    iny
    lda (fp),y
    sta tmp+1
    jsr f_stfac
    jmp (rp)

rt_fldp:                        // FAC = the real at the address in ac
    lda ac
    sta tmp
    lda ac+1
    sta tmp+1
    jmp f_ldfac

rt_fstp:                        // the real at the address popped from the stack = FAC
    jsr popt
    jmp f_stfac

rt_fli:                         // FAC = the number whose text follows the call: length byte + characters
    pla
    sta rp
    pla
    sta rp+1
    ldy #1
    lda (rp),y
    sta flen
    clc                         // tmp -> the characters
    lda rp
    adc #2
    sta tmp
    lda rp+1
    adc #0
    sta tmp+1
    clc                         // rp = the address after the text
    lda tmp
    adc flen
    sta rp
    lda tmp+1
    adc #0
    sta rp+1
    jsr f_atof
    jmp (rp)

rt_flit:                        // FAC = the number whose text (length byte + characters) is at the inline address
    :FETCH()
    ldy #0
    lda (wd),y
    sta flen
    clc
    lda wd
    adc #1
    sta tmp
    lda wd+1
    adc #0
    sta tmp+1
    jsr f_atof
    jmp (rp)

// ---- addition and subtraction ------------------------------------------------------------------------------
rt_fsub:                        // FAC = ARG - FAC
    jsr rt_fneg
rt_fadd:                        // FAC = ARG + FAC
    lda arx
    beq fa_ret                  // adding zero
    lda facx
    bne fa_both
    jmp f_arg2fac               // FAC is zero: the sum is ARG
fa_ret:
    rts
fa_both:
    lda arx                     // ARG gets the larger exponent
    cmp facx
    bcs fa_ordered
    jsr f_swap
fa_ordered:
    sec
    lda arx
    sbc facx
    sta fdiff
    cmp #25
    bcc fa_align
    jmp f_arg2fac               // FAC is too small to matter
fa_align:
    lda am0                     // fn = ARG mantissa with a guard byte
    sta fn3
    lda am1
    sta fn2
    lda am2
    sta fn1
    lda #0
    sta fn0
    lda fm0                     // ft = FAC mantissa shifted right by the difference
    sta ft3
    lda fm1
    sta ft2
    lda fm2
    sta ft1
    lda #0
    sta ft0
    ldx fdiff
    beq fa_shifted
fa_shift:
    lsr ft3
    ror ft2
    ror ft1
    ror ft0
    dex
    bne fa_shift
fa_shifted:
    lda arx
    sta fex
    lda #0
    sta fex+1
    lda ars
    eor facs
    bmi fa_sub
    lda ars                     // same sign: add the magnitudes
    sta fsg
    clc
    lda fn0
    adc ft0
    sta fn0
    lda fn1
    adc ft1
    sta fn1
    lda fn2
    adc ft2
    sta fn2
    lda fn3
    adc ft3
    sta fn3
    bcc fa_done
    ror fn3                     // carry out: shift it back in
    ror fn2
    ror fn1
    ror fn0
    inc fex
fa_done:
    jmp f_pack
fa_sub:                         // different signs: larger magnitude minus the smaller
    lda fn3
    cmp ft3
    bne fa_cmpd
    lda fn2
    cmp ft2
    bne fa_cmpd
    lda fn1
    cmp ft1
    bne fa_cmpd
    lda fn0
    cmp ft0
fa_cmpd:
    bcc fa_second
    lda ars                     // |ARG| >= |FAC|
    sta fsg
    sec
    lda fn0
    sbc ft0
    sta fn0
    lda fn1
    sbc ft1
    sta fn1
    lda fn2
    sbc ft2
    sta fn2
    lda fn3
    sbc ft3
    sta fn3
    jmp f_pack
fa_second:                      // |ARG| < |FAC|
    lda facs
    sta fsg
    sec
    lda ft0
    sbc fn0
    sta fn0
    lda ft1
    sbc fn1
    sta fn1
    lda ft2
    sbc fn2
    sta fn2
    lda ft3
    sbc fn3
    sta fn3
    jmp f_pack

// ---- multiplication ---------------------------------------------------------------------------------------------
rt_fmul:                        // FAC = ARG * FAC
    lda arx
    bne fm_a
    jmp f_zero
fm_a:
    lda facx
    bne fm_b
    rts                         // FAC is zero: the product is zero
fm_b:
    lda ars
    eor facs
    sta fsg
    clc                         // exponent = arx + facx - 128
    lda arx
    adc facx
    sta fex
    lda #0
    adc #0
    sta fex+1
    sec
    lda fex
    sbc #128
    sta fex
    lda fex+1
    sbc #0
    sta fex+1
    lda #0                      // 48 bit product: high half 0, low half = the multiplier (FAC mantissa)
    sta ph0
    sta ph1
    sta ph2
    lda fm0
    sta pl0
    lda fm1
    sta pl1
    lda fm2
    sta pl2
    ldx #24
fm_loop:
    lda pl2                     // lowest multiplier bit
    lsr
    bcc fm_shift                // 0: nothing to add (carry is clear)
    clc
    lda ph2
    adc am2
    sta ph2
    lda ph1
    adc am1
    sta ph1
    lda ph0
    adc am0
    sta ph0
fm_shift:
    ror ph0                     // shift the whole 48 bits right (the carry comes in at the top)
    ror ph1
    ror ph2
    ror pl0
    ror pl1
    ror pl2
    dex
    bne fm_loop
    lda ph0                     // the top 32 bits of the product
    sta fn3
    lda ph1
    sta fn2
    lda ph2
    sta fn1
    lda pl0
    sta fn0
    jmp f_pack

// ---- division -----------------------------------------------------------------------------------------------------
rt_fdiv:                        // FAC = ARG / FAC
    lda facx
    bne fd_ok
    lda #1                      // runtime error 1: division by zero
    jmp rt_err
fd_ok:
    lda arx
    bne fd_a
    jmp f_zero
fd_a:
    lda ars
    eor facs
    sta fsg
    sec                         // exponent = arx - facx + 135
    lda arx
    sbc facx
    sta fex
    lda #0
    sbc #0
    sta fex+1
    clc
    lda fex
    adc #135
    sta fex
    lda fex+1
    adc #0
    sta fex+1
    lda am0                     // remainder = the mantissa of ARG, the divisor is the mantissa of FAC
    sta dr0
    lda am1
    sta dr1
    lda am2
    sta dr2
    lda #0
    sta fn0
    sta fn1
    sta fn2
    sta fn3
    sta fcy
    ldx #26                     // 26 quotient bits: 24 for the mantissa, a rounding bit and the integer bit
fd_loop:
    asl fn0                     // quotient <<= 1
    rol fn1
    rol fn2
    rol fn3
    lda fcy                     // the remainder overflowed 24 bits: it is certainly >= the divisor
    bne fd_sub
    lda dr0
    cmp fm0
    bne fd_cmp
    lda dr1
    cmp fm1
    bne fd_cmp
    lda dr2
    cmp fm2
fd_cmp:
    bcc fd_nosub
fd_sub:
    sec
    lda dr2
    sbc fm2
    sta dr2
    lda dr1
    sbc fm1
    sta dr1
    lda dr0
    sbc fm0
    sta dr0
    inc fn0                     // quotient bit = 1
fd_nosub:
    lda #0
    sta fcy
    asl dr2                     // remainder <<= 1
    rol dr1
    rol dr0
    rol fcy
    dex
    bne fd_loop
    jmp f_pack

// ---- comparison ---------------------------------------------------------------------------------------------------
f_cmp:                          // compare ARG with FAC: A = 0 equal, 1 ARG > FAC, $ff ARG < FAC (flags set)
    lda ars
    cmp facs
    beq fc_same
    lda ars                     // different signs: the positive one is greater
    bmi fc_less
    lda #1
    rts
fc_less:
    lda #$ff
    rts
fc_same:
    lda arx                     // same sign: compare exponent and mantissa
    cmp facx
    bne fc_d
    lda am0
    cmp fm0
    bne fc_d
    lda am1
    cmp fm1
    bne fc_d
    lda am2
    cmp fm2
    bne fc_d
    lda #0
    rts
fc_d:
    bcc fc_ml
    lda #1                      // |ARG| > |FAC|
    bne fc_sg
fc_ml:
    lda #$ff
fc_sg:
    ldx ars                     // both negative: reverse
    beq fc_ret
    eor #$fe                    // 1 <-> $ff
fc_ret:
    rts

rt_feq:
    jsr f_cmp
    cmp #0
    beq f_true
    bne f_false
rt_fne:
    jsr f_cmp
    cmp #0
    bne f_true
    beq f_false
rt_flt:
    jsr f_cmp
    cmp #$ff
    beq f_true
    bne f_false
rt_fgt:
    jsr f_cmp
    cmp #1
    beq f_true
    bne f_false
rt_fle:
    jsr f_cmp
    cmp #1
    bne f_true
    beq f_false
rt_fge:
    jsr f_cmp
    cmp #$ff
    bne f_true
f_false:
    clc
    jmp setbool
f_true:
    sec
    jmp setbool

// ---- conversion to integer ------------------------------------------------------------------------------------------
rt_ftrunc:                      // ac = FAC with the fraction removed (runtime error 5 if it does not fit)
    lda facx
    cmp #129
    bcc ftr_zero                // |x| < 1
    cmp #144
    bcs ftr_ovf                 // |x| >= 32768
    sec
    lda #144
    sbc facx
    tax                         // shift right by 144 - exponent
    lda fm0
    sta ac+1
    lda fm1
    sta ac
!:  lsr ac+1
    ror ac
    dex
    bne !-
    lda facs
    bpl !+
    :NEG16(ac)
!:  rts
ftr_zero:
    lda #0
    sta ac
    sta ac+1
    rts
ftr_ovf:
    lda #5
    jmp rt_err

rt_fround:                      // ac = FAC rounded to the nearest integer (halves away from zero)
    lda #128                    // ARG = 0.5 with the sign of FAC
    sta arx
    lda #$80
    sta am0
    lda #0
    sta am1
    sta am2
    lda facs
    sta ars
    jsr rt_fadd
    jmp rt_ftrunc

rt_fint:                        // FAC = the integer part of FAC (as a real)
    lda facx
    cmp #129
    bcs !+
    jmp f_zero                  // |x| < 1
!:  cmp #152
    bcs fi_done                 // no fraction bits left
    sec
    lda #152
    sbc facx
    tax                         // number of fraction bits (1..23)
    ldy #2
fi_b:
    cpx #8
    bcc fi_p
    lda #0
    sta fm0,y
    dey
    txa
    sec
    sbc #8
    tax
    jmp fi_b
fi_p:
    cpx #0
    beq fi_done
    lda #$ff
fi_m:
    asl
    dex
    bne fi_m
    and fm0,y
    sta fm0,y
fi_done:
    rts

rt_ffrac:                       // FAC = FAC - Int(FAC)
    :LDPTR(f_t1)
    jsr f_stfac
    jsr rt_fint
    jsr rt_fneg
    :LDARGC(f_t1)
    jmp rt_fadd

rt_fpi:
    :LDPTR(c_pi)
    jmp f_ldfac

// ---- square root (Newton) ----------------------------------------------------------------------------------------------
rt_fsqrt:
    lda facx
    beq fsq_ret
    lda facs
    bmi fsq_err
    :LDPTR(f_t1)
    jsr f_stfac                 // x
    lda facx                    // first guess: 2 to the power of half the exponent
    lsr
    adc #64
    sta facx
    lda #$80
    sta fm0
    lda #0
    sta fm1
    sta fm2
    lda #5
    sta fit
fsq_it:
    :LDPTR(f_t2)
    jsr f_stfac                 // y
    :LDARGC(f_t1)
    jsr rt_fdiv                 // x / y
    :LDARGC(f_t2)
    jsr rt_fadd                 // y + x / y
    dec facx                    // half of it
    dec fit
    bne fsq_it
fsq_ret:
    rts
fsq_err:
    lda #5
    jmp rt_err

// ---- polynomial: FAC = c(n) + w * (c(n-1) + w * ( ... c(0))) with w in f_t3 ------------------------------------------
f_horner:
    lda fhp
    sta tmp
    lda fhp+1
    sta tmp+1
    jsr f_ldfac
    jsr f_hadv
    dec fhn
fh_loop:
    lda fhn
    beq fh_end
    :LDARGC(f_t3)
    jsr rt_fmul
    lda fhp
    sta tmp
    lda fhp+1
    sta tmp+1
    jsr f_ldarg
    jsr rt_fadd
    jsr f_hadv
    dec fhn
    jmp fh_loop
fh_end:
    rts

f_hadv:                         // next coefficient
    clc
    lda fhp
    adc #4
    sta fhp
    bcc !+
    inc fhp+1
!:  rts

// ---- exponential, logarithm -----------------------------------------------------------------------------------------------
rt_fexp:                        // e^x = 2^n * e^r, n = round(x / ln 2), r = x - n ln 2
    lda facx
    bne !+
    jmp f_one
!:  cmp #136
    bcc fe_ok                   // |x| < 128
    lda facs
    bpl fe_ovf
    jmp f_zero
fe_ovf:
    lda #5
    jmp rt_err
fe_ok:
    :LDPTR(f_t1)
    jsr f_stfac                 // x
    :LDARGC(c_log2e)
    jsr rt_fmul
    jsr rt_fround               // ac = n
    lda ac
    sta fn_n
    lda ac+1
    sta fn_n+1
    jsr rt_i2f
    :LDARGC(c_ln2)
    jsr rt_fmul
    jsr rt_fneg
    :LDARGC(f_t1)
    jsr rt_fadd                 // r = x - n ln 2
    :LDPTR(f_t3)
    jsr f_stfac
    :FHORN(c_exp, 9)
    clc                         // times 2^n
    lda facx
    adc fn_n
    sta fex
    lda #0
    adc fn_n+1
    sta fex+1
    bmi fe_zero
    bne fe_ovf
    lda fex
    beq fe_zero
    sta facx
    rts
fe_zero:
    jmp f_zero

rt_fln:                         // ln x = e ln 2 + ln m with x = m 2^e and m in [0.7, 1.4)
    lda facx
    beq fl_err
    lda facs
    bpl fl_ok
fl_err:
    lda #5                      // runtime error 5: argument not positive
    jmp rt_err
fl_ok:
    sec
    lda facx
    sbc #128
    sta fln_e
    lda #0
    sbc #0
    sta fln_e+1
    lda #128
    sta facx                    // m in [0.5, 1)
    lda fm0
    cmp #$b5
    bcs fl_m
    inc facx                    // m * 2
    lda fln_e
    bne !+
    dec fln_e+1
!:  dec fln_e
fl_m:
    :LDPTR(f_t1)
    jsr f_stfac                 // m
    jsr f_one
    :LDARGC(f_t1)
    jsr rt_fsub                 // m - 1
    :LDPTR(f_t2)
    jsr f_stfac
    jsr f_one
    :LDARGC(f_t1)
    jsr rt_fadd                 // m + 1
    :LDARGC(f_t2)
    jsr rt_fdiv                 // z = (m - 1) / (m + 1)
    :LDPTR(f_t2)
    jsr f_stfac
    jsr f_fac2arg
    jsr rt_fmul                 // z^2
    :LDPTR(f_t3)
    jsr f_stfac
    :FHORN(c_ln, 5)
    :LDARGC(f_t2)
    jsr rt_fmul                 // * z
    lda facx
    beq !+
    inc facx                    // * 2
!:  :LDPTR(f_t1)
    jsr f_stfac                 // ln m
    lda fln_e
    sta ac
    lda fln_e+1
    sta ac+1
    jsr rt_i2f
    :LDARGC(c_ln2)
    jsr rt_fmul                 // e ln 2
    :LDARGC(f_t1)
    jmp rt_fadd

// ---- sine, cosine, arc tangent -----------------------------------------------------------------------------------------------
rt_fcos:                        // cos x = sin (x + pi/2): one quarter turn more
    lda #1
    bne fsn_go
rt_fsin:
    lda #0
fsn_go:
    sta fq_off
    :LDPTR(f_t1)
    jsr f_stfac                 // x
    :LDARGC(c_2opi)
    jsr rt_fmul
    jsr rt_fround               // ac = n, the number of quarter turns
    lda ac
    sta fn_n
    jsr rt_i2f
    :LDARGC(c_pio2)
    jsr rt_fmul
    jsr rt_fneg
    :LDARGC(f_t1)
    jsr rt_fadd                 // r = x - n pi/2
    :LDPTR(f_t1)
    jsr f_stfac
    jsr f_fac2arg
    jsr rt_fmul                 // r^2
    :LDPTR(f_t3)
    jsr f_stfac
    clc
    lda fn_n
    adc fq_off
    and #3
    sta fq_q
    and #1
    bne fsn_cos
    :FHORN(c_sin, 5)
    :LDARGC(f_t1)
    jsr rt_fmul                 // sin r = r * polynomial
    jmp fsn_sign
fsn_cos:
    :FHORN(c_cos, 5)
fsn_sign:
    lda fq_q                    // quarters 2 and 3 are negative
    and #2
    beq !+
    jsr rt_fneg
!:  rts

rt_fatan:
    lda facx
    bne fat_go
    rts                         // atan 0 = 0
fat_go:
    lda facs
    sta fat_s
    lda #0
    sta facs                    // |x|
    sta fat_inv
    sta fat_add
    lda facx                    // |x| > 1 ?
    cmp #129
    bcc fat_small
    bne fat_big
    lda fm0
    and #$7f
    ora fm1
    ora fm2
    beq fat_small
fat_big:
    :LDPTR(f_t1)
    jsr f_stfac
    jsr f_one
    jsr f_swap                  // ARG = 1
    :LDPTR(f_t1)
    jsr f_ldfac                 // FAC = |x|
    jsr rt_fdiv                 // 1 / |x|
    lda #1
    sta fat_inv
fat_small:
    :LDARGC(c_tan8)             // above tan(pi/8) use atan x = pi/4 + atan((x-1)/(x+1))
    jsr f_cmp
    cmp #1
    beq fat_ser
    :LDPTR(f_t1)
    jsr f_stfac
    jsr f_one
    :LDARGC(f_t1)
    jsr rt_fsub                 // x - 1
    :LDPTR(f_t2)
    jsr f_stfac
    jsr f_one
    :LDARGC(f_t1)
    jsr rt_fadd                 // x + 1
    :LDARGC(f_t2)
    jsr rt_fdiv
    lda #1
    sta fat_add
fat_ser:
    :LDPTR(f_t1)
    jsr f_stfac                 // t
    jsr f_fac2arg
    jsr rt_fmul
    :LDPTR(f_t3)
    jsr f_stfac                 // t^2
    :FHORN(c_atan, 9)
    :LDARGC(f_t1)
    jsr rt_fmul
    lda fat_add
    beq !+
    :LDARGC(c_pio4)
    jsr rt_fadd
!:  lda fat_inv
    beq !+
    :LDARGC(c_pio2)
    jsr rt_fsub                 // pi/2 - result
!:  lda facx
    beq fat_ret
    lda fat_s
    sta facs
fat_ret:
    rts

// ---- powers of ten, text to number --------------------------------------------------------------------------------------------
// The "wide" number: fn3..fn0 (32 bit mantissa), fex (exponent), fsg (sign), the same as the input of f_pack. Numbers are
// scaled by powers of ten in this form (32 bit mantissas, error about 1E-9) and converted to a real or to digits afterwards.
f_fac2w:                        // wide number = FAC (FAC must not be zero)
    lda fm0
    sta fn3
    lda fm1
    sta fn2
    lda fm2
    sta fn1
    lda #0
    sta fn0
    sta fex+1
    lda facx
    sta fex
    lda facs
    sta fsg
    rts

f_wnorm:                        // shift the wide number (not zero) left until its top bit is set
    lda fn3
    bmi fwn_ret
    asl fn0
    rol fn1
    rol fn2
    rol fn3
    lda fex
    bne !+
    dec fex+1
!:  dec fex
    jmp f_wnorm
fwn_ret:
    rts

f_wmul:                         // wide number = wide number * the constant at (tmp) (5 bytes: exponent, mantissa)
    ldy #0
    lda (tmp),y
    sta wcx
    iny
    lda (tmp),y
    sta wc3
    iny
    lda (tmp),y
    sta wc2
    iny
    lda (tmp),y
    sta wc1
    iny
    lda (tmp),y
    sta wc0
    clc                         // exponent = fex + wcx - 128
    lda fex
    adc wcx
    sta fex
    lda fex+1
    adc #0
    sta fex+1
    sec
    lda fex
    sbc #128
    sta fex
    lda fex+1
    sbc #0
    sta fex+1
    lda #0                      // 64 bit product: high half 0, low half = the number (shift and add)
    sta rh3
    sta rh2
    sta rh1
    sta rh0
    lda fn3
    sta rl3
    lda fn2
    sta rl2
    lda fn1
    sta rl1
    lda fn0
    sta rl0
    ldx #32
wm_loop:
    lda rl0
    lsr
    bcc wm_shift
    clc
    lda rh0
    adc wc0
    sta rh0
    lda rh1
    adc wc1
    sta rh1
    lda rh2
    adc wc2
    sta rh2
    lda rh3
    adc wc3
    sta rh3
wm_shift:
    ror rh3
    ror rh2
    ror rh1
    ror rh0
    ror rl3
    ror rl2
    ror rl1
    ror rl0
    dex
    bne wm_loop
    lda rh3                     // the top 32 bits are the result; at most one left shift normalises them
    sta fn3
    lda rh2
    sta fn2
    lda rh1
    sta fn1
    lda rh0
    sta fn0
    lda fn3
    bmi wm_ret
    asl rl3
    rol fn0
    rol fn1
    rol fn2
    rol fn3
    lda fex
    bne !+
    dec fex+1
!:  dec fex
wm_ret:
    rts

f_wscale:                       // wide number = wide number * 10^A (A = signed byte, |A| < 64)
    cmp #0
    beq ws_ret
    bpl !+
    eor #$ff
    clc
    adc #1
    ldx #30                     // negative: the second table
    bne ws_go
!:  ldx #0
ws_go:
    sta fkabs
    stx fkneg
    lda #0
    sta fti
ws_loop:
    lsr fkabs
    bcc ws_next
    lda fti                     // entry = table + 30 * negative + 5 * i
    sta ftmp
    asl
    asl
    clc
    adc ftmp
    adc fkneg
    clc
    adc #<f_wpos
    sta tmp
    lda #>f_wpos
    adc #0
    sta tmp+1
    jsr f_wmul
ws_next:
    inc fti
    lda fkabs
    bne ws_loop
ws_ret:
    rts

f_wto32:                        // fn = the wide number as an integer, rounded (the sign is ignored); A = 1 if it is too big
    sec                         // shift right by 160 - exponent
    lda #160
    sbc fex
    sta fsl
    lda #0
    sbc fex+1
    sta fsl+1
    bmi fwt_big
    bne fwt_zero
    lda fsl
    cmp #33
    bcs fwt_zero
    tax
    beq fwt_ok
fwt_sh:
    lsr fn3
    ror fn2
    ror fn1
    ror fn0
    dex
    bne fwt_sh
    bcc fwt_ok                  // the last bit shifted out rounds
    inc fn0
    bne fwt_ok
    inc fn1
    bne fwt_ok
    inc fn2
    bne fwt_ok
    inc fn3
fwt_ok:
    lda #0
    rts
fwt_zero:
    lda #0
    sta fn0
    sta fn1
    sta fn2
    sta fn3
    rts
fwt_big:
    lda #1
    rts

f_mul10add:                     // fi = fi * 10 + fdg
    lda fi0
    sta ft0
    lda fi1
    sta ft1
    lda fi2
    sta ft2
    lda fi3
    sta ft3
    asl fi0
    rol fi1
    rol fi2
    rol fi3
    asl fi0
    rol fi1
    rol fi2
    rol fi3
    clc
    lda fi0
    adc ft0
    sta fi0
    lda fi1
    adc ft1
    sta fi1
    lda fi2
    adc ft2
    sta fi2
    lda fi3
    adc ft3
    sta fi3
    asl fi0
    rol fi1
    rol fi2
    rol fi3
    clc
    lda fi0
    adc fdg
    sta fi0
    bcc !+
    inc fi1
    bne !+
    inc fi2
    bne !+
    inc fi3
!:  rts

f_atof:                         // text at (tmp), length flen -> FAC; fused = number of characters used
    lda #0
    sta fi0
    sta fi1
    sta fi2
    sta fi3
    sta fdot
    sta fdp
    sta fexv
    sta fexn
    sta fsg
    ldy #0
    cpy flen
    bcs fa_endj
    lda (tmp),y
    cmp #'-'
    bne fa_p
    lda #$80
    sta fsg
    iny
    jmp fa_dig
fa_p:
    cmp #'+'
    bne fa_dig
    iny
fa_dig:
    cpy flen
    bcs fa_endj
    lda (tmp),y
    cmp #'.'
    bne fa_nd
    lda fdot                    // a second point ends the number
    bne fa_endj
    inc fdot
    iny
    jmp fa_dig
fa_nd:
    sec
    sbc #'0'
    cmp #10
    bcs fa_e
    sta fdg
    lda fi3
    cmp #5
    bcs fa_drop                 // enough digits: ignore the rest
    sty fix
    jsr f_mul10add
    ldy fix
    lda fdot
    beq fa_next
    dec fdp                     // a digit after the point: divide by 10 more
    jmp fa_next
fa_drop:
    lda fdot
    bne fa_next
    inc fdp                     // an ignored digit before the point: multiply by 10 more
fa_next:
    iny
    jmp fa_dig
fa_endj:
    jmp fa_end
fa_e:
    lda (tmp),y                 // exponent: E[+-]digits
    and #$df
    cmp #'E'
    bne fa_endj
    iny
    cpy flen
    bcs fa_endj
    lda (tmp),y
    cmp #'-'
    bne fa_ep
    inc fexn
    iny
    jmp fa_ed
fa_ep:
    cmp #'+'
    bne fa_ed
    iny
fa_ed:
    cpy flen
    bcs fa_endj
    lda (tmp),y
    sec
    sbc #'0'
    cmp #10
    bcs fa_endj
    sta fdg
    lda fexv
    cmp #100
    bcs fa_edn
    asl                         // fexv * 10 + digit
    sta ftmp
    asl
    asl
    clc
    adc ftmp
    clc
    adc fdg
    sta fexv
fa_edn:
    iny
    jmp fa_ed
fa_end:
    sty fused
    lda fi0                     // the integer of the digits
    sta fn0
    lda fi1
    sta fn1
    lda fi2
    sta fn2
    lda fi3
    sta fn3
    ora fn2
    ora fn1
    ora fn0
    bne fa_nz
    jmp f_zero
fa_nz:
    lda #160
    sta fex
    lda #0
    sta fex+1
    jsr f_wnorm
    lda fexn                    // decimal exponent = fdp +- fexv
    beq fa_add
    sec
    lda fdp
    sbc fexv
    jmp fa_k
fa_add:
    clc
    lda fdp
    adc fexv
fa_k:
    cmp #64                     // clamp to -63 .. 63
    bcc fa_scale
    cmp #128
    bcs fa_neg
    lda #63                     // 64 .. 127: too large
    jmp fa_scale
fa_neg:
    cmp #$c1                    // $80 .. $c0: too small
    bcs fa_scale
    lda #$c1
fa_scale:
    jsr f_wscale
    jmp f_pack

rt_readreal:                    // FAC = the next number of the input line (blanks and line ends are skipped)
rr_skip:
    lda rt_havel
    bne !+
    jsr rt_getline
!:  ldx rt_inpos
    cpx rt_inlen
    bcc rr_ch
    lda #0
    sta rt_havel
    jmp rr_skip
rr_ch:
    lda RT_INBUF,x
    cmp #' '
    bne rr_go
    inc rt_inpos
    jmp rr_skip
rr_go:
    clc
    lda #<RT_INBUF
    adc rt_inpos
    sta tmp
    lda #>RT_INBUF
    adc #0
    sta tmp+1
    sec
    lda rt_inlen
    sbc rt_inpos
    sta flen
    jsr f_atof
    clc
    lda rt_inpos
    adc fused
    sta rt_inpos
    rts

// ---- number to text ------------------------------------------------------------------------------------------------------------
f_u32dec:                       // fdbuf = the decimal digits of fn (least significant first), fnd = their number
    ldx #0
fu_loop:
    lda #0
    sta frm
    ldy #32
fu_div:
    asl fn0
    rol fn1
    rol fn2
    rol fn3
    rol frm
    lda frm
    sec
    sbc #10
    bcc fu_nosub
    sta frm
    inc fn0
fu_nosub:
    dey
    bne fu_div
    lda frm
    ora #'0'
    sta fdbuf,x
    inx
    lda fn0
    ora fn1
    ora fn2
    ora fn3
    bne fu_loop
    stx fnd
    rts

f_spaces:                       // print A spaces (the count is kept in RAM: the Plus/4 KERNAL's CHROUT does not preserve X)
    sta fsp_cnt
    beq fsp_ret
!:  lda #' '
    jsr f_put
    dec fsp_cnt
    bne !-
fsp_ret:
    rts
fsp_cnt: .byte 0

// rt_wreal: print FAC. Inline word: low byte = field width (0 = none), high byte = decimals ($ff = none:
// scientific notation  [-]d.dddddE+dd)
rt_wreal:
    :FETCH()
    lda #0
    sta fsmode
    jsr f_wreal
    jmp (rp)
f_wreal:
    lda wd
    sta fwid
    lda wd+1
    sta fdec
    lda facs
    sta fneg
    lda #0
    sta facs                    // |x|
    lda fdec
    cmp #$ff
    bne fw_nsci
    jmp fw_sci
fw_nsci:
    cmp #10
    bcc fw_fix
    lda #9
    sta fdec
fw_fix:
    :LDPTR(f_t1)
    jsr f_stfac                 // keep |x| in case the fixed format does not fit
    lda #0
    sta fn0
    sta fn1
    sta fn2
    sta fn3
    lda facx
    beq fw_have                 // zero
    jsr f_fac2w
    lda fdec
    jsr f_wscale                // |x| * 10^decimals
    jsr f_wto32
    beq fw_have
    jmp fw_big                  // 2^32 or more
fw_have:
    jsr f_u32dec
    clc
    lda fdec
    adc #1
    sta ftmp                    // at least decimals + 1 digits
fw_zp:
    lda fnd
    cmp ftmp
    bcs fw_zdone
    ldx fnd
    lda #'0'
    sta fdbuf,x
    inc fnd
    jmp fw_zp
fw_zdone:
    lda #0                      // a minus sign only if some digit is not zero
    sta fnz
    ldx #0
fw_nz:
    lda fdbuf,x
    cmp #'0'
    beq !+
    inc fnz
!:  inx
    cpx fnd
    bne fw_nz
    lda #0
    sta fsc
    lda fneg
    bpl !+
    lda fnz
    beq !+
    lda #1
    sta fsc
!:  clc                         // characters: digits + sign + point
    lda fnd
    adc fsc
    ldx fdec
    beq !+
    adc #1
!:  sta ftot
    lda fwid
    sec
    sbc ftot
    bcc fw_np
    jsr f_spaces
fw_np:
    lda fsc
    beq !+
    lda #'-'
    jsr f_put
!:  ldx fnd
fw_pl:
    dex
    stx fix
    lda fdbuf,x
    jsr f_put
    ldx fix
    cpx fdec
    bne fw_pn
    lda fdec
    beq fw_pn
    lda #'.'
    jsr f_put
fw_pn:
    ldx fix
    bne fw_pl
    rts
fw_big:
    :LDPTR(f_t1)
    jsr f_ldfac
fw_sci:                         // scientific notation of |x| in FAC
    lda #0
    sta fd10
    lda facx
    bne fw_est
    sta fn0                     // zero
    sta fn1
    sta fn2
    sta fn3
    jmp fw_digits
fw_est:
    :LDPTR(f_t1)
    jsr f_stfac
    sec                         // decimal exponent estimate: (exponent - 129) * 77 / 256
    lda facx
    sbc #129
    sta fv
    lda #0
    bit fv
    bpl !+
    lda #$ff
!:  sta fv+1
    lda fv
    sta fpl
    lda fv+1
    sta fpl+1
    lda fv
    sta ft0
    lda fv+1
    sta ft1
    asl ft0                     // v * 4
    rol ft1
    asl ft0
    rol ft1
    jsr fw_addp                 // + v * 4  = 5 v
    asl ft0                     // v * 8
    rol ft1
    jsr fw_addp                 // 13 v
    ldx #3
!:  asl ft0                     // v * 64
    rol ft1
    dex
    bne !-
    jsr fw_addp                 // 77 v
    lda fpl+1
    sta fd10                    // / 256 (arithmetic)
fw_try:
    :LDPTR(f_t1)
    jsr f_ldfac
    jsr f_fac2w
    sec
    lda #6
    sbc fd10
    jsr f_wscale                // |x| * 10^(6 - d10), expected in [10^6, 10^7)
    jsr f_wto32
    lda fn3                     // 10^7 ($989680) or more: the exponent was too small
    bne fw_up
    lda fn2
    cmp #$98
    bcc fw_lo
    bne fw_up
    lda fn1
    cmp #$96
    bcc fw_lo
    bne fw_up
    lda fn0
    cmp #$80
    bcc fw_lo
fw_up:
    inc fd10
    jmp fw_try
fw_lo:                          // below 10^6 ($0f4240): too large
    lda fn3
    bne fw_digits
    lda fn2
    cmp #$0f
    bcc fw_dn
    bne fw_digits
    lda fn1
    cmp #$42
    bcc fw_dn
    bne fw_digits
    lda fn0
    cmp #$40
    bcs fw_digits
fw_dn:
    dec fd10
    jmp fw_try
fw_digits:
    jsr f_u32dec
fw_pad7:
    lda fnd
    cmp #7
    bcs fw_p7
    ldx fnd
    lda #'0'
    sta fdbuf,x
    inc fnd
    jmp fw_pad7
fw_p7:
    lda fwid
    sec
    sbc #13                     // sign + d.dddddd + E+dd
    bcc fw_sp
    jsr f_spaces
fw_sp:
    lda #' '
    ldx fneg
    bpl !+
    lda #'-'
!:  jsr f_put
    lda fdbuf+6
    jsr f_put
    lda #'.'
    jsr f_put
    ldx #5
fw_sd:
    stx fix
    lda fdbuf,x
    jsr f_put
    ldx fix
    dex
    bpl fw_sd
    lda #'E'
    jsr f_put
    lda fd10
    ldx #'+'
    cmp #0
    bpl !+
    eor #$ff
    clc
    adc #1
    ldx #'-'
!:  pha
    txa
    jsr f_put
    pla
    ldx #'0'
fw_ex:
    cmp #10
    bcc fw_ex2
    sbc #10                     // (carry is set)
    inx
    bne fw_ex
fw_ex2:
    pha
    txa
    jsr f_put
    pla
    ora #'0'
    jmp f_put

fw_addp:                        // fp = fp + ft (16 bit)
    clc
    lda fpl
    adc ft0
    sta fpl
    lda fpl+1
    adc ft1
    sta fpl+1
    rts

// f_put: print the ASCII character in A, or (fsmode = 1, Str) append it to the string at (wd2), at most fsmax characters.
f_put:
    ldx fsmode
    bne fput_s
    jmp putc
fput_s:
    pha
    ldy #0
    lda (wd2),y
    cmp fsmax
    bcs fput_full
    clc
    adc #1
    sta (wd2),y
    tay
    pla
    sta (wd2),y
    rts
fput_full:
    pla
    rts

// rt_fstr: Str(x:w:d, s). The real is on the software stack, ac = address of the string s. Inline: word = width +
// 256 * decimals (as for rt_wreal), byte = maximum length of s.
rt_fstr:
    :FETCH()
    ldy #0
    lda (rp),y
    sta fsmax
    inc rp
    bne !+
    inc rp+1
!:  lda ac
    sta wd2
    lda ac+1
    sta wd2+1
    lda #0
    tay
    sta (wd2),y                 // empty string
    jsr rt_fpop
    jsr f_arg2fac
    lda #1
    sta fsmode
    jsr f_wreal
    lda #0
    sta fsmode
    jmp (rp)

// rt_valreal: Val(s, x, code) with x a real: s and the address of x are on the stack, ac = address of code
rt_valreal:
    lda ac
    sta sb
    lda ac+1
    sta sb+1
    jsr popt
    lda tmp
    sta sa
    lda tmp+1
    sta sa+1
    jsr popt                    // tmp = the string
    ldy #0
    lda (tmp),y
    sta flen
    inc tmp
    bne !+
    inc tmp+1
!:  jsr f_atof
    lda flen
    beq vr_err
    lda fused
    cmp flen
    bne vr_err
    lda sa
    sta tmp
    lda sa+1
    sta tmp+1
    jsr f_stfac
    lda #0                      // code := 0
    beq vr_code
vr_err:
    jsr f_zero
    lda sa
    sta tmp
    lda sa+1
    sta tmp+1
    jsr f_stfac
    lda fused                   // code := position of the first character that is not part of the number
    clc
    adc #1
vr_code:
    ldy #0
    sta (sb),y
    iny
    lda #0
    sta (sb),y
    rts

// rt_frandom: FAC = a random real in [0, 1) (24 random bits)
rt_frandom:
    jsr rnd_step
    lda rnd_x+1
    sta fn3
    lda rnd_x
    sta fn2
    jsr rnd_step
    lda rnd_x+1
    sta fn1
    lda #0
    sta fn0
    sta fsg
    sta fex+1
    lda #128
    sta fex
    jmp f_pack
