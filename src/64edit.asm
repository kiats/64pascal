// This file is in the public domain: use it, change it, share it, sell it - do whatever you like with it.
// No permission, credit or payment needed. It comes as it is, with no warranty. Enjoy!
// Note: this has only been tested in the VICE emulator, never on real hardware.
// 64edit - the editor alone (no compiler, no runtime), for big source texts.
// Same program as 64ide.asm, built without the compiler: the text may use all RAM up to $CFFF.
//   java -jar KickAss.jar src/64edit.asm
#define IDE
#define EDONLY
.import source "64ide.asm"
