// This file is in the public domain: use it, change it, share it, sell it - do whatever you like with it.
// No permission, credit or payment needed. It comes as it is, with no warranty. Enjoy!
// Note: this has only been tested in the VICE emulator, never on real hardware.
// =====================================================================================
// 64pascal.asm - the SIMPLE COMPILER (no editor)
// =====================================================================================
//
// A small command-line style program:
//   1. asks for the name of a Pascal source file on drive 8 (for example HELLO.PAS),
//   2. loads it into the source buffer,
//   3. compiles it to a standalone program image,
//   4. writes that program to the disk under the same name without the extension (HELLO),
//   5. offers to run the program right away.
// Errors are reported with a message and the source line. The output program runs on a bare
// machine: LOAD"HELLO",8,1 and RUN.
//
// Build:   java -jar KickAss.jar src/64pascal.asm            (C64, also C128 in C64 mode)
//          java -jar KickAss.jar src/64pascal.asm -define C128
// Test:    ... :name=HELLO.PAS     builds in a file name instead of asking for one
//
//          java -jar KickAss.jar src/64pascal.asm -define PLUS4
//
// (The Plus/4 version runs with the ROMs off, so that the source text and the compiler's tables can use the RAM under
// them: see HIROM in memmap.asm and kfstubs.asm.)

#if PLUS4
#define HIROM
#define NOSTORE                 // 64pascal never overwrites its own program image: the extension chunks are read from it
#endif

.encoding "ascii"
.var presetname = cmdLineVars.containsKey("name") ? cmdLineVars.get("name") : ""
.const NAME_LEN = presetname.size()   // > 0: test build with a built-in source file name
.import source "memmap.asm"
.import source "zp.asm"
.import source "platform.asm"   // BASIC line "SYS start", PLAT_ENTER / PLAT_LEAVE

start:
#if C128
.assert "BASIC SYS address must match start", start == 7181, true
#elif PLUS4
.assert "BASIC SYS address must match start", start == 4109, true
#endif
    :PLAT_ENTER()
#if HIROM
    jsr rom_off_enter           // the KERNAL is only reached through the KF_ stubs from here on; the images at the end of
#endif                          // the program file may lie under the ROMs: switch them off before copying them
    jsr install_runtime
    lda #<m_banner
    ldx #>m_banner
    jsr KF_puts

.if (NAME_LEN > 0) {
    ldx #NAME_LEN - 1           // test build: use the preset file name
!:  lda preset,x
    sta fbuf,x
    dex
    bpl !-
    lda #NAME_LEN
    sta fname_len
} else {
ask_name:
    lda #<m_prompt              // ask for the source file name (typed on its own line)
    ldx #>m_prompt
    jsr KF_puts
    jsr read_line
    lda fname_len               // RETURN alone: list the Pascal files on the disk and ask again
    bne have_name
    lda #13
    jsr KF_CHROUT
    jsr list_pas
    bcs list_failed
    bne listed
    lda #<m_nofiles
    ldx #>m_nofiles
    jsr KF_puts
listed:
    lda #13
    jsr KF_CHROUT
    jmp ask_name
list_failed:
    lda #<m_nodisk
    ldx #>m_nodisk
    jsr KF_puts
    jmp quit
}
have_name:
    lda #<fbuf
    sta fname_ptr
    lda #>fbuf
    sta fname_ptr+1

    lda #<m_loading
    ldx #>m_loading
    jsr KF_puts
    jsr load_source
    bcs load_failed
    jsr drive_check             // the drive may report an error even if reading "worked"
    bcc loaded
load_failed:
    lda #<m_cannot
    ldx #>m_cannot
    jsr KF_puts
    jsr drive_check
    jmp quit
loaded:
    lda #<m_comp
    ldx #>m_comp
    jsr KF_puts
    lda #1                      // build a standalone program image
    sta cmode
    jsr compile_source
    bcc compiled
    jsr show_error
    jmp quit

compiled:
    lda #<m_ok                  // size of the program file (without the two load address bytes)
    ldx #>m_ok
    jsr KF_puts
    sec
    lda cout
    sbc codebase
    sta ac
    lda cout+1
    sbc codebase+1
    sta ac+1
    jsr KF_rt_wint
    lda #<m_bytes
    ldx #>m_bytes
    jsr KF_puts

    jsr make_output_name        // "@0:" + name up to the first '.' + ",P,W"
    lda #<oname
    sta fname_ptr
    lda #>oname
    sta fname_ptr+1
    jsr save_prg
    bcs save_failed
    jsr drive_check
    bcc saved
save_failed:
    lda #<m_savefail
    ldx #>m_savefail
    jsr KF_puts
    jmp quit
saved:
    lda #<m_saved
    ldx #>m_saved
    jsr KF_puts
    ldx #0                      // the base name, as typed (PETSCII)
!:  cpx obase_len
    beq !+
    lda oname+3,x
    jsr KF_CHROUT
    inx
    bne !-
!:  lda #13
    jsr KF_CHROUT

.if (NAME_LEN == 0) {
    lda #<m_runq                // offer to run it
    ldx #>m_runq
    jsr KF_puts
ask:
    jsr KF_GETIN                   // GETIN: wait for a key
    beq ask
    cmp #'Y'
    beq run_it
    cmp #'N'
    beq quit_nl
    jmp ask
}
    jmp quit_nl
run_it:
    lda #13
    jsr KF_CHROUT
#if HIROM
    jmp run_image               // Plus/4: the program is started from its file image (below)
#endif
    lda #0                      // compile again for running in place
    sta cmode
    jsr compile_source
    bcs quit
    jsr KF_run_program
    lda #<m_done
    ldx #>m_done
    jsr KF_puts
    jmp quit
quit_nl:
    lda #13
    jsr KF_CHROUT
quit:
.if (cmdLineVars.containsKey("hold")) {
    jmp *
}
#if HIROM
    jsr rom_on_leave
#endif
    :PLAT_LEAVE()
    rts

#if HIROM
// run_image (Plus/4): run the program that was just compiled. Its file image is in the buffer behind the source text
// (codebase .. cout); this routine copies it to its load address $1001, over this compiler, and starts it exactly as BASIC
// would after RUN: the image saves the zero page, runs and returns to BASIC through the stack level of our own SYS (the
// stack is balanced here). The copy loop has to live outside the area it overwrites: it is put in the cassette buffer.
.const TRAMP = $0340
run_image:
    ldx #tr_end - tr_code - 1   // the copy loop to TRAMP
!:  lda tr_code,x
    sta TRAMP,x
    dex
    bpl !-
    lda codebase+1              // source page of the image (the buffer starts on a page boundary)
    sta tr_ld + 2
    sec                         // number of pages (rounded up) = cout - codebase, high byte, + 1
    lda cout+1
    sbc codebase+1
    clc
    adc #1
    sta tr_pages
    ldx #$27                    // restore zero page $02-$29: the image saves and restores BASIC's own copy again
!:  lda zpsave,x
    sta $02,x
    dex
    bpl !-
    jmp TRAMP

tr_code:
.pseudopc TRAMP {
    ldx tr_pages
tr_next:
    ldy #0
tr_ld:
    lda $0000,y                 // source page (patched)
tr_st:
    sta STAND_BASE,y            // destination: the load address of the image, page by page
    iny
    bne tr_ld
    inc tr_ld + 2
    inc tr_st + 2
    dex
    bne tr_next
    sta $ff3e                   // ROMs on
    cli
    jmp STAND_BASE + 12         // the start-up code of the image (the address of its BASIC SYS line)
tr_pages: .byte 0
}
tr_end:
#endif

// compile_source: compile the text in the source buffer. Carry set = error.
compile_source:
#if HIROM
    lda cmode                   // Plus/4: a standalone image is built behind the source text (RAM under the ROMs), a
    bne cs_buf                  // program that is run in place goes to the low RAM (it runs with the ROMs on)
    lda #<CODE_BASE
    sta codebase
    lda #>CODE_BASE
    sta codebase+1
    jmp cs_inplace
cs_buf:
    clc
    lda src_end
    adc #1
    lda src_end+1
    adc #1
    sta codebase+1
    lda #0
    sta codebase
    lda #<BUF_LIMIT
    sta codelimit
    lda #>BUF_LIMIT
    sta codelimit+1
    jmp cs_go
#else
    clc                         // the code goes to the page behind the source text
    lda src_end
    adc #1
    lda src_end+1
    adc #1
    sta codebase+1
    lda #0
    sta codebase
    lda cmode
    beq cs_inplace
    lda #<STK_TOP               // standalone file: nothing runs, so the code buffer may use all memory
    sta codelimit               // up to the software stack
    lda #>STK_TOP
    sta codelimit+1
    jmp cs_go
#endif
cs_inplace:                     // to run in place the code must stay below the program's data
    lda #<CODE_LIMIT
    sta codelimit
    lda #>CODE_LIMIT
    sta codelimit+1
cs_go:
    lda #<SRC_BASE
    sta src
    lda #>SRC_BASE
    sta src+1
    jsr compile
    php
    jsr pg_clear                // wipe the progress number
    plp
    rts

// compile_progress: called by the lexer for every line feed: show the number of the line being compiled at the cursor
// position (the cursor is put back, so the next number overwrites it). Keeps A, X and Y.
compile_progress:
    pha
    txa
    pha
    tya
    pha
    sec                         // remember the cursor position
    jsr KF_PLOT
    stx pg_row
    sty pg_col
    lda line
    sta ac
    lda line+1
    sta ac+1
    jsr KF_rt_wint                 // (ac is not used by the compiler)
    jsr pg_back
    pla
    tay
    pla
    tax
    pla
    rts

pg_back:                        // cursor back to the remembered position
    clc
    ldx pg_row
    ldy pg_col
    jmp KF_PLOT

pg_clear:                       // blank the progress number (6 characters) and go back
    sec
    jsr KF_PLOT
    stx pg_row
    sty pg_col
    ldx #6
!:  lda #' '
    jsr KF_CHROUT
    dex
    bne !-
    jmp pg_back

pg_row: .byte 0
pg_col: .byte 0

// show_error: print the compile error that 'compile' reported, with its source line.
show_error:
    lda #<m_err
    ldx #>m_err
    jsr KF_puts
    lda errcode
    jsr KF_print_errmsg
    lda #<m_line
    ldx #>m_line
    jsr KF_puts
    lda line
    sta ac
    lda line+1
    sta ac+1
    jsr KF_rt_wint
    jmp KF_rt_wln

// make_output_name: oname = "@0:" + the source name up to its first '.' + ",P,W";
// fname_len = its length (the name is then passed to save_prg through fname_ptr).
make_output_name:
    ldx #0
mo1:
    cpx fname_len
    beq mo2
    lda fbuf,x
    cmp #'.'
    beq mo2
    sta oname+3,x
    inx
    jmp mo1
mo2:
    stx obase_len
    ldy #0
mo3:
    lda oname_tail,y            // append ",P,W"
    sta oname+3,x
    inx
    iny
    cpy #4
    bne mo3
    txa                         // total length = "@0:" + base + ",P,W"
    clc
    adc #3
    sta fname_len
    rts

.encoding "petscii_upper"
oname_tail: .text ",P,W"
oname:      .text "@0:"
            .fill 24, 0
.encoding "ascii"
obase_len:  .byte 0

preset:                         // the preset file name of a test build (PETSCII)
.encoding "petscii_upper"
    .text presetname
.encoding "ascii"

#if C128
m_banner:   .text "64PASCAL - PASCAL COMPILER FOR C128"
#elif PLUS4
m_banner:   .text "64PASCAL - PASCAL COMPILER FOR PLUS/4"
#else
m_banner:   .text "64PASCAL - PASCAL COMPILER FOR C64"
#endif
            .byte 13,13,0
m_prompt:   .text "SOURCE FILE (RETURN = LIST):"
            .byte 13,0
m_nofiles:  .text "NO .PAS FILES ON THE DISK"
            .byte 13,0
m_nodisk:   .text "CANNOT READ THE DISK"
            .byte 13,0
m_loading:  .byte 13
            .text "LOADING..."
            .byte 13,0
m_cannot:   .text "CANNOT READ THE SOURCE"
            .byte 13,0
m_comp:     .text "COMPILING..."
            .byte 13,0
m_err:      .text "ERROR: "
            .byte 0
m_line:     .text " IN LINE "
            .byte 0
m_ok:       .text "OK, "
            .byte 0
m_bytes:    .text " BYTES"
            .byte 13,0
m_savefail: .text "COULD NOT SAVE THE PROGRAM"
            .byte 13,0
m_saved:    .text "SAVED AS "
            .byte 0
m_runq:     .text "RUN NOW (Y/N)?"
            .byte 0
m_done:     .text "[DONE]"
            .byte 13,0

.import source "compiler.asm"
.import source "messages.asm"
.import source "platcode.asm"
.import source "fileio.asm"
#if HIROM
.import source "kfstubs.asm"
#endif
.import source "runtime.asm"       // last: its image (rt_image) is dead once install_runtime has copied it, see below

prg_end:
#if HIROM
// (no assert: 64pascal does not run programs in place, the code area is not used)
#else
.label SRC_BASE = (RECLAIM + $ff) & $ff00     // the source buffer starts at the next page after the program, which
                                               // means INSIDE the images at the end of the program file
#endif
.assert "the source buffer must hold at least 2 KB", SRC_LIMIT - SRC_BASE >= $800, true
