// This file is in the public domain: use it, change it, share it, sell it - do whatever you like with it.
// No permission, credit or payment needed. It comes as it is, with no warranty. Enjoy!
// Note: this has only been tested in the VICE emulator, never on real hardware.
// =====================================================================================
// proc.asm - procedures and functions: declarations and calls
// =====================================================================================
//
//   procedure name [ ( params ) ] ;  block ;
//   function  name [ ( params ) ] : type ;  block ;
//   params = [var] a, b : type { ; [var] c : type }          (at most 8 parameters; any type name)
//   block  = [const/var sections] begin ... end
//
// Calling convention (see the frame layout in runtime.asm): the caller pushes the arguments
// left to right (a value, or for var parameters the address; a real value takes 4 bytes, everything else 2),
// then "jsr rt_call routine".
// The routine starts with "jsr rt_enter L" and ends with "jsr rt_leave L,A"; a function
// delivers its result in the accumulator. A function assigns its result by assigning to its
// own name, which is stored in the frame slot at offset 0 (a real result is returned in FAC).
//
// Symbol record of a routine (K_PROCU / K_FUNC):
//   17 result type, 18/19 code address, 20 number of parameters, 21 bit i set = parameter i
//   is a var parameter, 22..29 type code of each parameter (a scalar type, or $80 + the
//   descriptor index for arrays/strings). Arrays and strings are always passed by address;
//   a value parameter of such a type is read-only (kind K_CPARAM).
// Routines cannot be nested. Locals and parameters are discarded from the symbol table at the
// end of the routine (symp is reset to 'scopebase').
//
// Forward declarations:  procedure p(a: integer); forward;  ...  procedure p(a: integer); begin ... end;
// The first header enters the routine and sets byte 30 of its symbol record (the record is no longer a plain routine: its
// code address is not known). Every call that is compiled before the definition emits "jsr rt_call <operand>" where the
// operand is part of a CHAIN: it holds the address of the operand of the previous such call (0 = the first one) and the
// record's address field (18/19) holds the last one. The definition (a second header with the same name, which must repeat
// the parameter list) walks the chain and stores the real address into every operand (chain_resolve_at, ctlfn.asm), clears
// byte 30 and compiles the body as usual. check_forward (ctlfn.asm) reports a routine that was never defined.
// Exit inside a routine is a jump chain that is resolved at the end of the body (exithead, ctlfn.asm).

// ---- helpers ------------------------------------------------------------------------------------
bitmask: .byte 1, 2, 4, 8, 16, 32, 64, 128

// paramptr: tmpc3 = address of the symbol record of parameter X (X is preserved).
// Parameters are the first records of a routine's scope.
paramptr:
    lda scopebase
    sta tmpc3
    lda scopebase+1
    sta tmpc3+1
    txa
    beq pp_done
    tay
pp1:
    clc
    lda tmpc3
    adc #SYM_SIZE
    sta tmpc3
    bcc !+
    inc tmpc3+1
!:  dey
    bne pp1
pp_done:
    rts

// getbit: carry = bit X of A.
getbit:
gb1:
    cpx #0
    beq gb2
    lsr
    dex
    jmp gb1
gb2:
    and #1
    lsr
    rts

// getptype: A = type code of parameter X of the routine whose record is at (tmpc3):
// a scalar type, or $80 + descriptor index for arrays/strings.
getptype:
    txa
    clc
    adc #22
    tay
    lda (tmpc3),y
    rts

// argok: A = type code of the parameter. The argument just compiled (etype/edesc) must fit it:
// scalars follow typeok; arrays must have the same descriptor; any string fits any string.
argok:
    bmi ao_struct
    jmp typeok
ao_struct:
    and #$7f
    sta tmpc2
    lda etype
    cmp #T_CHAR                 // a character may be passed where a string is expected
    bne ao_nc
    lda tmpc2
    jsr desc_ptr
    ldy #D_KIND
    lda (tmpc3),y
    cmp #T_STRING
    bne ao_bad
    jsr gc_c2s
    lda #T_STRING
    sta etype
    rts
ao_nc:
    lda etype
    cmp #T_ARRAY
    bcs ao_chk
ao_bad:
    jmp err_type
ao_chk:
    cmp #T_STRING
    beq ao_str
    ldx edesc                   // array: structurally identical type
    lda tmpc2
    jsr descsame
    bne ao_bad
    rts
ao_str:
    lda tmpc2
    jsr desc_ptr
    ldy #D_KIND
    lda (tmpc3),y
    cmp #T_STRING
    bne ao_bad
    rts

// varok: A = type code of a var parameter; vtype = type code of the variable passed. Reports
// E_TYPE unless they are identical (for arrays and strings: structurally identical, so a
// string[10] variable only fits a string[10] parameter and memory can never be overrun).
varok:
    sta tmpc2
    cmp vtype
    beq vo_ok
    lda tmpc2
    bpl vo_bad
    lda vtype
    bpl vo_bad
    and #$7f
    tax
    lda tmpc2
    and #$7f
    jsr descsame
    beq vo_ok
vo_bad:
    jmp err_type
vo_ok:
    rts

// cp_ptr: tmpc3 = curproc (indirect addressing needs a zero page pointer).
cp_ptr:
    lda curproc
    sta tmpc3
    lda curproc+1
    sta tmpc3+1
    rts

// ---- declaration -------------------------------------------------------------------------------
do_proc:
    lda inproc
    beq !+
    jmp err_syntax   // routines cannot be nested
!:  lda #0
    sta isfunc
    lda tok
    cmp #TK_FUNCTION
    bne !+
    inc isfunc
!:  jsr nexttok
    lda tok
    cmp #TK_IDENT
    beq !+
    jmp err_syntax
!:  jsr lookup                  // a routine that was declared 'forward' is completed here
    bcc dp_new
    ldy #30
    lda (sptr),y
    beq dp_new
    ldy #16
    lda (sptr),y
    ldx isfunc
    bne dp_wantf
    cmp #K_PROCU
    beq dp_complete
    bne dp_new
dp_wantf:
    cmp #K_FUNC
    bne dp_new
dp_complete:
    ldy #18                     // the calls emitted so far get the address of the code that starts here
    lda (sptr),y
    sta tmpc1
    iny
    lda (sptr),y
    sta tmpc1+1
    lda cpc
    sta tmpc2
    lda cpc+1
    sta tmpc2+1
    ldy #18                     // the record gets the real address
    lda cpc
    sta (sptr),y
    iny
    lda cpc+1
    sta (sptr),y
    ldy #30
    lda #0
    sta (sptr),y
    jsr chain_resolve_at        // resolve the chain that starts at tmpc1
    lda sptr
    sta curproc
    lda sptr+1
    sta curproc+1
    jmp dp_have
dp_new:
    lda #K_PROCU                // enter the routine's name; its code starts here
    ldx isfunc
    beq !+
    lda #K_FUNC
!:  sta nkind
    lda #T_INT
    sta ntype
    lda cpc
    sta nval
    lda cpc+1
    sta nval+1
    jsr addsym
    sec                         // curproc = the record just added
    lda symp
    sbc #SYM_SIZE
    sta curproc
    lda symp+1
    sbc #0
    sta curproc+1
dp_have:
    jsr cp_ptr                  // tmpc3 -> record of the routine
    ldy #20                     // clear parameter info
    lda #0
    sta (tmpc3),y
    iny
    sta (tmpc3),y
    iny
    sta (tmpc3),y
    iny
    sta (tmpc3),y
    ldy #30                     // (not forward)
    lda #0
    sta (tmpc3),y
    sta exithead                // Exit chain of this routine
    sta exithead+1
    lda symp                    // everything declared from now on is local
    sta scopebase
    lda symp+1
    sta scopebase+1
    lda #1
    sta inproc
    lda #0
    sta locoff
    sta pcount
    sta pvm
    lda isfunc                  // functions keep their result in frame slot 0
    beq !+
    lda #2
    sta locoff
!:  jsr nexttok
    lda tok
    cmp #TK_LPAR
    beq !+
    jmp dp_hdrend
!:  jsr nexttok
dp_grp:                         // one group: [var] a, b : type
    lda #0
    sta isvar
    lda tok
    cmp #TK_VAR
    bne !+
    inc isvar
    jsr nexttok
!:  lda pcount
    sta grpstart
dp_id:
    lda tok
    cmp #TK_IDENT
    beq !+
    jmp err_syntax
!:  lda pcount
    cmp #8                      // at most 8 parameters
    bcc !+
    jmp err_args
!:  lda #K_LOCAL
    ldx isvar
    beq !+
    lda #K_VARPARAM
!:  sta nkind
    lda #T_INT
    sta ntype
    lda #0
    sta nval
    sta nval+1
    jsr addsym
    inc pcount
    jsr nexttok
    lda tok
    cmp #TK_COMMA
    bne !+
    jsr nexttok
    jmp dp_id
!:  lda #TK_COLON
    jsr expect
    jsr parse_type              // parameter type -> curtype / curdesc
    ldx grpstart                // record type / var-ness for every parameter of the group
dp_set:
    cpx pcount
    bcs dp_setdone
    jsr paramptr
    ldy #17                     // type of the parameter
    lda curtype
    sta (tmpc3),y
    ldy #20
    lda curdesc
    sta (tmpc3),y
    lda curtype                 // type code used in the routine's signature
    cmp #T_ARRAY
    bcc dp_sc
    lda curdesc                 // array/string: $80 + descriptor index
    ora #$80
    sta ptype,x
    lda isvar
    bne dp_vm
    ldy #16                     // a value parameter of structured type is passed by address and
    lda #K_CPARAM               // may only be read
    sta (tmpc3),y
    jmp dp_vm
dp_sc:
    sta ptype,x
dp_vm:
    lda isvar
    beq !+
    lda pvm
    ora bitmask,x
    sta pvm
!:  inx
    jmp dp_set
dp_setdone:
    lda tok
    cmp #TK_SEMI
    bne !+
    jsr nexttok
    jmp dp_grp
!:  lda #TK_RPAR
    jsr expect
dp_hdrend:
    lda #0                      // frame offsets of the parameters, relative to the argument area: the last
    sta argbytes                // one is on top (offset 0); a cell takes 2 bytes, a real value parameter 4
    ldx pcount
dp_off:
    dex
    bmi dp_offdone
    jsr paramptr
    lda argbytes
    ldy #18
    sta (tmpc3),y
    ldy #17
    lda (tmpc3),y
    cmp #T_REAL
    bne dp_sz2
    ldy #16
    lda (tmpc3),y
    cmp #K_VARPARAM
    beq dp_sz2
    lda argbytes
    clc
    adc #4
    sta argbytes
    jmp dp_off
dp_sz2:
    lda argbytes
    clc
    adc #2
    sta argbytes
    jmp dp_off
dp_offdone:
    lda isfunc
    beq dp_semi
    lda #TK_COLON               // function result type
    jsr expect
    lda tok
    cmp #TK_IDENT
    beq !+
    jmp err_syntax
!:  jsr lookup
    bcs !+
    jmp err_undef
!:  ldy #16
    lda (sptr),y
    cmp #K_TYPE
    beq !+
    jmp err_syntax
!:  ldy #18
    lda (sptr),y
    pha
    jsr cp_ptr
    pla
    ldy #17
    sta (tmpc3),y
    cmp #T_REAL                 // a real result needs 4 bytes in the frame
    bne !+
    lda #4
    sta locoff
!:  jsr nexttok
dp_semi:
    lda #TK_SEMI
    jsr expect
    jsr cp_ptr
    ldy #20                     // store the signature in the routine's record
    lda pcount
    sta (tmpc3),y
    iny
    lda pvm
    sta (tmpc3),y
    iny                         // parameter type codes
    ldx #0
!:  lda ptype,x
    sta (tmpc3),y
    iny
    inx
    cpx #8
    bne !-

    jsr is_forward              // procedure p(...); forward;
    bne dp_body
    jsr nexttok
    lda #TK_SEMI
    jsr expect
    jsr cp_ptr
    ldy #30                     // mark it, the chain of the calls that come before the definition starts empty
    lda #1
    sta (tmpc3),y
    ldy #18
    lda #0
    sta (tmpc3),y
    iny
    sta (tmpc3),y
    jmp dp_scope_end
dp_body:
    jsr decls                   // local const / var sections
    lda tok
    cmp #TK_BEGIN
    beq !+
    jmp err_syntax
!:  lda locoff                  // now the size of the locals is known: parameters lie above the
    clc                         // locals, saved frame pointer (2) and return address (2)
    adc #4
    sta tmpc2
    ldx #0
dp_fix:
    cpx pcount
    bcs dp_fixed
    jsr paramptr
    ldy #18
    lda (tmpc3),y
    clc
    adc tmpc2
    sta (tmpc3),y
    inx
    jmp dp_fix
dp_fixed:
    :GCALL(rt_enter)            // prologue: reserve the locals
    lda locoff
    jsr emit
    jsr stmt                    // the body
    ldx #4                      // Exit jumps here
    jsr res_here
    lda isfunc
    beq dp_noret
    jsr cp_ptr                  // function result slot -> accumulator (a real: -> FAC)
    ldy #17
    lda (tmpc3),y
    cmp #T_REAL
    bne dp_ri
    :GCALL(rt_fldl)
    jmp dp_rs
dp_ri:
    jsr gc_ldl
dp_rs:
    lda #0
    jsr emit
dp_noret:
    :GCALL(rt_leave)            // epilogue: drop frame and arguments, return
    lda locoff
    jsr emit
    lda argbytes                // bytes of arguments
    jsr emit
    lda #TK_SEMI
    jsr expect
dp_scope_end:
    lda scopebase               // forget the parameters and locals
    sta symp
    lda scopebase+1
    sta symp+1
    lda #<SYM_BASE
    sta scopebase
    lda #>SYM_BASE
    sta scopebase+1
    lda #0
    sta inproc
    sta curproc
    sta curproc+1
    jmp decls

// ---- calls ---------------------------------------------------------------------------------------
// gen_call: compile a call of the routine whose record is at 'sptr'. The current token is the
// routine's name. Compiles the argument list, emits the pushes and the rt_call. For a function
// 'etype' is set to the result type. Hardware stack while compiling: argument index (top),
// then the record address (low, high).
.macro GETCP() {                // tmpc3 = record of the routine being called; leaves X = S
    tsx
    lda $0102,x
    sta tmpc3
    lda $0103,x
    sta tmpc3+1
}

gen_call:
    lda sptr+1
    pha
    lda sptr
    pha
    lda #0
    pha                         // argument index
    jsr nexttok                 // skip the name
    lda tok
    cmp #TK_LPAR
    beq gc_args
    :GETCP()                    // no argument list: the routine must have no parameters
    ldy #20
    lda (tmpc3),y
    bne !+
    jmp gc_emit
!:  lda #E_ARGS
    jmp error
gc_args:
    jsr nexttok
gc_arg:
    :GETCP()
    lda $0101,x                 // index of this argument
    sta tmpc2
    ldy #20
    lda tmpc2
    cmp (tmpc3),y               // index < parameter count ?
    bcc !+
    jmp err_args   // too many arguments
!:  ldy #21
    lda (tmpc3),y
    ldx tmpc2
    jsr getbit                  // carry set: this is a var parameter
    bcs gc_var
    jsr expr                    // value parameter: evaluate and push
    :GETCP()
    lda $0101,x
    tax
    jsr getptype
    jsr argok                   // argument type must fit the parameter type
    :GETCP()
    lda $0101,x
    tax
    jsr getptype
    cmp #T_REAL                 // a real value takes 4 bytes
    bne gc_pi
    :GCALL(rt_fpush)
    jmp gc_next
gc_pi:
    jsr gc_push
    jmp gc_next
gc_var:                         // var parameter: the argument must be a variable; push its address
    lda tok
    cmp #TK_IDENT
    beq !+
    jmp err_syntax
!:  jsr lookup
    bcs !+
    jmp err_undef
!:  ldy #17
    lda (sptr),y
    cmp #T_ARRAY
    bcc gv_scalar
    jsr gen_desig               // array/string variable or element: its address is in ac
    lda etype
    cmp #T_ARRAY
    bcs gv_s2
    cmp #T_INT                  // only integer elements can be passed (1-byte elements would
    beq gv_s3                   // be overwritten with 2 bytes)
    jmp err_type
gv_s2:
    lda edesc
    ora #$80
gv_s3:
    sta vtype
    jmp gv_cmp
gv_scalar:
    ldy #17
    lda (sptr),y
    sta vtype
    ldy #18
    lda (sptr),y
    sta tmpc1
    iny
    lda (sptr),y
    sta tmpc1+1
    ldy #16
    lda (sptr),y
    cmp #K_VAR
    bne !+
    jsr gc_ldi              // global: its address is a constant
    jsr emit_op_word
    jmp gv_chk
!:  cmp #K_LOCAL
    bne !+
    :GCALL(rt_lea)              // local: address = fp + offset
    jsr emit_op_byte
    jmp gv_chk
!:  cmp #K_VARPARAM
    beq !+
    jmp err_type   // byte variables and others cannot be passed by reference
!:  jsr gc_ldl              // var parameter passed on: its cell already holds the address
    jsr emit_op_byte
gv_chk:
    jsr nexttok
gv_cmp:
    :GETCP()
    lda $0101,x
    tax
    jsr getptype
    jsr varok                   // var parameters need exactly the same type
    jsr gc_push
gc_next:
    tsx
    inc $0101,x                 // next argument
    lda tok
    cmp #TK_COMMA
    bne gc_close
    jsr nexttok
    jmp gc_arg
gc_close:
    lda #TK_RPAR
    jsr expect
    :GETCP()                    // were all parameters supplied?
    lda $0101,x
    ldy #20
    cmp (tmpc3),y
    beq gc_emit
    jmp err_args
gc_emit:
    :GETCP()
    ldy #17                     // result type (meaningful for functions)
    lda (tmpc3),y
    sta etype
    ldy #30
    lda (tmpc3),y
    beq gc_known
    :GCALL(rt_call)             // routine declared 'forward': the address is not known yet, chain the operand
    :GETCP()
    ldy #18
    lda (tmpc3),y               // old head of the chain -> becomes the operand
    pha
    iny
    lda (tmpc3),y
    pha
    lda cout                    // this operand is the new head
    ldy #18
    sta (tmpc3),y
    lda cout+1
    iny
    sta (tmpc3),y
    pla
    tax
    pla
    jsr emit_word
    jmp gcall_end
gc_known:
    ldy #18                     // code address of the routine
    lda (tmpc3),y
    sta tmpc1
    iny
    lda (tmpc3),y
    sta tmpc1+1
    :GCALL(rt_call)
    jsr emit_op_word
gcall_end:
    pla                         // drop index and record address from the hardware stack
    pla
    pla
    rts
