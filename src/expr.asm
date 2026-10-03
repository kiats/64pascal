// This file is in the public domain: use it, change it, share it, sell it - do whatever you like with it.
// No permission, credit or payment needed. It comes as it is, with no warranty. Enjoy!
// Note: this has only been tested in the VICE emulator, never on real hardware.
// =====================================================================================
// expr.asm - expressions
// =====================================================================================
//
// Grammar (standard Pascal precedence, lowest to highest):
//   expr   = simple [ relop simple ]                relop: = <> < <= > >=
//   simple = [+|-] term { (+ | - | OR | XOR) term }
//   term   = factor { (* | DIV | MOD | AND) factor }
//   factor = number | 'c' | identifier | ( expr ) | NOT factor
//
// Every routine generates code that leaves its result in the runtime accumulator 'ac' and
// sets 'etype' (T_INT / T_BOOL / T_CHAR) to the type of the result.
//
// Binary operators use the pattern
//     <code for left operand>      result in ac
//     jsr rt_push                  left operand saved on the software stack
//     <code for right operand>     result in ac
//     jsr rt_<op>                  pops the left operand, ac = left <op> ac
// so no registers have to be preserved by the code generator.

// needbool: report E_BOOL unless the last expression was boolean.
needbool:
    lda etype
    cmp #T_BOOL
    beq !+
    lda #E_BOOL
    jmp error
!:  rts

// genop: A = operator token. Emits a call of the runtime routine that implements it
// (looked up in optab).
genop:
    sta tmpc2
    ldx #0
go1:
    lda optab,x                 // token of this entry, 0 = end of table
    beq go_err
    cmp tmpc2
    beq go_f
    inx                         // entries are 3 bytes: token, routine low, routine high
    inx
    inx
    jmp go1
go_err:
    jmp err_syntax
go_f:
    lda optab+1,x
    pha
    lda optab+2,x
    tax
    pla
    jmp gen_jsr                 // emit "jsr routine"

optab:
    .byte TK_PLUS
    .word rt_add
    .byte TK_MINUS
    .word rt_sub
    .byte TK_STAR
    .word rt_mul
    .byte TK_DIV
    .word rt_div
    .byte TK_MOD
    .word rt_mod
    .byte TK_AND
    .word rt_and
    .byte TK_OR
    .word rt_or
    .byte TK_XOR
    .word rt_xor
    .byte TK_EQ
    .word rt_eq
    .byte TK_NE
    .word rt_ne
    .byte TK_LT
    .word rt_lt
    .byte TK_LE
    .word rt_le
    .byte TK_GT
    .word rt_gt
    .byte TK_GE
    .word rt_ge
    .byte 0

// ---- factor ------------------------------------------------------------------------------------
factor:
    lda tok
    cmp #TK_NUM
    bne f1
    jsr gc_ldi              // number: load immediate
    lda tokval
    ldx tokval+1
    jsr emit_word
    lda #T_INT
    sta etype
    jmp nexttok
f1:
    cmp #TK_REALNUM
    bne f1b
    jmp f_realnum               // real literal (realop.asm)
f1b:
    cmp #TK_STR
    bne f2
    lda strbuf                  // one character: a char value; otherwise a string literal
    cmp #1
    beq f1_char
    :GCALL(rt_slit)             // string literal: the text follows the call inline
    jsr emit_strlit
    lda #T_STRING
    sta etype
    lda #0
    sta edesc
    jmp nexttok
f1_char:
    jsr gc_ldi
    lda strbuf+1
    ldx #0
    jsr emit_word
    lda #T_CHAR
    sta etype
    jmp nexttok
f2:
    cmp #TK_IDENT
    bne f3
    jmp f_ident
f3:
    cmp #TK_LPAR                // ( expr )
    bne f4
    jsr nexttok
    jsr expr
    lda #TK_RPAR
    jmp expect
f4:
    cmp #TK_NOT                 // NOT factor: logical for booleans, bitwise otherwise
    bne f5
    jsr nexttok
    jsr factor
    lda etype
    cmp #T_REAL
    bne !+
    jmp err_type   // NOT of a real
!:  lda etype
    cmp #T_BOOL
    bne !+
    :GCALL(rt_bnot)
    rts
!:  :GCALL(rt_not)
    lda #T_INT
    sta etype
    rts
f5:
#if !NOEXT
    cmp #TK_AT                  // @ designator
    bne f6
    jmp f_address
f6:
#endif
    jmp err_syntax

// f_ident: a variable, constant, array element or function call.
f_ident:
    jsr lookup_must             // (reports "undefined identifier" itself)
!:  ldy #16
    lda (sptr),y
    cmp #K_FUNC
    bne !+
    jmp gen_call                // function call: pushes arguments, emits the call, sets etype
!:  cmp #K_BFUNC
    bne !+
    jmp bfunc                   // built-in function (strfn.asm)
!:  cmp #K_CONST               // a string constant (const s = 'abc'): its value is the address of the text
    bne fi_notstr
    ldy #17
    lda (sptr),y
    cmp #T_STRING
    bne fi_notstr
    jsr gc_ldi
    ldy #18
    lda (sptr),y
    pha
    iny
    lda (sptr),y
    tax
    pla
    jsr emit_word
    lda #T_STRING
    sta etype
    lda #0
    sta edesc
    jmp nexttok
fi_notstr:
    ldy #17                     // array or string variable? (type code >= T_ARRAY)
    lda (sptr),y
    cmp #T_ARRAY
    bcc fi_scalar
    jsr gen_desig               // ac = address of the variable or of the indexed element
    lda etype
    cmp #T_ARRAY
    bcc fi_elem
    rts                         // whole array/string: its address is the value
fi_elem:
    jmp gen_ldp                 // scalar element: load it through the address
fi_scalar:
    ldy #16
    lda (sptr),y
    pha                         // kind
    ldy #17                     // type of the identifier becomes the type of the expression
    lda (sptr),y
    sta etype
    ldy #20                     // (pointer types: descriptor of the pointer type)
    lda (sptr),y
    sta edesc
    ldy #18                     // address / frame offset / constant value
    lda (sptr),y
    sta tmpc1
    iny
    lda (sptr),y
    sta tmpc1+1
    pla
    ldx etype
    cpx #T_REAL
    bne fi_int
    jsr gen_fload               // real variable or constant: into FAC
    jmp fi_loaded
fi_int:
    jsr gen_load                // emits the load for this kind of variable (vars.asm)
fi_loaded:
    jsr nexttok
    lda etype
    cmp #T_PTR                  // p^ : follow the pointer that is now in ac
    bne fi_ret
    lda tok
    cmp #TK_CARET
    bne fi_ret
    jsr deref_type
    jsr nexttok
    jsr gd_loop                 // p^.f  p^[i]  p^^ ...
    lda etype
    cmp #T_ARRAY
    bcs fi_ret                  // record / array / string: its address is the value
    jmp gen_ldp                 // scalar: load it
fi_ret:
    rts

// ---- term: * / DIV MOD AND SHL SHR ----------------------------------------------------------------
// The multiplying operators. SHL and SHR (tm_shift in ctlfn.asm) shift the left operand by a CONSTANT number of bits and are
// compiled to inline shift instructions; they stand at this precedence level, so  a shl 2 + 1  is  (a shl 2) + 1.
term:
    jsr factor
tm1:
    lda tok
    cmp #TK_STAR
    beq tm_op
    cmp #TK_SLASH
    beq tm_op
    cmp #TK_DIV
    beq tm_op
    cmp #TK_MOD
    beq tm_op
    cmp #TK_AND
    beq tm_op
    cmp #TK_SHL
    beq tm_sh
    cmp #TK_SHR
    beq tm_sh
    rts
tm_sh:
    jsr tm_shift                // a shl n / a shr n with a constant n (ctlfn.asm)
    jmp tm1
tm_op:
    pha                         // keep the operator token
    lda etype
    pha                         // and the type of the left operand
    jsr push_left               // save the left operand
    jsr nexttok
    jsr factor                  // right operand
    pla
    tax
    pla
    jsr numop                   // emit the operator (realop.asm)
    jmp tm1                     // there may be more: a * b * c

// ---- simple expression: + - OR XOR -----------------------------------------------------------------
simple:
    lda tok
    cmp #TK_MINUS               // leading minus: negate the first term
    bne sm1
    jsr nexttok
    jsr term
    jsr negate_num              // integer or real
    jmp s_loop
sm1:
    cmp #TK_PLUS                // leading plus is ignored
    bne !+
    jsr nexttok
!:  jsr term
s_loop:
    lda tok
    cmp #TK_PLUS
    beq s_op
    cmp #TK_MINUS
    beq s_op
    cmp #TK_OR
    beq s_op
    cmp #TK_XOR
    beq s_op
    rts
s_op:
    pha
    cmp #TK_PLUS                // '+' after a string or char: concatenation
    bne so_num
    lda etype
    cmp #T_STRING
    beq so_cat
    cmp #T_CHAR
    bne so_num
so_cat:
    pla
    lda etype
    cmp #T_CHAR                 // left operand: character -> string
    bne !+
    jsr gc_c2s
!:  jsr gc_push
    jsr nexttok
    jsr term
    lda etype
    cmp #T_CHAR                 // right operand: character -> string
    bne !+
    jsr gc_c2s
    lda #T_STRING
    sta etype
!:  lda etype
    cmp #T_STRING
    beq !+
    jmp err_type
!:  :GCALL(rt_scat)
    lda #0
    sta edesc
    jmp s_loop
so_num:
    lda etype
    pha                         // type of the left operand
    jsr push_left
    jsr nexttok
    jsr term
    pla
    tax
    pla                         // the operator
    jsr numop
    jmp s_loop

// ---- expression: relations ----------------------------------------------------------------------------
expr:
    jsr simple
    lda tok
    cmp #TK_EQ                  // is the token a relational operator (TK_EQ..TK_GE)?
    bcc !+
    cmp #TK_GE+1
    bcs !+
    pha                         // operator token
    lda etype
    pha                         // type of the left operand
    jsr push_left
    jsr nexttok
    jsr simple
    pla
    tax                         // X = type of the left operand
    pla                         // A = operator token
    cpx #T_STRING
    beq ex_str
    pha
    lda etype                   // a string or array on the right of a numeric left operand
    cmp #T_ARRAY
    bcc !++
    jmp err_type
!:  rts
!:  pla
    jsr numop                   // (X = type of the left operand)
    lda #T_BOOL                 // a comparison always yields a boolean
    sta etype
    rts
ex_str:                         // string comparison; a character on the right becomes a string
    pha
    lda etype
    cmp #T_CHAR
    bne !+
    jsr gc_c2s
    lda #T_STRING
    sta etype
!:  lda etype
    cmp #T_STRING
    beq !+
    jmp err_type
!:  pla
    jsr genstrop
    lda #T_BOOL
    sta etype
    rts
