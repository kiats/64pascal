// This file is in the public domain: use it, change it, share it, sell it - do whatever you like with it.
// No permission, credit or payment needed. It comes as it is, with no warranty. Enjoy!
// Note: this has only been tested in the VICE emulator, never on real hardware.
// =====================================================================================
// iofn.asm - input and the Crt unit in the compiler
// =====================================================================================
//
//   read(x, y) / readln(x, y)   x may be an integer, byte, char or string variable, an array element
//                               or a record field; readln also discards the rest of the input line
//   Val(s, n, code)             string to integer; code = 0 if ok, else the position of the bad character
//   Crt procedures              ClrScr, ClrEol, GotoXY(x, y), TextColor(c), TextBackground(c), Delay(ms),
//                               HighVideo, LowVideo, NormVideo
//   Crt functions               ReadKey (char), KeyPressed (boolean), WhereX, WhereY (integer)
//   uses Crt, ...;              accepted and ignored: all these routines are always available
//
// The Crt names are entered in the symbol table as K_BPROC / K_BFUNC (see symtab.asm); strfn.asm hands
// the routine numbers >= 4 (procedures) and >= 7 (functions) to bproc2 / bfunc2 below.

// ---- uses clause -------------------------------------------------------------------------------------
parse_uses:                     // at USES: uses name {, name} ;
    jsr nexttok
pu1:
    lda tok
    cmp #TK_IDENT
    beq !+
    jmp err_syntax
!:  jsr nexttok
    lda tok
    cmp #TK_COMMA
    bne !+
    jsr nexttok
    jmp pu1
!:  lda #TK_SEMI
    jmp expect

// ---- read / readln -----------------------------------------------------------------------------------------
// st_read: A = 3 for read, 4 for readln; the current token is the procedure name.
st_read:
    sta rdid
    jsr nexttok
    lda tok
    cmp #TK_LPAR
    bne sr_end
    jsr nexttok
sr_arg:
    jsr read_target
    lda tok
    cmp #TK_COMMA
    bne sr_close
    jsr nexttok
    jmp sr_arg
sr_close:
    lda #TK_RPAR
    jsr expect
sr_end:
    lda rdid
    cmp #4
    bne sr_done
    :GCALL(rt_readln_end)       // readln: throw away the rest of the line
sr_done:
    rts

// read_target: compile the input of one variable.
//   plain variable:  <call rt_readint / rt_readchar>  <store into the variable>
//   array element, field, string: <address>  rt_push  <call>  <store through the address>
read_target:
    lda tok
    cmp #TK_IDENT
    beq !+
    jmp err_syntax
!:  jsr lookup
    bcs !+
    jmp err_undef
!:  jsr is_outer                // a variable of a routine around the current one (nested routines): read through its address,
    bcs rd_struct               // like an array element
    ldy #17
    lda (sptr),y
    cmp #T_ARRAY
    bcs rd_struct
    ldy #16                     // plain scalar variable
    lda (sptr),y
    pha                         // kind
    ldy #17
    lda (sptr),y
    sta tmpc2                   // type
    ldy #18
    lda (sptr),y
    sta tmpc1
    iny
    lda (sptr),y
    sta tmpc1+1
    lda tmpc2
    cmp #T_CHAR
    beq rd_char
    cmp #T_INT
    beq rd_num
    cmp #T_BYTE
    beq rd_num
    cmp #T_REAL
    beq rd_real
    jmp err_type   // booleans cannot be read
rd_num:
    :GCALL(rt_readint)
    jmp rd_store
rd_real:
    :GCALL(rt_readreal)
    pla
    jsr gen_fstore              // FAC -> the variable
    jmp nexttok
rd_char:
    :GCALL(rt_readchar)
rd_store:
    pla
    jsr gen_store               // ac -> the variable
    jmp nexttok
rd_struct:                      // array element, record field or string variable
    ldy #16
    lda (sptr),y
    cmp #K_CPARAM               // read-only parameter
    bne !+
    jmp err_type
!:  jsr gen_desig               // ac = address, etype / edesc = its type
    lda etype
    cmp #T_STRING
    beq rd_str
    cmp #T_ARRAY                // whole arrays and records cannot be read
    bcc !+
    jmp err_type
!:  cmp #T_BOOL
    bne !+
    jmp err_type
!:  jsr gc_push             // save the address
    lda etype
    cmp #T_CHAR
    beq rds_char
    cmp #T_REAL
    beq rds_real
    :GCALL(rt_readint)
    jmp gen_stp                 // store through the address (word or byte, by etype)
rds_char:
    :GCALL(rt_readchar)
    jmp gen_stp
rds_real:
    :GCALL(rt_readreal)
    jmp gen_stp
rd_str:
    jsr gc_push
    lda edesc
    sta tmpc2
    :GCALL(rt_readstr)          // reads the rest of the line, at most the string's maximum length
    lda tmpc2
    jmp emit_maxlen

// ---- Val(s, n, code) ----------------------------------------------------------------------------------------------
// parse_intvar: the current token starts an integer variable (or an integer array element / field);
// generates its address into ac and consumes it.
parse_intvar:
    lda tok
    cmp #TK_IDENT
    beq !+
    jmp err_syntax
!:  jsr lookup
    bcs !+
    jmp err_undef
!:  jsr is_outer                // a variable of a routine around the current one (nested routines): its address by gen_desig
    bcs piv_dsg
    ldy #17
    lda (sptr),y
    cmp #T_ARRAY
    bcc piv_plain
piv_dsg:
    jsr gen_desig
    lda etype
    cmp #T_INT
    beq piv_ok
    cmp #T_REAL
    bne piv_bad
    sta valreal
    rts
piv_bad:
    jmp err_type
piv_ok:
    lda #0
    sta valreal
    rts
piv_plain:
    cmp #T_INT
    beq piv_int
    cmp #T_REAL
    bne piv_bad
    sta valreal
    jmp piv_adr
piv_int:
    lda #0
    sta valreal
piv_adr:
    ldy #18
    lda (sptr),y
    sta tmpc1
    iny
    lda (sptr),y
    sta tmpc1+1
    ldy #16
    lda (sptr),y
    cmp #K_VAR
    bne !+
    jsr gc_ldi              // global: its address is a constant
    jsr emit_op_word
    jmp nexttok
!:  cmp #K_LOCAL
    bne !+
    :GCALL(rt_lea)              // local: frame pointer + offset
    jsr emit_op_byte
    jmp nexttok
!:  cmp #K_VARPARAM
    bne piv_bad
    jsr gc_ldl              // var parameter: the cell holds the address
    jsr emit_op_byte
    jmp nexttok

bp_val:                         // Val(s, n, code)
    lda #TK_LPAR
    jsr expect
    jsr expr_string
    jsr gc_push
    jsr comma
    jsr parse_intvar
    lda valreal                 // n may be an integer or a real variable
    pha
    jsr gc_push
    jsr comma
    jsr parse_intvar
    pla
    bne bv_real
    :GCALL(rt_val)
    jmp bv_close
bv_real:
    :GCALL(rt_valreal)
bv_close:
    lda #TK_RPAR
    jmp expect

// ---- Crt procedures ---------------------------------------------------------------------------------------------------------
// bproc2: bfid >= 4, the current token follows the name. Table p2tab: number, routine, number of arguments.
bproc2:
    lda bfid
    cmp #17                     // Exit, Break, Continue, Halt, Inc, Dec (ctlfn.asm)
    bcc !+
    jmp bproc4
!:  cmp #13
    bne !+
    jmp bp_val
!:
#if !NOEXT
    cmp #14                     // New / Dispose (ptrfn.asm)
    bne !+
    jmp bp_new
!:  cmp #15
    bne !+
    jmp bp_dispose
!:
#endif
    ldx #0
b2find:
    lda p2tab,x
    bne !+
    jmp err_syntax
!:  cmp bfid
    beq b2found
    inx
    inx
    inx
    inx
    jmp b2find
b2found:
    lda p2tab+2,x
    pha                         // routine address (high, then low) is kept on the stack
    lda p2tab+1,x
    pha
    lda p2tab+3,x               // number of arguments
    beq b2noarg
    pha
    lda #TK_LPAR
    jsr expect
    jsr expr_int                // first argument
    pla
    cmp #2
    bne b2close
    jsr gc_push             // two arguments: the first one is pushed, the second stays in ac
    jsr comma
    jsr expr_int
b2close:
    lda #TK_RPAR
    jsr expect
    jmp b2emit
b2noarg:                        // no arguments; empty parentheses are allowed
    lda tok
    cmp #TK_LPAR
    bne b2emit
    jsr nexttok
    lda #TK_RPAR
    jsr expect
b2emit:                         // emit "jsr routine" (the address is on the stack: low byte on top)
    pla
    sta tmpc1
    pla
    tax
    lda tmpc1
    jmp gen_jsr

p2tab:
#if HAVEREAL
    .byte 16
    .word rt_randomize
    .byte 0
#endif
    .byte 4
    .word rt_clrscr
    .byte 0
    .byte 5
    .word rt_clreol
    .byte 0
    .byte 6
    .word rt_gotoxy
    .byte 2
    .byte 7
    .word rt_textcolor
    .byte 1
    .byte 8
    .word rt_textbg
    .byte 1
    .byte 9
    .word rt_delay
    .byte 1
    .byte 10
    .word rt_highvideo
    .byte 0
    .byte 11
    .word rt_lowvideo
    .byte 0
    .byte 12
    .word rt_normvideo
    .byte 0
    .byte 0

// ---- Crt functions ---------------------------------------------------------------------------------------------------------------
// bfunc2: bfid >= 7. Table f2tab: number, routine, result type. None of them has arguments.
bfunc2:
    ldx #0
f2find:
    lda f2tab,x
    bne !+
    jmp err_syntax
!:  cmp bfid
    beq f2found
    inx
    inx
    inx
    inx
    jmp f2find
f2found:
    lda f2tab+3,x               // result type
    pha
    lda f2tab+2,x
    pha
    lda f2tab+1,x
    pha
    lda tok                     // empty parentheses are allowed
    cmp #TK_LPAR
    bne f2emit
    jsr nexttok
    lda #TK_RPAR
    jsr expect
f2emit:                         // routine address (low byte on top), then the result type
    pla
    sta tmpc1
    pla
    tax
    pla
    sta etype
    lda #0
    sta edesc
    lda tmpc1
    jmp gen_jsr

f2tab:
    .byte 7
    .word rt_readkey
    .byte T_CHAR
    .byte 8
    .word rt_keypressed
    .byte T_BOOL
    .byte 9
    .word rt_wherex
    .byte T_INT
    .byte 10
    .word rt_wherey
    .byte T_INT
    .byte 0
