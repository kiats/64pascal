// This file is in the public domain: use it, change it, share it, sell it - do whatever you like with it.
// No permission, credit or payment needed. It comes as it is, with no warranty. Enjoy!
// Note: this has only been tested in the VICE emulator, never on real hardware.
// =====================================================================================
// messages.asm - texts for compile errors
// =====================================================================================
//
// print_errmsg prints the text for a compile error code (E_* in defs.asm). Strings are ASCII and
// are printed with 'puts' from the runtime (which converts them for the screen).

.encoding "ascii"

print_errmsg:                   // A = error code
    cmp #11
    bcs pe_generic
    asl
    tay
    lda errtab,y
    ldx errtab+1,y
    jmp puts
pe_generic:
    lda #<em_generic
    ldx #>em_generic
    jmp puts

// get_errmsg: A = error code -> X:A = address of its text
get_errmsg:
    cmp #11
    bcc ge_ok
    lda #0
ge_ok:
    asl
    tay
    lda errtab,y
    ldx errtab+1,y
    rts

errtab:
    .word em_generic            // 0 (unused)
    .word em_syntax             // E_SYNTAX
    .word em_undef              // E_UNDEF
    .word em_dup                // E_DUP
    .word em_type               // E_TYPE
    .word em_bool               // E_BOOL
    .word em_eof                // E_EOF
    .word em_mem                // E_MEM
    .word em_str                // E_STR
    .word em_char               // E_CHARLIT
    .word em_args               // E_ARGS

em_generic: .text "ERROR"
            .byte 0
em_syntax:  .text "SYNTAX ERROR"
            .byte 0
em_undef:   .text "UNKNOWN IDENTIFIER"
            .byte 0
em_dup:     .text "DUPLICATE IDENTIFIER"
            .byte 0
em_type:    .text "TYPE MISMATCH"
            .byte 0
em_bool:    .text "BOOLEAN EXPRESSION EXPECTED"
            .byte 0
em_eof:     .text "UNEXPECTED END OF FILE"
            .byte 0
em_mem:     .text "OUT OF MEMORY"
            .byte 0
em_str:     .text "STRING TOO LONG"
            .byte 0
em_char:    .text "CHARACTER EXPECTED"
            .byte 0
em_args:    .text "WRONG NUMBER OF ARGUMENTS"
            .byte 0
