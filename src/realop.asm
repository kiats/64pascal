// This file is in the public domain: use it, change it, share it, sell it - do whatever you like with it.
// No permission, credit or payment needed. It comes as it is, with no warranty. Enjoy!
// Note: this has only been tested in the VICE emulator, never on real hardware.
// =====================================================================================
// realop.asm - the type real in the compiler: literals, operators, write, Trunc / Sqrt / ...
// =====================================================================================
//
// A real value lives in the float accumulator FAC while it is evaluated (rt_f* routines, rt_float.asm);
// 'etype' = T_REAL tells the code generator so. Integers are converted with rt_i2f wherever a real is needed.
//
//   literals      1.5   2.0E-3   1E6       the text is kept in the code and converted when the program runs
//                                          (the compiler itself has no floating point code: the runtime for it
//                                          shares memory with the compiler's tables)
//   operators     + - * /   and the relations; / always gives a real; DIV MOD AND OR XOR need integers
//   mixed         integer and real operands are allowed everywhere; the integer is converted
//   write(x)      x:width   x:width:decimals     (width and decimals are constants)
//   functions     Trunc Round (integer result)   Abs Sqr   Sqrt Sin Cos Arctan Exp Ln Int Frac Pi (real result)
//
// Binary operators (see the header of rt_float.asm): the left operand is pushed (rt_fpush if it is real,
// rt_push if it is an integer, push_left), the right one is evaluated, then numop emits the conversion of the
// operands and the operator. The left operand's type is passed in X, the right operand's type is 'etype'.

// push_left: save the left operand of a binary operator (type = etype) on the software stack.
push_left:
    lda etype
    cmp #T_REAL
    bne !+
    :GCALL(rt_fpush)
    rts
!:  jsr gc_push
    rts

// noreal: report E_TYPE if the last expression is a real (for loop bounds, case selectors ...).
noreal:
    lda etype
    cmp #T_REAL
    bne !+
    jmp err_type
!:  rts

// negate_num: unary minus for an integer or a real value (etype is kept for a real).
negate_num:
    lda etype
    cmp #T_REAL
    bne !+
    :GCALL(rt_fneg)
    rts
!:  :GCALL(rt_neg)
    lda #T_INT
    sta etype
    rts

// numop: A = operator token, X = type of the left operand (already pushed), etype = type of the right operand
// (in ac or FAC). Emits the operator. Integer operands use the integer routines (genop); if either operand is a
// real, or the operator is '/', the operation is done on reals. Sets etype for arithmetic operators.
numop:
    sta rop
    stx rlty
    lda etype
    cmp #T_REAL
    beq no_rr
    lda rlty
    cmp #T_REAL
    beq no_lr
    lda rop                     // both integer
    cmp #TK_SLASH
    beq no_idiv
    jmp genop
no_idiv:                        // integer / integer: a real result
    jsr gc_i2f
    :GCALL(rt_fpopi)
    jmp no_op
no_lr:                          // real op integer
    jsr gc_i2f
    :GCALL(rt_fpop)
    jmp no_op
no_rr:
    lda rlty
    cmp #T_REAL
    beq no_rrl
    :GCALL(rt_fpopi)            // integer op real
    jmp no_op
no_rrl:
    :GCALL(rt_fpop)
no_op:
    ldx #0                      // find the operator in foptab: token, routine, result type
no_find:
    lda foptab,x
    bne !+
    jmp err_type   // DIV, MOD, AND ... are not defined for reals
!:  cmp rop
    beq no_found
    inx
    inx
    inx
    inx
    jmp no_find
no_found:
    lda foptab+3,x
    sta etype
    lda foptab+1,x
    pha
    lda foptab+2,x
    tax
    pla                         // A = low, X = high byte of the routine
    jmp gen_jsr

foptab:
    .byte TK_PLUS
    .word rt_fadd
    .byte T_REAL
    .byte TK_MINUS
    .word rt_fsub
    .byte T_REAL
    .byte TK_STAR
    .word rt_fmul
    .byte T_REAL
    .byte TK_SLASH
    .word rt_fdiv
    .byte T_REAL
    .byte TK_EQ
    .word rt_feq
    .byte T_BOOL
    .byte TK_NE
    .word rt_fne
    .byte T_BOOL
    .byte TK_LT
    .word rt_flt
    .byte T_BOOL
    .byte TK_LE
    .word rt_fle
    .byte T_BOOL
    .byte TK_GT
    .word rt_fgt
    .byte T_BOOL
    .byte TK_GE
    .word rt_fge
    .byte T_BOOL
    .byte 0

// ---- literals ---------------------------------------------------------------------------------------------
// f_realnum: the current token is a real literal. Emits rt_fli followed by its text (length byte + characters).
f_realnum:
    :GCALL(rt_fli)
    lda numbuf
    jsr emit
    lda numbuf
    beq rn_done
    ldx #1
!:  lda numbuf,x
    jsr emit
    cpx numbuf
    beq rn_done
    inx
    jmp !-
rn_done:
    lda #T_REAL
    sta etype
    lda #0
    sta edesc
    jmp nexttok

// ---- write ------------------------------------------------------------------------------------------------------
// write_real: the value to print is in FAC (etype = T_REAL), the current token follows the expression.
// Reads the optional  :width  and  :decimals  (constants) and emits rt_wreal with the inline word
// width + 256 * decimals ($ff = none: scientific notation).
write_real:
    jsr parse_realfmt
    :GCALL(rt_wreal)
    lda fmt_w
    ldx fmt_d
    jmp emit_word

// parse_realfmt: the optional  :width  and  :decimals  (constants) after a real value (write, Str):
// fmt_w = width (0 = none), fmt_d = decimals ($ff = none).
parse_realfmt:
    lda #0
    sta fmt_w
    lda #$ff
    sta fmt_d
    lda tok
    cmp #TK_COLON
    bne wr_done
    jsr nexttok
    jsr parse_const
    lda cval
    sta fmt_w
    lda tok
    cmp #TK_COLON
    bne wr_done
    jsr nexttok
    jsr parse_const
    lda cval
    sta fmt_d
wr_done:
    rts

// ---- numeric functions -------------------------------------------------------------------------------------
// bfunc3: the built-in functions with the numbers 20 .. 32; bfid = the number, the current token follows the name.
//   20 Trunc  21 Round (-> integer)   22 Abs  23 Sqr (same type as the argument)
//   24 Sqrt  25 Sin  26 Cos  27 Arctan  28 Exp  29 Ln  30 Int  31 Frac (-> real)   32 Pi (no argument)
//   33 Random: without argument a real in [0, 1), Random(n) an integer 0 .. n-1
bfunc3:
    lda bfid
    cmp #33
    bne b3_nr
    jmp b3_random
b3_nr:
    cmp #32
    bne b3_arg
    :GCALL(rt_fpi)              // Pi, with or without ()
    lda tok
    cmp #TK_LPAR
    bne b3_pi
    jsr nexttok
    lda #TK_RPAR
    jsr expect
b3_pi:
    lda #T_REAL
    sta etype
    lda #0
    sta edesc
    rts
b3_arg:
    lda #TK_LPAR
    jsr expect
    jsr expr
    lda etype                   // a number
    cmp #T_INT
    beq b3_num
    cmp #T_BYTE
    beq b3_num
    cmp #T_REAL
    beq b3_num
    jmp err_type
b3_num:
    lda bfid
    cmp #22
    bcs b3_ge22
    lda etype                   // Trunc / Round: an integer needs nothing
    cmp #T_REAL
    beq b3_conv
    jmp b3_inta
b3_conv:
    lda bfid
    cmp #21
    beq b3_round
    :GCALL(rt_ftrunc)
    jmp b3_inta
b3_round:
    :GCALL(rt_fround)
b3_inta:
    lda #T_INT
    jmp b3_done
b3_ge22:
    cmp #24
    bcs b3_real
    cmp #23
    beq b3_sqr
    lda etype                   // Abs
    cmp #T_REAL
    bne b3_absi
    :GCALL(rt_fabs)
    lda #T_REAL
    jmp b3_done
b3_absi:
    :GCALL(rt_abs)
    jmp b3_inta
b3_sqr:
    lda etype
    cmp #T_REAL
    bne b3_sqri
    :GCALL(rt_fsqr)
    lda #T_REAL
    jmp b3_done
b3_sqri:
    jsr gc_push             // x * x
    :GCALL(rt_mul)
    jmp b3_inta
b3_real:                        // functions of a real
    lda etype
    cmp #T_REAL
    beq !+
    jsr gc_i2f
!:  lda bfid
    sec
    sbc #24
    asl
    tax
    lda b3tab,x
    pha
    lda b3tab+1,x
    tax
    pla
    jsr gen_jsr
    lda #T_REAL
b3_done:
    pha
    lda #TK_RPAR
    jsr expect
    pla
    sta etype
    lda #0
    sta edesc
    rts

// Random / Random(n)
b3_random:
    lda tok
    cmp #TK_LPAR
    bne b3_rr
    jsr nexttok
    jsr expr_int
    :GCALL(rt_random)
    lda #TK_RPAR
    jsr expect
    lda #T_INT
    sta etype
    lda #0
    sta edesc
    rts
b3_rr:
    :GCALL(rt_frandom)
    lda #T_REAL
    sta etype
    lda #0
    sta edesc
    rts

b3tab:
    .word rt_fsqrt, rt_fsin, rt_fcos, rt_fatan, rt_fexp, rt_fln, rt_fint, rt_ffrac
