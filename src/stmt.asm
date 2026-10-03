// This file is in the public domain: use it, change it, share it, sell it - do whatever you like with it.
// No permission, credit or payment needed. It comes as it is, with no warranty. Enjoy!
// Note: this has only been tested in the VICE emulator, never on real hardware.
// =====================================================================================
// stmt.asm - statements
// =====================================================================================
//
//   stmt = [ BEGIN stmt {; stmt} END | assignment | IF | WHILE | REPEAT | FOR
//            | WRITE/WRITELN call ]            (an empty statement is allowed)
//
// Control flow is compiled with JMP instructions and the runtime routine rt_jf
// ("jump if the accumulator is false"). Forward jumps whose target is not yet known are
// emitted with a placeholder (JPLACE) and fixed up later (PATCH). The placeholder addresses
// and loop heads are kept on the hardware stack, so statements can nest freely.
//
// Break and Continue are built-in procedures (ctlfn.asm). Their jumps go forward to places that are only known when the loop
// has been compiled, so each loop calls loop_enter before its body and resolves the chains of pending jumps when it knows
// the targets (res_here / loop_done / loop_exit): Break goes behind the loop, Continue to the next test of the condition
// (while: the head L1, repeat: the 'until' test, for: the end test). 'sdepth' counts the values that for and case keep on
// the software stack, so that a Break inside them can drop what the loop body pushed.

stmt:
    lda tok
    cmp #TK_BEGIN
    bne !+
    jmp st_begin
!:  cmp #TK_IF
    bne !+
    jmp st_if
!:  cmp #TK_WHILE
    bne !+
    jmp st_while
!:  cmp #TK_REPEAT
    bne !+
    jmp st_repeat
!:  cmp #TK_FOR
    bne !+
    jmp st_for
!:  cmp #TK_CASE
    bne !+
    jmp st_case
!:  cmp #TK_IDENT
    bne !+
    jmp st_ident
!:  rts                         // anything else: empty statement

// ---- BEGIN stmt ; stmt ; ... END ----------------------------------------------------------------
st_begin:
    jsr nexttok                 // skip BEGIN
sb1:
    jsr stmt
    lda tok
    cmp #TK_SEMI                // statements are separated by ';'
    bne sb2
    jsr nexttok
    jmp sb1
sb2:
    lda #TK_END
    jmp expect

// ---- IF cond THEN stmt [ELSE stmt] ----------------------------------------------------------------
//   <cond>  jsr rt_jf P1      jump to P1 if the condition is false
//   <then>  jmp P2            (only with ELSE) skip the else part
//   P1:     <else>
//   P2:
st_if:
    jsr nexttok
    jsr expr
    jsr needbool
    jsr gc_jf
    :JPLACE()                   // P1 placeholder (address pushed on hardware stack)
    lda #TK_THEN
    jsr expect
    jsr stmt                    // then part
    lda tok
    cmp #TK_ELSE
    bne si_noelse
    jsr nexttok                 // skip ELSE
    pla                         // take P1 off the stack for now
    sta tmpc1
    pla
    sta tmpc1+1
    lda #$4c                    // jmp over the else part
    jsr emit
    :JPLACE()                   // P2 placeholder
    jsr patch                   // P1 := here (start of else part)
    jsr stmt                    // else part
    :PATCH()                    // P2 := here
    rts
si_noelse:
    :PATCH()                    // P1 := here
    rts

// ---- WHILE cond DO stmt ------------------------------------------------------------------------------
//   L1: <cond>  jsr rt_jf P
//       <body>
//       jmp L1
//   P:
st_while:
    jsr nexttok
    lda cpc+1                   // L1 = current address, kept on the stack
    pha
    lda cpc
    pha
    jsr expr
    jsr needbool
    jsr gc_jf
    :JPLACE()                   // P
    lda #TK_DO
    jsr expect
    jsr loop_enter              // (Break / Continue chains, ctlfn.asm)
    jsr stmt
    pla                         // P
    sta tmpc1
    pla
    sta tmpc1+1
    pla                         // L1
    sta tmpc2
    pla
    sta tmpc2+1
    lda #$4c                    // jmp L1
    jsr emit
    lda tmpc2
    ldx tmpc2+1
    jsr emit_word
    jsr patch                   // P := here
    jmp loop_done               // Continue -> L1 (tmpc2), Break -> here

// ---- REPEAT stmt ; stmt ... UNTIL cond -------------------------------------------------------------
//   L1: <body>
//       <cond>  jsr rt_jf L1      loop again while the condition is false
st_repeat:
    jsr nexttok
    lda cpc+1                   // L1
    pha
    lda cpc
    pha
    jsr loop_enter
sr1:
    jsr stmt
    lda tok
    cmp #TK_SEMI
    bne sr2
    jsr nexttok
    jmp sr1
sr2:
    lda #TK_UNTIL
    jsr expect
    ldx #2                      // Continue goes to the test of the condition
    jsr res_here
    jsr expr
    jsr needbool
    jsr gc_jf
    pla                         // inline word of rt_jf = L1
    sta tmpc2
    pla
    tax
    lda tmpc2
    jsr emit_word
    ldx #0                      // Break goes behind the test
    jsr res_here
    jmp loop_exit

// ---- FOR v := a TO|DOWNTO b DO stmt ------------------------------------------------------------------
//       <a>  v := ac
//       <b>  rt_push              the end value stays on the software stack during the loop
//       v <= limit (TO) or v >= limit (DOWNTO)       jsr rt_jf EXIT      loop not run at all
//   L1: <body>
//       v <> limit                                    jsr rt_jf EXIT      stop BEFORE incrementing,
//       v := v + 1 (or - 1)      jmp L1                                  so byte loops to 255 end
//   EXIT: jsr rt_drop            discard the end value
// Keeping the limit on the stack (not in a hidden variable) makes for loops safe in recursion.
// Hardware stack while compiling (top first): [L1], P1 (lo,hi), direction, kind, variable operand (lo,hi).
st_for:
    jsr nexttok
    lda tok                     // control variable
    cmp #TK_IDENT
    beq !+
    jmp err_syntax
!:  jsr lookup
    bcs !+
    jmp err_undef
!:  ldy #16
    lda (sptr),y
    cmp #K_VAR                  // must be a global (16 or 8 bit) or a local variable
    beq !+
    cmp #K_VARB
    beq !+
    cmp #K_LOCAL
    beq !+
    jmp err_type
!:  ldy #17
    lda (sptr),y
    cmp #T_PTR                  // an ordinal type: integer, byte, char, boolean
    bcc !+
    jmp err_type
!:  ldy #19
    lda (sptr),y
    pha                         // operand (address / offset), high
    ldy #18
    lda (sptr),y
    pha                         // low
    ldy #16
    lda (sptr),y
    pha                         // kind
    jsr nexttok
    lda #TK_ASSIGN
    jsr expect
    jsr expr                    // start value
    jsr noreal
    tsx                         // v := start
    lda $0102,x
    sta tmpc1
    lda $0103,x
    sta tmpc1+1
    lda $0101,x
    jsr gen_store
    lda tok                     // TO or DOWNTO
    cmp #TK_TO
    bne !+
    lda #0
    jmp fd
!:  cmp #TK_DOWNTO
    beq !+
    jmp err_syntax
!:  lda #1
fd: pha                         // direction
    jsr nexttok
    jsr expr                    // end value
    jsr noreal
    jsr gc_push             // the end value stays on the software stack during the loop
    inc sdepth                  // (counted for Break / Continue, ctlfn.asm)
    lda #TK_DO
    jsr expect
    tsx                         // initial test: skip the loop if v is already past the limit
    lda $0103,x
    sta tmpc1
    lda $0104,x
    sta tmpc1+1
    lda $0101,x
    sta forflag
    lda #0
    sta fmode
    lda $0102,x
    jsr for_test
    jsr gc_jf
    :JPLACE()                   // P1: exit when the loop does not run at all
    lda cpc+1                   // L1: start of the body
    pha
    lda cpc
    pha
    jsr loop_enter
    jsr stmt                    // loop body
    ldx #2                      // Continue goes to the end test
    jsr res_here
    pla                         // L1
    sta tmpc2
    pla
    sta tmpc2+1
    tsx                         // end test: leave when v has reached the limit, BEFORE incrementing
    lda $0105,x                 // (so a byte loop up to 255 does not wrap around)
    sta tmpc1
    lda $0106,x
    sta tmpc1+1
    lda $0103,x
    sta forflag
    lda #1
    sta fmode
    lda $0104,x
    jsr for_test
    jsr gc_jf
    :JPLACE()                   // P2: exit when v = limit
    pla
    sta tmpc1                   // tmpc1 = P2
    pla
    sta tmpc1+1
    tsx                         // v := v + 1 / v - 1
    lda $0105,x
    sta tmpc3
    lda $0106,x
    sta tmpc3+1
    lda $0103,x
    sta forflag
    lda $0104,x
    sta forkind
    jsr gen_incdec
    lda #$4c                    // jmp L1
    jsr emit
    lda tmpc2
    ldx tmpc2+1
    jsr emit_word
    jsr patch                   // P2 := here (loop exit)
    pla                         // P1
    sta tmpc1
    pla
    sta tmpc1+1
    pla                         // direction, kind, operand are no longer needed
    pla
    pla
    pla
    jsr patch                   // P1 := here (loop exit)
    ldx #0                      // Break leaves here, with the end value still on the software stack
    jsr res_here
    jsr loop_exit
    dec sdepth
    :GCALL(rt_drop)             // discard the end value
    rts

// for_test: emit a comparison of the control variable with the limit that is on the software stack.
// A = kind of the variable, tmpc1 = its operand, forflag = direction.
// fmode 0: v <= limit (to) / v >= limit (downto);  fmode 1: v <> limit.
for_test:
    jsr gen_load                // ac = v
    jsr gc_push
    :GCALL(rt_peek2)            // ac = limit
    lda fmode
    bne ft_ne
    lda forflag
    bne ft_ge
    :GCALL(rt_le)
    rts
ft_ge:
    :GCALL(rt_ge)
    rts
ft_ne:
    :GCALL(rt_ne)
    rts

// ---- CASE expr OF label {, label} : stmt ; ... [ELSE stmt] END ---------------------------------------
//   label = constant | constant .. constant
//       <expr>  rt_push                the selector stays on the software stack during the whole case
//   per arm, per label:  selector <> label  (range: not (sel >= lo and sel <= hi))   jsr rt_jf BODY
//   after the labels:    jmp NEXT       (this arm does not match)
//   BODY: <stmt>  jmp END               NEXT: next arm
//   END:  jsr rt_drop
// Hardware stack while compiling: a 2-byte zero marker, then the placeholders of the 'jmp END' of
// the finished arms; during one arm the BODY placeholders (cs_n of them) and the NEXT placeholder
// are on top of that.
st_case:
    jsr nexttok
    jsr expr                    // selector
    jsr noreal
    jsr gc_push
    inc sdepth                  // (the selector: counted for Break / Continue, ctlfn.asm)
    lda #TK_OF
    jsr expect
    lda #0                      // marker below the list of END placeholders
    pha
    pha
sc_arm:
    lda tok
    cmp #TK_END
    bne !+
    jmp sc_end
!:  cmp #TK_ELSE
    bne !+
    jmp sc_else
!:  cmp #TK_SEMI                // empty arm
    bne !+
    jsr nexttok
    jmp sc_arm
!:  lda #0
    sta cs_n
sc_label:
    jsr parse_const             // first (or only) constant of the label
    lda tok
    cmp #TK_DOTDOT
    beq sc_range
    :GCALL(rt_peek1)            // selector <> constant: skip to BODY when equal
    jsr gc_push
    jsr gc_ldi
    lda cval
    ldx cval+1
    jsr emit_word
    :GCALL(rt_ne)
    jmp sc_test
sc_range:
    lda cval                    // low bound
    sta cs_lo
    lda cval+1
    sta cs_lo+1
    jsr nexttok
    jsr parse_const             // high bound
    :GCALL(rt_peek1)            // selector >= low
    jsr gc_push
    jsr gc_ldi
    lda cs_lo
    ldx cs_lo+1
    jsr emit_word
    :GCALL(rt_ge)
    jsr gc_push             // the first result is now on top: the selector is the second word
    :GCALL(rt_peek2)
    jsr gc_push
    jsr gc_ldi              // selector <= high
    lda cval
    ldx cval+1
    jsr emit_word
    :GCALL(rt_le)
    :GCALL(rt_and)              // both
    :GCALL(rt_bnot)             // then a false 'ne'-style flag means "inside the range"
sc_test:
    jsr gc_jf               // jump to BODY when the flag is false
    :JPLACE()
    inc cs_n
    lda tok
    cmp #TK_COMMA
    bne !+
    jsr nexttok
    jmp sc_label
!:  lda #TK_COLON
    jsr expect
    lda #$4c                    // no label matched: jmp NEXT
    jsr emit
    :JPLACE()
    pla                         // NEXT placeholder -> cs_next while the BODY placeholders are patched
    sta cs_next
    pla
    sta cs_next+1
sc_patchb:
    :PATCH()                    // BODY := here
    dec cs_n
    bne sc_patchb
    lda cs_next+1               // NEXT back on the stack
    pha
    lda cs_next
    pha
    jsr stmt                    // body
    pla                         // NEXT
    sta cs_next
    pla
    sta cs_next+1
    lda #$4c                    // jmp END
    jsr emit
    :JPLACE()
    lda cs_next
    sta tmpc1
    lda cs_next+1
    sta tmpc1+1
    jsr patch                   // NEXT := here (the next arm)
    lda tok
    cmp #TK_SEMI
    bne !+
    jsr nexttok
!:  jmp sc_arm
sc_else:
    jsr nexttok
sc_el1:
    jsr stmt
    lda tok
    cmp #TK_SEMI
    bne sc_end
    jsr nexttok
    jmp sc_el1
sc_end:
    lda #TK_END
    jsr expect
sc_done:
    pla                         // patch every 'jmp END' placeholder (lo, hi); the marker has hi = 0
    sta tmpc1
    pla
    sta tmpc1+1
    beq !+
    jsr patch
    jmp sc_done
!:  dec sdepth
    :GCALL(rt_drop)             // discard the selector
    rts

// ---- statements that start with an identifier ------------------------------------------------------------
st_ident:
    jsr lookup_must             // (reports "undefined identifier" itself)
!:  ldy #17                     // array or string variable: the statement is an element or
    lda (sptr),y                // whole-structure assignment
    cmp #T_ARRAY
    bcc !+
    jmp st_desig
!:  cmp #T_PTR                  // pointer variable: p := ...  or  p^ := ...  (designator code handles both)
    bne !+
    jmp st_desig
!:  ldy #16
    lda (sptr),y
    cmp #K_VAR
    beq st_atr
    cmp #K_VARB
    beq st_atr
    cmp #K_LOCAL
    beq st_atr
    cmp #K_VARPARAM
    beq st_atr
    cmp #K_PROC
    beq st_ptr
    cmp #K_BPROC
    beq st_bptr
    cmp #K_PROCU
    bne !+
    jmp gen_call                // procedure call
!:  cmp #K_FUNC
    beq st_ftr
    jmp err_syntax   // constants and types cannot start a statement

st_atr:                         // trampolines (the targets are too far for a branch)
    jmp st_assign
st_ptr:
    jmp st_proc
st_bptr:
    jmp bproc                   // built-in procedure with arguments (strfn.asm)
st_ftr:
    jmp st_funcres

// assignment to an array/string variable or one of its elements:   a[i, j] := expr
// The target address is computed first and saved on the software stack, then the right hand
// side is evaluated and stored through the address.
st_desig:
    ldy #16
    lda (sptr),y
    cmp #K_CPARAM               // value parameters of structured type are read-only
    bne !+
    jmp err_type
!:  jsr gen_desig               // ac = target address; etype/edesc = target type
    lda edesc
    pha
    lda etype
    pha
    jsr gc_push
    jsr assign_start
    jsr assign_rhs
    pla                         // target type
    sta tmpc2
    pla
    sta tmpc2+1                 // target descriptor
    lda tmpc2
    cmp #T_ARRAY
    bcs sd_struct
    jsr typeok                  // scalar element
    lda tmpc2
    sta etype
    jmp gen_stp                 // store through the address (word or byte)
sd_struct:
    cmp #T_STRING
    beq sd_str
    lda etype                   // whole array or record: the source must have the same type
    cmp tmpc2
    bne sd_bad
    ldx edesc
    lda tmpc2+1
    jsr descsame
    bne sd_bad
    :GCALL(rt_amove)            // copy the bytes of the array
    lda tmpc2+1
    jsr desc_ptr
    ldy #D_SIZE+1
    lda (tmpc3),y
    tax
    dey
    lda (tmpc3),y
    jmp emit_word
sd_str:                         // string assignment: the value is a string, or a character
    lda etype
    cmp #T_CHAR
    bne !+
    jsr gc_c2s
    lda #T_STRING
    sta etype
!:  lda etype
    cmp #T_STRING
    bne sd_bad
    :GCALL(rt_sset)             // copies at most the target's maximum length
    lda tmpc2+1
    jmp emit_maxlen
sd_bad:
    jmp err_type

// "fname := expr" inside function fname assigns the result (stored in frame slot 0)
st_funcres:
    lda sptr                    // only the function currently being compiled
    cmp curproc
    bne sf_bad
    lda sptr+1
    cmp curproc+1
    bne sf_bad
    lda #0
    pha                         // operand high
    pha                         // operand low
    lda #K_LOCAL
    pha                         // kind
    ldy #17
    lda (sptr),y
    pha                         // result type
    jmp sa_go
sf_bad:
    jmp err_syntax

// assignment: var := expr   (the types must match)
st_assign:
    ldy #19                     // keep operand, kind and type on the stack across the expression
    lda (sptr),y
    pha
    ldy #18
    lda (sptr),y
    pha
    ldy #16
    lda (sptr),y
    pha                         // kind
    ldy #17
    lda (sptr),y
    pha                         // variable type
sa_go:
    jsr nexttok
    jsr assign_start            // ':=' (or nothing for Inc / Dec, ctlfn.asm)
    jsr assign_rhs
    pla
    sta asgtype
    jsr typeok                  // variable type must fit the expression type (an integer is converted to real)
    pla
    tax                         // kind
    pla
    sta tmpc1
    pla
    sta tmpc1+1
    txa
    ldy asgtype
    cpy #T_REAL
    bne !+
    jmp gen_fstore              // FAC -> real variable
!:  jmp gen_store               // emit the store for this kind of variable

// wr_width: the optional ":width" after a value that is written: fmt_w = the width (0 = none).
wr_width:
    lda #0
    sta fmt_w
#if !NOEXT
    lda tok
    cmp #TK_COLON
    bne !+
    jsr nexttok
    jsr parse_const
    lda cval
    sta fmt_w
!:
#endif
    rts

// built-in procedures WRITE / WRITELN:   write( item {, item} )
// An item is a string literal or an expression (printed according to its type), optionally followed by
// :width (integer, char, boolean, string) or :width:decimals (real).
st_proc:
    ldy #18
    lda (sptr),y
    cmp #3
    bcc !+
    jmp st_read                 // read / readln (iofn.asm)
!:  pha                         // procedure id: 1 = write, 2 = writeln
    jsr nexttok
    lda tok
    cmp #TK_LPAR
    beq !+
    jmp sp_done                 // no argument list
!:  jsr nexttok
sp_arg:
    lda tok
    cmp #TK_STR
    bne sp_expr
    :GCALL(rt_wlit)             // string literal: text is stored inline after the jsr
    lda strbuf                  // length byte
    jsr emit
    lda strbuf
    beq sp_strdone              // empty string
    ldx #1
!:  lda strbuf,x                // characters
    jsr emit
    cpx strbuf
    beq sp_strdone
    inx
    jmp !-
sp_strdone:
    jsr nexttok
    jmp sp_next
sp_expr:
    jsr expr                    // choose the print routine from the type of the expression
    lda etype
    cmp #T_REAL
    bne !+
    jsr write_real              // x  or  x:width  or  x:width:decimals (realop.asm)
    jmp sp_next
!:  jsr wr_width               // optional :width
    lda etype
    cmp #T_BOOL
    bne !+
    :WOP(rt_wbool, rt_wboolw)
    jmp sp_next
!:  cmp #T_STRING
    bne !+
    :WOP(rt_wstr, rt_wstrw)
    jmp sp_next
!:  cmp #T_ARRAY
    bcc !+
    jmp err_type   // arrays cannot be written
!:  cmp #T_CHAR
    bne !+
    :WOP(rt_wch, rt_wchw)
    jmp sp_next
!:  :WOP(rt_wint, rt_wintw)
sp_next:
    lda tok
    cmp #TK_COMMA               // more items?
    bne !+
    jsr nexttok
    jmp sp_arg
!:  lda #TK_RPAR
    jsr expect
sp_done:
    pla
    cmp #2                      // WRITELN also prints a new line
    bne !+
    :GCALL(rt_wln)
!:  rts
