// This file is in the public domain: use it, change it, share it, sell it - do whatever you like with it.
// No permission, credit or payment needed. It comes as it is, with no warranty. Enjoy!
// Note: this has only been tested in the VICE emulator, never on real hardware.
// =====================================================================================
// desig.asm - designators: variables of array/string type and their elements
// =====================================================================================
//
// A DESIGNATOR names a storage location:   a    a[i]    a[i][j]    a[i, j]    s[3]
// For arrays and strings the "value" of the variable name is its ADDRESS, so gen_desig always
// produces the address of the designated object in the accumulator and sets etype/edesc to
// its type. Callers then
//   - load a scalar element through the pointer (rt_ldpw / rt_ldpb),
//   - or store through it (rt_push the address first, then rt_stpw / rt_stpb), or
//   - use the address itself for a whole array/string (assignment, parameters, write).
//
// Indexing one level generates:
//     <address of the array>   in ac
//     jsr rt_push              save it
//     <index expression>       in ac
//     jsr rt_aidx1/2/n lo...   ac = base + (index - lo) * element size   (pops the base)

// ---- variables of the routines around the current one (nested routines) ------------------------------------------
// WCELL: value of 'edesc' that gen_outer_base leaves for a boolean, char or byte LOCAL of an enclosing routine. The cell in the
// frame is 16 bits wide (the routine itself loads and stores it with rt_ldl / rt_stl), so code that reaches it through its
// address (gen_ldp / gen_stp) must load and store 16 bits as well; for these types the descriptor index is not used otherwise.
.const WCELL = $ff
// is_outer: sptr = record of a variable. Carry set if it is a local, a value parameter or a var parameter of a routine OTHER than
// the one being compiled, i.e. one of the routines that contain it (its record byte 31 = the depth of the routine it belongs to,
// 'inproc' = the depth of the current routine). Globals and the variables of the current routine give carry clear.
is_outer:
    ldy #16
    lda (sptr),y
    cmp #K_LOCAL
    beq io_chk
    cmp #K_VARPARAM
    beq io_chk
    cmp #K_CPARAM
    bne io_no
io_chk:
    ldy #31
    lda (sptr),y
    cmp inproc
    beq io_no
    sec
    rts
io_no:
    clc
    rts

// gen_outer_base: sptr = record of an outer variable (is_outer), tmpc1 = its offset. Emit the code that leaves in ac the address
// of the variable, like the base address code at the start of gen_desig does for the variables of the current routine:
//   1. the frame pointer of the routine the variable belongs to (gen_frame)
//   2. the address of the variable's cell in that frame: for a local fp + offset; for a PARAMETER the offset is still relative
//      to the argument area (the routine's declarations are not complete, its fp-relative offsets are not known yet), so go
//      through the slot where the routine keeps the address of its argument area (pbs_tab): [fp + slot] + offset
//   3. a var parameter (or a read-only structured parameter) holds the address of the variable in its cell: load it
gen_outer_base:
    ldy #31
    lda (sptr),y
    sta go_lv                   // depth of the routine the variable belongs to
    ldy #21
    lda (sptr),y
    sta go_par                  // 1 = parameter
    ldy #16
    lda (sptr),y
    sta go_kind
    lda tmpc1
    sta go_off
    lda go_lv
    jsr gen_frame               // ac = frame pointer of that routine
    lda go_par
    beq go_cell                 // a local: the offset is already relative to fp
    ldx go_lv                   // a parameter: ac = [ac + slot] = address of the argument area
    lda pbs_tab,x
    sec
    sbc #1
    sta go_t
    :GCALL(rt_addi)
    lda go_t
    ldx #0
    jsr emit_word
    :GCALL(rt_ldpw)
go_cell:
    :GCALL(rt_addi)             // + the offset: ac = address of the variable's cell
    lda go_off
    ldx #0
    jsr emit_word
    lda go_kind
    cmp #K_LOCAL
    beq go_local
    :GCALL(rt_ldpw)             // var parameter: the cell holds the address of the variable
    rts
go_local:
    lda etype                   // a boolean / char / byte cell is 16 bits wide: mark the address (see WCELL)
    cmp #T_BOOL
    beq go_w
    cmp #T_CHAR
    beq go_w
    cmp #T_BYTE
    bne go_done
go_w:
    lda #WCELL
    sta edesc
go_done:
    rts
go_lv:   .byte 0
go_par:  .byte 0
go_kind: .byte 0
go_off:  .byte 0
go_t:    .byte 0

// gen_desig: sptr = record of the variable, the current token is its name. Consumes the name
// and any index list. On return ac holds (at run time) the address; etype/edesc = its type.
gen_desig:
    ldy #17                     // type of the variable
    lda (sptr),y
    sta etype
    ldy #20
    lda (sptr),y
    sta edesc
    ldy #18                     // operand: address or frame offset
    lda (sptr),y
    sta tmpc1
    iny
    lda (sptr),y
    sta tmpc1+1
    jsr is_outer                // a variable of a routine around the current one (nested routines): see gen_outer_base
    bcc gd_normal
    jsr gen_outer_base
    jmp gd_idx
gd_normal:
    ldy #16
    lda (sptr),y
    cmp #K_VAR                  // global: the address is a constant
    beq gd_glob
    cmp #K_VARB
    bne !+
gd_glob:
    jsr gc_ldi
    jsr emit_op_word
    jmp gd_idx
!:  cmp #K_LOCAL                // local: address = frame pointer + offset
    bne !+
    :GCALL(rt_lea)
    jsr emit_op_byte
    jmp gd_idx
!:  cmp #K_VARPARAM             // parameters passed by address: the frame cell holds it
    beq gd_ptr
    cmp #K_CPARAM
    beq gd_ptr
    jmp err_type
gd_ptr:
    jsr gc_ldl
    jsr emit_op_byte
gd_idx:
    jsr nexttok                 // past the name
gd_loop:
    lda tok
    cmp #TK_LBRK                // another index list?
    beq !+
    cmp #TK_DOT                 // or a field selection  r.f ?
    beq gd_field
    cmp #TK_CARET               // or a pointer dereference  p^ ?
    beq gd_caret
    rts
!:  lda etype                   // only arrays and strings can be indexed
    cmp #T_ARRAY
    bcc gd_notidx
    cmp #T_RECORD
    bcs gd_notidx
    jmp gd_dim
gd_notidx:
    jmp err_type
gd_caret:                       // ac = address of a pointer variable: load the pointer, then follow it
    lda etype
    cmp #T_PTR
    beq !+
    rts
!:  :GCALL(rt_ldpw)
    jsr deref_type
    jsr nexttok                 // past ^
    jmp gd_loop

// deref_type: etype = T_PTR, edesc = its descriptor (ac holds the pointer VALUE). Sets etype/edesc to the
// type the pointer points to. An untyped pointer (from @) cannot be followed.
deref_type:
    lda edesc
    jsr desc_ptr
    ldy #D_KIND
    lda (tmpc3),y
    cmp #T_PTR
    beq !+
    jmp err_type
!:  ldy #D_ETYPE
    lda (tmpc3),y
    sta etype
    ldy #D_EDESC
    lda (tmpc3),y
    sta edesc
    rts

gd_field:                       // r.f : add the field's offset to the address in ac
    lda etype
    cmp #T_RECORD
    beq !+
    rts                         // not a record: the dot belongs to someone else (end of program)
!:  jsr nexttok
    lda tok
    cmp #TK_IDENT
    beq !+
    jmp err_syntax
!:  lda edesc
    sta fowner
    jsr find_field
    bcs !+
    jmp err_undef
!:  ldy #18
    lda (sptr),y
    sta tmpc1
    iny
    lda (sptr),y
    sta tmpc1+1
    lda tmpc1                   // offset 0 needs no code
    ora tmpc1+1
    beq gf_type
    :GCALL(rt_addi)
    jsr emit_op_word
gf_type:
    ldy #17
    lda (sptr),y
    sta etype
    ldy #20
    lda (sptr),y
    sta edesc
    jsr nexttok
    jmp gd_loop
gd_dim:                         // ac = address of an array/string; token is '[' or ','
    jsr gc_push
    jsr nexttok
    lda edesc                   // remember which array is being indexed
    pha
    jsr expr                    // the index
    jsr noreal
    lda etype
    cmp #T_ARRAY                // must be a scalar
    bcc !+
    jmp err_type
!:  pla
    jsr gen_aidx                // emits the address calculation, sets etype/edesc to the element
    lda tok
    cmp #TK_COMMA               // a[i, j]: the element must be an array again
    bne !+
    lda etype
    cmp #T_ARRAY
    bcc gd_bad2
    cmp #T_RECORD
    bcc gd_dim
gd_bad2:
    jmp gd_notidx
!:  lda #TK_RBRK
    jsr expect
    jmp gd_loop

// gen_aidx: A = descriptor index of the array/string being indexed. Emits the address
// calculation (the index is in ac, the base address on the software stack) and sets
// etype/edesc to the element type.
gen_aidx:
    jsr desc_ptr
    ldy #D_ESIZE+1
    lda (tmpc3),y
    bne ga_gen                  // element size > 255
    dey
    lda (tmpc3),y
    cmp #1
    beq ga_1
    cmp #2
    beq ga_2
ga_gen:                         // general element size: jsr rt_aidx, lo, size
    :GCALL(rt_aidx)
    jsr ga_lo
    ldy #D_ESIZE+1
    lda (tmpc3),y
    tax
    dey
    lda (tmpc3),y
    jsr emit_word
    jmp ga_type
ga_1:
    :GCALL(rt_aidx1)
    jsr ga_lo
    jmp ga_type
ga_2:
    :GCALL(rt_aidx2)
    jsr ga_lo
ga_type:
    ldy #D_ETYPE
    lda (tmpc3),y
    sta etype
    ldy #D_EDESC
    lda (tmpc3),y
    sta edesc
    rts
ga_lo:                          // emit the low bound of the array
    ldy #D_LO+1
    lda (tmpc3),y
    tax
    dey
    lda (tmpc3),y
    jmp emit_word

// gen_ldp: emit the load of a scalar element whose address is in ac, according to etype:
// integers are 2 bytes, reals 4 bytes (into FAC), byte/char/boolean elements are 1 byte.
gen_ldp:
    lda etype
    cmp #T_REAL
    bne !+
    :GCALL(rt_fldp)             // real: 4 bytes into FAC
    rts
!:  cmp #T_INT
    beq gl_w
    cmp #T_PTR
    bne !+
gl_w:
    :GCALL(rt_ldpw)
    rts
!:  lda edesc                   // a boolean / char / byte in a 16 bit frame cell of an enclosing routine (WCELL, see
    cmp #WCELL                  // gen_outer_base): load the whole cell
    beq gl_w
    :GCALL(rt_ldpb)
    rts

// gen_stp: emit the store of ac through the element address on the software stack, for a
// target of scalar type etype.
gen_stp:
    lda etype
    cmp #T_REAL
    bne !+
    :GCALL(rt_fstp)             // real: FAC to the address on the stack
    rts
!:  cmp #T_INT
    beq gs_w
    cmp #T_PTR
    bne !+
gs_w:
    :GCALL(rt_stpw)
    rts
!:  lda edesc                   // a 16 bit frame cell (WCELL): store the whole cell, so that its high byte is never stale
    cmp #WCELL
    beq gs_w
    :GCALL(rt_stpb)
    rts
