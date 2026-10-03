// This file is in the public domain: use it, change it, share it, sell it - do whatever you like with it.
// No permission, credit or payment needed. It comes as it is, with no warranty. Enjoy!
// Note: this has only been tested in the VICE emulator, never on real hardware.
// =====================================================================================
// vars.asm - code generation for accessing variables
// =====================================================================================
//
// A variable can live in several places, and each needs different machine code:
//   K_VAR      global, 16-bit cell at a fixed address          (operand = address)
//   K_VARB     global, one byte at a fixed address             (operand = address)
//   K_LOCAL    local variable or value parameter in the frame  (operand = frame offset)
//   K_VARPARAM var parameter: the frame cell holds the address (operand = frame offset)
//   K_CONST    constant                                        (operand = value)
// These helpers take the kind in A and the operand word in 'tmpc1' (or 'tmpc3' for gen_incdec)
// and emit the right runtime call followed by its inline operand.

// gen_load: emit code that loads the variable/constant into the accumulator.
gen_load:
    cmp #K_VAR
    bne !+
    :GCALL(rt_ldv)
    jmp emit_op_word
!:  cmp #K_VARB
    bne !+
    :GCALL(rt_ldvb)
    jmp emit_op_word
!:  cmp #K_CONST
    bne !+
    jsr gc_ldi
    jmp emit_op_word
!:  cmp #K_LOCAL
    bne !+
    jsr gc_ldl
    jmp emit_op_byte
!:  cmp #K_VARPARAM
    beq !+
    jmp err_syntax   // procedures, types ... are not values
!:  :GCALL(rt_ldlp)
    jmp emit_op_byte

// gen_store: emit code that stores the accumulator into the variable.
gen_store:
    cmp #K_VAR
    bne !+
    :GCALL(rt_stv)
    jmp emit_op_word
!:  cmp #K_VARB
    bne !+
    :GCALL(rt_stvb)
    jmp emit_op_word
!:  cmp #K_LOCAL
    bne !+
    :GCALL(rt_stl)
    jmp emit_op_byte
!:  cmp #K_VARPARAM
    beq !+
    jmp err_type   // cannot assign to constants, types, ...
!:  :GCALL(rt_stlp)
    jmp emit_op_byte

// gen_incdec: add (forflag = 0) or subtract (forflag = 1) one from the variable whose kind is
// in A and whose operand is in tmpc3. Used by the for statement.
gen_incdec:
    cmp #K_VAR
    bne gi_b
    lda forflag
    bne !+
    :GCALL(rt_incv)
    jmp gi_w
!:  :GCALL(rt_decv)
gi_w:
    lda tmpc3
    ldx tmpc3+1
    jmp emit_word
gi_b:
    cmp #K_VARB
    bne gi_l
    lda forflag
    bne !+
    :GCALL(rt_incvb)
    jmp gi_w
!:  :GCALL(rt_decvb)
    jmp gi_w
gi_l:
    lda forflag                 // K_LOCAL
    bne !+
    :GCALL(rt_incl)
    jmp gi_lb
!:  :GCALL(rt_decl)
gi_lb:
    lda tmpc3
    jmp emit

// gen_fload / gen_fstore: like gen_load / gen_store for a variable of type real (4 bytes): FAC <-> variable.
// A real constant (K_CONST of type real) has the address of its text as its value.
gen_fload:
    cmp #K_VAR
    bne !+
    :GCALL(rt_fldv)
    jmp emit_op_word
!:  cmp #K_CONST
    bne !+
    :GCALL(rt_flit)
    jmp emit_op_word
!:  cmp #K_LOCAL
    bne !+
    :GCALL(rt_fldl)
    jmp emit_op_byte
!:  cmp #K_VARPARAM
    beq !+
    jmp err_syntax
!:  :GCALL(rt_fldlp)
    jmp emit_op_byte

gen_fstore:
    cmp #K_VAR
    bne !+
    :GCALL(rt_fstv)
    jmp emit_op_word
!:  cmp #K_LOCAL
    bne !+
    :GCALL(rt_fstl)
    jmp emit_op_byte
!:  cmp #K_VARPARAM
    beq !+
    jmp err_type
!:  :GCALL(rt_fstlp)
    jmp emit_op_byte

emit_op_word:                   // emit the 16-bit operand held in tmpc1
    lda tmpc1
    ldx tmpc1+1
    jmp emit_word

emit_op_byte:                   // emit the low byte of the operand held in tmpc1
    lda tmpc1
    jmp emit

// typeok: A = the type that is required. Reports E_TYPE unless the type of the last expression
// ('etype') is the same, or both are numeric (integer and byte are interchangeable). If a real is
// required and the expression is an integer, code to convert it is emitted.
typeok:
    cmp etype
    beq to_ok
    cmp #T_REAL                 // a real is wanted: integers and bytes are converted
    bne to_nr
    lda etype
    cmp #T_INT
    beq to_i2f
    cmp #T_BYTE
    bne to_bad
to_i2f:
    jsr gc_i2f
    lda #T_REAL
    sta etype
    rts
to_nr:
    cmp #T_INT
    bne to_1
    lda etype
    cmp #T_BYTE
    beq to_ok
    bne to_bad
to_1:
    cmp #T_BYTE
    bne to_bad
    lda etype
    cmp #T_INT
    beq to_ok
to_bad:
    jmp err_type
to_ok:
    rts
