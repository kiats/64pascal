// This file is in the public domain: use it, change it, share it, sell it - do whatever you like with it.
// No permission, credit or payment needed. It comes as it is, with no warranty. Enjoy!
// Note: this has only been tested in the VICE emulator, never on real hardware.
// =====================================================================================
// fileio.asm - disk files through the KERNAL
// =====================================================================================
//
// The KERNAL routines are the same on the C64, C128 and Plus/4 ($FFxx jump table). The ROM must be
// visible while they are called (the harness keeps BASIC off but the KERNAL on).
//
// save_prg writes the file image built by the standalone compiler: the two byte load address
// STAND_BASE followed by the bytes from CODE_BASE up to the output pointer 'cout'. (The KERNAL
// SAVE call would write the physical buffer address as load address, which is why the file is
// written byte by byte with OPEN / CHROUT.)


// C128 only: SETBNK selects RAM bank 0 for file names and data. Without it the KERNAL reads the
// name from the system bank, where $4000-$7FFF is ROM, so names stored there would be garbage.
.macro SETBANK() {
#if C128
    lda #0
    ldx #0
    jsr $ff68
#endif
}

.const FILE_NO  = 2             // logical file number used for the output
.const DEVICE   = 8             // disk drive

#if !EDONLY                     // (the editor alone has no compiler, hence no program files to write)
// save_prg: write the standalone file; fname_ptr / fname_len = file name in PETSCII
// (for example "@0:OUT,P,W": "@0:" replaces an existing file). Returns carry clear = ok,
// carry set = error (the KERNAL's error status is left in A).
save_prg:
    :SETBANK()
    lda #FILE_NO
    ldx #DEVICE
    ldy #FILE_NO                // secondary address (data channel)
    jsr KF_SETLFS
    lda fname_len
    ldx fname_ptr
    ldy fname_ptr+1
    jsr KF_SETNAM
    jsr KF_OPEN
    bcs sp_fail
    ldx #FILE_NO
    jsr KF_CHKOUT
    bcs sp_fail
    lda #<STAND_BASE            // load address of the file
    jsr KF_CHROUT
    lda #>STAND_BASE
    jsr KF_CHROUT
    lda codebase                // source = the code buffer
    sta tmpc1
    lda codebase+1
    sta tmpc1+1
sp_loop:
    lda tmpc1                   // done when tmpc1 reaches the output pointer
    cmp cout
    bne sp_byte
    lda tmpc1+1
    cmp cout+1
    beq sv_done
sp_byte:
    ldy #0
    lda (tmpc1),y
    jsr KF_CHROUT
    inc tmpc1
    bne sp_loop
    inc tmpc1+1
    jmp sp_loop
sv_done:
    jsr KF_READST                // any error while writing?
    pha
    jsr KF_CLRCHN
    lda #FILE_NO
    jsr KF_CLOSE
    pla
    bne sp_err
    clc
    rts
sp_fail:                        // OPEN / CHKOUT failed: A = KERNAL error code
    pha
    jsr KF_CLRCHN
    lda #FILE_NO
    jsr KF_CLOSE
    pla
sp_err:
    sec
    rts

#endif

fname_ptr: .word 0
fname_len: .byte 0

// ---- reading ---------------------------------------------------------------------------------------
.const SRC_FILE = 3             // logical file number used for the source

// load_source: read the file named by fname_ptr / fname_len (PETSCII) from drive 8 into the source
// buffer at SRC_BASE and end it with a zero byte. Line ends are normalised to LF (a CR, or a CR LF
// pair, becomes one LF). Carry clear = ok, carry set = failed: A = 1 source too long, 0 = the
// drive/KERNAL reported a problem (use drive_check for the drive's message).
load_source:
    :SETBANK()
    lda #SRC_FILE
    ldx #DEVICE
    ldy #SRC_FILE               // secondary address
    jsr KF_SETLFS
    lda fname_len
    ldx fname_ptr
    ldy fname_ptr+1
    jsr KF_SETNAM
    jsr KF_OPEN
    bcc !+
    jmp ls_fail
!:  ldx #SRC_FILE
    jsr KF_CHKIN
    bcc !+
    jmp ls_fail
!:
    lda #<SRC_BASE
    sta tmpc1
    lda #>SRC_BASE
    sta tmpc1+1
    lda #0
    sta ls_lastcr
ls_loop:
    jsr KF_CHRIN
    sta ls_byte
    jsr KF_READST
    sta ls_status
    and #$bf                    // any status bit except end-of-file: the read failed
    beq ls_ok
    jmp ls_fail
ls_ok:
    lda ls_byte
ls_store:
    cmp #13                     // CR becomes LF; the LF of a CR LF pair is dropped
    bne ls_notcr
    lda #1
    sta ls_lastcr
    lda #10
    jmp ls_put
ls_notcr:
    ldx ls_lastcr
    beq ls_other
    ldx #0
    stx ls_lastcr
    cmp #10
    beq ls_next                 // second half of CR LF: skip
ls_other:
    ldx #0
    stx ls_lastcr
ls_put:
    ldy #0
    sta (tmpc1),y
    ldx #1
    stx ls_any                  // the buffer has been written to
    inc tmpc1
    bne ls_nc
    inc tmpc1+1
ls_nc:
    lda tmpc1+1                 // buffer full?
    cmp #>SRC_LIMIT
    bcc ls_next
    jsr ls_close
    lda #1
    sec
    rts
ls_next:
    lda ls_status
    and #$40                    // end of file after this byte?
    beq ls_loop
    lda tmpc1                   // remember where the text ends (the editor needs it)
    sta src_end
    lda tmpc1+1
    sta src_end+1
    lda #0                      // terminate the text
    tay
    sta (tmpc1),y
    jsr ls_close
    clc
    rts
ls_fail:
    jsr ls_close
    lda #0
    sec
    rts
ls_close:
    jsr KF_CLRCHN
    lda #SRC_FILE
    jmp KF_CLOSE

ls_lastcr:  .byte 0
src_end:    .word 0             // address of the terminating zero of the text loaded by load_source
ls_byte:    .byte 0
ls_any:     .byte 0             // 1 once load_source has stored a byte in the buffer
ls_status:  .byte 0

// drive_check: read the drive's error channel. Prints the message (for example
// "62,FILE NOT FOUND,00,00") and returns carry set if the error number is not 00, carry
// clear if the last operation succeeded.
drive_check:
    :SETBANK()
    lda #15
    ldx #DEVICE
    ldy #15
    jsr KF_SETLFS
    lda #0
    jsr KF_SETNAM
    jsr KF_OPEN
    bcs dc_fail
    ldx #15
    jsr KF_CHKIN
    bcs dc_fail
    ldx #0
dc_read:
    jsr KF_CHRIN
    cmp #13
    beq dc_end
    cpx #40
    bcs dc_read                 // ignore anything beyond the buffer
    sta dc_buf,x
    inx
    jmp dc_read
dc_end:
    stx dc_len
    jsr KF_CLRCHN
    lda #15
    jsr KF_CLOSE
    lda dc_buf                  // "00" means no error
    cmp #'0'
    bne dc_err
    lda dc_buf+1
    cmp #'0'
    bne dc_err
    clc
    rts
dc_err:
    lda dc_quiet                // quiet: the caller shows the message from dc_buf / dc_len itself
    bne dc_qdone
    ldx #0                      // show the drive's message (PETSCII, printed as it is)
dc_print:
    cpx dc_len
    beq dc_nl
    lda dc_buf,x
    jsr KF_CHROUT
    inx
    bne dc_print
dc_nl:
    lda #13
    jsr KF_CHROUT
dc_qdone:
    sec
    rts
dc_fail:
    jsr KF_CLRCHN
    lda #15
    jsr KF_CLOSE
    sec                         // no drive answered
    rts

dc_buf: .fill 41, 0
dc_len: .byte 0
dc_quiet: .byte 0               // 1 = drive_check does not print the message

// read_line: read one line from the keyboard (the user types it on its own line and presses
// RETURN) into fbuf, at most 16 characters; fname_len = its length without trailing blanks.
read_line:
    ldx #0
rl_loop:
    jsr KF_CHRIN                 // the screen editor returns the line when RETURN is pressed
    cmp #13
    beq rl_done
    cpx #16
    bcs rl_loop
    sta fbuf,x
    inx
    jmp rl_loop
rl_done:
    cpx #0                      // drop trailing blanks
    beq rl_end
    lda fbuf-1,x
    cmp #' '
    bne rl_end
    dex
    jmp rl_done
rl_end:
    stx fname_len
    rts

fbuf: .fill 17, 0

// ---- directory listing -------------------------------------------------------------------------------
// list_pas: print the names of the files on drive 8 that end in ".PAS" (one per line, in PETSCII as
// the drive stores them). Returns A = number of names printed (0 = none); carry set if the directory
// could not be read at all. A directory is read like a BASIC program: "$" is opened and each line is
//     link (2 bytes), block count (2 bytes), text ending in 0, e.g.   <blocks> "NAME" PRG
// and the list ends with a link of 0. Only the text between the first pair of quotes is a name.
list_pas:
    :SETBANK()
    lda #0
    sta lp_count
    lda #1                      // logical file 1, device 8, secondary address 0 (directory)
    ldx #DEVICE
    ldy #0
    jsr KF_SETLFS
    lda #1                      // file name "$"
    ldx #<lp_dollar
    ldy #>lp_dollar
    jsr KF_SETNAM
    jsr KF_OPEN
    bcs lp_failj
    ldx #1
    jsr KF_CHKIN
    bcs lp_failj
    jsr KF_CHRIN                 // skip the two byte load address
    jsr KF_CHRIN
    jmp lp_line
lp_failj:
    jmp lp_fail
lp_endj:
    jmp lp_end
lp_line:
    jsr KF_CHRIN                 // link to the next line: 0 = end of the directory
    sta lp_tmp
    jsr KF_CHRIN
    ora lp_tmp
    beq lp_endj
    jsr KF_READST
    bne lp_endj
    jsr KF_CHRIN                 // block count (ignored)
    jsr KF_CHRIN
    ldx #0                      // the text of the line
lp_text:
    jsr KF_CHRIN
    beq lp_got
    cpx #48
    bcs lp_text
    sta dirbuf,x
    inx
    jmp lp_text
lp_got:
    stx dirlen
    ldx #0                      // find the opening quote
lp_q1:
    cpx dirlen
    beq lp_line                 // no quote: header or "blocks free" line
    lda dirbuf,x
    cmp #$22
    beq lp_q2
    inx
    jmp lp_q1
lp_q2:
    inx
    stx lp_start                // the name starts after the quote
lp_q3:
    cpx dirlen
    beq lp_line
    lda dirbuf,x
    cmp #$22
    beq lp_name
    inx
    jmp lp_q3
lp_name:
    txa                         // length of the name
    sec
    sbc lp_start
    sta lp_len
    cmp #5                      // at least one character plus ".PAS"
    bcc lp_nomatch
    clc                         // does it end in .PAS ?  (letters compare with the shift bit ignored)
    lda lp_start
    adc lp_len
    tay                         // y = index after the last character
    dey
    lda dirbuf,y
    and #$7f
    cmp #'S'
    bne lp_nomatch
    dey
    lda dirbuf,y
    and #$7f
    cmp #'A'
    bne lp_nomatch
    dey
    lda dirbuf,y
    and #$7f
    cmp #'P'
    bne lp_nomatch
    dey
    lda dirbuf,y
    cmp #'.'
    bne lp_nomatch
    jmp lp_match
lp_nomatch:
    jmp lp_line
lp_match:
    ldy lp_start                // it does: print the name followed by a new line
    ldx lp_len
lp_print:
    lda dirbuf,y
    jsr KF_CHROUT
    iny
    dex
    bne lp_print
    lda #13
    jsr KF_CHROUT
    inc lp_count
    jmp lp_line
lp_end:
    jsr KF_CLRCHN
    lda #1
    jsr KF_CLOSE
    lda lp_count
    clc
    rts
lp_fail:
    jsr KF_CLRCHN
    lda #1
    jsr KF_CLOSE
    sec
    rts

lp_dollar: .byte '$'
lp_count:  .byte 0
lp_tmp:    .byte 0
lp_start:  .byte 0
lp_len:    .byte 0
dirlen:    .byte 0
dirbuf:    .fill 49, 0

// ---- saving the editor text ------------------------------------------------------------------------------------
// save_text: write the text of the editor (before the gap, then after it) to the file fname_ptr / fname_len
// (PETSCII, for example "@0:NAME,S,W"). Carry clear = ok, set = error. The cursor and gap are not changed.
save_text:
    :SETBANK()
    lda #FILE_NO
    ldx #DEVICE
    ldy #FILE_NO
    jsr KF_SETLFS
    lda fname_len
    ldx fname_ptr
    ldy fname_ptr+1
    jsr KF_SETNAM
    jsr KF_OPEN
    bcs stx_fail
    ldx #FILE_NO
    jsr KF_CHKOUT
    bcs stx_fail
    lda #<SRC_BASE              // first part: from the start of the text to the cursor
    sta tmpc1
    lda #>SRC_BASE
    sta tmpc1+1
stx_p1:
    lda tmpc1
    cmp gs
    bne stx_b1
    lda tmpc1+1
    cmp gs+1
    beq stx_part2
stx_b1:
    ldy #0
    lda (tmpc1),y
    jsr KF_CHROUT
    inc tmpc1
    bne stx_p1
    inc tmpc1+1
    jmp stx_p1
stx_part2:
    lda ge                      // second part: from the end of the gap to the end of the buffer
    sta tmpc1
    lda ge+1
    sta tmpc1+1
stx_p2:
    lda tmpc1
    cmp #<SRC_LIMIT
    bne stx_b2
    lda tmpc1+1
    cmp #>SRC_LIMIT
    beq stx_end
stx_b2:
    ldy #0
    lda (tmpc1),y
    jsr KF_CHROUT
    inc tmpc1
    bne stx_p2
    inc tmpc1+1
    jmp stx_p2
stx_end:
    jsr KF_READST
    pha
    jsr KF_CLRCHN
    lda #FILE_NO
    jsr KF_CLOSE
    pla
    bne stx_err
    clc
    rts
stx_fail:
    pha
    jsr KF_CLRCHN
    lda #FILE_NO
    jsr KF_CLOSE
    pla
stx_err:
    sec
    rts
