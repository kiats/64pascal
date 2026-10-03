// This file is in the public domain: use it, change it, share it, sell it - do whatever you like with it.
// No permission, credit or payment needed. It comes as it is, with no warranty. Enjoy!
// Note: this has only been tested in the VICE emulator, never on real hardware.
// =====================================================================================
// ptrfn.asm - pointers: New, Dispose and the address operator @
// =====================================================================================
//
//   var p: ^integer;  q: PNode;        pointer types: see pt_pointer in types.asm
//   new(p)       allocate a block of the size of the type p points to; p receives its address
//   dispose(p)   give the block back (a later New of the same size can reuse it)
//   @x           the address of a variable, array element, record field ...   (type: untyped pointer)
//   nil          the pointer that points nowhere (a predeclared constant, 0)
//   p^           the object p points to (parsed in desig.asm / expr.asm)
//
// The heap itself is the extension chunk of rt_heap.asm. A program that uses pointers starts with
// rt_hinit, which tells the heap where the global data ends (see compiler.asm).

// bp_new: NEW ( pointer designator )
bp_new:
    lda #TK_LPAR
    jsr expect
    lda tok
    cmp #TK_IDENT
    beq !+
    jmp err_syntax
!:  jsr lookup
    bcs !+
    jmp err_undef
!:  jsr gen_desig               // ac = address of the pointer variable
    lda etype
    cmp #T_PTR
    beq !+
    jmp err_type
!:  lda edesc                   // what does it point to?
    jsr desc_ptr
    ldy #D_KIND
    lda (tmpc3),y
    cmp #T_PTR
    beq !+
    jmp err_type   // an untyped pointer has no size
!:  ldy #D_ETYPE
    lda (tmpc3),y
    sta curtype
    ldy #D_EDESC
    lda (tmpc3),y
    sta curdesc
    jsr gc_push             // the address of the variable waits on the stack
    jsr type_size               // tmpc2 = size of the target
    lda tmpc2
    sta cval
    lda tmpc2+1
    sta cval+1
    jsr gc_ldi
    lda cval
    ldx cval+1
    jsr emit_word
    :GCALL(rt_new)
    lda #TK_RPAR
    jmp expect

// bp_dispose: DISPOSE ( pointer expression )
bp_dispose:
    lda #TK_LPAR
    jsr expect
    jsr expr
    lda etype
    cmp #T_PTR
    beq !+
    jmp err_type
!:  :GCALL(rt_dispose)
    lda #TK_RPAR
    jmp expect

// f_address: the factor  @ designator  : ac = its address, type = untyped pointer
f_address:
    jsr nexttok                 // past @
    lda tok
    cmp #TK_IDENT
    beq !+
    jmp err_syntax
!:  jsr lookup
    bcs !+
    jmp err_undef
!:  jsr gen_desig
    lda #T_PTR
    sta etype
    lda #0
    sta edesc                   // descriptor 0 is not a pointer type: such a pointer cannot be followed
    rts
