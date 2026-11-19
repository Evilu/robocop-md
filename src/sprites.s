| Arcade sprite RAM to Mega Drive sprites.
| Each arcade entry is a column of 1, 2, 4 or 8 tiles of 16x16; a column becomes
| sprites of 16x16 (one tile) or 16x32 (two tiles). Patterns are fetched from ROM
| into a VRAM cache of 8-pattern slots, keyed by tile (singles) or tile pair.

    .equ SPRITE_RAM,    0xffc000
    .equ SPRITE_END,    0xffc800

    .equ SAT_BUFFER,    0xffd100    | 64 entries of 8 bytes; entry 0 heads the chain
    .equ UPLOADS,       0xffd300    | 8 bytes each: ROM address, length in words, VRAM address
    .equ SLOT_KEY,      0xffd500    | word per slot: key held, 0xffff = empty
    .equ SLOT_STAMP,    0xffd600    | word per slot: last latch that used it
    .equ CRAM_BUFFER,   0xffd700    | 32 words: palette lines 0-1
    .equ SLOT_OF,       0xffe000    | byte per key: slot + 1, 0 = not in VRAM

    .equ spr_stamp,     HAL_VARS + 0x10
    .equ spr_hand,      HAL_VARS + 0x12
    .equ upload_count,  HAL_VARS + 0x14
    .equ spr_ready,     HAL_VARS + 0x16
    .equ spr_cols,      HAL_VARS + 0x18
    .equ spr_x,         HAL_VARS + 0x1a
    .equ spr_y,         HAL_VARS + 0x1c
    .equ spr_skip,      HAL_VARS + 0x1e
    .equ spr_size,      HAL_VARS + 0x20
    .equ spr_height,    HAL_VARS + 0x22
    .equ spr_piece,     HAL_VARS + 0x24
    .equ spr_dropped,   HAL_VARS + 0x26
    .equ spr_limit,     HAL_VARS + 0x42
    .equ spr_game,      HAL_VARS + 0x44    | game sprites in the table, plus the heading entry
    .equ hal_tick,      HAL_VARS + 0x46
    .equ since_latch,   HAL_VARS + 0x48
    .equ IDLE_FRAMES,   4
    .equ PAL_COUNT,     0xff1600    | 16 bytes: sprites using each arcade palette in the list being walked
    .equ LINE_STAMP,    HAL_VARS + 0x28    | 3 words
    .equ LINE_PAL,      HAL_VARS + 0x2e    | 3 bytes: arcade palette on each line, 0xff = none
    .equ PAL_LINE,      HAL_VARS + 0x32    | 16 bytes: line of each arcade palette, 0xff = none

    .equ SLOTS,         65
    .equ MAX_UPLOADS,   64
    .equ MAX_SPRITES,   64
    .equ SPRITE_PATTERNS, 0x340
    .equ VRAM_SAT,      0xb800
    .equ PAIR_KEYS,     SPRITE_TILES
    .equ TOP_LINE,      16
    .equ BOTTOM_LINE,   240

sprites_init:
    lea     SLOT_KEY, a0
    moveq   #SLOTS - 1, d0
1:  move.w  #0xffff, (a0)+
    dbra    d0, 1b
    lea     LINE_PAL, a0
    moveq   #-1, d0
    move.b  d0, (a0)+
    move.b  d0, (a0)+
    move.b  d0, (a0)+
    lea     PAL_LINE, a0
    moveq   #15, d1
2:  move.b  d0, (a0)+
    dbra    d1, 2b
    rts

hal_sprites:
    movem.l d0-d7/a0-a6, -(sp)
    tst.w   upload_count
    beq.s   1f
    bsr.w   sprites_flush
1:  addq.w  #1, spr_stamp
    addq.w  #1, hal_tick
    clr.w   since_latch
    bsr.w   bg_update
    bsr.w   text_update
    move.w  #MAX_SPRITES, d0
    btst    #0, hal_tick + 1
    beq.s   2f
    sub.w   text_active, d0
2:  move.w  d0, spr_limit
    lea     SPRITE_RAM, a0
    lea     SAT_BUFFER + 8, a2
    moveq   #1, d7
spr_entry:
    cmpa.l  #SPRITE_END, a0
    bhs.w   spr_end
    move.w  (a0), d0
    bmi.s   1f
    addq.l  #8, a0
    bra.s   spr_entry
1:  move.w  4(a0), d1
    move.w  d0, d2
    lsr.w   #8, d2
    lsr.w   #1, d2
    andi.w  #3, d2
    moveq   #1, d3
    lsl.w   d2, d3
    move.w  d3, spr_cols
    move.w  d0, d2
    lsr.w   #8, d2
    lsr.w   #3, d2
    andi.w  #3, d2
    moveq   #1, d4
    lsl.w   d2, d4
    move.w  d1, d2
    andi.w  #0x1ff, d2
    cmpi.w  #256, d2
    blo.s   2f
    subi.w  #512, d2
2:  neg.w   d2
    addi.w  #240, d2
    move.w  d2, spr_x
    move.w  d0, d2
    andi.w  #0x1ff, d2
    cmpi.w  #256, d2
    blo.s   3f
    subi.w  #512, d2
3:  neg.w   d2
    addi.w  #240, d2
    move.w  d2, spr_y
    moveq   #0, d5
    btst    #13, d0
    beq.s   4f
    ori.w   #0x0800, d5
4:  btst    #14, d0
    beq.s   5f
    ori.w   #0x1000, d5
5:  clr.w   spr_skip
    btst    #11, d1
    beq.s   6f
    btst    #0, spr_stamp + 1
    bne.s   6f
    move.w  #1, spr_skip
6:  move.w  d1, d2
    rol.w   #4, d2
    andi.w  #15, d2
    bsr.w   palette_line
    ror.w   #3, d2
    or.w    d2, d5
spr_column:
    cmpa.l  #SPRITE_END, a0
    bhs.w   spr_end
    tst.w   spr_skip
    bne.w   spr_next_column
    move.w  2(a0), d3
    andi.w  #0x1fff, d3
    move.w  d4, d2
    subq.w  #1, d2
    not.w   d2
    and.w   d2, d3
    move.w  spr_x, d1
    cmpi.w  #-16, d1
    ble.w   spr_next_column
    cmpi.w  #256, d1
    bge.w   spr_next_column
    move.w  d4, d2
    subq.w  #1, d2
    lsl.w   #4, d2
    move.w  spr_y, d0
    sub.w   d2, d0
    cmpi.w  #1, d4
    bne.s   spr_tall
    move.w  d3, d2
    cmpi.w  #SPRITE_TILES, d2
    bhs.w   spr_next_column
    move.w  #0x0500, spr_size
    move.w  #16, spr_height
    bsr.w   spr_emit
    bra.s   spr_next_column
spr_tall:
    clr.w   spr_piece
1:  move.w  spr_piece, d2
    btst    #12, d5
    beq.s   2f
    neg.w   d2
    add.w   d4, d2
    subq.w  #2, d2
2:  add.w   d3, d2
    lsr.w   #1, d2
    cmpi.w  #SPRITE_TILES / 2, d2
    bhs.s   3f
    addi.w  #PAIR_KEYS, d2
    move.w  #0x0700, spr_size
    move.w  #32, spr_height
    bsr.w   spr_emit
3:  addi.w  #32, d0
    addq.w  #2, spr_piece
    cmp.w   spr_piece, d4
    bhi.s   1b
spr_next_column:
    subi.w  #16, spr_x
    addq.l  #8, a0
    subq.w  #1, spr_cols
    bne.w   spr_column
    bra.w   spr_entry
spr_end:
    move.w  d7, spr_game
    bsr.w   text_sprites
    lea     SAT_BUFFER, a2
    clr.w   (a2)+
    move.w  d7, d0
    subq.w  #1, d0
    move.w  d0, (a2)+
    clr.l   (a2)
    bsr.w   palette_assign
    bsr.w   palettes_convert
    move.w  #1, spr_ready
    movem.l (sp)+, d0-d7/a0-a6
    rts

| Called every VBlank. When the game has not latched its sprites for a few frames
| (text screens never do), the tile layers and the text are brought up to date
| here and the text's sprites are put after the last game sprites.
hal_idle:
    addq.w  #1, since_latch
    cmpi.w  #IDLE_FRAMES, since_latch
    blo.s   1f
    clr.w   since_latch
    movem.l d0-d7/a0-a6, -(sp)
    addq.w  #1, hal_tick
    bsr.w   bg_update
    bsr.w   text_update
    move.w  spr_game, d7
    bne.s   2f
    moveq   #1, d7
2:  move.w  d7, d0
    lsl.w   #3, d0
    lea     SAT_BUFFER, a2
    adda.w  d0, a2
    bsr.w   text_sprites
    lea     SAT_BUFFER, a2
    clr.w   (a2)+
    move.w  d7, d0
    subq.w  #1, d0
    move.w  d0, (a2)+
    clr.l   (a2)
    move.w  #1, spr_ready
    movem.l (sp)+, d0-d7/a0-a6
1:  rts

| d2 = key, d0 = top line, d1 = left column, d5 = attributes, a2 = next table entry, d7 = its index.
spr_emit:
    cmp.w   spr_limit, d7
    bhs.s   8f
    cmpi.w  #BOTTOM_LINE, d0
    bge.s   9f
    movea.w d0, a3
    adda.w  spr_height, a3
    cmpa.w  #TOP_LINE, a3
    ble.s   9f
    bsr.w   slot_for
    bmi.s   8f
    move.w  d0, d6
    addi.w  #128 - TOP_LINE, d6
    move.w  d6, (a2)+
    move.w  spr_size, d6
    move.b  d7, d6
    subq.b  #1, d6
    move.w  d6, (a2)+
    or.w    d5, d2
    move.w  d2, (a2)+
    move.w  d1, d6
    addi.w  #128, d6
    move.w  d6, (a2)+
    addq.w  #1, d7
9:  rts
8:  addq.w  #1, spr_dropped
    rts

| d2 = key. Returns the first pattern of its slot in d2, or minus when no slot or upload is free.
slot_for:
    lea     SLOT_OF, a3
    moveq   #0, d6
    move.b  (a3, d2.w), d6
    bne.w   slot_use
    cmpi.w  #MAX_UPLOADS, upload_count
    bhs.w   slot_none
    movem.l d0-d1, -(sp)
    move.w  spr_hand, d0
    move.w  #SLOTS - 1, d1
    lea     SLOT_STAMP, a4
    move.w  spr_stamp, d6
1:  addq.w  #2, d0
    cmpi.w  #SLOTS * 2, d0
    blo.s   2f
    moveq   #0, d0
2:  cmp.w   (a4, d0.w), d6
    bne.s   slot_take
    dbra    d1, 1b
    movem.l (sp)+, d0-d1
slot_none:
    moveq   #-1, d6
    rts
slot_take:
    move.w  d0, spr_hand
    lea     SLOT_KEY, a4
    move.w  (a4, d0.w), d1
    bmi.s   3f
    clr.b   (a3, d1.w)
3:  move.w  d2, (a4, d0.w)
    move.w  d0, d6
    lsr.w   #1, d6
    addq.w  #1, d6
    move.b  d6, (a3, d2.w)
    lea     UPLOADS, a4
    move.w  upload_count, d1
    lsl.w   #3, d1
    adda.w  d1, a4
    addq.w  #1, upload_count
    moveq   #0, d1
    move.w  d2, d1
    cmpi.w  #PAIR_KEYS, d1
    bhs.s   4f
    lsl.l   #7, d1
    addi.l  #GFX_SINGLE, d1
    move.l  d1, (a4)+
    move.w  #64, (a4)+
    bra.s   5f
4:  subi.w  #PAIR_KEYS, d1
    lsl.l   #8, d1
    addi.l  #GFX_PAIR, d1
    move.l  d1, (a4)+
    move.w  #128, (a4)+
5:  lsl.w   #7, d0
    addi.w  #SPRITE_PATTERNS * 32, d0
    move.w  d0, (a4)+
    movem.l (sp)+, d0-d1
slot_use:
    subq.w  #1, d6
    add.w   d6, d6
    lea     SLOT_STAMP, a4
    move.w  spr_stamp, (a4, d6.w)
    lsl.w   #2, d6
    addi.w  #SPRITE_PATTERNS, d6
    move.w  d6, d2
    rts

| d2 = arcade sprite palette (0-15). Returns its palette line (0-1) in d2 and counts the use.
palette_line:
    lea     PAL_COUNT, a3
    addq.b  #1, (a3, d2.w)
    lea     PAL_LINE, a3
    moveq   #0, d6
    move.b  (a3, d2.w), d6
    bpl.s   1f
    moveq   #0, d6
1:  move.w  d6, d2
    rts

| After a list has been walked: the two palettes used by the most sprites own
| lines 0 and 1 (a palette that already has a line keeps it). Every other
| palette in use is shown with the line whose owner's colours are closest to
| its own, pen for pen. Takes effect from the next list.
palette_assign:
    lea     PAL_COUNT, a0
    moveq   #-1, d1
    moveq   #0, d2
    moveq   #-1, d3
    moveq   #0, d4
    moveq   #0, d0
1:  moveq   #0, d5
    move.b  (a0, d0.w), d5
    cmp.w   d2, d5
    bls.s   2f
    move.w  d1, d3
    move.w  d2, d4
    move.w  d0, d1
    move.w  d5, d2
    bra.s   3f
2:  cmp.w   d4, d5
    bls.s   3f
    move.w  d0, d3
    move.w  d5, d4
3:  addq.w  #1, d0
    cmpi.w  #16, d0
    bne.s   1b
    lea     LINE_PAL, a1
    moveq   #0, d5
    move.b  (a1), d5
    moveq   #0, d6
    move.b  1(a1), d6
    cmp.b   d5, d1
    beq.s   4f
    cmp.b   d5, d3
    beq.s   5f
    cmp.b   d6, d1
    beq.s   6f
    cmp.b   d6, d3
    beq.s   7f
    move.b  d1, (a1)
    move.b  d3, 1(a1)
    bra.s   8f
4:  cmp.b   d6, d3
    beq.s   9f
    tst.w   d3
    bmi.s   9f
    move.b  d3, 1(a1)
    bra.s   8f
5:  cmp.b   d6, d1
    beq.s   9f
    move.b  d1, 1(a1)
    bra.s   8f
6:  tst.w   d3
    bmi.s   9f
    move.b  d3, (a1)
    bra.s   8f
7:  move.b  d1, (a1)
8:  lea     PAL_LINE, a2
    moveq   #-1, d0
    move.l  d0, (a2)+
    move.l  d0, (a2)+
    move.l  d0, (a2)+
    move.l  d0, (a2)+
9:  lea     PAL_LINE, a2
    moveq   #0, d0
    move.b  (a1), d0
    bmi.s   1f
    clr.b   (a2, d0.w)
1:  move.b  1(a1), d0
    bmi.s   2f
    move.b  #1, (a2, d0.w)
2:  moveq   #0, d7
3:  tst.b   (a0, d7.w)
    beq.s   6f
    tst.b   (a2, d7.w)
    bpl.s   6f
    moveq   #0, d1
    move.b  (a1), d1
    bmi.s   6f
    bsr.s   palette_distance
    move.l  d2, d6
    moveq   #0, d5
    moveq   #0, d1
    move.b  1(a1), d1
    bmi.s   5f
    bsr.s   palette_distance
    cmp.l   d6, d2
    bhs.s   5f
    moveq   #1, d5
5:  move.b  d5, (a2, d7.w)
6:  clr.b   (a0, d7.w)
    addq.w  #1, d7
    cmpi.w  #16, d7
    bne.s   3b
    rts

| d7 and d1 = two arcade sprite palettes. Returns in d2 how far apart their 15 colours are.
palette_distance:
    movem.l d3-d4/a0-a3, -(sp)
    lea     PALETTE_RG + 0x202, a0
    lea     PALETTE_B + 0x203, a2
    movea.l a0, a1
    movea.l a2, a3
    move.w  d7, d0
    lsl.w   #5, d0
    adda.w  d0, a0
    adda.w  d0, a2
    lsl.w   #5, d1
    adda.w  d1, a1
    adda.w  d1, a3
    moveq   #0, d2
    moveq   #14, d3
1:  moveq   #0, d0
    moveq   #0, d4
    move.b  (a0)+, d0
    move.b  (a1)+, d4
    sub.w   d4, d0
    bpl.s   2f
    neg.w   d0
2:  add.l   d0, d2
    moveq   #0, d0
    move.b  (a0)+, d0
    move.b  (a1)+, d4
    sub.w   d4, d0
    bpl.s   3f
    neg.w   d0
3:  add.l   d0, d2
    moveq   #0, d0
    move.b  (a2), d0
    move.b  (a3), d4
    sub.w   d4, d0
    bpl.s   4f
    neg.w   d0
4:  add.l   d0, d2
    addq.l  #2, a2
    addq.l  #2, a3
    dbra    d3, 1b
    movem.l (sp)+, d3-d4/a0-a3
    rts

| Arcade palette entries (8 bits per channel, red and green in one word, blue in
| another) to the console's 3 bits per channel, for the palettes on lines 0-1.
palettes_convert:
    lea     CRAM_BUFFER, a2
    lea     LINE_PAL, a3
    moveq   #1, d7
1:  moveq   #0, d0
    move.b  (a3)+, d0
    bmi.s   4f
    lsl.w   #5, d0
    lea     PALETTE_RG + 0x200, a0
    adda.w  d0, a0
    lea     PALETTE_B + 0x200, a1
    adda.w  d0, a1
    clr.w   (a2)+
    addq.l  #2, a0
    addq.l  #2, a1
    moveq   #14, d6
2:  move.w  (a0)+, d0
    move.w  (a1)+, d1
    move.w  d0, d2
    lsr.w   #4, d2
    andi.w  #0x00e, d2
    lsr.w   #8, d0
    andi.w  #0x0e0, d0
    or.w    d0, d2
    andi.w  #0x0e0, d1
    lsl.w   #4, d1
    or.w    d1, d2
    move.w  d2, (a2)+
    dbra    d6, 2b
3:  dbra    d7, 1b
    rts
4:  lea     32(a2), a2
    bra.s   3b

| Called at the start of VBlank: sends queued patterns, the sprite table and the palettes.
sprites_flush:
    move.w  upload_count, d0
    beq.s   2f
    lea     UPLOADS, a0
    subq.w  #1, d0
1:  move.l  (a0)+, d1
    move.w  (a0)+, d2
    move.w  (a0)+, d3
    bsr.w   dma_to_vram
    dbra    d0, 1b
    clr.w   upload_count
2:  tst.w   spr_ready
    beq.s   4f
    clr.w   spr_ready
    move.l  #SAT_BUFFER, d1
    move.w  #MAX_SPRITES * 4, d2
    move.w  #VRAM_SAT, d3
    bsr.w   dma_to_vram
    move.l  #0xc0000000, VDP_CTRL
    lea     CRAM_BUFFER, a0
    moveq   #31, d0
3:  move.w  (a0)+, VDP_DATA
    dbra    d0, 3b
4:  rts

| d1 = source address, d2 = length in words, d3 = VRAM address.
dma_to_vram:
    lea     VDP_CTRL, a1
    move.w  #0x9300, d4
    move.b  d2, d4
    move.w  d4, (a1)
    move.w  d2, d4
    lsr.w   #8, d4
    ori.w   #0x9400, d4
    move.w  d4, (a1)
    lsr.l   #1, d1
    move.w  #0x9500, d4
    move.b  d1, d4
    move.w  d4, (a1)
    lsr.l   #8, d1
    move.w  #0x9600, d4
    move.b  d1, d4
    move.w  d4, (a1)
    lsr.l   #8, d1
    andi.w  #0x007f, d1
    ori.w   #0x9700, d1
    move.w  d1, (a1)
    move.w  d3, d4
    andi.w  #0x3fff, d4
    ori.w   #0x4000, d4
    move.w  d4, (a1)
    rol.w   #2, d3
    andi.w  #3, d3
    ori.w   #0x0080, d3
    move.w  d3, (a1)
    rts
