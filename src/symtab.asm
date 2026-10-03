// This file is in the public domain: use it, change it, share it, sell it - do whatever you like with it.
// No permission, credit or payment needed. It comes as it is, with no warranty. Enjoy!
// Note: this has only been tested in the VICE emulator, never on real hardware.
// =====================================================================================
// symtab.asm - symbol table
// =====================================================================================
//
// The table is a plain array of fixed-size records between SYM_BASE and 'symp'.
// Record layout (SYM_SIZE = 32 bytes):
//    0        name length
//    1..15    name (upper case)
//    16       kind  (K_VAR, K_CONST, K_TYPE, K_PROC)
//    17       type  (T_INT, T_BOOL, T_CHAR)
//    18..19   variable: address   constant: value   type: type code   proc: id
//    20       variable/type: descriptor index (arrays, strings)    routine: parameter count
//    21       routine: bit mask of var parameters
//    22..29   routine: type code of each parameter (scalar type, or $80 + descriptor index)
// Lookup is a linear search; this is fast enough for programs that fit in memory.

// lookup: search idbuf in the whole table, newest record first, so that a local name hides a
// global one. On return carry set = found and 'sptr' points to the record; clear = not found.
lookup:
    lda #<SYM_BASE
    sta lkbound
    lda #>SYM_BASE
    sta lkbound+1
    jmp lk_go

// lookup_local: like lookup but only searches the current scope (records from 'scopebase'
// up). Used to detect duplicate declarations.
lookup_local:
    lda scopebase
    sta lkbound
    lda scopebase+1
    sta lkbound+1
lk_go:
    lda symp                    // start just past the newest record
    sta sptr
    lda symp+1
    sta sptr+1
lk1:
    lda sptr                    // reached the lower bound: not found
    cmp lkbound
    bne lk2
    lda sptr+1
    cmp lkbound+1
    bne lk2
    clc
    rts
lk2:
    sec                         // step back one record
    lda sptr
    sbc #SYM_SIZE
    sta sptr
    lda sptr+1
    sbc #0
    sta sptr+1
    ldy #16
    lda (sptr),y                // record fields are only found through their record type
    cmp #K_FIELD
    beq lk1
    ldy #0
    lda (sptr),y                // lengths must match
    cmp idbuf
    bne lk1
    ldy idbuf
lk3:
    lda (sptr),y                // compare characters from the end back to the first
    cmp idbuf,y
    bne lk1
    dey
    bne lk3
    sec                         // found
    rts

// addsym: add idbuf to the table with kind/type/value taken from nkind, ntype, nval.
// Reports E_DUP if the name already exists, E_MEM if the table is full.
addsym:
    jsr lookup_local            // duplicates are only errors within the same scope
    bcc !+
    lda #E_DUP
    jmp error
!:  // (falls into addsym_raw)
addsym_raw:                     // add without the duplicate check (record fields)
    lda symp+1                  // room left?
    cmp #>SYM_LIMIT
    bcc !+
    jmp err_mem
!:  ldy idbuf                   // copy the name (length byte .. last character)
!:  lda idbuf,y
    sta (symp),y
    dey
    bpl !-
    ldy #16                     // kind, type, address/value
    lda nkind
    sta (symp),y
    iny
    lda ntype
    sta (symp),y
    iny
    lda nval
    sta (symp),y
    iny
    lda nval+1
    sta (symp),y
    iny                         // clear the remaining fields (20..SYM_SIZE-1)
    lda #0
!:  sta (symp),y
    iny
    cpy #SYM_SIZE
    bcc !-
    clc                         // symp += SYM_SIZE
    lda symp
    adc #SYM_SIZE
    sta symp
    bcc !+
    inc symp+1
!:  rts

// init_builtins: enter the predeclared identifiers (table btab below) into the symbol table.
init_builtins:
    lda #<btab
    sta tmpc1
    lda #>btab
    sta tmpc1+1
ib1:
    ldy #0
    lda (tmpc1),y               // name length, 0 = end of table
    beq ib_done
    sta idbuf
ib2:                            // copy the name into idbuf
    iny
    lda (tmpc1),y
    sta idbuf,y
    cpy idbuf
    bne ib2
    iny                         // then kind, type, value (lo, hi)
    lda (tmpc1),y
    sta nkind
    iny
    lda (tmpc1),y
    sta ntype
    iny
    lda (tmpc1),y
    sta nval
    iny
    lda (tmpc1),y
    sta nval+1
    jsr addsym
    lda idbuf                   // advance to next entry: length byte + name + 4 bytes
    clc
    adc #5
    adc tmpc1
    sta tmpc1
    bcc ib1
    inc tmpc1+1
    jmp ib1
ib_done:
    rts

// predeclared identifiers: name, kind, type, value
.macro BI(name, kind, type, val) {
    .byte name.size()
    .text name
    .byte kind, type
    .word val
}
btab:
    :BI("INTEGER", K_TYPE, 0, T_INT)
    :BI("BOOLEAN", K_TYPE, 0, T_BOOL)
    :BI("CHAR", K_TYPE, 0, T_CHAR)
    :BI("BYTE", K_TYPE, 0, T_BYTE)
    :BI("STRING", K_TYPE, 0, T_STRING)
    :BI("TRUE", K_CONST, T_BOOL, 1)
    :BI("FALSE", K_CONST, T_BOOL, 0)
    :BI("MAXINT", K_CONST, T_INT, 32767)
    :BI("WRITE", K_PROC, 0, 1)
    :BI("WRITELN", K_PROC, 0, 2)
    :BI("READ", K_PROC, 0, 3)
    :BI("READLN", K_PROC, 0, 4)
    :BI("CLRSCR", K_BPROC, 0, 4)
    :BI("CLREOL", K_BPROC, 0, 5)
    :BI("GOTOXY", K_BPROC, 0, 6)
    :BI("TEXTCOLOR", K_BPROC, 0, 7)
    :BI("TEXTBACKGROUND", K_BPROC, 0, 8)
    :BI("DELAY", K_BPROC, 0, 9)
    :BI("HIGHVIDEO", K_BPROC, 0, 10)
    :BI("LOWVIDEO", K_BPROC, 0, 11)
    :BI("NORMVIDEO", K_BPROC, 0, 12)
    :BI("VAL", K_BPROC, 0, 13)
    :BI("READKEY", K_BFUNC, 0, 7)
    :BI("KEYPRESSED", K_BFUNC, 0, 8)
    :BI("WHEREX", K_BFUNC, 0, 9)
    :BI("WHEREY", K_BFUNC, 0, 10)
    :BI("LENGTH", K_BFUNC, 0, 1)
    :BI("COPY", K_BFUNC, 0, 2)
    :BI("POS", K_BFUNC, 0, 3)
    :BI("UPCASE", K_BFUNC, 0, 4)
    :BI("CHR", K_BFUNC, 0, 5)
    :BI("ORD", K_BFUNC, 0, 6)
    :BI("DELETE", K_BPROC, 0, 1)
    :BI("INSERT", K_BPROC, 0, 2)
    :BI("STR", K_BPROC, 0, 3)
    :BI("EXIT", K_BPROC, 0, 17)         // control: Exit, Break, Continue, Halt, Inc, Dec (ctlfn.asm)
    :BI("BREAK", K_BPROC, 0, 18)
    :BI("CONTINUE", K_BPROC, 0, 19)
    :BI("HALT", K_BPROC, 0, 20)
    :BI("INC", K_BPROC, 0, 21)
    :BI("DEC", K_BPROC, 0, 22)
    :BI("ODD", K_BFUNC, 0, 34)          // Odd, Succ, Pred (ctlfn.asm)
    :BI("SUCC", K_BFUNC, 0, 35)
    :BI("PRED", K_BFUNC, 0, 36)
#if !NOEXT
    :BI("NEW", K_BPROC, 0, 14)
    :BI("DISPOSE", K_BPROC, 0, 15)
    :BI("NIL", K_CONST, T_PTR, 0)
#endif
#if HAVEREAL
    :BI("REAL", K_TYPE, 0, T_REAL)
    :BI("SINGLE", K_TYPE, 0, T_REAL)
    :BI("DOUBLE", K_TYPE, 0, T_REAL)
    :BI("TRUNC", K_BFUNC, 0, 20)
    :BI("ROUND", K_BFUNC, 0, 21)
    :BI("ABS", K_BFUNC, 0, 22)
    :BI("SQR", K_BFUNC, 0, 23)
    :BI("SQRT", K_BFUNC, 0, 24)
    :BI("SIN", K_BFUNC, 0, 25)
    :BI("COS", K_BFUNC, 0, 26)
    :BI("ARCTAN", K_BFUNC, 0, 27)
    :BI("EXP", K_BFUNC, 0, 28)
    :BI("LN", K_BFUNC, 0, 29)
    :BI("INT", K_BFUNC, 0, 30)
    :BI("FRAC", K_BFUNC, 0, 31)
    :BI("PI", K_BFUNC, 0, 32)
    :BI("RANDOM", K_BFUNC, 0, 33)
    :BI("RANDOMIZE", K_BPROC, 0, 16)
#endif
    .byte 0
