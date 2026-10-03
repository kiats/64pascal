// This file is in the public domain: use it, change it, share it, sell it - do whatever you like with it.
// No permission, credit or payment needed. It comes as it is, with no warranty. Enjoy!
// Note: this has only been tested in the VICE emulator, never on real hardware.
// =====================================================================================
// platcode.asm - routines shared by the programs that contain the compiler
// =====================================================================================
//
//   install_runtime   copy the runtime image to its fixed address RT_BASE
//   run_program       run the program compiled in place at CODE_BASE; returns when it ends
// (the start-up macros are in platform.asm)

install_runtime:                // copy the runtime image to its fixed address
#if HIROM
    lda #>rt_image              // Plus/4: the image lies next to RT_BASE and may overlap it. Image below RT_BASE: copy from
    cmp #>RT_BASE               // the top down, otherwise (the normal ascending copy) from the bottom up
    bcs ir_up
    lda #<rt_image
    sta tmp
    lda #(>rt_image) + (RT_SIZE >> 8)
    sta tmp+1
    lda #<RT_BASE
    sta wd
    lda #(>RT_BASE) + (RT_SIZE >> 8)
    sta wd+1
    ldx #(RT_SIZE>>8)+1
ir_page:
    ldy #255
!:  lda (tmp),y
    sta (wd),y
    dey
    cpy #255
    bne !-
    dec tmp+1
    dec wd+1
    dex
    bne ir_page
    jmp ir_done
ir_up:
#endif
    lda #<rt_image
    sta tmp
    lda #>rt_image
    sta tmp+1
    lda #<RT_BASE
    sta wd
    lda #>RT_BASE
    sta wd+1
    ldx #(RT_SIZE>>8)+1
    ldy #0
!:  lda (tmp),y
    sta (wd),y
    iny
    bne !-
    inc tmp+1
    inc wd+1
    dex
    bne !-
ir_done:
#if HAVEREAL
#if !NOSTORE
    jmp install_ext_store
#else
    rts
#endif
#else
    rts
#endif

#if HAVEREAL
#if !NOSTORE
// install_ext_store: keep the extension chunks (heap, floating point, write formats) in the RAM under the KERNAL ROM,
// at HIDDEN_BASE, so that their image in the program file is dead like the runtime image. (Writing to an address under
// a ROM stores into the RAM below it.) install_ext copies the chunks a program uses to EXT_BASE when it runs.
install_ext_store:
    lda #<ext_image
    sta tmp
    lda #>ext_image
    sta tmp+1
    lda #<HIDDEN_BASE
    sta wd
    lda #>HIDDEN_BASE
    sta wd+1
    ldx #((ek3 - ek0) >> 8) + 1
    ldy #0
!:  lda (tmp),y
    sta (wd),y
    iny
    bne !-
    inc tmp+1
    inc wd+1
    dex
    bne !-
#if !HIROM                      // (the Plus/4 programs keep interrupts disabled while the ROMs are off)
    lda #<hid_rti               // while the KERNAL is switched off an interrupt would use these vectors (they
    sta $fffa                   // are in the RAM then): they point to an RTI
    sta $fffe
    lda #>hid_rti
    sta $fffb
    sta $ffff
#endif
    rts
hid_rti:
    rti
#endif
#endif

// install_ext: copy the extension chunks (heap, floating point) that the compiled program uses to EXT_BASE.
// They share their memory with the compiler's tables, which are no longer needed once the program runs.
install_ext:
#if HIROM
    rts                         // (a program with extension chunks is not run in place on the Plus/4: see ideops.asm,
                                // 64pascal.asm; standalone images carry their chunks)
#elif !NOEXT
#if HAVEREAL
    sei                         // the chunks are kept in the RAM under the KERNAL ROM: switch it off while copying
    lda #BANK_HIDDEN
    sta BANK_REG
#endif
    ldx #9                      // first extension chunk
ie_loop:
    jsr ck_used
    beq ie_next
    jsr ck_entry                // tmpc3 -> table entry: start, end, dependencies, source
    stx ck_chunk
    ldy #0
    lda (tmpc3),y               // destination
    sta wd
    iny
    lda (tmpc3),y
    sta wd+1
    ldy #6
    lda (tmpc3),y               // source
    sta tmp
    iny
    lda (tmpc3),y
    sta tmp+1
    sec                         // length = end - start
    ldy #2
    lda (tmpc3),y
    ldy #0
    sbc (tmpc3),y
    sta rem
    ldy #3
    lda (tmpc3),y
    ldy #1
    sbc (tmpc3),y
    sta rem+1
    ldy #0
ie_copy:
    lda rem
    ora rem+1
    beq ie_done
    lda (tmp),y
    sta (wd),y
    iny
    bne !+
    inc tmp+1
    inc wd+1
!:  lda rem
    bne !+
    dec rem+1
!:  dec rem
    jmp ie_copy
ie_done:
    ldx ck_chunk
ie_next:
    inx
    cpx #CK_COUNT
    bne ie_loop
#if HAVEREAL
    lda #BANK_NORMAL
    sta BANK_REG
    cli
#endif
#endif
    rts

run_program:                    // run the program in the code buffer
    jsr install_ext
    tsx                         // rt_halt returns to our caller at this stack level
    stx rt_savesp
    lda #<STK_TOP               // software stack; the main program has no frame, fp is only a
    sta ssp                     // sane initial value
    sta fp
    lda #>STK_TOP
    sta ssp+1
    sta fp+1
    jmp (codebase)              // the program ends with 'jmp rt_halt'

zpsave:  .fill 40, 0            // saved copy of zero page $02-$29

