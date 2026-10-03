// This file is in the public domain: use it, change it, share it, sell it - do whatever you like with it.
// No permission, credit or payment needed. It comes as it is, with no warranty. Enjoy!
// Note: this has only been tested in the VICE emulator, never on real hardware.
// =====================================================================================
// decls.asm - declaration sections: const and var
// =====================================================================================
//
//   const name = value;            value: number, -number, real number, 'c', TRUE/FALSE, or a constant name
//   var a, b, c: type;             type: INTEGER, BYTE, BOOLEAN or CHAR
//   var r: type absolute address;  the variable lives at a fixed address (e.g. a hardware register)
//
// Each declared name becomes a symbol record (see symtab.asm). Global variables get
// consecutive addresses in the data area starting at DATA_BASE ('datap' is the next free one).
// Inside a procedure ('inproc' set) variables are locals: they get frame offsets ('locoff').
// Storage: byte globals take one byte (kind K_VARB), other globals a 16-bit cell (K_VAR).
// Locals and parameters are always 16-bit cells.

// decls: parse any number of const / var / procedure / function sections; returns when the
// current token starts something else (normally BEGIN).
decls:
    lda tok
    cmp #TK_CONST
    bne !+
    jmp do_const
!:  cmp #TK_TYPE
    bne !+
    jmp do_type
!:  cmp #TK_VAR
    bne !+
    jmp do_var
!:  cmp #TK_PROCEDURE
    beq dc_proc
    cmp #TK_FUNCTION
    bne !+
dc_proc:
    jmp do_proc                 // see proc.asm
!:  rts

// ---- const section -----------------------------------------------------------------------------
//   const name = value;     value = number | -number | 'c' (one character) | 'text' | real number | another constant
// An integer, character or boolean constant is stored in the symbol record itself (field 18/19 = its value). A real or a
// string constant has its text in the generated code (a "jmp over" jumps across it) and the symbol's value is the ADDRESS of
// that text: see dc_real and dc_string. A string constant is used like a string literal (f_ident, expr.asm).
do_const:
    jsr nexttok                 // skip CONST
dc1:
    lda tok
    cmp #TK_IDENT
    bne decls                   // no more constants: back to the section loop
    lda #K_CONST                // enter the name now with a dummy value; fixed up below
    sta nkind
    lda #0
    sta ntype
    sta nval
    sta nval+1
    jsr addsym
    jsr nexttok
    lda #TK_EQ
    jsr expect
    // now read the constant's value into curtype (type) and tmpc2 (value)
    lda tok
    cmp #TK_REALNUM
    bne dc_nr
    jmp dc_real
dc_nr:
    cmp #TK_NUM
    bne dc_neg
    lda #T_INT                  // plain number
    sta curtype
    lda tokval
    sta tmpc2
    lda tokval+1
    sta tmpc2+1
    jmp dc_set
dc_neg:
    cmp #TK_MINUS
    bne dc_str
    jsr nexttok                 // -number
    lda tok
    cmp #TK_REALNUM
    bne dc_ni
    jmp dc_nreal
dc_ni:
    cmp #TK_NUM
    beq !+
    jmp err_syntax
!:  sec                         // value = 0 - number
    lda #0
    sbc tokval
    sta tmpc2
    lda #0
    sbc tokval+1
    sta tmpc2+1
    lda #T_INT
    sta curtype
    jmp dc_set
dc_str:
    cmp #TK_STR
    bne dc_id
    lda strbuf                  // exactly one character: a character constant, else a string constant
    cmp #1
    beq !+
    jmp dc_string
!:  lda strbuf+1
    sta tmpc2
    lda #0
    sta tmpc2+1
    lda #T_CHAR
    sta curtype
    jmp dc_set
dc_string:                      // string constant: its text is kept in the code (jumped over), the value is its address
    lda #$4c
    jsr emit
    :JPLACE()
    lda cpc
    sta tmpc2
    lda cpc+1
    sta tmpc2+1
    jsr emit_strlit
    :PATCH()
    lda #T_STRING
    sta curtype
    jmp dc_set
dc_id:
    cmp #TK_IDENT               // another constant (TRUE, FALSE, MAXINT, earlier constant)
    beq !+
    jmp err_syntax
!:  jsr lookup
    bcs !+
    jmp err_undef
!:  ldy #16
    lda (sptr),y
    cmp #K_CONST
    beq !+
    jmp err_syntax
!:  ldy #17                     // copy its type and value
    lda (sptr),y
    sta curtype
    ldy #18
    lda (sptr),y
    sta tmpc2
    iny
    lda (sptr),y
    sta tmpc2+1
dc_real:                        // real constant: its text is kept in the code (jumped over), the value is its address
    lda #0
    sta rop                     // (rop = 1: the constant is negative)
    beq dc_rl
dc_nreal:
    lda #1
    sta rop
dc_rl:
    lda #$4c                    // jmp over the text
    jsr emit
    :JPLACE()
    lda cpc                     // the text starts here
    sta tmpc2
    lda cpc+1
    sta tmpc2+1
    lda numbuf                  // length byte (+ the minus sign)
    clc
    adc rop
    jsr emit
    lda rop
    beq dc_rn
    lda #'-'
    jsr emit
dc_rn:
    lda numbuf
    beq dc_rd
    ldx #1
!:  lda numbuf,x
    jsr emit
    cpx numbuf
    beq dc_rd
    inx
    jmp !-
dc_rd:
    :PATCH()
    lda #T_REAL
    sta curtype
    jmp dc_set
dc_set:                         // store type and value into the record just added
    sec                         // (it is the last record: symp - SYM_SIZE)
    lda symp
    sbc #SYM_SIZE
    sta tmpc3
    lda symp+1
    sbc #0
    sta tmpc3+1
    ldy #17
    lda curtype
    sta (tmpc3),y
    iny
    lda tmpc2
    sta (tmpc3),y
    iny
    lda tmpc2+1
    sta (tmpc3),y
    jsr nexttok
    lda #TK_SEMI
    jsr expect
    jmp dc1

// ---- type section ------------------------------------------------------------------------------
//   type name = <type>;       (see parse_type in types.asm for the type syntax)
do_type:
    jsr nexttok                 // skip TYPE
dt1:
    lda tok
    cmp #TK_IDENT
    bne dt_end
    lda #0
    sta fwd_desc
    jsr lookup_local            // a name used earlier as ^name: now its record type is defined
    bcc dt_new
    ldy #16
    lda (sptr),y
    cmp #K_TYPE
    bne dt_new
    ldy #21
    lda (sptr),y
    beq dt_new
    lda #0
    sta (sptr),y                // no longer forward
    ldy #20
    lda (sptr),y
    sta fwd_desc                // pt_record fills this descriptor
    lda sptr                    // the type's own symbol (as below)
    pha
    lda sptr+1
    pha
    jmp dt_got
dt_new:
    lda #K_TYPE                 // enter the name now; the type is filled in below
    sta nkind
    lda #0
    sta ntype
    sta nval
    sta nval+1
    jsr addsym
    sec                         // remember the type's own symbol: parse_type may add field
    lda symp                    // symbols (records) after it
    sbc #SYM_SIZE
    pha
    lda symp+1
    sbc #0
    pha
dt_got:
    jsr nexttok
    lda #TK_EQ
    jsr expect
    jsr parse_type
    lda #0
    sta fwd_desc
    pla
    sta tmpc3+1
    pla
    sta tmpc3                   // type code in field 18, descriptor in 20
    ldy #18
    lda curtype
    sta (tmpc3),y
    ldy #20
    lda curdesc
    sta (tmpc3),y
    lda #TK_SEMI
    jsr expect
    jmp dt1
dt_end:
    jmp decls

// ---- var section -------------------------------------------------------------------------------
do_var:
    jsr nexttok                 // skip VAR
dv1:
    lda tok                     // each iteration handles "a, b, c: type [absolute addr];"
    cmp #TK_IDENT
    beq dv_go
    jmp dv_end                  // no more variable groups
dv_go:
    lda symp                    // remember where this group's records start
    sta varstart
    lda symp+1
    sta varstart+1
    lda #0
    sta vcount
dv2:                            // read the comma separated names
    lda tok
    cmp #TK_IDENT
    beq !+
    jmp err_syntax
!:  lda #K_VAR                  // provisional kind; the exact kind is set below
    ldx inproc
    beq !+
    lda #K_LOCAL
!:  sta nkind
    lda #T_INT
    sta ntype
    lda #0
    sta nval
    sta nval+1
    jsr addsym
    inc vcount
    jsr nexttok
    lda tok
    cmp #TK_COMMA
    bne dv3
    jsr nexttok
    jmp dv2
dv3:
    lda #TK_COLON
    jsr expect
    jsr parse_type              // curtype / curdesc
    // optional "absolute <address>"
    lda #0
    sta isabs
    lda tok
    cmp #TK_ABSOLUTE
    bne dv_alloc
    lda inproc                  // only global variables can be placed at an address
    beq !+
    jmp err_syntax
!:  jsr nexttok
    lda tok
    cmp #TK_NUM
    bne da_id
    lda tokval                  // literal address (decimal or $hex)
    sta absaddr
    lda tokval+1
    sta absaddr+1
    jmp da_got
da_id:
    cmp #TK_IDENT               // or the name of a constant
    beq !+
    jmp err_syntax
!:  jsr lookup
    bcs !+
    jmp err_undef
!:  ldy #16
    lda (sptr),y
    cmp #K_CONST
    beq !+
    jmp err_syntax
!:  ldy #18
    lda (sptr),y
    sta absaddr
    iny
    lda (sptr),y
    sta absaddr+1
da_got:
    lda #1
    sta isabs
    jsr nexttok
dv_alloc:
    jsr var_size                // vsize = bytes needed by each variable of the group
    lda varstart
    sta tmpc3
    lda varstart+1
    sta tmpc3+1
dv4:
    lda vcount                  // done when every variable of the group has been handled
    bne dv_body                 // (the table may also hold record fields from an inline type)
    jmp dv5
dv_body:
    ldy #17
    lda curtype
    sta (tmpc3),y
    ldy #20
    lda curdesc
    sta (tmpc3),y
    lda inproc
    bne dv_loc
    lda isabs
    beq dv_glob
    ldy #18                     // absolute: the address was given
    lda absaddr
    sta (tmpc3),y
    iny
    lda absaddr+1
    sta (tmpc3),y
    jsr set_scalar_kind
    jmp dv_next
dv_glob:                        // ordinary global: next free data address
    ldy #18
    lda datap
    sta (tmpc3),y
    iny
    lda datap+1
    sta (tmpc3),y
    jsr set_scalar_kind
    clc
    lda datap
    adc vsize
    sta datap
    lda datap+1
    adc vsize+1
    sta datap+1
    bcs dv_mem
    cmp #>DATA_LIMIT
    bcc dv_next
dv_mem:
    jmp err_mem   // data area full
dv_loc:                         // local: next free frame offset
    ldy #18
    lda locoff
    sta (tmpc3),y
    iny
    lda #0
    sta (tmpc3),y
    lda vsize+1
    bne dv_mem
    clc
    lda locoff
    adc vsize
    bcs dv_mem
    sta locoff
    cmp #200                    // keep the frame small enough for 8-bit offsets
    bcs dv_mem
dv_next:
    clc                         // next record
    lda tmpc3
    adc #SYM_SIZE
    sta tmpc3
    bcc !+
    inc tmpc3+1
!:  dec vcount
    jmp dv4
dv5:
    lda #TK_SEMI
    jsr expect
    jmp dv1
dv_end:
    jmp decls                   // maybe another section follows

// var_size: vsize = storage needed by one variable of type curtype/curdesc.
// Global integers take 2 bytes, other global scalars 1 byte; locals are always 16-bit cells;
// arrays and strings take the size recorded in their descriptor.
var_size:
    lda curtype
    cmp #T_ARRAY
    bcs vs_struct
    lda #2
    ldx curtype
    cpx #T_REAL                 // reals take 4 bytes (also as locals)
    bne vs_nr
    lda #4
    bne vs_set
vs_nr:
    ldx inproc
    bne vs_set
    ldx curtype
    cpx #T_INT
    beq vs_set
    cpx #T_PTR
    beq vs_set
    lda #1
vs_set:
    sta vsize
    lda #0
    sta vsize+1
    rts
vs_struct:
    lda curdesc
    jsr desc_ptr
    ldy #D_SIZE
    lda (tmpc3),y
    sta vsize
    iny
    lda (tmpc3),y
    sta vsize+1
    rts

// set_scalar_kind: global variable record at (tmpc3): every scalar except integer is stored
// in one byte and gets the kind K_VARB.
set_scalar_kind:
    lda curtype
    cmp #T_INT
    beq ssk_done
    cmp #T_PTR                  // pointers and reals are stored in full (K_VAR)
    beq ssk_done
    cmp #T_REAL
    beq ssk_done
    cmp #T_ARRAY
    bcs ssk_done
    ldy #16
    lda #K_VARB
    sta (tmpc3),y
ssk_done:
    rts
