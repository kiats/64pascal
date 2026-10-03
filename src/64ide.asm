// This file is in the public domain: use it, change it, share it, sell it - do whatever you like with it.
// No permission, credit or payment needed. It comes as it is, with no warranty. Enjoy!
// Note: this has only been tested in the VICE emulator, never on real hardware.
// =====================================================================================
// 64ide.asm - the IDE: editor + compiler in one program
// =====================================================================================
//
// A Turbo Pascal style environment: a full-screen editor for the source text, with the compiler
// and the runtime in the same program so that a program can be compiled and run from the editor.
//
// Keys (PETSCII codes from the C64 keyboard):
//   cursor keys, HOME (line start), SHIFT+HOME (text start), CTRL+E (line end), F7 / F8 (page down / up)
//   DEL (delete before the cursor), SHIFT+DEL (delete under the cursor), RETURN (new line, keeps indent)
//   F2 save, F3 open (an empty name lists the .pas files), F5 autosave + compile + run, F6 run without autosave,
//   F4 autosave + compile to disk (a standalone program named like the source without .pas)
//   (on the Plus/4 the function keys type text: use CTRL+S / L / R / C for save / load / run / compile to disk, or ESC then
//    s / l / r / x / c / u / d / e / t / q)
//   (the editor-only build 64edit, -define EDONLY, has no compiler: F5 / F6 do nothing there),
//   RUN/STOP quit (twice when there are unsaved changes)
//
// Build:  java -jar KickAss.jar src/64ide.asm -define IDE            (C64, also C128 in C64 mode)
//         java -jar KickAss.jar src/64ide.asm -define IDE -define EDONLY     = 64edit: the editor alone, for big texts
// Test:   ... :keys=path/to/keys.bin     feeds the keys from a file before the real keyboard is read

#if PLUS4
#if !EDONLY
#define HIROM                   // the Plus/4 IDE runs with the ROMs off: text and compiler tables are in the RAM under them
#endif
#endif

.encoding "ascii"
.var keysfile = cmdLineVars.containsKey("keys") ? cmdLineVars.get("keys") : ""
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
    jsr rom_off_enter           // from here on the KERNAL is only reached through the KF_ stubs (kfstubs.asm); the images
#endif                          // at the end of the program file may lie under the ROMs: switch them off first
#if !EDONLY
    jsr install_runtime
#endif
    jsr ide_colors
    jsr ed_new
    jsr ide_main
#if HIROM
    jsr rom_on_leave
#endif
    :PLAT_LEAVE()
    rts

// ide_colors: blue background, white text on the whole screen.
ide_colors:
#if PLUS4
    lda #$6e                    // TED: border (luminance 6, hue 14), background blue
    sta $ff19
    lda #$26
    sta $ff15
    lda #$71                    // white (luminance 7, hue 1)
#else
    lda #14                     // border light blue, background blue (the usual C64 colours)
    sta $d020
    lda #6
    sta $d021
    lda #1                      // white
#endif
    sta ic_color
    lda #<COLOR_RAM
    sta tp
    lda #>COLOR_RAM
    sta tp+1
    ldx #4                      // 4 pages cover the 1000 colour cells
    ldy #0
ic1:
    lda ic_color
    sta (tp),y
    iny
    bne ic1
    inc tp+1
    dex
    bne ic1
    rts
ic_color: .byte 0

// ide_main: the main loop: draw, read a key, act.
ide_main:
im_loop:
    jsr ed_redraw
    jsr getkey
    pha
    lda #0
    sta msgptr+1                // a message is shown until the next key
    pla
    jsr ed_key
    lda quit
    beq im_loop
    rts

// getkey: wait for a key; keys of a test script come first.
getkey:
    ldx ks_idx
    cpx #KS_LEN
    bcs gk_real
    lda keyscript,x
    inc ks_idx
    rts
gk_real:
    jsr KF_GETIN
    beq gk_real
    rts

// ed_key: A = key. Executes it.
ed_key:
    ldx esc_pending             // ESC prefix: the machines whose function keys type text (Plus/4) use ESC + letter
    beq ek_noesc
    ldx #0
    stx esc_pending
    jsr esc_translate           // A = the equivalent of the function key, or 0 for an unknown letter
    bne ek_normal
    rts
ek_noesc:
#if PLUS4
    jsr ctrl_translate          // CTRL+S/L/R/C -> the F2/F3/F5/F4 command codes
#endif
    cmp #$1b                    // ESC
    bne ek_normal
    lda #1
    sta esc_pending
    SETMSG(m_esc)
    rts
ek_normal:
    cmp #$03                    // any key but RUN/STOP cancels a pending quit
    beq !+
    ldx #0
    stx quit_armed
!:  cmp #$11                    // cursor down
    bne !+
    jmp cur_down
!:  cmp #$91                    // cursor up
    bne !+
    jmp cur_up
!:  cmp #$1d                    // cursor right
    bne !+
    jmp move_right
!:  cmp #$9d                    // cursor left
    bne !+
    jmp move_left
!:  cmp #$13                    // HOME
    bne !+
    jmp cur_home
!:  cmp #$93                    // SHIFT+HOME (CLR)
    bne !+
    jmp cur_top
!:  cmp #$05                    // CTRL+E
    bne !+
    jmp cur_end
!:  cmp #$14                    // DEL
    bne !+
    jmp ed_backspace
!:  cmp #$94                    // SHIFT+DEL (INST)
    bne !+
    jmp ed_delete
!:  cmp #$0d                    // RETURN
    bne !+
    jmp ed_return
!:  cmp #$09                    // TAB (CTRL+I): two blanks
    bne !+
    lda #' '
    jsr ed_insert
    lda #' '
    jmp ed_insert
!:  cmp #$88                    // F7
    bne !+
    jmp page_down
!:  cmp #$8c                    // F8
    bne !+
    jmp page_up
!:  cmp #$89                    // F2: save
    bne !+
    jmp save_file
!:  cmp #$86                    // F3: load
    bne !+
    jmp load_file
!:  cmp #$87                    // F5: autosave, compile and run
    bne !+
    lda #1
    jmp run_cmd
!:  cmp #$8a                    // F4: autosave, compile and write the program to disk
    bne !+
    lda #3
    jmp run_cmd
!:  cmp #$8b                    // F6: compile and run without the autosave
    bne !+
    lda #0
    jmp run_cmd
!:  cmp #$03                    // RUN/STOP: quit (twice if there are unsaved changes)
    bne !+
    lda modified
    beq ek_quit
    lda quit_armed
    bne ek_quit
    lda #1
    sta quit_armed
    SETMSG(m_unsaved)
    rts
ek_quit:
    lda #1
    sta quit
    rts
!:  cmp #$20                    // printable characters
    bcc ek_ignore
    cmp #$7f
    bcc ek_char
    cmp #$c1                    // shifted letters $C1-$DA
    bcc ek_ignore
    cmp #$db
    bcs ek_ignore
ek_char:
    jsr p2a                     // PETSCII -> ASCII (routine of the runtime)
    jmp ed_insert
ek_ignore:
    rts

run_cmd:                        // A = 1: autosave first
#if EDONLY
    SETMSG(m_nocomp)
    rts
m_nocomp: .text "No compiler in 64edit (use 64ide)"
          .byte 0
#else
    jmp run_text
#endif

// esc_translate: A = the key pressed after ESC (PETSCII). Returns the key code of the equivalent command in A
// (function key / control code), or 0 if the letter means nothing.
esc_translate:
    jsr p2a                     // lower case ASCII letter
    ldx #0
et_find:
    cmp esc_keys,x
    beq et_hit
    inx
    inx
    ldy esc_keys,x
    bne et_find
    lda #0
    rts
et_hit:
    lda esc_keys+1,x
    rts

esc_keys:                       // letter after ESC, key code of the command
    .byte 's', $89              // save           (F2)
    .byte 'l', $86              // load           (F3)
    .byte 'r', $87              // run + autosave (F5)
    .byte 'x', $8b              // run without autosave (F6)
    .byte 'c', $8a              // compile to disk (F4)
    .byte 'u', $8c              // page up        (F8)
    .byte 'd', $88              // page down      (F7)
    .byte 'e', $05              // end of line    (CTRL+E)
    .byte 't', $93              // top of the text (SHIFT+HOME)
    .byte 'q', $03              // quit           (RUN/STOP)
    .byte 0, 0

#if PLUS4
// ctrl_translate: A = key. On the Plus/4 (function keys type text) CTRL + letter commands: CTRL+S save, CTRL+L load,
// CTRL+R run, CTRL+C compile to disk. CTRL+S and CTRL+C give the same codes as HOME and RUN/STOP ($13, $03), so the
// CTRL flag of the KERNAL ($0543 bit 2, only CTRL held) decides. Returns the command code in A, or A unchanged.
ctrl_translate:
    ldx $0543                   // keyboard shift flags: 1 = SHIFT, 2 = C=, 4 = CTRL
    cpx #4                      // CTRL alone
    bne ct_done
    ldx #0
ct_find:
    cmp ctrl_keys,x
    beq ct_hit
    inx
    inx
    ldy ctrl_keys,x
    bne ct_find
ct_done:
    rts
ct_hit:
    lda ctrl_keys+1,x
    rts

ctrl_keys:                      // code of CTRL + letter, key code of the command
    .byte $13, $89              // CTRL+S save           (F2)
    .byte $0c, $86              // CTRL+L load           (F3)
    .byte $12, $87              // CTRL+R run + autosave (F5)
    .byte $03, $8a              // CTRL+C compile to disk (F4)
    .byte 0, 0
#endif

esc_pending: .byte 0
m_esc:     .text "ESC+ S save L load R run Q quit E end"
           .byte 0
quit:      .byte 0
quit_armed: .byte 0
ks_idx:    .byte 0
m_unsaved: .text "Unsaved changes: RUN/STOP again to quit"
           .byte 0

#if !HIROM
.import source "editor.asm"
.import source "ideops.asm"
#endif
#if EDONLY
.import source "conio.asm"          // putc / puts / p2a without the runtime
#else
.import source "compiler.asm"
.import source "messages.asm"
.import source "platcode.asm"
#endif
.import source "fileio.asm"
#if HIROM
.import source "kfstubs.asm"
// Data that the KERNAL (or puts, which calls it) reads while the ROMs are on must be in the low RAM, but the editor and the IDE
// commands are up in the RAM under the ROMs: the file names and the text for puts are defined here instead of in editor.asm /
// ideops.asm.
namelen:     .byte 0                    // current file name (PETSCII)
namebuf:     .fill 17, 0
fnbuf:       .fill 28, 0                // "@0:" + name + ",S,W" for save / autosave
prg_name:    .byte $40, $30, $3a        // "@0:" (replace an existing file) + name + ",P,W" for compile to disk
             .fill 24, 0
m_anykey:    .text "-- press a key --"
             .byte 0
#endif

keyscript:
.if (keysfile != "") {
    .import binary keysfile
}
ks_end:
.label KS_LEN = ks_end - keyscript

#if !EDONLY
.import source "runtime.asm"       // last: its image (rt_image) is dead once install_runtime has copied it
#endif
prg_end:
#if HIROM
.assert "the program must end below the code buffer", RECLAIM <= CODE_BASE, true
.assert "the runtime image must end below the editor", prg_end <= $8000, true
// Plus/4: the editor and the IDE commands (about 5 KB) are not in the low RAM, where the room is needed for the compiler and
// for programs that are run in place: they are assembled for $8000, in the RAM under the ROMs, which the IDE can execute
// because it runs with the ROMs off. The program file simply continues up there (the loader stores the bytes in the RAM under
// the ROMs; the gap between prg_end and $8000 is filled with zeros). The text buffer starts behind them.
* = $8000
.import source "editor.asm"
.import source "ideops.asm"
ed_end:
.label SRC_BASE = (ed_end + $ff) & $ff00
#elif EDONLY
.label SRC_BASE = (prg_end + $ff) & $ff00      // the text buffer starts at the next page after the program
#else
.label SRC_BASE = (RECLAIM + $ff) & $ff00      // ... which means INSIDE the images at the end of the program file
#endif
.assert "the text buffer must hold at least 2 KB", SRC_LIMIT - SRC_BASE >= $800, true
