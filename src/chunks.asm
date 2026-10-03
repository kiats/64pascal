// This file is in the public domain: use it, change it, share it, sell it - do whatever you like with it.
// No permission, credit or payment needed. It comes as it is, with no warranty. Enjoy!
// Note: this has only been tested in the VICE emulator, never on real hardware.
// =====================================================================================
// chunks.asm - linking only the runtime routines a program needs
// =====================================================================================
//
// The runtime (runtime.asm) is divided into chunks ck0 .. ck8. The compiler notes every chunk that
// the generated code calls (mark_chunk, called from gen_jsr). When a standalone program file is
// written, only the used chunks are included, together with the chunks they depend on (a chunk may
// call routines in another one). Each chunk keeps its own fixed address, the start-up code of the
// program copies it there, so no relocation is needed.
//
// Chunk table entry: see below.
// 'rtused' is the 16 bit mask of the chunks used so far (bit 0 = core, always set).
//
// File layout of a standalone program written by emit_standalone_trailer:
//     BASIC line + start-up code (standalone.asm)
//     the program code
//     directory: one 6 byte entry per used chunk (destination, source in the file, length), then 6 zeros
//     the used chunks

#if NOEXT
.const CK_COUNT = 9
#elif HAVEREAL
.const CK_COUNT = 12            // 9 core chunks + 3 extension chunks (heap, floating point, write formats)
#else
.const CK_COUNT = 11            // 9 core chunks + the heap and the write formats
#endif

// Table entry (8 bytes): start address, end address, bit mask of the chunks it depends on, address of the
// chunk's bytes. The core chunks are read from the live runtime at RT_BASE (so a standalone file must be compiled
// before a program has run in place: its variables would be dirty), the extension chunks from the image that the
// compiler carries (C64: they are kept in the RAM under the KERNAL ROM, HIDDEN_BASE, and read with the ROM switched
// off, see install_ext and emit_standalone_trailer). The extension chunks (9 heap, 10 float, 11 write formats)
// are assembled for EXT_BASE, a region that holds the compiler's tables while compiling: they are copied
// there only when a program is run (install_ext) or loaded (start-up code of a standalone file).
chunk_tab:
    .word ck0, ck1
    .word %0000000000000000     // core: depends on nothing
    .word ck0                    // (the live runtime at RT_BASE: the program file's copy is reused as buffer space)
    .word ck1, ck2
    .word %0000000000000001     // arrays and bytes: core
    .word ck1                    // (the live runtime at RT_BASE: the program file's copy is reused as buffer space)
    .word ck2, ck3
    .word %0000000000000001     // frames: core
    .word ck2                    // (the live runtime at RT_BASE: the program file's copy is reused as buffer space)
    .word ck3, ck4
    .word %0000000000100001     // multiply / divide: core, output (division by zero message)
    .word ck3                    // (the live runtime at RT_BASE: the program file's copy is reused as buffer space)
    .word ck4, ck5
    .word %0000000000000001     // logic and comparisons: core
    .word ck4                    // (the live runtime at RT_BASE: the program file's copy is reused as buffer space)
    .word ck5, ck6
    .word %0000000000000001     // output: core
    .word ck5                    // (the live runtime at RT_BASE: the program file's copy is reused as buffer space)
    .word ck6, ck7
    .word %0000000000100001     // strings: core, output
    .word ck6                    // (the live runtime at RT_BASE: the program file's copy is reused as buffer space)
    .word ck7, ck8
    .word %0000000000000001     // input: core
    .word ck7                    // (the live runtime at RT_BASE: the program file's copy is reused as buffer space)
    .word ck8, ck9
    .word %0000000010000001     // crt: core, input (character conversion)
    .word ck8                    // (the live runtime at RT_BASE: the program file's copy is reused as buffer space)
#if !NOEXT
    .word ek0, ek1
    .word %0000000000100001     // heap (new / dispose): core, output (out of memory message)
    .word EXT_SRC + (ek0 - EXT_BASE)
#if HAVEREAL
    .word ek1, ek2
    .word %0000100010100001     // floating point: core, output, input, write formats (random numbers)
    .word EXT_SRC + (ek1 - EXT_BASE)
#endif
    .word ek2, ek3
    .word %0000000000100001     // write formats (write(x:width)): core, output
    .word EXT_SRC + (ek2 - EXT_BASE)
#endif

ck_bit_lo: .byte $01, $02, $04, $08, $10, $20, $40, $80, $00, $00, $00, $00
ck_bit_hi: .byte $00, $00, $00, $00, $00, $00, $00, $00, $01, $02, $04, $08

// ck_entry: X = chunk number -> tmpc3 = address of its table entry (X is preserved).
ck_entry:
    lda #<chunk_tab
    sta tmpc3
    lda #>chunk_tab
    sta tmpc3+1
    txa
    beq ce_done
    tay
ce1:
    clc
    lda tmpc3
    adc #8
    sta tmpc3
    bcc !+
    inc tmpc3+1
!:  dey
    bne ce1
ce_done:
    rts

// ck_used: X = chunk number -> Z clear if the chunk is marked in rtused (X preserved, A destroyed).
ck_used:
    lda rtused
    and ck_bit_lo,x
    sta ck_tmp
    lda rtused+1
    and ck_bit_hi,x
    ora ck_tmp
    rts

// mark_chunk: mk_lo / mk_hi = address of a runtime routine that the program calls. Marks the chunk that
// contains it. (Called for every runtime call that is generated; preserves all registers it uses.)
mark_chunk:
    lda tmpc3                   // tmpc3 is used by callers of gen_jsr: keep it
    pha
    lda tmpc3+1
    pha
    stx ck_x
    ldx #0
mc1:
    jsr ck_entry
    ldy #1                      // address >= start ?
    lda mk_hi
    cmp (tmpc3),y
    bcc mc_next
    bne mc_ge
    dey
    lda mk_lo
    cmp (tmpc3),y
    bcc mc_next
mc_ge:
    ldy #3                      // address < end ?
    lda mk_hi
    cmp (tmpc3),y
    bcc mc_hit
    bne mc_next
    dey
    lda mk_lo
    cmp (tmpc3),y
    bcs mc_next
mc_hit:
    lda rtused
    ora ck_bit_lo,x
    sta rtused
    lda rtused+1
    ora ck_bit_hi,x
    sta rtused+1
    jmp mc_out
mc_next:
    inx
    cpx #CK_COUNT
    bne mc1
mc_out:
    ldx ck_x
    pla
    sta tmpc3+1
    pla
    sta tmpc3
    rts

// ck_closure: add the chunks that used chunks depend on, until nothing changes.
ck_closure:
cc_again:
    lda rtused
    sta ck_old
    lda rtused+1
    sta ck_old+1
    ldx #0
cc1:
    jsr ck_used
    beq cc_next
    jsr ck_entry
    ldy #4
    lda (tmpc3),y
    ora rtused
    sta rtused
    iny
    lda (tmpc3),y
    ora rtused+1
    sta rtused+1
cc_next:
    inx
    cpx #CK_COUNT
    bne cc1
    lda rtused
    cmp ck_old
    bne cc_again
    lda rtused+1
    cmp ck_old+1
    bne cc_again
    rts

// emit_standalone_trailer: after the program code has been generated, append the chunk directory and
// the chunks themselves, and store the address of the directory in the start-up code.
emit_standalone_trailer:
    jsr ck_closure
    ldx #0                      // n = number of used chunks
    stx ck_n
et_count:
    jsr ck_used
    beq !+
    inc ck_n
!:  inx
    cpx #CK_COUNT
    bne et_count
    clc                         // directory start: tell the start-up code (it is in the template at the
    lda codebase                // beginning of the code buffer)
    adc #<(sa_dirptr - STAND_BASE)
    sta tmpc3
    lda codebase+1
    adc #>(sa_dirptr - STAND_BASE)
    sta tmpc3+1
    ldy #0
    lda cpc
    sta (tmpc3),y
    iny
    lda cpc+1
    sta (tmpc3),y
    lda ck_n                    // first chunk starts after the directory: dir + 6 * (n + 1)
    clc
    adc #1
    sta ck_run
    lda #0
    sta ck_run+1
    asl ck_run                  // * 2
    rol ck_run+1
    lda ck_run                  // * 3 = * 2 + * 1
    sta ck_tmp
    lda ck_run+1
    sta ck_tmp2
    asl ck_run                  // * 4
    rol ck_run+1
    clc
    lda ck_run                  // * 6 = * 4 + * 2
    adc ck_tmp
    sta ck_run
    lda ck_run+1
    adc ck_tmp2
    sta ck_run+1
    clc                         // ck_run = dir + 6 * (n + 1)
    lda ck_run
    adc cpc
    sta ck_run
    lda ck_run+1
    adc cpc+1
    sta ck_run+1
    ldx #0                      // directory entries
et_dir:
    jsr ck_used
    beq et_dnext
    jsr ck_entry
    stx ck_chunk
    sec                         // length = end - start
    ldy #2
    lda (tmpc3),y
    ldy #0
    sbc (tmpc3),y
    sta ck_len
    ldy #3
    lda (tmpc3),y
    ldy #1
    sbc (tmpc3),y
    sta ck_len+1
    ldy #1                      // destination = start
    lda (tmpc3),y
    tax
    ldy #0
    lda (tmpc3),y
    jsr emit_word
    lda ck_run                  // source = where the chunk will be in the file
    ldx ck_run+1
    jsr emit_word
    lda ck_len
    ldx ck_len+1
    jsr emit_word
    clc                         // next chunk follows this one
    lda ck_run
    adc ck_len
    sta ck_run
    lda ck_run+1
    adc ck_len+1
    sta ck_run+1
    ldx ck_chunk
et_dnext:
    inx
    cpx #CK_COUNT
    bne et_dir
    ldx #6                      // terminator: an entry of zeros
!:  lda #0
    jsr emit
    dex
    bne !-
    ldx #0                      // the chunks
et_data:
    jsr ck_used
    beq et_xnext
    jsr ck_entry
    stx ck_chunk
    ldy #6                      // source = address of the chunk's bytes in the compiler
    lda (tmpc3),y
    sta tmpc1
    iny
    lda (tmpc3),y
    sta tmpc1+1
    ldy #2                      // length = end - start
    sec
    lda (tmpc3),y
    ldy #0
    sbc (tmpc3),y
    sta tmpc2
    ldy #3
    lda (tmpc3),y
    ldy #1
    sbc (tmpc3),y
    sta tmpc2+1
#if HAVEREAL
#if !HIROM                      // (the Plus/4 programs run with the ROMs off anyway: the chunks are read directly)
    cpx #9                      // an extension chunk is kept in the RAM under the KERNAL ROM: switch it off
    bcc et_plain                // while the bytes are copied (no interrupts meanwhile)
    sei
    lda #BANK_HIDDEN
    sta BANK_REG
    jsr emit_block
    lda #BANK_NORMAL
    sta BANK_REG
    cli
    jmp et_after
et_plain:
#endif
#endif
    jsr emit_block
et_after:
    ldx ck_chunk
et_xnext:
    inx
    cpx #CK_COUNT
    bne et_data
    rts
