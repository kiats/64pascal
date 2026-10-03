// This file is in the public domain: use it, change it, share it, sell it - do whatever you like with it.
// No permission, credit or payment needed. It comes as it is, with no warranty. Enjoy!
// Note: this has only been tested in the VICE emulator, never on real hardware.
// Zero page (BASIC is not used while we run, so $02-$27 are ours)
// runtime
.label ssp    = $02   // software stack pointer (2)
.label ac     = $04   // 16-bit accumulator (2)
.label tmp    = $06   // (2)
.label wd     = $08   // inline word argument (2)
.label rp     = $0a   // return pointer for inline-argument calls (2)
.label rem    = $0c   // division remainder (2)
.label fp     = $0e   // frame pointer of the running procedure (2)
.label wd2    = $12   // second inline word (runtime only; shares the compiler's 'src', which is idle while a program runs)
.label s1     = $10
.label s2     = $11
// compiler
.label src    = $12   // source read pointer (2)
.label cpc    = $14   // logical code address (2)
.label cout   = $16   // physical output pointer (2)
.label tok    = $18
.label tokval = $19   // (2)
.label etype  = $1b
.label line   = $1c   // (2)
.label datap  = $1e   // next free global data address (2)
.label symp   = $20   // end of symbol table (2)
.label sptr   = $22   // symbol search pointer (2)
.label tmpc1  = $24   // (2)
.label tmpc2  = $26   // (2)
.label tmpc3  = $28   // (2)

// Runtime string scratch. These reuse compiler zero page locations; that is safe because the
// compiler is idle while a compiled program runs.
.label sa     = $14   // string pointer (2)  [= cpc]
.label sb     = $16   // string pointer (2)  [= cout]
.label sn     = $18   // byte                [= tok]
.label sm     = $19   // byte                [= tokval]
.label sc     = $1a   // byte
.label sd     = $1b   // byte                [= etype]

// Editor (only while editing: these share locations with the compiler and runtime scratch, which are
// idle then; the editor copies what it needs to keep to RAM around a compile / run)
.label gs     = $14   // gap start = the cursor position (2)
.label ge     = $16   // gap end: first text byte after the gap (2)
.label ep     = $18   // text read pointer (2)
.label scr    = $1a   // screen pointer (2)
.label tp     = $1c   // scratch pointer (2)
.label et1    = $1e
.label et2    = $1f
.label et3    = $20
.label et4    = $21
