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
    .equ CRAM_BUFFER,   0xffd700    | 48 words: palette lines 0-2
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
    .equ LINE_STAMP,    HAL_VARS + 0x28    | 3 words
    .equ LINE_PAL,      HAL_VARS + 0x2e    | 3 bytes: arcade palette on each line, 0xff = none
    .equ PAL_LINE,      HAL_VARS + 0x32    | 16 bytes: line of each arcade palette, 0xff = none

    .equ SLOTS,         120
    .equ MAX_UPLOADS,   64
    .equ MAX_SPRITES,   64
    .equ SPRITE_PATTERNS, 0x200
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
    move.w  #0x8000, d5
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
    lea     SAT_BUFFER, a2
    clr.w   (a2)+
    move.w  d7, d0
    subq.w  #1, d0
    move.w  d0, (a2)+
    clr.l   (a2)
    bsr.w   palettes_convert
    move.w  #1, spr_ready
    movem.l (sp)+, d0-d7/a0-a6
    rts

| d2 = key, d0 = top line, d1 = left column, d5 = attributes, a2 = next table entry, d7 = its index.
spr_emit:
    cmpi.w  #MAX_SPRITES, d7
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

| d2 = arcade sprite palette (0-15). Returns its palette line (0-2) in d2.
palette_line:
    lea     PAL_LINE, a3
    moveq   #0, d6
    move.b  (a3, d2.w), d6
    bpl.s   3f
    lea     LINE_STAMP, a4
    move.w  spr_stamp, d6
    cmp.w   (a4), d6
    bne.s   1f
    addq.l  #2, a4
    cmp.w   (a4), d6
    bne.s   1f
    addq.l  #2, a4
    cmp.w   (a4), d6
    bne.s   1f
    moveq   #0, d2
    rts
1:  suba.l  #LINE_STAMP, a4
    move.w  a4, d6
    lsr.w   #1, d6
    lea     LINE_PAL, a4
    move.w  d0, -(sp)
    moveq   #0, d0
    move.b  (a4, d6.w), d0
    bmi.s   2f
    st      (a3, d0.w)
2:  move.w  (sp)+, d0
    move.b  d2, (a4, d6.w)
    move.b  d6, (a3, d2.w)
3:  add.w   d6, d6
    lea     LINE_STAMP, a4
    move.w  spr_stamp, (a4, d6.w)
    lsr.w   #1, d6
    move.w  d6, d2
    rts

| Arcade palette entries (8 bits per channel, red and green in one word, blue in
| another) to the console's 3 bits per channel, for the palettes on lines 0-2.
palettes_convert:
    lea     CRAM_BUFFER, a2
    lea     LINE_PAL, a3
    moveq   #2, d7
1:  moveq   #0, d0
    move.b  (a3)+, d0
    bmi.s   4f
    lsl.w   #5, d0
    lea     PALETTE_RG + 0x200, a0
    adda.w  d0, a0
    lea     PALETTE_B + 0x200, a1
    adda.w  d0, a1
    moveq   #15, d6
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
    moveq   #47, d0
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
