// This file is in the public domain: use it, change it, share it, sell it - do whatever you like with it.
// No permission, credit or payment needed. It comes as it is, with no warranty. Enjoy!
// Note: this has only been tested in the VICE emulator, never on real hardware.
// =====================================================================================
// conio.asm - small console routines for programs that do not contain the runtime
// =====================================================================================
//
// The editor-only program (64edit) has no runtime library, but its file dialog still needs to print text
// and to convert characters. These are the same routines as in the runtime (runtime.asm / rt_input.asm).

putc:                           // print the ASCII character in A (converted to PETSCII)
    cmp #$41
    bcc pc_out
    cmp #$5b
    bcc pc_up
    cmp #$61
    bcc pc_out
    cmp #$7b
    bcs pc_out
    sec
    sbc #$20                    // a-z -> $41-$5A (lower case in the mixed character set)
    jmp pc_out
pc_up:
    ora #$80                    // A-Z -> $C1-$DA
pc_out:
    jmp K_CHROUT

puts:                           // print the 0-terminated ASCII string at X:A
    sta tmp
    stx tmp+1
    ldy #0
pu_1:
    lda (tmp),y
    beq pu_done
    jsr putc
    iny
    bne pu_1
pu_done:
    rts

p2a:                            // PETSCII character in A -> ASCII (unshifted letters are lower case)
    cmp #$c1
    bcc pa_1
    cmp #$db
    bcs pa_1
    and #$7f
    rts
pa_1:
    cmp #$41
    bcc pa_2
    cmp #$5b
    bcs pa_2
    ora #$20
pa_2:
    rts

zpsave:  .fill 40, 0            // saved copy of zero page $02-$29 (platform.asm; elsewhere defined in platcode.asm)
