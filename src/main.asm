// This file is in the public domain: use it, change it, share it, sell it - do whatever you like with it.
// No permission, credit or payment needed. It comes as it is, with no warranty. Enjoy!
// Note: this has only been tested in the VICE emulator, never on real hardware.
// Development harness: copies the runtime to its fixed address, compiles the Pascal source that
// is embedded in this file, then runs the result in place (or, with -define STANDALONE, writes
// it to drive 8 as a standalone program named OUT).
//   C64 / C128(C64 mode):  java -jar KickAss.jar src/main.asm
//   C128 (128 mode):       java -jar KickAss.jar src/main.asm -define C128
//   Plus/4:                java -jar KickAss.jar src/main.asm -define PLUS4
//   other test source:     ... :src=path\to\file.pas
//   standalone file test:  ... -define STANDALONE   (writes the compiled program to drive 8 as OUT)
// The real programs are 64pascal.asm (simple compiler) and, later, the IDE.

.encoding "ascii"
.import source "memmap.asm"
.import source "zp.asm"
.import source "platform.asm"   // BASIC line "SYS start", PLAT_ENTER / PLAT_LEAVE, run_program

start:
#if PLUS4
.assert "BASIC SYS address must match start", start == 4109, true
#elif C128
.assert "BASIC SYS address must match start", start == 7181, true
#endif
    :PLAT_ENTER()
    jsr install_runtime
    lda #<m_comp
    ldx #>m_comp
    jsr puts
    lda #<test_src
    sta src
    lda #>test_src
    sta src+1
#if STANDALONE
    lda #1                      // build a standalone file image: nothing runs, so the code buffer may reach the stack
    sta cmode
    lda #<STK_TOP
    sta codelimit
    lda #>STK_TOP
    sta codelimit+1
#endif
    jsr compile
    bcc compiled
    lda #<m_err                 // compile error: code, text and line
    ldx #>m_err
    jsr puts
    lda errcode
    sta ac
    lda #0
    sta ac+1
    jsr rt_wint
    lda #' '
    jsr putc
    lda errcode
    jsr print_errmsg
    lda #<m_line
    ldx #>m_line
    jsr puts
    lda line
    sta ac
    lda line+1
    sta ac+1
    jsr rt_wint
    jsr rt_wln
    jmp finish
compiled:
    lda #<m_ok
    ldx #>m_ok
    jsr puts
    sec
    lda cout
    sbc #<CODE_BASE
    sta ac
    lda cout+1
    sbc #>CODE_BASE
    sta ac+1
    jsr rt_wint
    lda #<m_bytes
    ldx #>m_bytes
    jsr puts
#if STANDALONE
    lda #<fn_out                // write the standalone file to disk instead of running it
    sta fname_ptr
    lda #>fn_out
    sta fname_ptr+1
    lda #10
    sta fname_len
    jsr save_prg
    bcc saved
    pha
    lda #<m_saveerr
    ldx #>m_saveerr
    jsr puts
    pla
    sta ac
    lda #0
    sta ac+1
    jsr rt_wint
    jsr rt_wln
    jmp finish
saved:
    lda #<m_saved
    ldx #>m_saved
    jsr puts
#else
    jsr run_program
    lda #<m_done
    ldx #>m_done
    jsr puts
#endif
finish:
.if (cmdLineVars.containsKey("hold")) {
    jmp *                       // debug build: stay here so the screen can be inspected
}
    :PLAT_LEAVE()
    rts

m_comp:  .text "COMPILING..."
         .byte 13,0
m_err:   .text "ERROR "
         .byte 0
m_line:  .text " AT LINE "
         .byte 0
m_ok:    .text "OK, CODE "
         .byte 0
m_bytes: .text " BYTES"
         .byte 13,0
m_done:  .text "[DONE]"
         .byte 13,0
m_saved: .text "SAVED OUT"
         .byte 13,0
m_saveerr: .text "SAVE ERROR "
         .byte 0
.encoding "petscii_upper"
fn_out:  .text "@0:OUT,P,W"      // file name for the disk (PETSCII)
.encoding "ascii"

compile_progress:               // the harness shows no progress
    rts
.import source "compiler.asm"
.import source "messages.asm"
.import source "platcode.asm"
#if STANDALONE
.import source "fileio.asm"
#endif

test_src:
.var srcfile = cmdLineVars.containsKey("src") ? cmdLineVars.get("src") : "test.pas"
    .import binary srcfile
    .byte 0
.import source "runtime.asm"        // last: its image (rt_image) is dead once install_runtime has copied it
prg_end:
.label SRC_BASE = prg_end            // (only used by fileio.asm for the editor's save routine, which the harness does not call)

// everything except the images at the end must end below the generated code (the images may be overwritten by it)
#if PLUS4
.assert "program must end below the type descriptor table", RECLAIM <= DTAB_BASE, true
#else
.assert "program must end below generated code", RECLAIM <= CODE_BASE, true
#endif
