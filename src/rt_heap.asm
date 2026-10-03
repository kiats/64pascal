// This file is in the public domain: use it, change it, share it, sell it - do whatever you like with it.
// No permission, credit or payment needed. It comes as it is, with no warranty. Enjoy!
// Note: this has only been tested in the VICE emulator, never on real hardware.
// =====================================================================================
// rt_heap.asm - the heap: New and Dispose (extension chunk 9)
// =====================================================================================
//
// Pointers refer to blocks on a heap that grows upward from the end of the program's global data
// (rt_hinit, called first thing by a program that uses pointers) towards the software stack, which
// grows down. Every block has a 2-byte header in front of the address that the program sees: the size
// of the block. Dispose puts the block on a free list (the first two bytes of the block hold the link);
// New first looks through the free list for a block of exactly the requested size and only then takes
// new memory from the top of the heap. Blocks are never merged or split.

rt_hp:      .word 0             // next free heap address
rt_hfree:   .word 0             // first block of the free list (0 = empty)

rt_hinit:                       // inline word = first heap address
    FETCH()
    lda wd
    sta rt_hp
    lda wd+1
    sta rt_hp+1
    lda #0
    sta rt_hfree
    sta rt_hfree+1
    jmp (rp)

rt_new:                         // ac = size in bytes; the address of the pointer variable is popped
    jsr popt                    // tmp = address of the pointer variable
    lda ac+1
    bne rn_search
    lda ac                      // blocks are at least 2 bytes (room for the free list link)
    cmp #2
    bcs rn_search
    lda #2
    sta ac
rn_search:
    lda #<rt_hfree              // rem = address of the cell that points to the current block
    sta rem
    lda #>rt_hfree
    sta rem+1
rn_loop:
    ldy #0
    lda (rem),y                 // wd2 = current free block (its address, the header is 2 bytes below)
    sta wd2
    iny
    lda (rem),y
    sta wd2+1
    ora wd2
    beq rn_bump                 // end of the list: nothing fits
    sec
    lda wd2
    sbc #2
    sta wd
    lda wd2+1
    sbc #0
    sta wd+1
    ldy #0
    lda (wd),y                  // size in the header equal to the requested one?
    cmp ac
    bne rn_next
    iny
    lda (wd),y
    cmp ac+1
    bne rn_next
    ldy #0                      // yes: take it off the list (the link is in its first two bytes)
    lda (wd2),y
    sta (rem),y
    iny
    lda (wd2),y
    sta (rem),y
    jmp rn_give
rn_next:
    lda wd2                     // the link cell of this block is its first two bytes
    sta rem
    lda wd2+1
    sta rem+1
    jmp rn_loop
rn_bump:                        // take new memory from the top of the heap
    lda rt_hp
    sta wd
    lda rt_hp+1
    sta wd+1
    ldy #0                      // header = size
    lda ac
    sta (wd),y
    iny
    lda ac+1
    sta (wd),y
    clc                         // the block starts after the header
    lda wd
    adc #2
    sta wd2
    lda wd+1
    adc #0
    sta wd2+1
    clc                         // new top of heap = block + size
    lda wd2
    adc ac
    sta wd
    lda wd2+1
    adc ac+1
    sta wd+1
    bcs rn_oom
    cmp ssp+1                   // keep at least 256 bytes between the heap and the software stack
    bcs rn_oom
    lda wd
    sta rt_hp
    lda wd+1
    sta rt_hp+1
rn_give:
    ldy #0                      // the pointer variable receives the block address
    lda wd2
    sta (tmp),y
    iny
    lda wd2+1
    sta (tmp),y
    rts
rn_oom:
    lda #4                      // runtime error 4: out of memory
    jmp rt_err

rt_dispose:                     // ac = pointer to the block to free (nil is ignored)
    lda ac
    ora ac+1
    beq rd_done
    lda ac
    sta wd
    lda ac+1
    sta wd+1
    ldy #0                      // link the block into the free list
    lda rt_hfree
    sta (wd),y
    iny
    lda rt_hfree+1
    sta (wd),y
    lda ac
    sta rt_hfree
    lda ac+1
    sta rt_hfree+1
rd_done:
    rts
