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
    .equ PAL_LINE,      HAL_VARS + 0x32    | 16 bytes: line of each arcade palette, 0xff = its pen table is not built
    .equ SPR_CAND,      0xff1680    | 256 words: the sprite palettes as console colours
    .equ PAL_USE,       0xff1660    | byte per palette: sprites that used it since the palettes were loaded, to 255
    .equ spr_tol,       0xff1670
    .equ spr_left,      0xff1672
    .equ spr_refine,    0xff167a
    .equ spr_conversions, 0xff1674    | counters for the probes
    .equ spr_composes,  0xff1676
    .equ spr_dma_uploads, 0xff1678
    .equ SPR_NIB,       0xff1980    | 16 bytes per palette: pen -> colour on its line
    .equ BYTE_LUT,      0xff1a80    | LUTS tables of 256: a byte of two pens -> a byte of two line colours
    .equ SLOT_PAL,      0xff1f80    | byte per cache slot: palette its patterns were made for, 0 = as in the ROM, 0xfe = out of date
    .equ LUT_PAL,       0xff1fc8    | byte per byte table: its palette, 0xff = none
    .equ PAL_LUT,       0xff1fd0    | byte per palette: its byte table, 0xff = none
    .equ SPR_TMP,       0xff1fe0    | 16 bytes
    .equ spr_seen,      0xff1ff0    | bit per palette met since the sprite palettes were loaded
    .equ spr_pal,       0xff1ff2    | palette of the sprite being placed
    .equ spr_count,     0xff1ff4    | colours chosen for line 1
    .equ spr_n,         0xff1ff6
    .equ spr_err,       0xff1ff8
    .equ spr_conv_left, 0xff1ffa
    .equ spr_lut_hand,  0xff1ffc
    .equ spr_pal_sum,   0xff1ffe
    .equ spr_pal_flag,  HAL_VARS + 0x28
    .equ spr_between,   HAL_VARS + 0x2c
    .equ spr_walk,      HAL_VARS + 0x2e    | 1 = the list is being translated in the game's wait, 2 = it is ready for the latch
    .equ spr_latched,   HAL_VARS + 0x30    | the latch came while it was being translated
    .equ spr_updated,   HAL_VARS + 0x2a    | frame of the last list shown: the bonus stage latches every frame, and one frame is not enough to show each
    .equ LUTS,          5
    .equ CONVERSIONS,   4

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
    lea     LUT_PAL, a0
    moveq   #LUTS - 1, d1
2:  st      (a0)+
    dbra    d1, 2b
    lea     PAL_LUT, a0
    moveq   #15, d1
3:  st      (a0)+
    dbra    d1, 3b

| The sprite palettes have been loaded: forget which were met and what was chosen from them.
spr_palette_reset:
    lea     PAL_USE, a0
    clr.l   (a0)+
    clr.l   (a0)+
    clr.l   (a0)+
    clr.l   (a0)+
    clr.w   spr_seen
    clr.w   spr_count
    lea     CRAM_BUFFER + 32, a0
    moveq   #15, d0
1:  clr.w   (a0)+
    dbra    d0, 1b
    bra.w   spr_tables_stale

| The game's frame waits call this on every turn of their loops (in place of the
| count they keep there, which is kept here). The game has finished its sprite
| list when it waits, and the VBlank handler latches it: translating it here, in
| the time the game would spend waiting, leaves the handler short. With the work
| in the handler the bonus stage, which runs every frame, overran one frame in
| three, and the game skips its own logic for a frame when that happens.
hal_wait:
    addq.w  #1, 0xff8008
    tst.w   0xff8006
    beq.s   9f
    tst.w   spr_walk
    bne.s   9f
    tst.w   spr_ready
    bne.s   9f
    tst.w   upload_count
    bne.s   9f
    movem.l d0-d7/a0-a6, -(sp)
    move.w  hal_frames + 2, d0
    addq.w  #1, d0
    move.w  d0, d1
    sub.w   spr_updated, d0
    cmpi.w  #2, d0
    blo.s   8f
    move.w  #1, spr_walk
    move.w  d1, spr_updated
    addq.w  #1, spr_stamp
    bsr.w   spr_walk_list
    move.w  #2, spr_walk
    tst.w   spr_latched
    beq.s   8f
    clr.w   spr_latched
    clr.w   spr_walk
    move.w  #1, spr_ready
8:  movem.l (sp)+, d0-d7/a0-a6
9:  rts

hal_sprites:
    movem.l d0-d7/a0-a6, -(sp)
    clr.w   since_latch
    cmpi.w  #1, spr_walk
    beq.w   spr_latch_busy
    bhi.w   spr_latch_walked
    tst.w   upload_count
    beq.s   1f
    bsr.w   sprites_flush
1:  move.w  hal_frames + 2, d0
    sub.w   spr_updated, d0
    cmpi.w  #2, d0
    blo.w   spr_not_now
    move.w  hal_frames + 2, spr_updated
    addq.w  #1, spr_stamp
    tst.w   spr_between
    bne.s   6f
    addq.w  #1, hal_tick
    bsr.w   bg_update
    bsr.w   text_update
6:  clr.w   spr_between
    bsr.s   spr_walk_list
    move.w  #1, spr_ready
    movem.l (sp)+, d0-d7/a0-a6
    rts

spr_latch_walked:
    clr.w   spr_walk
    tst.w   spr_between
    bne.s   7f
    addq.w  #1, hal_tick
    bsr.w   bg_update
    bsr.w   text_update
7:  clr.w   spr_between
    move.w  #1, spr_ready
    movem.l (sp)+, d0-d7/a0-a6
    rts

spr_latch_busy:
    move.w  #1, spr_latched
    movem.l (sp)+, d0-d7/a0-a6
    rts

| Sprite RAM to the sprite table and the patterns it needs.
spr_walk_list:
    move.w  #CONVERSIONS, spr_conv_left
    move.w  spr_stamp, d0
    andi.w  #127, d0
    bne.s   4f
    lea     PAL_USE, a0
    moveq   #15, d0
5:  move.b  (a0), d1
    lsr.b   #1, d1
    move.b  d1, (a0)+
    dbra    d0, 5b
4:
    tst.w   spr_pal_flag
    beq.s   3f
    subq.w  #1, spr_pal_flag
    bsr.w   spr_palette_check
3:  move.w  #MAX_SPRITES, d0
    btst    #0, hal_tick + 1
    beq.s   2f
    sub.w   text_active, d0
2:  move.w  d0, spr_limit
    lea     SPRITE_RAM, a0
    lea     SPRITE_END, a6
    lea     SAT_BUFFER + 8, a2
    moveq   #1, d7
    bra.s   spr_entry
0:  addq.l  #8, a0
spr_entry:
    cmpa.l  a6, a0
    bhs.w   spr_end
    move.w  (a0), d0
    bpl.s   0b
    move.w  4(a0), d1
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
6:  tst.w   bg_front
    beq.s   spr_behind
    btst    #2, IO + 0x11
    beq.s   spr_low_palettes
    tst.w   d1
    bmi.s   spr_behind
    bra.s   spr_in_front
spr_low_palettes:
    tst.w   d1
    bpl.s   spr_behind
spr_in_front:
    ori.w   #0x8000, d5
spr_behind:
    move.w  d1, d2
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
    bra.w   palettes_convert

| A list latched the frame after the last one shown (the bonus stage latches every
| frame, and the game skips its own logic whenever a frame's work overruns): the
| list is not shown, and the tile layers and the text are brought up to date now so
| that the next list has the frame to itself.
spr_not_now:
    move.w  #1, spr_between
    addq.w  #1, hal_tick
    bsr.w   bg_update
    bsr.w   text_update
    movem.l (sp)+, d0-d7/a0-a6
    rts

| Called every VBlank. When the game has not latched its sprites for a few frames
| (text screens never do), the tile layers and the text are brought up to date
| here and the text's sprites are put after the last game sprites.
hal_idle:
    addq.w  #1, since_latch
    cmpi.w  #IDLE_FRAMES, since_latch
    blo.s   1f
    tst.w   spr_walk
    bne.s   1f
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
    bne.s   slot_check
slot_miss:
    tst.w   spr_pal
    beq.s   0f
    tst.w   spr_conv_left
    beq.w   slot_none
0:  cmpi.w  #MAX_UPLOADS, upload_count
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
slot_check:
    move.l  d0, -(sp)
    lea     SLOT_PAL - 1, a4
    move.b  (a4, d6.w), d0
    cmp.b   spr_pal + 1, d0
    beq.s   slot_found
    moveq   #0, d6
1:  move.w  d6, d0
    add.w   d0, d0
    lea     SLOT_KEY, a4
    cmp.w   (a4, d0.w), d2
    bne.s   2f
    lea     SLOT_PAL, a4
    move.b  (a4, d6.w), d0
    cmp.b   spr_pal + 1, d0
    bne.s   2f
    addq.w  #1, d6
    move.b  d6, (a3, d2.w)
    bra.s   slot_found
2:  addq.w  #1, d6
    cmpi.w  #SLOTS, d6
    bne.s   1b
    move.l  (sp)+, d0
    bra.w   slot_miss
slot_found:
    move.l  (sp)+, d0
    bra.w   slot_use
slot_take:
    move.w  d0, spr_hand
    lea     SLOT_KEY, a4
    move.w  (a4, d0.w), d1
    bmi.s   3f
    move.w  d0, d6
    lsr.w   #1, d6
    addq.w  #1, d6
    cmp.b   (a3, d1.w), d6
    bne.s   3f
    clr.b   (a3, d1.w)
3:  move.w  d2, (a4, d0.w)
    move.w  d0, d6
    lsr.w   #1, d6
    addq.w  #1, d6
    move.b  d6, (a3, d2.w)
    lea     SLOT_PAL - 1, a4
    move.b  spr_pal + 1, (a4, d6.w)
    tst.w   spr_pal
    beq.s   6f
    subq.w  #1, spr_conv_left
    bsr.w   spr_convert
    movem.l (sp)+, d0-d1
    bra.s   slot_use
6:  addq.w  #1, spr_dma_uploads
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
| d2 = arcade palette of a sprite. Returns its line in d2.
palette_line:
    move.w  d2, spr_pal
    lea     PAL_USE, a3
    cmpi.b  #0xff, (a3, d2.w)
    beq.s   0f
    addq.b  #1, (a3, d2.w)
0:  lea     PAL_LINE, a3
    moveq   #0, d6
    move.b  (a3, d2.w), d6
    bpl.s   1f
    bsr.s   spr_palette_new
1:  move.w  d6, d2
    rts

| A palette whose pen table is missing: when it is not among those line 1 was chosen
| from, line 1 is chosen again from it and the others still in use (the use counts
| halve every 128 lists, so a palette gone for half a minute drops out).
spr_palette_new:
    movem.l d0-d5/d7/a0-a6, -(sp)
    move.w  spr_pal, d0
    move.w  spr_seen, d1
    btst    d0, d1
    bne.s   1f
    lea     PAL_USE, a0
    moveq   #15, d2
2:  tst.b   (a0, d2.w)
    bne.s   3f
    bclr    d2, d1
3:  dbra    d2, 2b
    bset    d0, d1
    move.w  d1, spr_seen
    bsr.w   spr_compose
1:  bsr.w   spr_nib_build
    movem.l (sp)+, d0-d5/d7/a0-a6
    lea     PAL_LINE, a3
    move.w  spr_pal, d6
    move.b  (a3, d6.w), d6
    andi.w  #1, d6
    rts

| The game loads its sprite palettes in one frame at the start of a stage.
spr_palette_check:
    lea     PALETTE_RG + 0x200, a0
    lea     PALETTE_B + 0x200, a1
    moveq   #0, d0
    move.w  #255, d1
1:  add.w   (a0)+, d0
    rol.w   #1, d0
    add.w   (a1)+, d0
    dbra    d1, 1b
    cmp.w   spr_pal_sum, d0
    beq.s   2f
    move.w  d0, spr_pal_sum
    bsr.w   spr_palette_reset
2:  rts

| Line 0 is palette 0, the player's, as it is. Line 1 is up to 15 colours taken
| from the other palettes met so far, most used palette first: a colour is added
| unless one within the tolerance is there already, and the tolerance grows until
| all of them fit (letting only the commonest palettes add colours left the rest
| red and black). The step in tolerance that makes them fit usually leaves colours
| over, so a last pass at the tolerance before it fills what is left: without it
| skin merged into red. Every pen table and every pattern made with one is then out of date.
spr_compose:
    lea     PALETTE_RG + 0x200, a0
    lea     PALETTE_B + 0x200, a1
    lea     SPR_CAND, a2
    move.w  #255, d7
1:  move.w  (a0)+, d0
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
    dbra    d7, 1b
    addq.w  #1, spr_composes
    move.w  #2, spr_tol
    clr.w   spr_refine
spr_compose_try:
    clr.w   spr_count
spr_compose_pass:
    move.w  spr_seen, d5
    bclr    #0, d5
    move.w  d5, spr_left
spr_compose_palette:
    move.w  spr_left, d5
    bne.s   0f
    tst.w   spr_refine
    bne.w   spr_tables_stale
    cmpi.w  #2, spr_tol
    beq.w   spr_tables_stale
    move.w  #1, spr_refine
    subq.w  #2, spr_tol
    bra.s   spr_compose_pass
0:
    lea     PAL_USE, a0
    moveq   #-1, d4
    moveq   #-1, d3
    moveq   #1, d7
2:  btst    d7, d5
    beq.s   3f
    moveq   #0, d0
    move.b  (a0, d7.w), d0
    cmp.w   d3, d0
    ble.s   3f
    move.w  d0, d3
    move.w  d7, d4
3:  addq.w  #1, d7
    cmpi.w  #16, d7
    bne.s   2b
    bclr    d4, d5
    move.w  d5, spr_left
    lsl.w   #5, d4
    lea     SPR_CAND + 2, a6
    adda.w  d4, a6
    moveq   #14, d7
4:  move.w  (a6)+, d0
    movea.w d0, a3
    move.w  d0, d5
    andi.w  #0x00e, d5
    move.w  d0, d6
    lsr.w   #4, d6
    andi.w  #0x00e, d6
    lsr.w   #8, d0
    andi.w  #0x00e, d0
    lea     CRAM_BUFFER + 34, a2
    move.w  spr_count, d3
    bra.s   8f
5:  move.w  (a2), d1
    andi.w  #0x00e, d1
    sub.w   d5, d1
    bpl.s   6f
    neg.w   d1
6:  move.w  (a2), d2
    lsr.w   #4, d2
    andi.w  #0x00e, d2
    sub.w   d6, d2
    bpl.s   7f
    neg.w   d2
7:  add.w   d2, d1
    move.w  (a2)+, d2
    lsr.w   #8, d2
    andi.w  #0x00e, d2
    sub.w   d0, d2
    bpl.s   0f
    neg.w   d2
0:  add.w   d2, d1
    cmp.w   spr_tol, d1
    bls.s   9f
8:  dbra    d3, 5b
    cmpi.w  #15, spr_count
    beq.s   spr_compose_looser
    move.w  a3, (a2)
    addq.w  #1, spr_count
9:  dbra    d7, 4b
    bra.w   spr_compose_palette
spr_compose_looser:
    tst.w   spr_refine
    bne.w   spr_tables_stale
    addq.w  #2, spr_tol
    bra.w   spr_compose_try

spr_tables_stale:
    lea     PAL_LINE, a0
    clr.b   (a0)+
    moveq   #14, d0
1:  st      (a0)+
    dbra    d0, 1b
    lea     PAL_LUT, a0
    moveq   #15, d0
2:  st      (a0)+
    dbra    d0, 2b
    lea     LUT_PAL, a0
    moveq   #LUTS - 1, d0
3:  st      (a0)+
    dbra    d0, 3b
    lea     SLOT_PAL, a0
    lea     SLOT_KEY, a1
    lea     SLOT_OF, a2
    moveq   #0, d7
4:  tst.b   (a0, d7.w)
    beq.s   5f
    move.b  #0xfe, (a0, d7.w)
    move.w  d7, d0
    add.w   d0, d0
    move.w  (a1, d0.w), d1
    bmi.s   5f
    move.w  d7, d2
    addq.w  #1, d2
    cmp.b   (a2, d1.w), d2
    bne.s   5f
    clr.b   (a2, d1.w)
5:  addq.w  #1, d7
    cmpi.w  #SLOTS, d7
    bne.s   4b
    rts

| The pen table of the palette in spr_pal: each pen's nearest colour on line 1 and on
| line 0, and the line with the smaller total is the one its sprites use.
spr_nib_build:
    move.w  spr_pal, d0
    lsl.w   #4, d0
    lea     SPR_NIB, a5
    adda.w  d0, a5
    add.w   d0, d0
    lea     SPR_CAND, a6
    adda.w  d0, a6
    lea     CRAM_BUFFER + 34, a0
    move.w  spr_count, spr_n
    movea.l a5, a1
    bsr.s   spr_match
    move.w  spr_err, d0
    tst.w   spr_count
    bne.s   1f
    move.w  #0x7fff, d0
1:  move.w  d0, -(sp)
    lea     SPR_CAND + 2, a0
    move.w  #15, spr_n
    lea     SPR_TMP, a1
    bsr.s   spr_match
    move.w  (sp)+, d0
    moveq   #1, d1
    cmp.w   spr_err, d0
    bls.s   3f
    moveq   #0, d1
    lea     SPR_TMP, a1
    moveq   #15, d0
2:  move.b  (a1)+, (a5)+
    dbra    d0, 2b
3:  lea     PAL_LINE, a0
    move.w  spr_pal, d0
    move.b  d1, (a0, d0.w)
    rts

| a6 = a palette's 16 colours, a0 = a line's colours from colour 1, spr_n = how many,
| a1 = 16 bytes out. Leaves the sum of the distances in spr_err.
spr_match:
    clr.w   spr_err
    clr.b   (a1)
    moveq   #1, d7
1:  move.w  d7, d0
    add.w   d0, d0
    move.w  (a6, d0.w), d0
    move.w  d0, d5
    andi.w  #0x00e, d5
    move.w  d0, d6
    lsr.w   #4, d6
    andi.w  #0x00e, d6
    lsr.w   #8, d0
    andi.w  #0x00e, d0
    movea.l a0, a2
    move.w  spr_n, d3
    moveq   #1, d4
    movea.w #0x00ff, a3
    suba.l  a4, a4
    bra.s   6f
2:  move.w  (a2), d1
    andi.w  #0x00e, d1
    sub.w   d5, d1
    bpl.s   3f
    neg.w   d1
3:  move.w  (a2), d2
    lsr.w   #4, d2
    andi.w  #0x00e, d2
    sub.w   d6, d2
    bpl.s   4f
    neg.w   d2
4:  add.w   d2, d1
    move.w  (a2)+, d2
    lsr.w   #8, d2
    andi.w  #0x00e, d2
    sub.w   d0, d2
    bpl.s   5f
    neg.w   d2
5:  add.w   d2, d1
    cmpa.w  d1, a3
    bls.s   7f
    movea.w d1, a3
    movea.w d4, a4
7:  addq.w  #1, d4
6:  dbra    d3, 2b
    move.w  a4, d2
    move.b  d2, (a1, d7.w)
    move.w  a3, d2
    add.w   d2, spr_err
    addq.w  #1, d7
    cmpi.w  #16, d7
    bne.s   1b
    rts

| d2 = key, d0 = twice the slot. Writes the slot's patterns to VRAM with every pen
| replaced through the byte table of the palette in spr_pal, 16 words at a time
| with interrupts held off.
spr_convert:
    movem.l d0-d5/a0-a2/a4-a5, -(sp)
    addq.w  #1, spr_conversions
    move.w  spr_pal, d3
    lea     PAL_LUT, a0
    moveq   #0, d4
    move.b  (a0, d3.w), d4
    bpl.s   spr_convert_table
    move.w  spr_lut_hand, d4
    addq.w  #1, d4
    cmpi.w  #LUTS, d4
    blo.s   1f
    moveq   #0, d4
1:  move.w  d4, spr_lut_hand
    lea     LUT_PAL, a1
    moveq   #0, d5
    move.b  (a1, d4.w), d5
    bmi.s   2f
    st      (a0, d5.w)
2:  move.b  d3, (a1, d4.w)
    move.b  d4, (a0, d3.w)
    move.w  d4, d5
    lsl.w   #8, d5
    lea     BYTE_LUT, a5
    adda.w  d5, a5
    lsl.w   #4, d3
    lea     SPR_NIB, a1
    adda.w  d3, a1
    moveq   #0, d3
3:  move.b  (a1, d3.w), d5
    lsl.b   #4, d5
    movea.l a1, a2
    moveq   #15, d1
4:  move.b  (a2)+, d0
    or.b    d5, d0
    move.b  d0, (a5)+
    dbra    d1, 4b
    addq.w  #1, d3
    cmpi.w  #16, d3
    bne.s   3b
    move.w  2(sp), d0
spr_convert_table:
    lsl.w   #8, d4
    lea     BYTE_LUT, a4
    adda.w  d4, a4
    moveq   #0, d1
    move.w  d2, d1
    cmpi.w  #PAIR_KEYS, d1
    bhs.s   5f
    lsl.l   #7, d1
    addi.l  #GFX_SINGLE, d1
    moveq   #64, d2
    bra.s   6f
5:  subi.w  #PAIR_KEYS, d1
    lsl.l   #8, d1
    addi.l  #GFX_PAIR, d1
    move.w  #128, d2
6:  movea.l d1, a0
    lsl.w   #7, d0
    addi.w  #SPRITE_PATTERNS * 32, d0
    moveq   #0, d1
    lea     VDP_DATA, a5
    lea     -32(sp), sp
7:  movea.l sp, a1
    moveq   #7, d3
8:  move.b  (a0)+, d1
    move.b  (a4, d1.w), (a1)+
    move.b  (a0)+, d1
    move.b  (a4, d1.w), (a1)+
    move.b  (a0)+, d1
    move.b  (a4, d1.w), (a1)+
    move.b  (a0)+, d1
    move.b  (a4, d1.w), (a1)+
    dbra    d3, 8b
    movea.l sp, a1
    move.w  d0, d5
    andi.w  #0x3fff, d5
    ori.w   #0x4000, d5
    swap    d5
    move.w  d0, d5
    rol.w   #2, d5
    andi.w  #3, d5
    move.w  sr, d4
    move.w  #0x2700, sr
    move.l  d5, 4(a5)
    move.l  (a1)+, (a5)
    move.l  (a1)+, (a5)
    move.l  (a1)+, (a5)
    move.l  (a1)+, (a5)
    move.l  (a1)+, (a5)
    move.l  (a1)+, (a5)
    move.l  (a1)+, (a5)
    move.l  (a1)+, (a5)
    move.w  d4, sr
    addi.w  #32, d0
    subi.w  #16, d2
    bne.s   7b
    lea     32(sp), sp
    movem.l (sp)+, d0-d5/a0-a2/a4-a5
    rts

| Arcade palette 0 (8 bits per channel, red and green in one word, blue in another)
| to the console's 3 bits per channel on line 0.
palettes_convert:
    lea     CRAM_BUFFER, a2
    lea     PALETTE_RG + 0x202, a0
    lea     PALETTE_B + 0x202, a1
    clr.w   (a2)+
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
    rts

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
