// This file is in the public domain: use it, change it, share it, sell it - do whatever you like with it.
// No permission, credit or payment needed. It comes as it is, with no warranty. Enjoy!
// Note: this has only been tested in the VICE emulator, never on real hardware.
// =====================================================================================
// directive.asm - compiler directives: conditional compilation
// =====================================================================================
//
// A comment that starts with {$ is a compiler directive, as in Turbo Pascal:
//
//   {$DEFINE name}    define a symbol            {$UNDEF name}   remove it
//   {$IFDEF name}     compile the following text only if the symbol is defined
//   {$IFNDEF name}    ... only if it is NOT defined
//   {$ELSE}           switch to the other branch  {$ENDIF}      end of the conditional
//
// Conditionals nest up to 8 levels. Any other directive (for example {$R+}) is ignored.
// Symbols are case-insensitive. The compiler predefines symbols for the machine it was built
// for, so the same source can be compiled on each machine:
//
//   Commodore 64 (and C128 in C64 mode):  C64  VIC  SID
//   Commodore 128, 128 mode:              C128  VIC  SID  VDC
//   Commodore Plus/4:                     PLUS4  TED
//
//   {$IFDEF PLUS4}  border := 1;  {$ELSE}  border := 2;  {$ENDIF}
//
// The lexer calls lex_directive when it meets "{$". Skipped text is scanned only for
// directives (and line feeds, to keep the line count right), so it need not be valid Pascal.

.const DEF_COUNT = 16           // room for 16 defined symbols (16 bytes each)

// directive numbers returned in dcode
.const DIR_DEFINE = 1
.const DIR_UNDEF  = 2
.const DIR_IFDEF  = 3
.const DIR_IFNDEF = 4
.const DIR_ELSE   = 5
.const DIR_ENDIF  = 6

// ifstack values: state of one open conditional
.const IF_ACTIVE  = 1           // the branch being compiled is selected
.const IF_WAITING = 0           // the condition was false: waiting for $ELSE
.const IF_DONE    = 2           // $ELSE already seen / branch already taken

// parse_directive: src is at the '{' of "{$name symbol}". Reads the directive name into idbuf
// (upper case), the optional symbol into dsym, consumes everything through the closing '}'
// and sets dcode.
parse_directive:
    jsr adv                     // past '{'
    jsr adv                     // past '$'
    ldx #0
pd1:                            // the directive name: letters
    jsr getch
    jsr isalpha
    bcc pd2
    cmp #'a'
    bcc !+
    and #$df
!:  cpx #15
    bcs !+
    inx
    sta idbuf,x
!:  jsr adv
    jmp pd1
pd2:
    stx idbuf
pd3:                            // blanks between name and symbol
    jsr getch
    cmp #' '
    bne pd4
    jsr adv
    jmp pd3
pd4:
    ldx #0
pd5:                            // the symbol: letters, digits, underscore
    jsr getch
    jsr isalpha
    bcs pd6
    jsr isdigit
    bcc pd7
pd6:
    cmp #'a'
    bcc !+
    and #$df
!:  cpx #15
    bcs !+
    inx
    sta dsym,x
!:  jsr adv
    jmp pd5
pd7:
    stx dsym
pd8:                            // everything up to the closing brace is ignored
    jsr getch
    bne !+
    lda #E_EOF
    jmp error
!:  cmp #$0a
    bne !+
    jsr incline
    jsr getch
!:  cmp #'}'
    beq pd9
    jsr adv
    jmp pd8
pd9:
    jsr adv                     // past '}'
    lda #<dirtab                // classify the name
    sta tmpc1
    lda #>dirtab
    sta tmpc1+1
pdc1:
    ldy #0
    lda (tmpc1),y
    beq pdc_none
    cmp idbuf
    bne pdc_next
    ldy idbuf
pdc2:
    lda (tmpc1),y
    cmp idbuf,y
    bne pdc_next
    dey
    bne pdc2
    ldy idbuf                   // match: the directive number follows the name
    iny
    lda (tmpc1),y
    sta dcode
    rts
pdc_next:
    ldy #0
    lda (tmpc1),y
    clc
    adc #2
    adc tmpc1
    sta tmpc1
    bcc pdc1
    inc tmpc1+1
    jmp pdc1
pdc_none:
    lda #0
    sta dcode
    rts

.macro DIR(name, n) {
    .byte name.size()
    .text name
    .byte n
}
dirtab:
    :DIR("DEFINE", DIR_DEFINE)
    :DIR("UNDEF", DIR_UNDEF)
    :DIR("IFDEF", DIR_IFDEF)
    :DIR("IFNDEF", DIR_IFNDEF)
    :DIR("ELSE", DIR_ELSE)
    :DIR("ENDIF", DIR_ENDIF)
    .byte 0

// ---- the table of defined symbols ---------------------------------------------------------------
// DEFTAB_BASE: DEF_COUNT entries of 16 bytes (length byte + name); length 0 = free entry.

// find_def: look for dsym. Carry set = found, tmpc1 = its entry. Carry clear = not found,
// tmpc1 = the first free entry, or 0 if the table is full.
find_def:
    lda #0
    sta tmpc2+1                 // tmpc2+1 = first free entry (high byte, 0 = none yet)
    lda #<DEFTAB_BASE
    sta tmpc1
    lda #>DEFTAB_BASE
    sta tmpc1+1
    ldx #DEF_COUNT
fd1:
    ldy #0
    lda (tmpc1),y
    bne fd_used
    lda tmpc2+1                 // free entry: remember the first one
    bne fd_next
    lda tmpc1
    sta tmpc2
    lda tmpc1+1
    sta tmpc2+1
    jmp fd_next
fd_used:
    cmp dsym
    bne fd_next
    ldy dsym
fd2:
    lda (tmpc1),y
    cmp dsym,y
    bne fd_next
    dey
    bne fd2
    sec                         // found
    rts
fd_next:
    clc
    lda tmpc1
    adc #16
    sta tmpc1
    bcc !+
    inc tmpc1+1
!:  dex
    bne fd1
    lda tmpc2                   // not found: return the free entry (or 0)
    sta tmpc1
    lda tmpc2+1
    sta tmpc1+1
    clc
    rts

// def_define: define the symbol in dsym (nothing happens if it is already defined).
def_define:
    jsr find_def
    bcs dd_done
    lda tmpc1+1
    bne dd_free
    jmp err_mem   // too many symbols
dd_free:
    ldy dsym
!:  lda dsym,y
    sta (tmpc1),y
    dey
    bpl !-
dd_done:
    rts

// def_undef: remove the symbol in dsym.
def_undef:
    jsr find_def
    bcc !+
    ldy #0
    tya
    sta (tmpc1),y
!:  rts

// init_directives: clear the symbol table and the conditional stack, then define the symbols
// that identify the machine this compiler was built for.
init_directives:
    lda #0
    sta ifsp
    ldx #0
!:  sta DEFTAB_BASE,x
    inx
    bne !-
    lda #<predef
    sta tmpc3
    lda #>predef
    sta tmpc3+1
id1:
    ldy #0
    lda (tmpc3),y               // length, 0 = end of list
    beq id_done
    sta dsym
id2:
    iny
    lda (tmpc3),y
    sta dsym,y
    cpy dsym
    bne id2
    jsr def_define
    lda dsym
    sec                         // next entry: length + 1 bytes
    adc tmpc3
    sta tmpc3
    bcc id1
    inc tmpc3+1
    jmp id1
id_done:
    rts

.macro PD(name) {
    .byte name.size()
    .text name
}
predef:
#if PLUS4
    :PD("PLUS4")
    :PD("TED")
#elif C128
    :PD("C128")
    :PD("VIC")
    :PD("SID")
    :PD("VDC")
#else
    :PD("C64")
    :PD("VIC")
    :PD("SID")
#endif
    .byte 0

// ---- handling a directive found by the lexer ------------------------------------------------------------
// lex_directive: src is at "{$". Executes the directive, then continues with the next token
// (it may first skip text that is excluded by a conditional).
lex_directive:
    jsr parse_directive
    lda dcode
    cmp #DIR_DEFINE
    bne !+
    jsr def_define
    jmp nt_ws
!:  cmp #DIR_UNDEF
    bne !+
    jsr def_undef
    jmp nt_ws
!:  cmp #DIR_IFDEF
    bne !+
    jsr find_def                // carry = symbol defined
    jmp ld_cond
!:  cmp #DIR_IFNDEF
    bne !+
    jsr find_def
    bcc ld_true                 // not defined -> condition true
    jmp ld_false
!:  cmp #DIR_ELSE
    bne !+
    jsr dir_else
    jmp nt_ws
!:  cmp #DIR_ENDIF
    bne !+
    lda ifsp                    // pop a conditional (an unmatched $ENDIF is ignored)
    beq !+
    dec ifsp
!:  jmp nt_ws                   // other directives are ignored
ld_cond:
    bcs ld_true
ld_false:                       // condition false: skip until $ELSE or $ENDIF
    lda #IF_WAITING
    jsr if_push
    jsr skip_inactive
    jmp nt_ws
ld_true:
    lda #IF_ACTIVE
    jsr if_push
    jmp nt_ws

if_push:                        // push the state in A on the conditional stack
    ldx ifsp
    cpx #8
    bcc !+
    jmp err_mem   // nested too deeply
!:  sta ifstack,x
    inc ifsp
    rts

// dir_else: $ELSE reached while compiling an active branch: skip the rest of the conditional.
dir_else:
    ldx ifsp
    beq de_ret                  // $ELSE without $IFDEF: ignored
    lda ifstack-1,x
    cmp #IF_ACTIVE
    bne de_ret
    lda #IF_DONE
    sta ifstack-1,x
    jmp skip_inactive
de_ret:
    rts

// skip_inactive: skip source text up to the $ELSE that selects a waiting branch (then
// compilation continues with that branch) or up to the matching $ENDIF (which also pops the
// conditional). Nested conditionals inside the skipped text are counted.
skip_inactive:
    lda #0
    sta nest
si_loop:
    jsr getch
    bne !+
    lda #E_EOF                  // end of source inside an excluded section
    jmp error
!:  cmp #$0a
    bne !+
    jsr incline
    jsr adv
    jmp si_loop
!:  cmp #'{'
    bne si_adv
    jsr peek2
    cmp #'$'
    bne si_adv
    jsr parse_directive
    lda dcode
    cmp #DIR_IFDEF
    beq si_open
    cmp #DIR_IFNDEF
    beq si_open
    cmp #DIR_ENDIF
    beq si_end
    cmp #DIR_ELSE
    bne si_loop
    lda nest                    // $ELSE of a nested conditional: not ours
    bne si_loop
    ldx ifsp
    lda ifstack-1,x
    cmp #IF_WAITING             // our branch was waiting: select it now
    bne si_loop
    lda #IF_ACTIVE
    sta ifstack-1,x
    rts
si_open:
    inc nest
    jmp si_loop
si_end:
    lda nest
    beq !+
    dec nest
    jmp si_loop
!:  dec ifsp                    // our $ENDIF: the conditional is finished
    rts
si_adv:
    jsr adv
    jmp si_loop
