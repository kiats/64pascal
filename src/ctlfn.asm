// This file is in the public domain: use it, change it, share it, sell it - do whatever you like with it.
// No permission, credit or payment needed. It comes as it is, with no warranty. Enjoy!
// Note: this has only been tested in the VICE emulator, never on real hardware.
// =====================================================================================
// ctlfn.asm - Exit, Break, Continue, Halt, Inc, Dec, Odd, Succ, Pred, shl / shr, forward declarations
// =====================================================================================
//
// Built-in procedures (bfid 17..22, entered through bproc2 in iofn.asm) and functions (bfid 34..36, bfunc in strfn.asm):
//
//   Exit            leave the routine (in the main program: end the program)
//   Break           leave the innermost loop;  Continue  go on with the next turn of the innermost loop
//   Halt            end the program
//   Inc(v) Inc(v, n) Dec(v) Dec(v, n)    v := v + n / v - n  (n = 1 when left out); v may be any variable the assignment
//                   statement accepts: the text of v is read twice (a copy of the lexer state is kept, see inc_rhs)
//   Odd(n)          boolean   Succ(n) Pred(n)   n + 1 / n - 1 with the type of n
//   a shl n, a shr n   (in 'term', expr.asm)  n must be a constant 0..15
//
// Break, Continue and Exit jump forward to a place that is not known yet. The unresolved jumps of a loop are kept as a CHAIN:
// the 16 bit operand of each emitted 'jmp' holds the (physical) address of the operand of the previous one (0 = end), and
// 'brkhead' / 'conhead' / 'exithead' hold the last one. When the target is known every operand in the chain gets it.
// A loop saves the chains of the loop around it in 'ctxstk' (loop_enter / loop_exit).
// Loops and case statements keep values on the software stack (the end value of a for loop, the selector of a case):
// 'sdepth' counts them and Break / Continue drop the ones that were pushed inside the loop (rt_drop) before they jump.

// ---- state (RAM) ---------------------------------------------------------------------------------------
heads:                          // keep these three together: Break = heads + 0, Continue = heads + 2, Exit = heads + 4
brkhead:  .word 0
conhead:  .word 0
exithead: .word 0
sdepth:   .byte 0               // words on the software stack that belong to statements being compiled (for limit, case selector)
loopsd:   .byte 0               // sdepth when the innermost loop body started
inloop:   .byte 0               // number of loops around the statement being compiled
ctxsp:    .byte 0               // top of ctxstk
ctxstk:   .fill 40, 0           // 8 nesting levels: brkhead (2), conhead (2), loopsd (1)
incmode:  .byte 0               // 1 = Inc, 2 = Dec while the target of Inc / Dec is being compiled, else 0
inc_lt:   .byte 0               // type of the target (the left operand of the addition)
inc_op:   .byte 0               // TK_PLUS / TK_MINUS
lex_buf:  .fill 24, 0           // saved lexer state: src (2), tok, tokval (2), line (2), idbuf (17)

// ---- chains --------------------------------------------------------------------------------------------
// chain_resolve: X = 0, 2 or 4 (which chain of 'heads'), tmpc2 = the address the jumps must go to. Empties the chain.
chain_resolve:
    lda heads,x
    sta tmpc1
    lda heads+1,x
    sta tmpc1+1
    lda #0
    sta heads,x
    sta heads+1,x
chain_resolve_at:               // the chain starts at tmpc1 (a forward declared routine), tmpc2 = the address
cr_loop:
    lda tmpc1
    ora tmpc1+1
    beq cr_done
    ldy #0
    lda (tmpc1),y               // next operand of the chain
    sta tmpc3
    lda tmpc2
    sta (tmpc1),y               // this operand := the target
    iny
    lda (tmpc1),y
    sta tmpc3+1
    lda tmpc2+1
    sta (tmpc1),y
    lda tmpc3
    sta tmpc1
    lda tmpc3+1
    sta tmpc1+1
    jmp cr_loop
cr_done:
    rts

// res_here: X = chain number (0, 2, 4): make the jumps of that chain go to the current address.
res_here:
    lda cpc
    sta tmpc2
    lda cpc+1
    sta tmpc2+1
    jmp chain_resolve

// chain_jmp: X = chain number. Emit a 'jmp' whose operand is added to the chain.
chain_jmp:
    stx cj_x
    lda #$4c
    jsr emit
    ldx cj_x
    lda heads,x                 // old head -> stack
    pha
    lda heads+1,x
    pha
    lda cout                    // the new head is the operand that is emitted now
    sta heads,x
    lda cout+1
    sta heads+1,x
    pla
    tax                         // X = high byte of the old head
    pla                         // A = low byte
    jmp emit_word
cj_x: .byte 0

// ---- loops ---------------------------------------------------------------------------------------------
// loop_enter: a loop body starts (called before the body is compiled).
loop_enter:
    ldx ctxsp
    cpx #40
    bcc !+
    jmp err_syntax   // loops nested more than 8 deep
!:  lda brkhead
    sta ctxstk,x
    inx
    lda brkhead+1
    sta ctxstk,x
    inx
    lda conhead
    sta ctxstk,x
    inx
    lda conhead+1
    sta ctxstk,x
    inx
    lda loopsd
    sta ctxstk,x
    inx
    stx ctxsp
    lda #0
    sta brkhead
    sta brkhead+1
    sta conhead
    sta conhead+1
    lda sdepth
    sta loopsd
    inc inloop
    rts

// loop_exit: the loop has been compiled and its chains resolved: back to the chains of the enclosing loop.
loop_exit:
    ldx ctxsp
    dex
    lda ctxstk,x
    sta loopsd
    dex
    lda ctxstk,x
    sta conhead+1
    dex
    lda ctxstk,x
    sta conhead
    dex
    lda ctxstk,x
    sta brkhead+1
    dex
    lda ctxstk,x
    sta brkhead
    stx ctxsp
    dec inloop
    rts

// loop_done: end of a loop: Continue goes to tmpc2 (preset by the caller), Break to the current address.
loop_done:
    ldx #2
    jsr chain_resolve
    ldx #0
    jsr res_here
    jmp loop_exit

// ---- Exit, Break, Continue, Halt, Inc, Dec: bproc2 jumps here for bfid >= 17 ------------------------------------
bproc4:
    lda bfid
    cmp #17
    beq bp4_exit
    cmp #18
    beq bp4_break
    cmp #19
    beq bp4_cont
    cmp #20
    beq bp4_halt
    sec                         // 21 = Inc, 22 = Dec
    sbc #20
    sta incmode
    lda #TK_LPAR
    jsr expect
    jsr lex_save                // the target is compiled twice (as the variable to store into, and as the left operand)
    jmp st_ident

bp4_exit:
    jsr empty_parens
    lda inproc
    beq bp4_halt
    ldx #4
    jmp chain_jmp
bp4_halt:
    jsr empty_parens
    lda #$4c                    // jmp rt_halt
    jsr emit
    lda #<rt_halt
    ldx #>rt_halt
    jmp emit_word
bp4_break:
    ldx #0
    jmp bp4_loopjmp
bp4_cont:
    ldx #2
bp4_loopjmp:
    stx cj_x
    jsr empty_parens
    lda inloop
    bne !+
    jmp err_syntax   // Break / Continue outside a loop
!:  lda sdepth
    sec
    sbc loopsd
    sta cj_n
bl_drop:
    lda cj_n                    // drop what statements inside the loop left on the software stack
    beq bl_jmp
    :GCALL(rt_drop)
    dec cj_n
    jmp bl_drop
bl_jmp:
    ldx cj_x
    jmp chain_jmp
cj_n: .byte 0

empty_parens:                   // optional "()" after the name
    lda tok
    cmp #TK_LPAR
    bne !+
    jsr nexttok
    lda #TK_RPAR
    jmp expect
!:  rts

// ---- Inc / Dec -------------------------------------------------------------------------------------------
// The target v is compiled by the code of the assignment statement (st_assign, st_desig) which asks assign_start / assign_rhs
// where it would expect ':=' and the right hand side. Here (incmode <> 0) there is no ':=', and the right hand side is
// "v + n": the lexer goes back to the start of v, compiles it as a factor (the left operand), and then n.
lex_save:
    lda src
    sta lex_buf
    lda src+1
    sta lex_buf+1
    lda tok
    sta lex_buf+2
    lda tokval
    sta lex_buf+3
    lda tokval+1
    sta lex_buf+4
    lda line
    sta lex_buf+5
    lda line+1
    sta lex_buf+6
    ldx #16
!:  lda idbuf,x
    sta lex_buf+7,x
    dex
    bpl !-
    rts

lex_restore:
    lda lex_buf
    sta src
    lda lex_buf+1
    sta src+1
    lda lex_buf+2
    sta tok
    lda lex_buf+3
    sta tokval
    lda lex_buf+4
    sta tokval+1
    lda lex_buf+5
    sta line
    lda lex_buf+6
    sta line+1
    ldx #16
!:  lda lex_buf+7,x
    sta idbuf,x
    dex
    bpl !-
    rts

assign_start:                   // where the assignment statement expects ':='
    lda incmode
    bne !+
    lda #TK_ASSIGN
    jmp expect
!:  rts

assign_rhs:                     // where the assignment statement compiles its right hand side
    lda incmode
    bne !+
    jmp expr
!:  // fall through

inc_rhs:
    ldx incmode
    lda incops-1,x
    sta inc_op
    lda #0
    sta incmode
    lda tok                     // ',' (an amount follows) or ')'
    pha
    jsr lex_restore             // back to the start of the target
    jsr factor                  // its value is the left operand
    jsr noreal
    lda etype
    cmp #T_ARRAY
    bcc !+
    jmp err_type
!:  sta inc_lt
    jsr push_left
    pla
    cmp #TK_COMMA
    bne ir_one
    jsr nexttok
    jsr expr                    // the amount
    jsr noreal
    jmp ir_op
ir_one:
    jsr gc_ldi              // the amount 1
    lda #1
    ldx #0
    jsr emit_word
    lda #T_INT
    sta etype
ir_op:
    lda inc_op                  // left operand + / - amount: the sum is an integer ...
    ldx inc_lt
    jsr numop
    lda inc_lt                  // ... but it goes back into the target, so it takes the type of the target (a char stays a
    sta etype                   // char, a byte a byte); the assignment code then stores it like any other value
    lda #TK_RPAR
    jmp expect
incops: .byte TK_PLUS, TK_MINUS

// ---- Odd, Succ, Pred: bfunc jumps here for bfid >= 34 --------------------------------------------------------------
// Machine code is emitted directly (ac = $04): Odd:  lda ac; and #1; sta ac; lda #0; sta ac+1
//                                                Succ: inc ac; bne +; inc ac+1          Pred: lda ac; bne +; dec ac+1; dec ac
bfunc4:
    lda #TK_LPAR
    jsr expect
    jsr expr_int
    lda etype
    pha
    lda bfid
    sec
    sbc #34                     // 0 Odd, 1 Succ, 2 Pred
    tax
    lda code_len,x
    sta cj_n
    lda code_off,x
    tax
!:  lda ctl_code,x
    jsr emit
    inx
    dec cj_n
    bne !-
    pla                         // Succ and Pred keep the type, Odd gives a boolean
    ldx bfid
    cpx #34
    bne !+
    lda #T_BOOL
!:  jmp bf_done                 // sets etype, edesc, expects ')'
code_len: .byte 10, 6, 8
code_off: .byte 0, 10, 16
ctl_code:
    .byte $a5, $04, $29, $01, $85, $04, $a9, $00, $85, $05     // Odd
    .byte $e6, $04, $d0, $02, $e6, $05                         // Succ
    .byte $a5, $04, $d0, $02, $c6, $05, $c6, $04               // Pred

// ---- shl / shr ------------------------------------------------------------------------------------------------------
// tm_shift: 'term' found shl or shr (A = the token) after its left operand (in ac). The count must be a constant.
tm_shift:
    pha
    jsr noreal
    jsr nexttok
    jsr parse_const
    lda cval+1
    bne sh_bad
    lda cval
    cmp #16
    bcs sh_bad
    sta cj_n
    pla
    cmp #TK_SHL
    beq sh_left
sh_r:
    lda cj_n                    // shr: lsr ac+1; ror ac
    beq sh_done
    lda #$46
    jsr emit
    lda #$05
    jsr emit
    lda #$66
    jsr emit
    lda #$04
    jsr emit
    dec cj_n
    jmp sh_r
sh_left:
    lda cj_n                    // shl: asl ac; rol ac+1
    beq sh_done
    lda #$06
    jsr emit
    lda #$04
    jsr emit
    lda #$26
    jsr emit
    lda #$05
    jsr emit
    dec cj_n
    jmp sh_left
sh_done:
    lda #T_INT
    sta etype
    rts
sh_bad:
    jmp err_syntax   // the shift count must be a constant 0..15

// ---- forward declarations ---------------------------------------------------------------------------------------
// A routine declared with 'forward' has byte 30 of its symbol record set and the chain of the calls emitted before its
// definition in the code address field (18/19); the definition resolves the chain (do_proc, proc.asm).

// is_forward: Z set if the current token is the word FORWARD.
is_forward:
    lda tok
    cmp #TK_IDENT
    bne if_no
    ldx #7
!:  lda idbuf,x
    cmp fwd_word,x
    bne if_no
    dex
    bpl !-
    lda #0
    rts
if_no:
    lda #1
    rts
fwd_word: .byte 7, 'F', 'O', 'R', 'W', 'A', 'R', 'D'

// check_forward: every forward declared routine must have been defined (E_UNDEF otherwise). Called after the declarations.
check_forward:
    lda #<SYM_BASE
    sta tmpc1
    lda #>SYM_BASE
    sta tmpc1+1
cf_loop:
    lda tmpc1
    cmp symp
    bne !+
    lda tmpc1+1
    cmp symp+1
    beq cf_done
!:  ldy #16
    lda (tmpc1),y
    cmp #K_PROCU
    beq cf_chk
    cmp #K_FUNC
    bne cf_next
cf_chk:
    ldy #30
    lda (tmpc1),y
    beq cf_next
cf_bad:
    jmp err_undef
cf_next:
    clc
    lda tmpc1
    adc #SYM_SIZE
    sta tmpc1
    bcc cf_loop
    inc tmpc1+1
    jmp cf_loop
cf_done:
    rts
