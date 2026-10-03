// This file is in the public domain: use it, change it, share it, sell it - do whatever you like with it.
// No permission, credit or payment needed. It comes as it is, with no warranty. Enjoy!
// Note: this has only been tested in the VICE emulator, never on real hardware.
// =====================================================================================
// kernal.asm - addresses of the KERNAL jump table (the same on the C64, C128 and Plus/4)
// =====================================================================================
// The KERNAL ROM must be visible when these are called (the programs keep BASIC off, KERNAL on).

.const K_SETLFS = $ffba         // set logical file, device, secondary address
.const K_SETNAM = $ffbd         // set file name
.const K_OPEN   = $ffc0
.const K_CLOSE  = $ffc3
.const K_CHKIN  = $ffc6         // select an input channel
.const K_CHKOUT = $ffc9         // select an output channel
.const K_CLRCHN = $ffcc         // back to keyboard / screen
.const K_CHRIN  = $ffcf         // read a character (the keyboard: a whole line via the screen editor)
.const K_CHROUT = $ffd2         // write a character
.const K_READST = $ffb7         // I/O status
.const K_GETIN  = $ffe4         // get a key without waiting (0 = none)
.const K_PLOT   = $fff0         // read / set the cursor position (X = row, Y = column)
.const K_SCREEN = $ffed         // screen size: X = columns, Y = rows
.const K_RDTIM  = $ffde         // jiffy clock: A = low byte, X = middle, Y = high

// ---- KF_*: the KERNAL as seen by the programs that contain the compiler (fileio.asm, ideops.asm, 64ide.asm, 64pascal.asm)
// Normally the same as K_*. On the Plus/4 builds with the ROMs switched off (HIROM, see kfstubs.asm) every KF_ name is a
// stub in RAM that switches the KERNAL on for one call. (The runtime keeps using K_*: it runs with the ROMs on.)
#if !HIROM
.const KF_SETLFS = K_SETLFS
.const KF_SETNAM = K_SETNAM
.const KF_OPEN   = K_OPEN
.const KF_CLOSE  = K_CLOSE
.const KF_CHKIN  = K_CHKIN
.const KF_CHKOUT = K_CHKOUT
.const KF_CLRCHN = K_CLRCHN
.const KF_CHRIN  = K_CHRIN
.const KF_CHROUT = K_CHROUT
.const KF_READST = K_READST
.const KF_GETIN  = K_GETIN
.const KF_PLOT   = K_PLOT
// routines of the runtime / compiler that print (they call the KERNAL): the same routine, or a stub
.label KF_puts = puts
#if !EDONLY
.label KF_rt_wint = rt_wint
.label KF_rt_wln = rt_wln
.label KF_print_errmsg = print_errmsg
.label KF_run_program = run_program
#endif
#endif
