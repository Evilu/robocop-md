| The arcade's text layer (8x8 characters over everything).
| The visible 32 x 28 characters are divided into blocks of 4 x 2.
| When one of the tile layers is blank, the text is written into that layer's
| plane as high-priority cells, each character's pattern loaded once.
| Otherwise (the stages that use both layers) a block with anything in it owns
| eight patterns in VRAM and is shown as one 32x16 sprite, in front of the
| game's sprites; 20 blocks at most. A checksum per block tells when its
| characters changed; a quarter of the blocks are checked at a time. When the
| sprite table cannot hold both, game sprites and text take turns to lose. Pixels are renumbered onto palette line 2 with the tile
| layers' colour tables.

    .equ TEXT_MAP,      0xff6000
    .equ BLOCK_SUM,     0xff0e40    | 112 words
    .equ BLOCK_SLOT,    0xff0f20    | 112 bytes: pattern slot + 1, 0 = nothing shown
    .equ TEXT_SLOT_USED, 0xff0f90   | 20 bytes
    .equ text_budget,   0xff0fb0
    .equ text_active,   0xff0fb2
    .equ text_sum,      0xff0fb4
    .equ text_block_no, 0xff0fb6
    .equ TEXT_LUT_OK,   0xff0fc0    | 12 bytes
    .equ TEXT_LUT,      0xffd740    | 12 palettes of 16 pens
    .equ text_plane,    0xff1040    | 0 = sprites, 0xc000 or 0xe000 = that plane
    .equ text_chars,    0xff1042
    .equ text_flush,    0xff1044
    .equ text_planes_left, 0xff1046
    .equ text_inexact,  0xff1048
    .equ text_curtain,  0xff104a
    .equ TEXT_CELLS,    0xff1050    | 8 words: the block being written
    .equ CHAR_KEYS,     0xff1100    | 160 words: the character and palette in each pattern, 0xffff = free
    .equ CHAR_SLOTS,    160
    .equ CHAR_LIMIT,    150
    .equ TEXT_PLANE_BLOCKS, 8

    .equ TEXT_BLOCKS,   112
    .equ TEXT_SLOTS,    20
    .equ TEXT_PALETTES, 12
    .equ TEXT_PER_LATCH, 1
    .equ CHAR_BLANK,    GFX_BLANK + 3072

text_patterns:
    .word   0x548, 0x550, 0x558, 0x560, 0x568, 0x570, 0x578, 0x580
    .word   0x588, 0x590, 0x598, 0x5a0, 0x5a8, 0x5b0, 0x5b8
    .word   0x5d0, 0x5d8, 0x5e8, 0x5f0, 0x5f8

| The colour tables or the colours behind them changed: build them again and draw every block again.
text_invalidate:
    clr.w   text_inexact
    tst.w   text_plane
    beq.s   2f
    move.w  #1, text_flush
2:  lea     TEXT_LUT_OK, a0
    clr.l   (a0)+
    clr.l   (a0)+
    clr.l   (a0)+
    lea     BLOCK_SUM, a0
    moveq   #TEXT_BLOCKS - 1, d0
1:  not.w   (a0)+
    dbra    d0, 1b
    rts

| After a palette change: do the text's colour tables still give each pen its own colour?
text_validate:
    moveq   #0, d7
    moveq   #0, d6
    lea     BG_FULL, a3
1:  lea     TEXT_LUT_OK, a2
    tst.b   (a2, d6.w)
    beq.s   4f
    move.w  d6, d4
    lsl.w   #5, d4
    lea     PALETTE_RG, a0
    adda.w  d4, a0
    lea     PALETTE_B, a1
    adda.w  d4, a1
    lsr.w   #1, d4
    lea     TEXT_LUT, a2
    adda.w  d4, a2
    moveq   #15, d5
2:  move.w  (a0)+, d2
    swap    d2
    move.w  (a1)+, d2
    andi.w  #0x00ff, d2
    moveq   #0, d0
    move.b  (a2)+, d0
    beq.s   3f
    lsl.w   #2, d0
    cmp.l   (a3, d0.w), d2
    beq.s   3f
    addq.w  #1, d7
3:  dbra    d5, 2b
4:  addq.w  #1, d6
    cmpi.w  #TEXT_PALETTES, d6
    bne.s   1b
    move.w  text_inexact, d0
    addq.w  #2, d0
    cmp.w   d0, d7
    bhi.w   text_invalidate
    rts

| The arcade hides a scene being set up behind text cells that are all the same
| solid character. Sixteen cells spread over the screen are sampled; when they
| agree, the display is switched off, and back on when they stop. The display
| is also off while the tile layers load a scene.
text_curtain_check:
    lea     TEXT_MAP + (5 * 32 + 2) * 2, a0
    move.w  (a0), d0
    move.w  d0, d1
    andi.w  #0x0fff, d1
    lea     CHAR_BLANK, a1
    moveq   #0, d2
    tst.b   (a1, d1.w)
    bne.s   4f
    moveq   #3, d3
1:  moveq   #3, d4
2:  cmp.w   (a0), d0
    bne.s   3f
    addq.w  #1, d2
3:  lea     16(a0), a0
    dbra    d4, 2b
    lea     6 * 64 - 64(a0), a0
    dbra    d3, 1b
4:  cmpi.w  #14, d2
    scc     d2
    andi.w  #1, d2
    tst.w   bg_loading
    bne.s   8f
    tst.w   bg_hold
    beq.s   7f
8:  moveq   #1, d2
7:  cmp.w   text_curtain, d2
    beq.s   6f
    move.w  d2, text_curtain
    beq.s   5f
    move.w  #0x8134, VDP_CTRL
    move.w  #0x8700, VDP_CTRL
    rts
5:  move.w  #0x8174, VDP_CTRL
    move.w  #0x8730, VDP_CTRL
6:  rts

text_init:
    clr.w   text_plane
text_chars_clear:
    clr.w   text_chars
    clr.w   text_flush
    lea     CHAR_KEYS, a0
    move.w  #CHAR_SLOTS - 1, d0
1:  move.w  #0xffff, (a0)+
    dbra    d0, 1b
    rts

| The plane that can carry the text: a layer with nothing drawn and nothing waiting.
text_choose:
    move.w  #0xc000, d0
    lea     BG_LAYER2, a0
    tst.w   LAYER_COUNT(a0)
    bne.s   1f
    tst.w   LAYER_REDRAW(a0)
    beq.s   2f
1:  move.w  #0xe000, d0
    lea     BG_LAYER3, a0
    tst.w   LAYER_COUNT(a0)
    bne.s   3f
    tst.w   LAYER_REDRAW(a0)
    beq.s   2f
3:  moveq   #0, d0
2:  rts

| Takes the text off the plane or out of the sprites, ready for the other.
text_leave:
    move.w  text_plane, d0
    beq.s   4f
    lea     BG_LAYER2, a5
    cmpi.w  #0xc000, d0
    beq.s   1f
    lea     BG_LAYER3, a5
1:  bsr.w   text_plane_clear
    bsr.w   bg_layer_invalidate
    bra.w   text_chars_clear
4:  lea     BLOCK_SLOT, a0
    moveq   #TEXT_BLOCKS / 4 - 1, d0
5:  clr.l   (a0)+
    dbra    d0, 5b
    lea     TEXT_SLOT_USED, a0
    clr.l   (a0)+
    clr.l   (a0)+
    clr.l   (a0)+
    clr.l   (a0)+
    clr.l   (a0)+
    clr.w   text_active
    rts

| Blanks the 32 x 28 cells of the text's plane.
text_plane_clear:
    move.w  text_plane, d0
    addi.w  #2 * 128, d0
    andi.w  #0x3fff, d0
    ori.w   #0x4000, d0
    swap    d0
    move.w  #3, d0
    moveq   #27, d1
1:  move.l  d0, VDP_CTRL
    moveq   #15, d2
2:  move.l  #0, VDP_DATA
    dbra    d2, 2b
    addi.l  #0x00800000, d0
    dbra    d1, 1b
    rts

text_update:
    bsr.w   text_curtain_check
    bsr.w   text_choose
    cmp.w   text_plane, d0
    bne.s   1f
    tst.w   text_flush
    beq.s   2f
1:  move.w  d0, -(sp)
    bsr.w   text_leave
    move.w  (sp)+, text_plane
    lea     BLOCK_SUM, a0
    moveq   #TEXT_BLOCKS - 1, d0
3:  not.w   (a0)+
    dbra    d0, 3b
2:  move.w  #TEXT_PLANE_BLOCKS, text_planes_left
    move.w  #TEXT_PER_LATCH, text_budget
    move.w  hal_tick, d7
    andi.w  #3, d7
    mulu.w  #TEXT_BLOCKS / 4, d7
    moveq   #TEXT_BLOCKS / 4 - 1, d6
2:  move.w  d7, d0
    lsr.w   #3, d0
    lsl.w   #7, d0
    move.w  d7, d1
    andi.w  #7, d1
    lsl.w   #3, d1
    add.w   d1, d0
    lea     TEXT_MAP + 128, a0
    adda.w  d0, a0
    moveq   #0, d0
    add.w   (a0), d0
    rol.w   #3, d0
    add.w   2(a0), d0
    rol.w   #3, d0
    add.w   4(a0), d0
    rol.w   #3, d0
    add.w   6(a0), d0
    rol.w   #3, d0
    add.w   64(a0), d0
    rol.w   #3, d0
    add.w   66(a0), d0
    rol.w   #3, d0
    add.w   68(a0), d0
    rol.w   #3, d0
    add.w   70(a0), d0
    lea     BLOCK_SUM, a1
    move.w  d7, d1
    add.w   d1, d1
    cmp.w   (a1, d1.w), d0
    beq.s   3f
    movem.w d6-d7, -(sp)
    move.w  d0, text_sum
    move.w  d7, text_block_no
    tst.w   text_plane
    beq.s   4f
    tst.w   text_planes_left
    beq.s   5f
    bsr.w   text_block_plane
    bra.s   5f
4:  tst.w   text_budget
    beq.s   5f
    bsr.w   text_block
5:  movem.w (sp)+, d6-d7
3:  addq.w  #1, d7
    dbra    d6, 2b
    rts

| a0 = the block's first character in the map. Draws the block, or drops it when it is empty.
text_block:
    lea     CHAR_BLANK, a2
    moveq   #0, d2
    lea     (a0), a1
    moveq   #1, d1
1:  moveq   #3, d3
2:  move.w  (a1)+, d0
    andi.w  #0x0fff, d0
    tst.b   (a2, d0.w)
    bne.s   3f
    moveq   #1, d2
3:  dbra    d3, 2b
    lea     56(a1), a1
    dbra    d1, 1b
    lea     BLOCK_SLOT, a3
    adda.w  text_block_no, a3
    moveq   #0, d5
    move.b  (a3), d5
    tst.w   d2
    bne.s   5f
    tst.w   d5
    beq.w   text_block_done
    lea     TEXT_SLOT_USED - 1, a2
    clr.b   (a2, d5.w)
    clr.b   (a3)
    subq.w  #1, text_active
    bra.w   text_block_done
5:  tst.w   d5
    bne.s   8f
    lea     TEXT_SLOT_USED, a2
    moveq   #TEXT_SLOTS - 1, d1
6:  addq.w  #1, d5
    tst.b   (a2)+
    beq.s   7f
    dbra    d1, 6b
    rts
7:  st      -1(a2)
    move.b  d5, (a3)
    addq.w  #1, text_active
8:  add.w   d5, d5
    lea     text_patterns - 2(pc), a2
    move.w  (a2, d5.w), d0
    lsl.w   #5, d0
    move.w  d0, d1
    andi.w  #0x3fff, d1
    ori.w   #0x4000, d1
    swap    d1
    rol.w   #2, d0
    andi.w  #3, d0
    move.w  d0, d1
    move.l  d1, VDP_CTRL
    moveq   #3, d5
9:  move.w  (a0), d0
    bsr.w   text_cell
    move.w  64(a0), d0
    bsr.w   text_cell
    addq.l  #2, a0
    dbra    d5, 9b
    subq.w  #1, text_budget
text_block_done:
    lea     BLOCK_SUM, a1
    move.w  text_block_no, d1
    add.w   d1, d1
    move.w  text_sum, (a1, d1.w)
    rts

| a0 = the block's first character in the map. Writes the block's eight cells into the text's plane.
text_block_plane:
    lea     TEXT_CELLS, a1
    moveq   #1, d5
1:  moveq   #3, d6
2:  move.w  (a0)+, d0
    movem.l a0-a1, -(sp)
    bsr.w   text_char
    movem.l (sp)+, a0-a1
    move.w  d0, (a1)+
    dbra    d6, 2b
    lea     56(a0), a0
    dbra    d5, 1b
    move.w  text_block_no, d0
    move.w  d0, d1
    lsr.w   #3, d1
    addq.w  #1, d1
    lsl.w   #8, d1
    andi.w  #7, d0
    lsl.w   #3, d0
    add.w   d0, d1
    add.w   text_plane, d1
    andi.w  #0x3fff, d1
    ori.w   #0x4000, d1
    swap    d1
    move.w  #3, d1
    lea     TEXT_CELLS, a1
    move.l  d1, VDP_CTRL
    move.l  (a1)+, VDP_DATA
    move.l  (a1)+, VDP_DATA
    addi.l  #0x00800000, d1
    move.l  d1, VDP_CTRL
    move.l  (a1)+, VDP_DATA
    move.l  (a1)+, VDP_DATA
    subq.w  #1, text_planes_left
    bra.w   text_block_done

| d0 = map word. Returns the plane cell that shows it, loading the character's pattern if it is new.
text_char:
    move.w  d0, d2
    andi.w  #0x0fff, d2
    lea     CHAR_BLANK, a2
    tst.b   (a2, d2.w)
    beq.s   1f
    moveq   #0, d0
    rts
1:  move.w  d0, d3
    lsr.w   #7, d3
    eor.w   d0, d3
    andi.w  #0xff, d3
    cmpi.w  #CHAR_SLOTS, d3
    blo.s   2f
    subi.w  #CHAR_SLOTS, d3
2:  add.w   d3, d3
    lea     CHAR_KEYS, a2
3:  move.w  (a2, d3.w), d4
    cmp.w   d0, d4
    beq.s   6f
    cmpi.w  #0xffff, d4
    beq.s   4f
    addq.w  #2, d3
    cmpi.w  #CHAR_SLOTS * 2, d3
    blo.s   3b
    moveq   #0, d3
    bra.s   3b
4:  cmpi.w  #CHAR_LIMIT, text_chars
    blo.s   5f
    move.w  #1, text_flush
    moveq   #0, d0
    rts
5:  addq.w  #1, text_chars
    move.w  d0, (a2, d3.w)
    move.w  d3, -(sp)
    bsr.w   text_char_pattern
    lsl.w   #5, d1
    move.w  d1, d2
    andi.w  #0x3fff, d2
    ori.w   #0x4000, d2
    swap    d2
    rol.w   #2, d1
    andi.w  #3, d1
    move.w  d1, d2
    move.l  d2, VDP_CTRL
    bsr.w   text_cell
    move.w  (sp)+, d3
6:  bsr.w   text_char_pattern
    move.w  d1, d0
    ori.w   #0xc000, d0
    rts

| d3 = twice the character's place in CHAR_KEYS. Returns its pattern number in d1.
text_char_pattern:
    move.w  d3, d1
    lsr.w   #4, d1
    add.w   d1, d1
    lea     text_patterns(pc), a2
    move.w  (a2, d1.w), d1
    move.w  d3, d2
    lsr.w   #1, d2
    andi.w  #7, d2
    add.w   d2, d1
    rts

| d0 = map word. Sends the character's pattern, renumbered for its palette, to the data port.
text_cell:
    move.w  d0, d2
    andi.w  #0x0fff, d2
    lea     CHAR_BLANK, a2
    tst.b   (a2, d2.w)
    beq.s   2f
    moveq   #7, d1
1:  move.l  #0, VDP_DATA
    dbra    d1, 1b
    rts
2:  rol.w   #4, d0
    andi.w  #15, d0
    cmpi.w  #TEXT_PALETTES, d0
    blo.s   3f
    subi.w  #TEXT_PALETTES, d0
3:  lea     TEXT_LUT_OK, a2
    tst.b   (a2, d0.w)
    bne.s   4f
    st      (a2, d0.w)
    addi.w  #32, d0
    move.w  bg_inexact, -(sp)
    bsr.w   bg_lut_build
    move.w  bg_inexact, d1
    sub.w   (sp), d1
    add.w   d1, text_inexact
    move.w  (sp)+, bg_inexact
    subi.w  #32, d0
4:  lsl.w   #4, d0
    lea     TEXT_LUT, a4
    adda.w  d0, a4
    moveq   #0, d0
    move.w  d2, d0
    lsl.l   #5, d0
    addi.l  #GFX_CHARS, d0
    movea.l d0, a2
    moveq   #15, d3
5:  moveq   #0, d0
    move.b  (a2)+, d0
    move.w  d0, d1
    lsr.w   #4, d0
    andi.w  #15, d1
    move.b  (a4, d0.w), d4
    lsl.w   #4, d4
    or.b    (a4, d1.w), d4
    lsl.w   #8, d4
    moveq   #0, d0
    move.b  (a2)+, d0
    move.w  d0, d1
    lsr.w   #4, d0
    andi.w  #15, d1
    move.b  (a4, d0.w), d0
    lsl.b   #4, d0
    or.b    (a4, d1.w), d0
    move.b  d0, d4
    move.w  d4, VDP_DATA
    dbra    d3, 5b
    rts

| Adds a sprite for every block shown. a2 = next sprite table entry, d7 = its index.
text_sprites:
    lea     BLOCK_SLOT, a0
    moveq   #0, d6
1:  moveq   #0, d0
    move.b  (a0)+, d0
    beq.s   2f
    cmpi.w  #MAX_SPRITES, d7
    bhs.s   3f
    move.w  d6, d1
    lsr.w   #3, d1
    lsl.w   #4, d1
    addi.w  #128, d1
    move.w  d1, (a2)+
    move.w  #0x0d00, d1
    move.b  d7, d1
    subq.b  #1, d1
    move.w  d1, (a2)+
    add.w   d0, d0
    lea     text_patterns - 2(pc), a1
    move.w  (a1, d0.w), d1
    ori.w   #0xc000, d1
    move.w  d1, (a2)+
    move.w  d6, d1
    andi.w  #7, d1
    lsl.w   #5, d1
    addi.w  #128, d1
    move.w  d1, (a2)+
    addq.w  #1, d7
2:  addq.w  #1, d6
    cmpi.w  #TEXT_BLOCKS, d6
    bne.s   1b
3:  rts
