// This file is in the public domain: use it, change it, share it, sell it - do whatever you like with it.
// No permission, credit or payment needed. It comes as it is, with no warranty. Enjoy!
// Note: this has only been tested in the VICE emulator, never on real hardware.
// =====================================================================================
// compiler.asm - single-pass Pascal compiler: entry point and overall program structure
// =====================================================================================
//
// The compiler reads ASCII source through the pointer 'src' (terminated by a 0 byte)
// and writes 6502 machine code starting at CODE_BASE. There is no separate parse tree
// and no assembler stage: every construct emits its machine code the moment it is
// parsed (recursive descent, one pass, like Turbo Pascal).
//
// Files, in the order they are included below:
//   defs.asm    token / symbol / error constants and macros
//   emit.asm    writing bytes of generated code, jump patching
//   chunks.asm  which parts of the runtime a program uses (linking)
//   standalone.asm  building a self-running .prg image (BASIC stub, start-up code, used runtime chunks)
//   lexer.asm   character classes, tokenizer, reserved word table
//   directive.asm  compiler directives {$DEFINE} {$IFDEF} ... (conditional compilation)
//   symtab.asm  symbol table: lookup, add, built-in identifiers
//   vars.asm    code generation for variable access (global, byte, local, var parameter)
//   types.asm   type descriptors and type parsing (arrays, strings)
//   desig.asm   designators: array elements, string characters
//   strfn.asm   string operators and the built-in string routines
//   iofn.asm    read/readln, Val, the Crt unit, the uses clause
//   decls.asm   const and var sections
//   proc.asm    procedures and functions: declarations and calls
//   expr.asm    expressions (factor, term, simple expression, relation)
//   stmt.asm    statements (assignment, if, while, repeat, for, write/writeln, calls)
//   ctlfn.asm   Exit, Break, Continue, Halt, Inc, Dec, Odd, Succ, Pred, shl / shr, forward declarations (the jump chains,
//               the loop bookkeeping and the helper routines used by stmt.asm, proc.asm, expr.asm and decls.asm)
//
// Entry:  jsr compile        with 'src' pointing to the source text
// Exit:   carry clear = success, generated code is at CODE_BASE .. cpc-1
//         carry set   = error; 'errcode' holds the E_* code and 'line' the source line
//
// Generated code model (see runtime.asm): a stack machine around a 16-bit accumulator.
// Every expression leaves its value in 'ac'; binary operators push the left operand with
// "jsr rt_push" and the operator routine pops it again.

.import source "defs.asm"

// ---- compiler state kept in ordinary RAM (zero page names are in zp.asm) -------------------
cmode:    .byte 0               // 0 = compile to run in place, 1 = build a standalone file image
codebase: .word CODE_BASE      // where the generated code starts (the IDE places it behind the text)
codelimit: .word CODE_LIMIT    // first address that the generated code must not reach
csp:      .byte 0               // hardware stack pointer at entry, used to abort on error
errcode:  .byte 0               // E_* code of the last compile error
nkind:    .byte 0               // symbol kind to be used by the next addsym
ntype:    .byte 0               // symbol type to be used by the next addsym
nval:     .word 0               // symbol address/value to be used by the next addsym
digit:    .byte 0               // digit being added while lexing a number
chsave:   .byte 0               // punctuation character being decoded by the lexer
forflag:  .byte 0               // for loop direction: 0 = to, 1 = downto
curtype:  .byte 0               // type of the variable(s)/constant being declared
varstart: .word 0               // first symbol record of the current "a, b, c: type" group

// scopes and routines
scopebase: .word 0              // first symbol record of the current scope (SYM_BASE for globals)
lkbound:  .word 0               // lower bound used by the symbol lookup routines
inproc:   .byte 0               // 1 while compiling the inside of a procedure/function
locoff:   .byte 0               // bytes of locals allocated so far in the current frame
isfunc:   .byte 0               // routine being declared is a function
isvar:    .byte 0               // current parameter group is "var"
pcount:   .byte 0               // parameters of the routine being declared
argbytes: .byte 0               // bytes the arguments of the routine being declared take on the stack
pvm:      .byte 0               // var-parameter bit mask of the routine being declared
grpstart: .byte 0               // index of the first parameter of the current group
ptype:    .fill 8, 0            // parameter types of the routine being declared
curproc:  .word 0               // record of the routine being compiled (0 = none)
vtype:    .byte 0               // type of a var argument being passed
isabs:    .byte 0               // current var declaration has an 'absolute' address
absaddr:  .word 0               // that address
forkind:  .byte 0               // kind of the for loop control variable
fmode:    .byte 0               // for loop test being generated: 0 = range test, 1 = reached limit
dcount:   .byte 0               // number of type descriptors in use
curdesc:  .byte 0               // descriptor index of the type being parsed
edesc:    .byte 0               // descriptor index of the type of the last expression
newidx:   .byte 0               // index of the descriptor being built
cres:     .word 0               // result of the compile-time multiplication cmul
pt_base:  .byte 0               // pointer type being parsed: descriptor of its target
pt_btype: .byte 0               //   and the type code of its target
useheap:  .byte 0               // 1 when the program uses pointers / New (emit rt_hinit)
fwd_desc: .byte 0               // descriptor of a forward declared record type being defined (0 = none)
cs_n:     .byte 0               // case: number of BODY placeholders of the current arm
cs_lo:    .word 0               // case: low bound of a label range
cs_next:  .word 0               // case: NEXT placeholder while the BODY placeholders are patched
cval:     .word 0               // value read by parse_const
esize:    .word 0               // element size of the array being declared
vsize:    .word 0               // storage size of the variable(s) being declared
rfidx:    .byte 0               // descriptor index of the record type being declared
rofs:     .word 0               // next free field offset in that record
rfstart:  .word 0               // first field record of the current field group
rfn:      .byte 0               // number of fields in the current group
fowner:   .byte 0               // record descriptor whose fields find_field searches
vcount:   .byte 0               // number of variables in the current declaration group
dsym:     .fill 17, 0           // symbol named by the current compiler directive
dcode:    .byte 0               // number of the current directive
nest:     .byte 0               // nesting of conditionals inside skipped text
ifsp:     .byte 0               // number of open {$IFDEF}s
ifstack:  .fill 8, 0            // state of each open conditional
rdid:     .byte 0               // 3 = read, 4 = readln while compiling its arguments
rtused:   .word 0               // chunks of the runtime used by the program so far (chunks.asm)
mk_lo:    .byte 0               // address of the runtime routine being marked
mk_hi:    .byte 0
ck_x:     .byte 0
ck_tmp:   .byte 0
ck_tmp2:  .byte 0
ck_n:     .byte 0
ck_chunk: .byte 0
ck_old:   .word 0
ck_run:   .word 0
ck_len:   .word 0
bfid:     .byte 0               // number of the built-in routine being compiled
idbuf:    .fill 17, 0           // current identifier: length byte + up to 15 upper-case chars
strbuf:   .fill 256, 0          // current string literal: length byte + characters
numbuf:   .fill 32, 0           // text of the current real number literal: length byte + characters
lnstart:  .word 0               // where the number being lexed started
asgtype:  .byte 0               // type of the variable being assigned
fmt_w:    .byte 0               // write(x:w:d): width and decimals
fmt_d:    .byte 0
rop:      .byte 0               // numeric operator being compiled and the type of its left operand (realop.asm)
rlty:     .byte 0
valreal:  .byte 0               // Val: the variable n is a real

// ---- compile: entry point -----------------------------------------------------------------
compile:
    tsx                         // remember the stack level so 'error' can unwind to here
    stx csp
    lda codebase                // code is built at 'codebase' (CODE_BASE unless the IDE moved it); logical = physical address
    sta cpc
    sta cout
    lda codebase+1
    sta cpc+1
    sta cout+1
    lda cmode                   // standalone file: the code gets its real load address
    beq !+                      // (cpc) while it is built in the buffer (cout); the file starts
    lda #<STAND_BASE            // with the BASIC stub, start-up code and runtime (standalone.asm)
    sta cpc
    lda #>STAND_BASE
    sta cpc+1
    jsr emit_standalone_header
!:
    lda #<DATA_BASE             // global variables are allocated upward from DATA_BASE
    sta datap
    lda #>DATA_BASE
    sta datap+1
    lda #<SYM_BASE              // empty symbol table, global scope
    sta symp
    sta scopebase
    lda #>SYM_BASE
    sta symp+1
    sta scopebase+1
    lda #0
    sta inproc
    sta curproc
    sta curproc+1
    lda #1                      // source line counter starts at 1
    sta line
    lda #0
    sta line+1
    lda #1                      // runtime chunks: the core is always there
    sta rtused
    lda #0
    sta rtused+1
    sta useheap
    sta fwd_desc
    ldx #9                      // Break / Continue / Exit chains, loop nesting (ctlfn.asm)
    lda #0
!:  sta heads,x
    dex
    bpl !-
    sta incmode
    jsr init_builtins           // INTEGER, BOOLEAN, CHAR, TRUE, FALSE, WRITE, ...
    jsr init_types              // descriptor 0 = plain STRING
    jsr init_directives         // predefined symbols C64 / C128 / PLUS4 ...
    jsr nexttok                 // read the first token

    // optional program header: PROGRAM name [ ( ident list ) ] ;
    lda tok
    cmp #TK_PROGRAM
    bne !+                      // no header: go straight to the declarations
    jsr nexttok
    lda #TK_IDENT               // program name
    jsr expect
    lda tok
    cmp #TK_LPAR
    bne hdr_end
skiphdr:                        // skip "( input, output )" - the list is ignored
    jsr nexttok
    lda tok
    cmp #TK_RPAR
    beq hdr_rp
    cmp #TK_EOF
    bne skiphdr
    lda #E_EOF
    jmp error
hdr_rp:
    jsr nexttok                 // token after the ')'
hdr_end:
    lda #TK_SEMI
    jsr expect

!:  lda tok                    // optional  uses Crt, ...;
    cmp #TK_USES
    bne !+
    jsr parse_uses
!:  lda #$4c                    // jmp over the code of procedures/functions to the main block
    jsr emit
    :JPLACE()
    jsr decls                   // const / var / procedure / function sections
    jsr check_forward           // every 'forward' routine must have been defined
    lda tok                     // the main block must start with BEGIN
    cmp #TK_BEGIN
    beq !+
    lda #E_SYNTAX
    jmp error
!:  :PATCH()                    // the main block starts here
#if !NOEXT
    lda useheap                 // pointers in use: tell the heap where it may start (behind the global data)
    beq !+
    :GCALL(rt_hinit)
    lda datap
    ldx datap+1
    jsr emit_word
!:
#endif
    jsr stmt                    // compile "begin ... end"
    lda #TK_DOT                 // program ends with '.'
    jsr expect
    lda #$4c                    // emit "jmp rt_halt": end of the generated program
    jsr emit
    lda #<rt_halt
    ldx #>rt_halt
    jsr emit_word
    lda cmode                   // standalone file: append the runtime chunks the program uses
    beq !+
    jsr emit_standalone_trailer
!:
    clc                         // success
    rts

// ---- error: abort compilation ---------------------------------------------------------------
// A = E_* code. Restores the stack level saved by 'compile' and returns to its caller with
// carry set, from whatever depth of recursion the error was found in.
error:
    sta errcode
#if HAVEREAL
#if !HIROM
    lda #BANK_NORMAL            // (an error while the KERNAL was switched off to read an extension chunk)
    sta BANK_REG
    cli
#endif
#endif
    ldx csp
    txs
    sec
    rts

// ---- shared tails: the code is smaller when these are called instead of repeated ----------------------
// "lda #E_x / jmp error" costs 5 bytes at every place that reports an error, "jmp err_x" only 3.
err_syntax:
    lda #E_SYNTAX
    jmp error
err_undef:
    lda #E_UNDEF
    jmp error
err_type:
    lda #E_TYPE
    jmp error
err_args:
    lda #E_ARGS
    jmp error
err_mem:
    lda #E_MEM
    jmp error

// lookup_must: lookup of the identifier in idbuf that must exist; reports "undefined identifier" if it does not.
// Returns like lookup with the carry set (sptr = its symbol record).
lookup_must:
    jsr lookup
    bcs lm_ok
    jmp err_undef
lm_ok:
    rts

// The runtime routines that the generated code calls most often. "jsr gc_push" (3 bytes) replaces :GCALL(rt_push) (7 bytes);
// each stub loads the routine address into A / X and goes to gen_jsr, exactly as the macro does.
gc_push:
    lda #<rt_push
    ldx #>rt_push
    jmp gen_jsr
gc_ldi:
    lda #<rt_ldi
    ldx #>rt_ldi
    jmp gen_jsr
gc_jf:
    lda #<rt_jf
    ldx #>rt_jf
    jmp gen_jsr
gc_c2s:
    lda #<rt_c2s
    ldx #>rt_c2s
    jmp gen_jsr
gc_ldl:
    lda #<rt_ldl
    ldx #>rt_ldl
    jmp gen_jsr
gc_i2f:
    lda #<rt_i2f
    ldx #>rt_i2f
    jmp gen_jsr

// ---- expect: require the current token to be A, then read the next one -------------------------
expect:
    cmp tok
    bne !+
    jmp nexttok                 // matches: advance (tail call)
!:  lda #E_SYNTAX
    jmp error

.import source "emit.asm"
.import source "chunks.asm"
.import source "standalone.asm"
.import source "lexer.asm"
.import source "directive.asm"
.import source "symtab.asm"
.import source "vars.asm"
.import source "types.asm"
.import source "desig.asm"
.import source "decls.asm"
.import source "proc.asm"
.import source "strfn.asm"
#if !NOEXT
.import source "ptrfn.asm"
#endif
.import source "realop.asm"
.import source "iofn.asm"
.import source "expr.asm"
.import source "stmt.asm"
.import source "ctlfn.asm"
