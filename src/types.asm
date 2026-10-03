// This file is in the public domain: use it, change it, share it, sell it - do whatever you like with it.
// No permission, credit or payment needed. It comes as it is, with no warranty. Enjoy!
// Note: this has only been tested in the VICE emulator, never on real hardware.
// =====================================================================================
// types.asm - structured types: arrays and strings
// =====================================================================================
//
// Scalar types are just a code (T_INT, T_BOOL, T_CHAR, T_BYTE). Arrays and strings need more
// information, which is kept in a table of 16-byte DESCRIPTORS at DTAB_BASE (layout D_* in
// defs.asm). A symbol of array/string type has the type code T_ARRAY / T_STRING in field 17
// and the index of its descriptor in field 20; the same pair (type code, descriptor index) is
// used everywhere in the compiler: 'curtype'/'curdesc' while parsing a type, 'etype'/'edesc'
// for the type of an expression.
//
// Type syntax handled by parse_type:
//   type       = typename | ARRAY [ range {, range} ] OF type | STRING [ [ n ] ]
//              | RECORD field {; field} [;] END          field = name {, name} : type
//   range      = constant .. constant                      (numbers, characters, constants)
// "array[1..3, 1..4] of T" is the same as "array[1..3] of array[1..4] of T".
//
// Sizes: integer elements take 2 bytes, byte/char/boolean elements 1 byte. A string[n] takes
// n+1 bytes (length byte first); plain STRING is string[255].

// desc_ptr: A = descriptor index -> tmpc3 = address of the descriptor.
desc_ptr:
    sta tmpc3
    lda #0
    sta tmpc3+1
    ldx #4                      // index * 16
!:  asl tmpc3
    rol tmpc3+1
    dex
    bne !-
    clc
    lda tmpc3
    adc #<DTAB_BASE
    sta tmpc3
    lda tmpc3+1
    adc #>DTAB_BASE
    sta tmpc3+1
    rts

// new_desc: allocate a zeroed descriptor. Returns A = its index and tmpc3 = its address.
new_desc:
    lda dcount
    cmp #32
    bcc !+
    jmp err_mem   // too many array/string types
!:  pha
    jsr desc_ptr
    ldy #15
    lda #0
!:  sta (tmpc3),y
    dey
    bpl !-
    inc dcount
    pla
    rts

// descsame: A = descriptor index 1, X = descriptor index 2. Z set if the two descriptors
// describe identical types (kind, element type, bounds, sizes).
descsame:
    pha
    txa
    jsr desc_ptr
    lda tmpc3
    sta tmpc1
    lda tmpc3+1
    sta tmpc1+1
    pla
    jsr desc_ptr
    ldy #11
!:  lda (tmpc3),y
    cmp (tmpc1),y
    bne ds_ret                  // Z clear: different
    dey
    bpl !-
    lda #0                      // Z set: same
ds_ret:
    rts

// type_size: size in bytes of one array ELEMENT of type curtype/curdesc, returned in tmpc2.
type_size:
    lda curtype
    cmp #T_PTR                  // pointers take 2 bytes, reals 4
    beq ts_2
    cmp #T_REAL
    bne ts_r
    lda #4
    sta tmpc2
    lda #0
    sta tmpc2+1
    rts
ts_r:
    cmp #T_INT
    bne ts_1
ts_2:
    lda #2
    sta tmpc2
    lda #0
    sta tmpc2+1
    rts
ts_1:
    cmp #T_ARRAY                // byte, char, boolean: one byte
    bcs ts_s
    lda #1
    sta tmpc2
    lda #0
    sta tmpc2+1
    rts
ts_s:                           // array or string: the size stored in its descriptor
    lda curdesc
    jsr desc_ptr
    ldy #D_SIZE
    lda (tmpc3),y
    sta tmpc2
    iny
    lda (tmpc3),y
    sta tmpc2+1
    rts

// cmul: cres = tmpc1 * tmpc2 (16 bit). Reports E_MEM if the result exceeds 32767.
cmul:
    lda #0
    sta cres
    sta cres+1
    ldx #16
cm1:
    lsr tmpc2+1                 // next multiplier bit
    ror tmpc2
    bcc cm2
    clc                         // bit set: add the multiplicand
    lda cres
    adc tmpc1
    sta cres
    lda cres+1
    adc tmpc1+1
    sta cres+1
    bcs cm_ovf
cm2:
    asl tmpc1                   // multiplicand * 2
    rol tmpc1+1
    bcc cm3
    lda tmpc2                   // shifted out: only harmless if no multiplier bits remain
    ora tmpc2+1
    bne cm_ovf
cm3:
    dex
    bne cm1
    lda cres+1
    bpl cm_ok
cm_ovf:
    jmp err_mem
cm_ok:
    rts

// parse_const: read an ordinal constant (number, -number, 'c', or a constant name) into cval
// and advance past it.
parse_const:
    lda tok
    cmp #TK_NUM
    bne pc_neg
    lda tokval
    sta cval
    lda tokval+1
    sta cval+1
    jmp nexttok
pc_neg:
    cmp #TK_MINUS
    bne pc_str
    jsr nexttok
    lda tok
    cmp #TK_NUM
    beq !+
    jmp err_syntax
!:  sec
    lda #0
    sbc tokval
    sta cval
    lda #0
    sbc tokval+1
    sta cval+1
    jmp nexttok
pc_str:
    cmp #TK_STR
    bne pc_id
    lda strbuf
    cmp #1
    beq !+
    lda #E_CHARLIT
    jmp error
!:  lda strbuf+1
    sta cval
    lda #0
    sta cval+1
    jmp nexttok
pc_id:
    cmp #TK_IDENT
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
    sta cval
    iny
    lda (sptr),y
    sta cval+1
    jmp nexttok

// parse_type: parse a type at the current token. Result: curtype (type code) and curdesc
// (descriptor index, 0 for scalar types). Advances past the type.
parse_type:
    lda tok
    cmp #TK_ARRAY
    bne !+
    jmp pt_array
!:  cmp #TK_CARET
    bne !+
    jmp pt_pointer
!:  cmp #TK_RECORD
    bne !+
    jmp pt_record
!:  cmp #TK_IDENT
    beq !+
    jmp err_syntax
!:  jsr lookup                  // a type name
    bcs !+
    jmp err_undef
!:  ldy #16
    lda (sptr),y
    cmp #K_TYPE
    beq !+
    jmp err_syntax
!:  ldy #18
    lda (sptr),y
    sta curtype
    ldy #20
    lda (sptr),y
    sta curdesc
    jsr nexttok
    lda curtype                 // STRING [ n ] defines a string of maximum length n
    cmp #T_STRING
    bne pt_done
    lda tok
    cmp #TK_LBRK
    bne pt_done
    jsr nexttok
    lda tok
    cmp #TK_NUM
    beq !+
    jmp err_syntax
!:  lda tokval+1                // 1..255
    bne pt_badlen
    lda tokval
    bne !+
pt_badlen:
    lda #E_STR
    jmp error
!:  jsr nexttok
    lda #TK_RBRK
    jsr expect
    jsr new_desc                // descriptor of the new string type
    sta curdesc
    ldy #D_KIND
    lda #T_STRING
    sta (tmpc3),y
    ldy #D_ETYPE
    lda #T_CHAR
    sta (tmpc3),y
    ldy #D_HI                   // maximum length
    lda tokval
    sta (tmpc3),y
    ldy #D_ESIZE
    lda #1
    sta (tmpc3),y
    ldy #D_SIZE                 // length byte + characters
    lda tokval
    clc
    adc #1
    sta (tmpc3),y
    iny
    lda #0
    adc #0
    sta (tmpc3),y
pt_done:
    rts

// pt_pointer:  ^ type.   The pointer type is a descriptor of kind T_PTR whose element type / element
// descriptor say what it points to. The target may be a record type that is declared LATER (the usual
// linked list):  type PNode = ^Node;  Node = record ... next: PNode end;  An unknown name is entered as
// a "forward" record type (field 21 = 1) whose descriptor is filled in when the name is declared (do_type).
pt_pointer:
    jsr nexttok                 // past ^
    lda #TK_IDENT
    cmp tok
    beq !+
    jmp err_syntax
!:  jsr lookup
    bcs pp_known
    lda #K_TYPE                 // unknown name: a forward reference to a record type
    sta nkind
    lda #0
    sta ntype
    lda #T_RECORD
    sta nval
    lda #0
    sta nval+1
    jsr addsym
    jsr new_desc                // its descriptor, to be completed later
    sta pt_base
    ldy #D_KIND
    lda #T_RECORD
    sta (tmpc3),y
    sec
    lda symp                    // the symbol just added: copy the descriptor index, mark it forward
    sbc #SYM_SIZE
    sta tmpc3
    lda symp+1
    sbc #0
    sta tmpc3+1
    ldy #20
    lda pt_base
    sta (tmpc3),y
    ldy #21
    lda #1
    sta (tmpc3),y
    lda #T_RECORD
    sta pt_btype
    jmp pp_make
pp_known:
    ldy #16
    lda (sptr),y
    cmp #K_TYPE
    beq !+
    jmp err_syntax
!:  ldy #18
    lda (sptr),y
    sta pt_btype
    ldy #20
    lda (sptr),y
    sta pt_base
pp_make:
    jsr new_desc                // descriptor of the pointer type
    sta curdesc
    ldy #D_KIND
    lda #T_PTR
    sta (tmpc3),y
    ldy #D_ETYPE
    lda pt_btype
    sta (tmpc3),y
    ldy #D_EDESC
    lda pt_base
    sta (tmpc3),y
    ldy #D_ESIZE
    lda #2
    sta (tmpc3),y
    ldy #D_SIZE
    lda #2
    sta (tmpc3),y
    lda #T_PTR
    sta curtype
    lda #1
    sta useheap                 // the program needs the heap
    jmp nexttok                 // past the type name

pt_array:
    jsr nexttok                 // past ARRAY
    lda #TK_LBRK
    jsr expect
pt_dims:                        // one "lo..hi" range; recursion handles further ranges
    jsr parse_const
    lda cval+1
    pha                         // lo, high
    lda cval
    pha                         // lo, low
    lda #TK_DOTDOT
    jsr expect
    jsr parse_const
    lda cval+1
    pha                         // hi, high
    lda cval
    pha                         // hi, low
    lda tok
    cmp #TK_COMMA
    bne pd_last
    jsr nexttok
    jsr pt_dims                 // the remaining ranges + element type form the element type
    jmp pd_build
pd_last:
    lda #TK_RBRK
    jsr expect
    lda #TK_OF
    jsr expect
    jsr parse_type              // element type
pd_build:                       // curtype/curdesc = element type; stack: hi, lo (top first)
    jsr type_size               // tmpc2 = element size
    lda tmpc2
    sta esize
    lda tmpc2+1
    sta esize+1
    jsr new_desc
    sta newidx
    ldy #D_KIND
    lda #T_ARRAY
    sta (tmpc3),y
    ldy #D_ETYPE
    lda curtype
    sta (tmpc3),y
    ldy #D_EDESC
    lda curdesc
    sta (tmpc3),y
    ldy #D_ESIZE
    lda esize
    sta (tmpc3),y
    iny
    lda esize+1
    sta (tmpc3),y
    ldy #D_HI                   // hi (popped first)
    pla
    sta (tmpc3),y
    sta tmpc1
    iny
    pla
    sta (tmpc3),y
    sta tmpc1+1
    ldy #D_LO                   // lo
    pla
    sta (tmpc3),y
    sta tmpc2
    iny
    pla
    sta (tmpc3),y
    sta tmpc2+1
    sec                         // count = hi - lo + 1
    lda tmpc1
    sbc tmpc2
    sta tmpc1
    lda tmpc1+1
    sbc tmpc2+1
    sta tmpc1+1
    bpl !+
    jmp err_type   // hi < lo
!:  inc tmpc1
    bne !+
    inc tmpc1+1
!:  lda esize                   // total = count * element size
    sta tmpc2
    lda esize+1
    sta tmpc2+1
    jsr cmul
    lda newidx
    jsr desc_ptr                // cmul/new_desc clobbered tmpc3
    ldy #D_SIZE
    lda cres
    sta (tmpc3),y
    iny
    lda cres+1
    sta (tmpc3),y
    lda #T_ARRAY
    sta curtype
    lda newidx
    sta curdesc
    rts

// init_types: create descriptor 0 (plain STRING = string[255]) and attach it to the built-in
// type name STRING. Called once at the start of every compilation, after init_builtins.
init_types:
    lda #0
    sta dcount
    jsr new_desc                // index 0
    ldy #D_KIND
    lda #T_STRING
    sta (tmpc3),y
    ldy #D_ETYPE
    lda #T_CHAR
    sta (tmpc3),y
    ldy #D_HI
    lda #255
    sta (tmpc3),y
    ldy #D_ESIZE
    lda #1
    sta (tmpc3),y
    ldy #D_SIZE
    lda #0                      // 256 bytes: low byte 0, high byte 1
    sta (tmpc3),y
    iny
    lda #1
    sta (tmpc3),y
    rts                         // the symbol STRING already has descriptor index 0 (field 20 = 0)

// ---- records ---------------------------------------------------------------------------------
// A record type is a descriptor of kind T_RECORD (D_SIZE = total size; D_LO = a unique number so
// that two record types never compare equal in descsame). Its fields are K_FIELD records in the
// ordinary symbol table (hidden from normal lookups): field 17 = type, 18/19 = offset from the
// start of the record, 20 = descriptor of the field type, 21 = descriptor of the owning record.
// Fields are laid out one after the other with the same sizes as array elements.

// find_field: look for the field named idbuf of the record whose descriptor index is fowner.
// Carry set = found, sptr = its record.
find_field:
    lda #<SYM_BASE
    sta sptr
    lda #>SYM_BASE
    sta sptr+1
ff1:
    lda sptr+1                  // end of the table?
    cmp symp+1
    bne !+
    lda sptr
    cmp symp
!:  bcc ff2
    clc
    rts
ff2:
    ldy #16
    lda (sptr),y
    cmp #K_FIELD
    bne ff_next
    ldy #21
    lda (sptr),y
    cmp fowner
    bne ff_next
    ldy #0
    lda (sptr),y
    cmp idbuf
    bne ff_next
    ldy idbuf
ff3:
    lda (sptr),y
    cmp idbuf,y
    bne ff_next
    dey
    bne ff3
    sec
    rts
ff_next:
    clc
    lda sptr
    adc #SYM_SIZE
    sta sptr
    bcc ff1
    inc sptr+1
    jmp ff1

pt_record:
    jsr nexttok                 // past RECORD
    lda fwd_desc                // a forward declared record (type PNode = ^Node; ... Node = record): reuse its descriptor
    beq pr_newdesc
    jsr desc_ptr
    lda fwd_desc
    ldx #0
    stx fwd_desc
    jmp pr_gotdesc
pr_newdesc:
    jsr new_desc
pr_gotdesc:
    sta rfidx
    ldy #D_KIND
    lda #T_RECORD
    sta (tmpc3),y
    ldy #D_LO                   // unique number: descriptor index + 1
    lda rfidx
    clc
    adc #1
    sta (tmpc3),y
    lda #0
    sta rofs
    sta rofs+1
pr_loop:
    lda tok
    cmp #TK_END
    bne pr_group
    jmp pr_end
pr_group:                       // one group: name {, name} : type
    lda symp                    // the group's field records start here
    sta rfstart
    lda symp+1
    sta rfstart+1
    lda #0
    sta rfn
pr_name:
    lda tok
    cmp #TK_IDENT
    beq !+
    jmp err_syntax
!:  lda rfidx                   // duplicate field name?
    sta fowner
    jsr find_field
    bcc !+
    lda #E_DUP
    jmp error
!:  lda #K_FIELD
    sta nkind
    lda #0
    sta ntype
    sta nval
    sta nval+1
    jsr addsym_raw
    sec                         // record the owner in the field just added
    lda symp
    sbc #SYM_SIZE
    sta tmpc3
    lda symp+1
    sbc #0
    sta tmpc3+1
    ldy #21
    lda rfidx
    sta (tmpc3),y
    inc rfn
    jsr nexttok
    lda tok
    cmp #TK_COMMA
    bne !+
    jsr nexttok
    jmp pr_name
!:  lda #TK_COLON
    jsr expect
    lda rfidx                   // the field type may itself be a record: save our state
    pha
    lda rofs
    pha
    lda rofs+1
    pha
    lda rfstart
    pha
    lda rfstart+1
    pha
    lda rfn
    pha
    jsr parse_type
    pla
    sta rfn
    pla
    sta rfstart+1
    pla
    sta rfstart
    pla
    sta rofs+1
    pla
    sta rofs
    pla
    sta rfidx
    jsr type_size               // tmpc2 = size of one field of this type
    lda rfstart                 // give the group's fields their type and offsets
    sta tmpc3
    lda rfstart+1
    sta tmpc3+1
pr_fill:
    ldy #17
    lda curtype
    sta (tmpc3),y
    ldy #20
    lda curdesc
    sta (tmpc3),y
    ldy #18
    lda rofs
    sta (tmpc3),y
    iny
    lda rofs+1
    sta (tmpc3),y
    clc                         // next offset
    lda rofs
    adc tmpc2
    sta rofs
    lda rofs+1
    adc tmpc2+1
    sta rofs+1
    bpl !+
    jmp err_mem   // record larger than 32 KB
!:  clc
    lda tmpc3
    adc #SYM_SIZE
    sta tmpc3
    bcc !+
    inc tmpc3+1
!:  dec rfn
    bne pr_fill
    lda tok
    cmp #TK_SEMI
    bne pr_end
    jsr nexttok
    jmp pr_loop
pr_end:
    lda #TK_END
    jsr expect
    lda rfidx                   // total size
    jsr desc_ptr
    ldy #D_SIZE
    lda rofs
    sta (tmpc3),y
    iny
    lda rofs+1
    sta (tmpc3),y
    lda #T_RECORD
    sta curtype
    lda rfidx
    sta curdesc
    rts
