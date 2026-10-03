// This file is in the public domain: use it, change it, share it, sell it - do whatever you like with it.
// No permission, credit or payment needed. It comes as it is, with no warranty. Enjoy!
// Note: this has only been tested in the VICE emulator, never on real hardware.
// =====================================================================================
// lexer.asm - tokenizer
// =====================================================================================
//
// nexttok reads the next token from the source at (src) and leaves:
//   tok      token code (TK_*)
//   tokval   value of a number token
//   idbuf    name of an identifier token (upper-cased, length byte first, max 15 chars)
//   strbuf   contents of a string token (length byte first)
// Whitespace, { } comments, (* *) comments and // comments are skipped. 'line' counts LFs.

// ---- character helpers ------------------------------------------------------------------
getch:                          // A = current source character (Y is destroyed)
    ldy #0
    lda (src),y
    rts

peek2:                          // A = the character after the current one
    ldy #1
    lda (src),y
    rts

adv:                            // step to the next source character
    inc src
    bne !+
    inc src+1
!:  rts

incline:                        // count a line feed and tell the front end (compile_progress) which line is being compiled
    inc line
    bne !+
    inc line+1
!:  jmp compile_progress        // (defined by the program that contains the compiler; keeps A, X and Y)

isalpha:                        // carry set if A is a letter or '_' (A is preserved)
    cmp #'_'
    beq ia_yes
    pha
    ora #$20                    // fold to lower case
    cmp #'a'
    bcc ia_no
    cmp #'{'                    // 'z' + 1
    bcs ia_no
    pla
ia_yes:
    sec
    rts
ia_no:
    pla
    clc
    rts

isdigit:                        // carry set if A is '0'..'9' (A is preserved)
    cmp #'0'
    bcc id_no
    cmp #':'                    // '9' + 1
    bcc id_yes
id_no:
    clc
    rts
id_yes:
    sec
    rts

// ---- nexttok: main entry ------------------------------------------------------------------
nexttok:
nt_ws:
    jsr getch
    bne nt_c1
    lda #TK_EOF                 // 0 byte = end of source (not consumed)
    sta tok
    rts
nt_c1:
    cmp #$0a                    // line feed: count it and skip
    bne nt_c2
    jsr incline
    jsr adv
    jmp nt_ws
nt_c2:
    cmp #$21                    // anything below '!' is white space (CR, tab, space, ...)
    bcs nt_c3
    jsr adv
    jmp nt_ws
nt_c3:
    cmp #'{'                    // { comment }  or  {$directive}
    bne nt_c4
    jsr peek2
    cmp #'$'
    bne nt_bc
    jmp lex_directive           // directive.asm (returns to nt_ws)
nt_bc:
    jsr adv
    jsr getch
    bne !+
    lda #E_EOF                  // comment never closed
    jmp error
!:  cmp #$0a
    bne !+
    jsr incline
    jmp nt_bc
!:  cmp #'}'
    bne nt_bc
    jsr adv                     // skip the '}'
    jmp nt_ws
nt_c4:
    cmp #'('                    // "(*" starts a comment, otherwise '(' is a symbol
    bne nt_c5
    jsr peek2
    cmp #'*'
    bne nt_c6
    jsr adv                     // skip "(*"
    jsr adv
nt_pc:
    jsr getch
    bne !+
    lda #E_EOF
    jmp error
!:  cmp #$0a
    bne !+
    jsr incline
    jsr adv
    jmp nt_pc
!:  cmp #'*'                    // look for "*)"
    bne !+
    jsr peek2
    cmp #')'
    bne !+
    jsr adv
    jsr adv
    jmp nt_ws
!:  jsr adv
    jmp nt_pc
nt_c5:
    cmp #'/'                    // "//" line comment, otherwise '/' is a symbol
    bne nt_c6
    jsr peek2
    cmp #'/'
    bne nt_c6
nt_lc:
    jsr getch                   // skip up to (not including) the line feed
    beq nt_c6x
    cmp #$0a
    beq nt_c6x
    jsr adv
    jmp nt_lc
nt_c6x:
    jmp nt_ws
nt_c6:                          // a real token starts here: classify by first character
    jsr getch
    jsr isalpha
    bcc !+
    jmp lex_ident
!:  jsr isdigit
    bcc !+
    jmp lex_num
!:  cmp #'$'
    bne !+
    jmp lex_hex
!:  cmp #$27                    // quote
    bne !+
    jmp lex_str
!:  cmp #'#'                    // #nn : character with code nn
    bne !+
    jmp lex_charcode
!:  jmp lex_sym

// ---- identifiers and reserved words ------------------------------------------------------------
lex_ident:
    ldx #0                      // X = number of characters stored in idbuf
li_loop:
    jsr getch
    jsr isalpha
    bcs li_ok
    jsr isdigit
    bcc li_end                  // neither letter nor digit: identifier finished
li_ok:
    cmp #'a'                    // fold lower case to upper case: Pascal is case-insensitive
    bcc !+
    and #$df
!:  cpx #15                     // only the first 15 characters are significant
    bcs !+
    inx
    sta idbuf,x
!:  jsr adv
    jmp li_loop
li_end:
    stx idbuf                   // length byte
    // look the name up in the reserved word table
    lda #<kwtab
    sta tmpc1
    lda #>kwtab
    sta tmpc1+1
kw1:
    ldy #0
    lda (tmpc1),y               // length of this table entry's word; 0 = end of table
    beq kw_none
    cmp idbuf
    bne kw_next                 // different length: cannot match
    ldy idbuf
kwc:
    lda (tmpc1),y               // compare characters from the end back to the first
    cmp idbuf,y
    bne kw_next
    dey
    bne kwc
    ldy idbuf                   // match: the token code follows the word
    iny
    lda (tmpc1),y
    sta tok
    rts
kw_next:
    ldy #0                      // advance to the next entry: length + 2 bytes
    lda (tmpc1),y
    clc
    adc #2
    adc tmpc1
    sta tmpc1
    bcc kw1
    inc tmpc1+1
    jmp kw1
kw_none:
    lda #TK_IDENT               // not reserved: a plain identifier
    sta tok
    rts

// ---- numbers -------------------------------------------------------------------------------------
lex_num:                        // decimal number: tokval = tokval * 10 + digit
    lda src                     // (a real number is scanned again from here)
    sta lnstart
    lda src+1
    sta lnstart+1
    lda #0
    sta tokval
    sta tokval+1
ln1:
    jsr getch
    jsr isdigit
    bcc ln_end
    and #$0f                    // digit value
    sta digit
    lda tokval                  // save old value
    sta tmpc1
    lda tokval+1
    sta tmpc1+1
    asl tokval                  // x4
    rol tokval+1
    asl tokval
    rol tokval+1
    clc                         // + old value = x5
    lda tokval
    adc tmpc1
    sta tokval
    lda tokval+1
    adc tmpc1+1
    sta tokval+1
    asl tokval                  // x10
    rol tokval+1
    clc                         // + digit
    lda tokval
    adc digit
    sta tokval
    bcc !+
    inc tokval+1
!:  jsr adv
    jmp ln1
ln_end:
    jsr getch                   // digits '.' digit   or   digits E [sign] digit   make a real number
    cmp #'.'
    bne ln_e
    jsr peek2
    jsr isdigit
    bcs ln_real
    jmp ln_int
ln_e:
    and #$df
    cmp #'E'
    bne ln_int
    jsr peek2
    jsr isdigit
    bcs ln_real
    cmp #'+'
    beq ln_es
    cmp #'-'
    bne ln_int
ln_es:
    ldy #2
    lda (src),y
    jsr isdigit
    bcs ln_real
ln_int:
    lda #TK_NUM
    sta tok
    rts
ln_real:                        // copy the text of the real number into numbuf (length byte first)
    lda lnstart
    sta src
    lda lnstart+1
    sta src+1
    ldx #0
lr_loop:
    jsr getch
    cmp #'.'
    beq lr_st
    jsr isdigit
    bcs lr_st
    cmp #'+'
    beq lr_sg
    cmp #'-'
    beq lr_sg
    and #$df
    cmp #'E'
    bne lr_end
    jsr getch                   // the E (or e) itself
    jmp lr_st
lr_sg:                          // a sign only directly after the E
    lda numbuf,x
    and #$df
    cmp #'E'
    bne lr_end
    jsr getch
lr_st:
    cpx #30
    bcc !+
    lda #E_STR                  // literal too long
    jmp error
!:  inx
    sta numbuf,x
    jsr adv
    jmp lr_loop
lr_end:
    stx numbuf
    lda #TK_REALNUM
    sta tok
    rts

lex_charcode:                   // #65 is the same as 'A': a one character string
    jsr adv                     // past '#'
    jsr lex_num                 // the code, as a decimal number
    lda tokval
    sta strbuf+1
    lda #1
    sta strbuf
    lda #TK_STR
    sta tok
    rts

lex_hex:                        // $hhhh hexadecimal number
    jsr adv                     // skip '$'
    lda #0
    sta tokval
    sta tokval+1
lh1:
    jsr getch
    jsr isdigit
    bcc lh_a
    and #$0f                    // 0-9
    jmp lh_add
lh_a:
    ora #$20                    // a-f / A-F
    cmp #'a'
    bcc lh_end
    cmp #'g'
    bcs lh_end
    sec
    sbc #'a'-10
lh_add:
    sta digit
    ldx #4                      // tokval = tokval * 16 + digit
!:  asl tokval
    rol tokval+1
    dex
    bne !-
    lda tokval
    ora digit
    sta tokval
    jsr adv
    jmp lh1
lh_end:
    lda #TK_NUM
    sta tok
    rts

// ---- string literals ------------------------------------------------------------------------------
lex_str:                        // 'text' with '' standing for one quote
    jsr adv                     // skip opening quote
    ldx #0                      // X = length so far
ls1:
    jsr getch
    bne !+
    lda #E_EOF                  // source ended inside the string
    jmp error
!:  cmp #$27
    bne ls_ch                   // ordinary character
    jsr peek2
    cmp #$27
    bne ls_end                  // single quote = closing quote
    jsr adv                     // doubled quote: keep one, skip the other
    lda #$27
ls_ch:
    cpx #250
    bcc !+
    lda #E_STR                  // literal too long
    jmp error
!:  inx
    sta strbuf,x
    jsr adv
    jmp ls1
ls_end:
    jsr adv                     // skip closing quote
    stx strbuf
    lda #TK_STR
    sta tok
    rts

// ---- punctuation -------------------------------------------------------------------------------------
lex_sym:
    sta chsave
    jsr adv
    ldx #0
sy1:                            // find the character in the single-character table
    lda symchars,x
    beq sy_err
    cmp chsave
    beq sy_found
    inx
    bne sy1
sy_err:
    jmp err_syntax   // character not part of the language
sy_found:
    lda symtoks,x
    sta tok
    ldx #0                      // is it the first half of a two-character symbol?
cb1:
    lda combos,x
    beq cb_done
    cmp chsave
    bne cb_next
    jsr getch
    cmp combos+1,x
    bne cb_next
    jsr adv                     // yes (:= <= <> >= ..): take the second character too
    lda combos+2,x
    sta tok
    rts
cb_next:
    inx
    inx
    inx
    jmp cb1
cb_done:
    rts

// single-character symbols; symtoks[i] is the token for symchars[i]
symchars: .text "+-*/()[];,.=:<>"
#if !NOEXT
          .text "^@"
#endif
          .byte 0
symtoks:  .byte TK_PLUS, TK_MINUS, TK_STAR, TK_SLASH, TK_LPAR, TK_RPAR, TK_LBRK, TK_RBRK
          .byte TK_SEMI, TK_COMMA, TK_DOT, TK_EQ, TK_COLON, TK_LT, TK_GT
#if !NOEXT
          .byte TK_CARET, TK_AT
#endif
// two-character symbols: first char, second char, token
combos:   .text ":="
          .byte TK_ASSIGN
          .text "<="
          .byte TK_LE
          .text "<>"
          .byte TK_NE
          .text ">="
          .byte TK_GE
          .text ".."
          .byte TK_DOTDOT
          .byte 0

// reserved word table: length, upper-case word, token code; ends with a 0 length
.macro KW(name, t) {
    .byte name.size()
    .text name
    .byte t
}
kwtab:
    :KW("PROGRAM", TK_PROGRAM)
    :KW("VAR", TK_VAR)
    :KW("CONST", TK_CONST)
    :KW("BEGIN", TK_BEGIN)
    :KW("END", TK_END)
    :KW("IF", TK_IF)
    :KW("THEN", TK_THEN)
    :KW("ELSE", TK_ELSE)
    :KW("WHILE", TK_WHILE)
    :KW("DO", TK_DO)
    :KW("REPEAT", TK_REPEAT)
    :KW("UNTIL", TK_UNTIL)
    :KW("FOR", TK_FOR)
    :KW("TO", TK_TO)
    :KW("DOWNTO", TK_DOWNTO)
    :KW("DIV", TK_DIV)
    :KW("MOD", TK_MOD)
    :KW("AND", TK_AND)
    :KW("OR", TK_OR)
    :KW("NOT", TK_NOT)
    :KW("XOR", TK_XOR)
    :KW("PROCEDURE", TK_PROCEDURE)
    :KW("FUNCTION", TK_FUNCTION)
    :KW("ABSOLUTE", TK_ABSOLUTE)
    :KW("TYPE", TK_TYPE)
    :KW("ARRAY", TK_ARRAY)
    :KW("OF", TK_OF)
    :KW("RECORD", TK_RECORD)
    :KW("USES", TK_USES)
    :KW("CASE", TK_CASE)
    :KW("SHL", TK_SHL)
    :KW("SHR", TK_SHR)
    .byte 0
