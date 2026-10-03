// This file is in the public domain: use it, change it, share it, sell it - do whatever you like with it.
// No permission, credit or payment needed. It comes as it is, with no warranty. Enjoy!
// Note: this has only been tested in the VICE emulator, never on real hardware.
// Memory map. Selected at build time:
//   (default)      Commodore 64 - also used for the C128 running in C64 mode
//   -define C128   Commodore 128 native (128) mode
//   -define PLUS4  Commodore Plus/4
// All maps provide the same set of constants, so the rest of the source is identical.
#if PLUS4
// Plus/4: only about 28 KB of RAM ($1001-$7FFF) are usable with the ROMs switched on
.const STAND_BASE = $1001   // load address of a standalone program (BASIC start)
#if !HIROM
#define NOEXT               // the harness and 64edit: no extension chunks (real, pointers, write(x:w), Random)
#endif
#if HIROM
// ROM-off map (64ide and 64pascal on the Plus/4): the program runs with the ROMs switched off and interrupts disabled
// (kfstubs.asm), so the RAM under the ROMs ($8000-$FCFF) holds the source text and the compiler's tables. The KERNAL is
// reached through stubs that switch it on for the duration of one call. Programs that are run in place still use the
// low RAM (CODE_BASE..CODE_LIMIT) with the ROMs on, like the compiler harness.
#if NOSTORE
.const SRC_BASE   = $8000   // source buffer (the file loaded by 64pascal; 64ide has its editor there: its SRC_BASE is a label
                            // behind the editor, see 64ide.asm)
.const SRC_LIMIT  = $e9f0   // 64pascal: the extension chunks stay in the program image (low RAM), so the text buffer and
.const BUF_LIMIT  = $ea00   // the buffer for the program image may use everything up to the symbol table
#else
.const SRC_LIMIT  = $d2f0
.const HIDDEN_BASE = $d300  // the extension chunks (real, pointers, write(x:w), Random) are kept here, in the RAM under the
                            // ROMs, behind the text; install_ext_store copies them there at start-up (6 KB)
.const BUF_LIMIT  = HIDDEN_BASE // standalone program images are built behind the text, up to the stored extension chunks
#endif
.const EXT_BASE   = $4c00   // ... and a program that uses them gets them copied here (standalone start-up code) up to
.const EXT_LIMIT  = $6400   // the program's data
#define HAVEREAL            // the type real (rt_float.asm)
.const SYM_BASE   = $ea00   // compiler symbol table (4 KB)
.const SYM_LIMIT  = $fa00
.const DTAB_BASE  = $fa00   // type descriptors (512 bytes)
.const DEFTAB_BASE = $fc00  // table of {$DEFINE} symbols (256 bytes)
.const CODE_BASE  = $5200   // generated code of a program that is run in place (behind the program's own code)
.const CODE_LIMIT = $6400
#else
#if EDONLY
.const SRC_LIMIT  = $7ff0   // editor only: the text may fill all RAM up to the ROM at $8000
#else
.const SRC_LIMIT  = $4900
#endif
.const DTAB_BASE  = $4c00   // type descriptors (512 bytes)
#if !EDONLY
.const DEFTAB_BASE = $4e00  // table of {$DEFINE} symbols (256 bytes)
#endif
.const SYM_BASE   = $4f00   // compiler symbol table
.const SYM_LIMIT  = $5700
.const CODE_BASE  = $5700   // generated code (and the build buffer for standalone files)
.const CODE_LIMIT = $6400
#endif
.const DATA_BASE  = $6400   // program globals
.const DATA_LIMIT = $6800
.const STK_TOP    = $6b00   // software stack grows down from here (to DATA_LIMIT)
.const RT_INBUF   = $6b00   // 256-byte keyboard line buffer of read/readln
.const RT_TEMPS   = $6c00   // four 256-byte scratch strings used by the runtime
.const RT_BASE    = $7000   // runtime (fixed address)
.const KEYCOUNT   = $ef     // number of keys waiting in the keyboard buffer
.const BG_REG     = $ff15   // background colour register (TED)
.const SCRN_BASE  = $0c00   // text screen
.const COLOR_RAM  = $0800   // colour RAM
#elif C128
// C128 mode: BASIC at $1C01, ROM-free RAM runs up to $BFFF, KERNAL ROM stays at $C000-$FFFF
.const STAND_BASE = $1c01   // load address of a standalone program (BASIC start)
.const KEYCOUNT   = $d0     // number of keys waiting in the keyboard buffer
#if IDE
// IDE: the editor makes the program larger; generated code gets a smaller area further up
#if EDONLY
.const SRC_LIMIT  = $bff0   // editor only (no compiler / runtime in memory): the text may fill all RAM up to the ROM at $C000
#else
.const SRC_LIMIT  = $83f0   // end of the text buffer: it starts at the page after the program; the code of a program
                            // that is compiled in the IDE is placed in the free part behind the text
#endif
.const CODE_BASE  = $7800   // generated code
.const CODE_LIMIT = $8400
#else
.const SRC_LIMIT  = $77f0   // end of the source buffer (SRC_BASE is set by 64pascal.asm: the page after the program)
.const CODE_BASE  = $6800   // generated code
.const CODE_LIMIT = $8400
#endif
.const SCRN_BASE  = $0400   // text screen (40 columns)
.const COLOR_RAM  = $d800   // colour RAM
.const DATA_BASE  = $8400   // program globals
.const DATA_LIMIT = $8c00
.const STK_TOP    = $9300   // software stack grows down from here (to DATA_LIMIT)
.const RT_INBUF   = $9300   // 256-byte keyboard line buffer of read/readln
.const RT_TEMPS   = $9400   // four 256-byte scratch strings used by the runtime
.const BG_REG     = $d021   // background colour register (VIC-II)
.const DTAB_BASE  = $A000   // type descriptors (512 bytes)
#if !EDONLY
.const DEFTAB_BASE = $A200  // table of {$DEFINE} symbols (256 bytes)
#endif
.const SYM_BASE   = $A300   // compiler symbol table
.const SYM_LIMIT  = $AF00
.const RT_BASE    = $B000   // runtime (fixed address)
.const EXT_BASE   = $9800   // extension chunks (heap, floating point, write formats): copied here only when a program uses
.const EXT_LIMIT  = $B000   // them (up to the runtime). The compiler's tables ($A000..) overlap this region, but they are dead
                            // once the program runs.
.const HIDDEN_BASE = $E000  // RAM under the KERNAL ROM: the extension chunks are kept here (platcode.asm)
.const BANK_REG   = $ff00   // MMU configuration register
.const BANK_NORMAL = $0e    // BASIC off, KERNAL + I/O on
.const BANK_HIDDEN = $3e    // ... but RAM instead of the KERNAL: the hidden chunks can be read (bank 0, I/O stays)
#define HAVEREAL            // the type real (rt_float.asm)
#else
.const STAND_BASE = $0801   // load address of a standalone program (BASIC start)
.const KEYCOUNT   = $c6     // number of keys waiting in the keyboard buffer
#if IDE
// IDE: the editor makes the program larger; generated code gets a smaller area further up
#if EDONLY
.const SRC_LIMIT  = $cff0   // editor only (no compiler / runtime in memory): the text may fill all RAM up to the I/O area at $D000
#else
.const SRC_LIMIT  = $7ff0   // end of the text buffer: it starts at the page after the program; the code of a program
                            // that is compiled in the IDE is placed in the free part behind the text
#endif
.const CODE_BASE  = $7000
.const CODE_LIMIT = $8000
#else
.const SRC_LIMIT  = $7ff0   // end of the source buffer (SRC_BASE is set by 64pascal.asm: the page after the program); the
                            // code of the program is placed behind the source text (see compile_source), up to CODE_LIMIT
.const CODE_BASE  = $6000   // (the development harness main.asm compiles here)
.const CODE_LIMIT = $8000
#endif
.const SCRN_BASE  = $0400   // text screen (40 columns)
.const COLOR_RAM  = $d800   // colour RAM
.const DATA_BASE  = $8000
.const DATA_LIMIT = $9000
.const STK_TOP    = $9b00   // software stack grows down from here (to DATA_LIMIT)
.const RT_INBUF   = $9b00   // 256-byte keyboard line buffer of read/readln
.const RT_TEMPS   = $9c00   // four 256-byte scratch strings used by the runtime
.const BG_REG     = $d021   // background colour register (VIC-II)
.const DTAB_BASE  = $A000
#if !EDONLY
.const DEFTAB_BASE = $A200
#endif
.const SYM_BASE   = $A300
.const SYM_LIMIT  = $BF00
.const RT_BASE    = $C000
.const EXT_BASE   = $A000   // extension chunks (heap, floating point, write formats): copied here only when a program
.const EXT_LIMIT  = $C000   // uses them (8 KB). The compiler's tables live here too, but they are dead once the program runs.
.const HIDDEN_BASE = $E000  // RAM under the KERNAL ROM: the extension chunks are kept here (platcode.asm), so that their image
                            // in the program file can be reused as buffer space
.const BANK_REG   = $01     // processor port: memory configuration
.const BANK_NORMAL = $36    // BASIC off, KERNAL + I/O on
.const BANK_HIDDEN = $35    // KERNAL and BASIC off: the RAM under them can be read
#define HAVEREAL            // the type real (rt_float.asm): C64, C128 (both modes), not the Plus/4
#endif
// DTAB_BASE: table of 32 type descriptors (16 bytes each) for arrays and strings.
// RT_TEMPS: four 256-byte scratch strings used by the runtime for string expressions.
.const SYM_SIZE   = 32      // bytes per symbol record
