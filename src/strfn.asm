// This file is in the public domain: use it, change it, share it, sell it - do whatever you like with it.
// No permission, credit or payment needed. It comes as it is, with no warranty. Enjoy!
// Note: this has only been tested in the VICE emulator, never on real hardware.
// =====================================================================================
// strfn.asm - string support in the compiler: operators and built-in routines
// =====================================================================================
//
// String values are addresses of length-prefixed strings (see rt_strings.asm). A single
// character literal 'x' has type char and is converted to a string (rt_c2s) wherever a string is
// required. Built-in routines are entered in the symbol table with the kinds K_BFUNC / K_BPROC
// (field 18 = routine number) and are parsed here instead of by the general call code:
//
//   functions:  Length(s)  Copy(s, index, count)  Pos(sub, s)  UpCase(c)  Chr(n)  Ord(x)
//   procedures: Delete(var s, index, count)  Insert(src, var s, index)  Str(n, var s)
// (The other built-in routines are in iofn.asm (Crt, Val, read), ptrfn.asm (New, Dispose), realop.asm (numeric functions) and
// ctlfn.asm (Exit, Break, Continue, Halt, Inc, Dec, Odd, Succ, Pred); 'bfid' = the routine number picks the file, see bfunc / bproc.)

// emit_strlit: emit the contents of the string literal in strbuf as inline data (length + chars).
emit_strlit:
    lda strbuf
    jsr emit
    lda strbuf
    beq es_done
    ldx #1
!:  lda strbuf,x
    jsr emit
    cpx strbuf
    beq es_done
    inx
    jmp !-
es_done:
    rts

// expr_string: compile an expression that must be a string (a character is converted).
expr_string:
    jsr expr
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
!:  rts

// expr_int: compile an expression that must be scalar (integer, byte, char or boolean).
expr_int:
    jsr expr
    jsr noreal
    lda etype
    cmp #T_ARRAY
    bcc !+
    jmp err_type
!:  rts

comma:                          // require ','
    lda #TK_COMMA
    jmp expect

// genstrop: A = relational operator token. Emits the string comparison routine for it.
genstrop:
    sta tmpc2
    ldx #0
gs1:
    lda soptab,x
    beq gs_err
    cmp tmpc2
    beq gs_f
    inx
    inx
    inx
    jmp gs1
gs_err:
    jmp err_syntax
gs_f:
    lda soptab+1,x
    pha
    lda soptab+2,x
    tax
    pla
    jmp gen_jsr

soptab:
    .byte TK_EQ
    .word rt_seq
    .byte TK_NE
    .word rt_sne
    .byte TK_LT
    .word rt_slt
    .byte TK_LE
    .word rt_sle
    .byte TK_GT
    .word rt_sgt
    .byte TK_GE
    .word rt_sge
    .byte 0

// parse_strvar: the current token starts a designator that must denote a string variable
// (or a string element of an array). Generates its address into ac; edesc = its descriptor.
parse_strvar:
    lda tok
    cmp #TK_IDENT
    beq !+
    jmp err_syntax
!:  jsr lookup
    bcs !+
    jmp err_undef
!:  ldy #17
    lda (sptr),y
    cmp #T_ARRAY
    bcs !+
    jmp err_type
!:  ldy #16
    lda (sptr),y
    cmp #K_CPARAM               // read-only parameter: cannot be modified
    bne !+
    jmp err_type
!:  jsr gen_desig
    lda etype
    cmp #T_STRING
    beq !+
    jmp err_type
!:  rts

// emit_maxlen: emit the maximum length (byte) of the string type whose descriptor index is A.
emit_maxlen:
    jsr desc_ptr
    ldy #D_HI
    lda (tmpc3),y
    jmp emit

// ---- built-in functions: the current token is the name, sptr its record -------------------------------
bfunc:
    ldy #18
    lda (sptr),y
    sta bfid
    jsr nexttok
    lda bfid
    cmp #7
    bcc bf_args
    cmp #20
    bcc bf_crt
    cmp #34
    bcc bf_num
    jmp bfunc4                  // Odd, Succ, Pred (ctlfn.asm)
bf_num:
    jmp bfunc3                  // numeric functions: Trunc, Sqrt, ... (realop.asm)
bf_crt:
    jmp bfunc2                  // Crt functions (iofn.asm)
bf_args:
    lda #TK_LPAR
    jsr expect
    lda bfid
    cmp #1
    beq bf_length
    cmp #2
    beq bf_copy
    cmp #3
    beq bf_pos
    cmp #4
    beq bf_upcase
    cmp #5
    beq bf_chr
    jmp bf_ord

bf_length:                      // Length(s) -> integer
    jsr expr_string
    :GCALL(rt_slen)
    lda #T_INT
    jmp bf_done
bf_copy:                        // Copy(s, index, count) -> string
    jsr expr_string
    jsr gc_push
    jsr comma
    jsr expr_int
    jsr gc_push
    jsr comma
    jsr expr_int
    :GCALL(rt_copy)
    lda #T_STRING
    jmp bf_done
bf_pos:                         // Pos(sub, s) -> integer
    jsr expr_string
    jsr gc_push
    jsr comma
    jsr expr_string
    :GCALL(rt_pos)
    lda #T_INT
    jmp bf_done
bf_upcase:                      // UpCase(c) -> char
    jsr expr
    lda etype
    cmp #T_CHAR
    beq !+
    jmp err_type
!:  :GCALL(rt_upcase)
    lda #T_CHAR
    jmp bf_done
bf_chr:                         // Chr(n) -> char (the value is already the character code)
    jsr expr_int
    lda #T_CHAR
    jmp bf_done
bf_ord:                         // Ord(x) -> integer (no code needed)
    jsr expr_int
    lda #T_INT
bf_done:
    pha
    lda #TK_RPAR
    jsr expect
    pla
    sta etype
    lda #0
    sta edesc
    rts

// ---- built-in procedures: the current token is the name, sptr its record ----------------------------------
bproc:
    ldy #18
    lda (sptr),y
    sta bfid
    jsr nexttok
    lda bfid
    cmp #4
    bcc bp_args
    jmp bproc2                  // Crt procedures and Val (iofn.asm)
bp_args:
    lda #TK_LPAR
    jsr expect
    lda bfid
    cmp #1
    beq bp_delete
    cmp #2
    beq bp_insert
    jmp bp_str

bp_delete:                      // Delete(var s, index, count)
    jsr parse_strvar
    jsr gc_push
    jsr comma
    jsr expr_int
    jsr gc_push
    jsr comma
    jsr expr_int
    :GCALL(rt_delete)
    jmp bp_close
bp_insert:                      // Insert(src, var s, index)
    jsr expr_string
    jsr gc_push
    jsr comma
    jsr parse_strvar
    lda edesc
    pha                         // descriptor of s: its maximum length is needed after the call
    jsr gc_push
    jsr comma
    jsr expr_int
    pla
    sta tmpc2
    :GCALL(rt_insert)
    lda tmpc2
    jsr emit_maxlen
    jmp bp_close
bp_str:                         // Str(n, var s)   or   Str(x:width:decimals, var s) for a real x
    jsr expr
    lda etype
    cmp #T_REAL
    bne !+
    jmp bp_strreal
!:  cmp #T_ARRAY
    bcc !+
    jmp err_type
!:  jsr gc_push
    jsr comma
    jsr parse_strvar
    lda edesc
    sta tmpc2
    :GCALL(rt_str)
    lda tmpc2
    jsr emit_maxlen
bp_close:
    lda #TK_RPAR
    jmp expect
bp_strreal:                     // the real is pushed, then the address of s, then  jsr rt_fstr  word(width, decimals)  byte(max length)
    jsr parse_realfmt
    :GCALL(rt_fpush)
    jsr comma
    jsr parse_strvar
    lda edesc
    sta tmpc2
    :GCALL(rt_fstr)
    lda fmt_w
    ldx fmt_d
    jsr emit_word
    lda tmpc2
    jsr emit_maxlen
    jmp bp_close
