| Arcade tile layers 2 and 3 on planes A and B.
| The game writes its two 32x32 maps of 16x16 tiles into RAM. At every sprite
| latch the maps are compared with a copy of what has been drawn; each changed
| tile is drawn as four cells. Tile patterns come from ROM through a cache of
| four-pattern slots keyed by tile and arcade palette, and their pixels are
| renumbered on the way in: layer 2 has palette line 2 and layer 3 line 3, whose
| colours are chosen from the layer's whole palette block when a scene is
| loaded (bg_choose_colours); every pen then takes the nearest one. The text
| shares line 2: three of its colours are kept back for the text, which claims
| them as it needs them. Layer 3 is opaque on the arcade, so it also uses colour 0 of
| its line, shown as the backdrop.

    .equ L2_MAP,        0xff4800
    .equ L3_MAP,        0xff5000
    .equ L2_DRAWN,      0xffd800
    .equ L3_DRAWN,      0xfff200
    .equ BG_HASH,       0xfffa00    | 256 entries: key, slot
    .equ BG_HASH_END,   0xfffe00
    .equ BG_LUT,        0xfffe00    | 32 palettes of 16 pens: colour number on the layer's line
    .equ BG_SLOT_KEY,   0xff0880
    .equ BG_SLOT_REF,   0xff0a20    | cells drawn with each slot
    .equ BG_VARS,       0xff0e00
    .equ bg_hand,       BG_VARS
    .equ bg_uploads_left, BG_VARS + 2
    .equ bg_cells_left, BG_VARS + 4
    .equ bg_pal_sum,    BG_VARS + 6
    .equ bg_line_dirty, BG_VARS + 10
    .equ bg_inexact,    BG_VARS + 12
    .equ bg_plane,      BG_VARS + 14
    .equ bg_full,       BG_VARS + 16
    .equ bg_resets,     BG_VARS + 18
    .equ bg_row,        BG_VARS + 20
    .equ bg_rows_left,  BG_VARS + 22
    .equ bg_cols_left,  BG_VARS + 24
    .equ bg_new_window, BG_VARS + 26
    .equ bg_line_used,  BG_VARS + 28    | 2 words: colours given out on each line
    .equ bg_first,      BG_VARS + 32
    .equ bg_capacity,   BG_VARS + 34
    .equ bg_pal_flag,   BG_VARS + 36
    .equ bg_text_colours, BG_VARS + 38    | colours on line 2 that text asked for
    .equ TEXT_RESERVE,  2
    .equ bg_dark,       BG_VARS + 40    | the tile palettes are all black: nothing is drawn
    .equ bg_loading,    BG_VARS + 42    | a scene is being drawn with the display off; counts down
    .equ LOADING_LATCHES, 8
    .equ bg_full_base,  BG_VARS + 44
    .equ bg_settle,     BG_VARS + 48    | latches to wait after the last palette change before judging the colour tables
    .equ SETTLE_LATCHES, 3
    .equ bg_hold,       BG_VARS + 50    | a scene's palette has arrived: latches left before it is built regardless
    .equ bg_bad,        BG_VARS + 52    | the colour tables have gone wrong: latches left before a rebuild regardless
    .equ HOLD_LATCHES,  12
    .equ DARK_TEARDOWN, 8    | updates with a black palette, while the text has no plane, before the scene is given up so that it can have one
    .equ BG_KNOWN,      0xff1070    | per layer: the palettes whose pens have a line colour each, or all ones
    .equ bg_front,      BG_VARS + 62    | 0x8000 while the arcade draws some sprites behind layer 2
    .equ BG_SIGNATURE,  BG_VARS + 54    | per layer: palettes its map used and the map's checksum when its colours were chosen
    .equ NEAR,          1
    .equ CANDIDATES,    0xff1300    | 256 words: a palette block as console colours
    .equ FARNESS,       0xff1500    | 256 bytes: each one's distance from the colours chosen so far
    .equ BG_FULL,       0xff1240    | 32 longs: the arcade colour (red, green, blue) each line colour was given for
    .equ BG_LINE,       0xff0dc0    | 32 words: palette lines 2 and 3 as sent to the console
    .equ BG_OWNER,      0xff0d80    | 32 words: the arcade palette entry each colour follows
    .equ BG_LUT_OK,     0xff0c20    | 32 bytes
    .equ BG_LAYER2,     0xff0c40    | per layer: map, drawn copy, valid bits, registers, key bit, plane, window, redraw flag
    .equ BG_LAYER3,     0xff0c5a
    .equ L2_VALID,      0xff0c80    | bit per map entry: its cells in VRAM show the drawn copy
    .equ L3_VALID,      0xff0d00
    .equ LAYER_MAP,     0
    .equ LAYER_DRAWN,   4
    .equ LAYER_VALID,   8
    .equ LAYER_REGS,    12
    .equ LAYER_BIT,     16
    .equ LAYER_PLANE,   18
    .equ LAYER_WINDOW,  20
    .equ LAYER_REDRAW,  22
    .equ LAYER_COUNT,   24    | cells drawn with a tile that is not blank

    .equ BG_SLOTS,      207
    .equ BG_PATTERNS,   4
    .equ BG_UPLOADS,    8
    .equ BG_CELLS,      160
    .equ BG_PALETTES,   PALETTE_RG + 0x400
    .equ BG_BLUES,      PALETTE_B + 0x400
    .equ L3_TILES,      2048
    .equ EMPTY,         0xffff
    .equ DELETED,       0xfffe
    .equ WINDOW_COLS,   19
    .equ WINDOW_ROWS,   17

bg_reset:
    addq.w  #1, bg_resets
    move.w  #LOADING_LATCHES, bg_loading
    clr.w   bg_hold
    clr.w   bg_bad
    clr.l   bg_line_used
    clr.w   bg_text_colours
    clr.w   bg_inexact
    move.w  #1, bg_line_dirty
    move.w  #4, bg_pal_flag
    lea     BG_LINE, a0
    moveq   #31, d0
1:  clr.w   (a0)+
    dbra    d0, 1b
    lea     BG_LUT_OK, a0
    moveq   #7, d0
2:  clr.l   (a0)+
    dbra    d0, 2b
    moveq   #-1, d1
    lea     BG_HASH, a0
    move.w  #255, d0
3:  move.l  d1, (a0)+
    dbra    d0, 3b
    lea     BG_SLOT_KEY, a0
    lea     BG_SLOT_REF, a1
    move.w  #BG_SLOTS - 1, d0
4:  move.w  d1, (a0)+
    clr.w   (a1)+
    dbra    d0, 4b
    lea     L2_DRAWN, a0
    lea     L3_DRAWN, a1
    move.w  #511, d0
5:  move.l  d1, (a0)+
    move.l  d1, (a1)+
    dbra    d0, 5b
    lea     L2_VALID, a0
    moveq   #63, d0
6:  clr.l   (a0)+
    dbra    d0, 6b
    lea     BG_LAYER2, a0
    move.l  #L2_MAP, (a0)+
    move.l  #L2_DRAWN, (a0)+
    move.l  #L2_VALID, (a0)+
    move.l  #PF2_REGS, (a0)+
    move.w  #0, (a0)+
    move.w  #0xc000, (a0)+
    move.w  d1, (a0)+
    move.w  #1, (a0)+
    clr.w   (a0)+
    move.l  #L3_MAP, (a0)+
    move.l  #L3_DRAWN, (a0)+
    move.l  #L3_VALID, (a0)+
    move.l  #PF3_REGS, (a0)+
    move.w  #0x0800, (a0)+
    move.w  #0xe000, (a0)+
    move.w  d1, (a0)+
    move.w  #1, (a0)+
    clr.w   (a0)+
    move.l  #0x40000003, VDP_CTRL
    move.w  #0x0fff, d0
7:  move.l  #0, VDP_DATA
    dbra    d0, 7b
    moveq   #0, d0
    bsr.w   bg_choose_colours
    moveq   #16, d0
    bsr.w   bg_choose_colours
    bra.w   text_invalidate

bg_update:
    moveq   #0, d0
    btst    #1, IO + 0x11
    beq.s   1f
    move.w  #0x8000, d0
1:  cmp.w   bg_front, d0
    beq.s   2f
    move.w  d0, bg_front
    lea     BG_LAYER2, a5
    bsr.w   bg_layer_invalidate
2:  bsr.w   bg_palette_check
    bsr.w   bg_palette_wait
    tst.w   bg_dark
    beq.s   0f
    cmpi.w  #DARK_TEARDOWN, bg_dark
    bhs.w   5f
    tst.w   text_plane
    bne.w   5f
    addq.w  #1, bg_dark
    cmpi.w  #DARK_TEARDOWN, bg_dark
    bne.w   5f
    bsr.w   bg_reset
    clr.w   bg_loading
    bra.w   5f
0:
    tst.w   bg_hold
    bne.w   5f
    tst.w   bg_loading
    beq.s   4f
    subq.w  #1, bg_loading
    move.w  #0x7fff, bg_uploads_left
    move.w  #0x7fff, bg_cells_left
    lea     BG_LAYER2, a5
    bsr.w   bg_layer
    lea     BG_LAYER3, a5
    bsr.w   bg_layer
    lea     BG_LAYER2, a5
    tst.w   LAYER_REDRAW(a5)
    bne.s   5f
    lea     BG_LAYER3, a5
    tst.w   LAYER_REDRAW(a5)
    bne.s   5f
    clr.w   bg_loading
    bra.s   5f
4:  move.w  #BG_UPLOADS, bg_uploads_left
    move.w  #BG_CELLS, bg_cells_left
    lea     BG_LAYER2, a5
    btst    #0, hal_tick + 1
    beq.s   3f
    lea     BG_LAYER3, a5
3:  bsr.w   bg_layer
5:  tst.w   bg_line_dirty
    beq.s   2f
    clr.w   bg_line_dirty
    move.l  #0xc0400000, VDP_CTRL
    lea     BG_LINE, a0
    moveq   #31, d0
1:  move.w  (a0)+, VDP_DATA
    dbra    d0, 1b
2:  rts

| a5 = layer. Notes the map entries the game changed, releases the tiles that
| left the window when it moved, and draws what the window still lacks.
bg_layer:
    movea.l LAYER_MAP(a5), a0
    movea.l LAYER_DRAWN(a5), a1
    movea.l LAYER_VALID(a5), a6
    move.w  LAYER_BIT(a5), d5
    move.w  LAYER_PLANE(a5), bg_plane
    move.w  #511, d7
1:  cmpm.l  (a0)+, (a1)+
    dbne    d7, 1b
    beq.s   2f
    subq.l  #4, a0
    subq.l  #4, a1
    moveq   #1, d4
7:  cmpm.w  (a0)+, (a1)+
    beq.s   8f
    move.l  a0, d6
    sub.l   LAYER_MAP(a5), d6
    lsr.w   #1, d6
    subq.w  #1, d6
    move.w  d4, -(sp)
    move.w  -2(a1), d0
    bsr.w   bg_release
    move.w  (sp)+, d4
    move.w  -2(a0), -2(a1)
    move.w  #1, LAYER_REDRAW(a5)
8:  dbra    d4, 7b
    dbra    d7, 1b
2:  movea.l LAYER_MAP(a5), a0
    movea.l LAYER_DRAWN(a5), a1
    movea.l LAYER_REGS(a5), a2
    move.w  0x10(a2), d0
    lsr.w   #4, d0
    subq.w  #1, d0
    andi.w  #31, d0
    move.w  0x12(a2), d1
    addi.w  #TOP_LINE, d1
    lsr.w   #4, d1
    subq.w  #1, d1
    andi.w  #31, d1
    lsl.w   #8, d1
    or.w    d0, d1
    move.w  LAYER_WINDOW(a5), d2
    cmp.w   d1, d2
    beq.w   bg_layer_draw
    move.w  d1, LAYER_WINDOW(a5)
    move.w  #1, LAYER_REDRAW(a5)
    cmpi.w  #EMPTY, d2
    beq.w   bg_layer_draw
    move.w  d1, bg_new_window
    move.w  d2, d6
    andi.w  #31, d6
    lsr.w   #8, d2
    move.w  d2, bg_row
    move.w  #WINDOW_ROWS, bg_rows_left
3:  move.w  #WINDOW_COLS, bg_cols_left
    move.w  d6, -(sp)
4:  move.w  bg_new_window, d0
    move.w  d6, d1
    sub.w   d0, d1
    andi.w  #31, d1
    cmpi.w  #WINDOW_COLS, d1
    bhs.s   5f
    lsr.w   #8, d0
    move.w  bg_row, d1
    sub.w   d0, d1
    andi.w  #31, d1
    cmpi.w  #WINDOW_ROWS, d1
    blo.s   6f
5:  bsr.w   bg_index
    move.w  d6, d4
    move.w  d7, d6
    lsr.w   #1, d6
    move.w  (a1, d7.w), d0
    bsr.w   bg_release
    move.w  d4, d6
6:  bsr.w   bg_next_column
    bne.s   4b
    move.w  (sp)+, d6
    addq.w  #1, bg_row
    andi.w  #31, bg_row
    subq.w  #1, bg_rows_left
    bne.s   3b
bg_layer_draw:
    tst.w   LAYER_REDRAW(a5)
    beq.s   9f
    clr.w   LAYER_REDRAW(a5)
    move.w  LAYER_WINDOW(a5), d6
    move.w  d6, d0
    lsr.w   #8, d0
    move.w  d0, bg_row
    andi.w  #31, d6
    move.w  #WINDOW_ROWS, bg_rows_left
7:  move.w  #WINDOW_COLS, bg_cols_left
    move.w  d6, -(sp)
8:  bsr.w   bg_index
    move.w  d7, d0
    lsr.w   #1, d0
    move.w  d0, d1
    lsr.w   #3, d0
    btst    d1, (a6, d0.w)
    bne.s   1f
    bsr.w   bg_draw
    bpl.s   1f
    move.w  #1, LAYER_REDRAW(a5)
    addq.l  #2, sp
    rts
1:  bsr.w   bg_next_column
    bne.s   8b
    move.w  (sp)+, d6
    addq.w  #1, bg_row
    andi.w  #31, bg_row
    subq.w  #1, bg_rows_left
    bne.s   7b
9:  rts

| d6 = column, bg_row = row. Returns twice the map index in d7.
bg_index:
    move.w  bg_row, d7
    lsl.w   #4, d7
    move.w  d6, d0
    andi.w  #15, d0
    add.w   d0, d7
    btst    #4, d6
    beq.s   1f
    addi.w  #0x200, d7
1:  add.w   d7, d7
    rts

bg_next_column:
    addq.w  #1, d6
    andi.w  #31, d6
    subq.w  #1, bg_cols_left
    rts

| d6 = map index, d0 = the word drawn there. If its cells are in VRAM, gives the tile's slot back.
bg_release:
    move.w  d6, d1
    lsr.w   #3, d1
    btst    d6, (a6, d1.w)
    beq.s   2f
    bclr    d6, (a6, d1.w)
    bsr.w   bg_key
    lea     GFX_BLANK, a2
    tst.b   (a2, d3.w)
    bne.s   2f
    bsr.w   bg_hash_find
    bne.s   2f
    move.w  2(a3), d0
    add.w   d0, d0
    lea     BG_SLOT_REF, a2
    tst.w   (a2, d0.w)
    beq.s   2f
    subq.w  #1, (a2, d0.w)
    subq.w  #1, LAYER_COUNT(a5)
2:  rts

| d7 = twice the map index. Draws the tile recorded there as four cells. Minus when it could not.
bg_draw:
    tst.w   bg_cells_left
    beq.w   bg_draw_none
    move.w  (a1, d7.w), d0
    bsr.w   bg_key
    lea     GFX_BLANK, a2
    moveq   #0, d4
    tst.b   (a2, d3.w)
    bne.s   1f
    bsr.w   bg_slot_for
    bmi.w   bg_draw_none
    lea     BG_SLOT_REF, a2
    move.w  d4, d0
    add.w   d0, d0
    addq.w  #1, (a2, d0.w)
    addq.w  #1, LAYER_COUNT(a5)
    lsl.w   #2, d4
    addi.w  #BG_PATTERNS + 0x4000, d4
    tst.w   d5
    bne.s   9f
    or.w    bg_front, d4
    bra.s   1f
9:  addi.w  #0x2000, d4
1:  move.w  d7, d0
    lsr.w   #1, d0
    move.w  d0, d1
    lsr.w   #3, d1
    bset    d0, (a6, d1.w)
    tst.w   d4
    bne.s   7f
    move.w  LAYER_PLANE(a5), d1
    cmp.w   text_plane, d1
    beq.w   6f
7:  move.w  d0, d1
    lsr.w   #4, d1
    andi.w  #31, d1
    lsl.w   #8, d1
    move.w  d0, d2
    andi.w  #15, d2
    btst    #9, d0
    beq.s   4f
    addi.w  #16, d2
4:  lsl.w   #2, d2
    add.w   d2, d1
    add.w   bg_plane, d1
    andi.w  #0x3fff, d1
    ori.w   #0x4000, d1
    swap    d1
    move.w  #3, d1
    move.l  d1, VDP_CTRL
    move.w  d4, d2
    beq.s   5f
    move.w  d2, VDP_DATA
    addq.w  #1, d2
    move.w  d2, VDP_DATA
    addq.w  #1, d2
    addi.l  #0x00800000, d1
    move.l  d1, VDP_CTRL
    move.w  d2, VDP_DATA
    addq.w  #1, d2
    move.w  d2, VDP_DATA
    bra.s   6f
5:  move.l  #0, VDP_DATA
    addi.l  #0x00800000, d1
    move.l  d1, VDP_CTRL
    move.l  #0, VDP_DATA
6:  subq.w  #1, bg_cells_left
    moveq   #0, d0
    rts
bg_draw_none:
    moveq   #-1, d0
    rts

| d0 = map word, d5 = layer bit. Returns the cache key in d2 and the tile number in the ROM set in d3.
bg_key:
    move.w  d0, d2
    andi.w  #0xf000, d2
    tst.w   d5
    bne.s   1f
    andi.w  #0x07ff, d0
    or.w    d0, d2
    move.w  d0, d3
    rts
1:  andi.w  #0x03ff, d0
    or.w    d0, d2
    ori.w   #0x0800, d2
    move.w  d0, d3
    addi.w  #L3_TILES, d3
    rts

| d2 = key. Z set and a3 = its entry when the key is in the table.
bg_hash_find:
    move.w  d2, d0
    lsr.w   #5, d0
    eor.w   d2, d0
    andi.w  #0xff, d0
    lsl.w   #2, d0
    lea     BG_HASH, a3
    adda.w  d0, a3
    move.w  #255, d1
1:  move.w  (a3), d0
    cmp.w   d2, d0
    beq.s   3f
    cmpi.w  #EMPTY, d0
    beq.s   2f
    addq.l  #4, a3
    cmpa.l  #BG_HASH_END, a3
    blo.s   4f
    lea     BG_HASH, a3
4:  dbra    d1, 1b
2:  moveq   #1, d0
3:  rts

| d2 = key, d4 = slot.
bg_hash_insert:
    move.w  d2, d0
    lsr.w   #5, d0
    eor.w   d2, d0
    andi.w  #0xff, d0
    lsl.w   #2, d0
    lea     BG_HASH, a3
    adda.w  d0, a3
1:  cmpi.w  #DELETED, (a3)
    bhs.s   2f
    addq.l  #4, a3
    cmpa.l  #BG_HASH_END, a3
    blo.s   1b
    lea     BG_HASH, a3
    bra.s   1b
2:  move.w  d2, (a3)
    move.w  d4, 2(a3)
    rts

| d2 = key, d3 = tile number, d5 = layer bit. Returns the slot in d4, or minus
| when the tile is not in VRAM and nothing more may be loaded this time.
bg_slot_for:
    bsr.w   bg_hash_find
    bne.s   1f
    move.w  2(a3), d4
    rts
1:  tst.w   bg_uploads_left
    beq.s   bg_slot_none
    move.w  bg_hand, d0
    move.w  #BG_SLOTS - 1, d1
    lea     BG_SLOT_REF, a2
2:  addq.w  #2, d0
    cmpi.w  #BG_SLOTS * 2, d0
    blo.s   3f
    moveq   #0, d0
3:  tst.w   (a2, d0.w)
    beq.s   4f
    dbra    d1, 2b
    addq.w  #1, bg_full
bg_slot_none:
    clr.w   bg_cells_left
    moveq   #-1, d4
    rts
4:  move.w  d0, bg_hand
    move.w  d0, d4
    lea     BG_SLOT_KEY, a2
    move.w  (a2, d4.w), d1
    cmpi.w  #EMPTY, d1
    beq.s   6f
    move.w  d2, -(sp)
    move.w  d1, d2
    bsr.w   bg_hash_find
    bne.s   5f
    move.w  #DELETED, (a3)
5:  move.w  (sp)+, d2
6:  lea     BG_SLOT_KEY, a2
    move.w  d2, (a2, d4.w)
    lsr.w   #1, d4
    bsr.w   bg_hash_insert
    move.w  d2, d0
    rol.w   #4, d0
    andi.w  #15, d0
    tst.w   d5
    beq.s   7f
    addi.w  #16, d0
7:  lea     BG_LUT_OK, a2
    tst.b   (a2, d0.w)
    bne.s   8f
    bsr.w   bg_lut_build
8:  lsl.w   #4, d0
    lea     BG_LUT, a4
    adda.w  d0, a4
    move.w  d4, d0
    lsl.w   #7, d0
    addi.w  #BG_PATTERNS * 32, d0
    move.w  d0, d1
    andi.w  #0x3fff, d1
    ori.w   #0x4000, d1
    swap    d1
    rol.w   #2, d0
    andi.w  #3, d0
    move.w  d0, d1
    move.l  d1, VDP_CTRL
    moveq   #0, d0
    move.w  d3, d0
    lsl.l   #7, d0
    addi.l  #GFX_TILES, d0
    movea.l d0, a2
    move.w  d4, -(sp)
    move.w  d6, -(sp)
    moveq   #63, d6
9:  moveq   #0, d0
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
    dbra    d6, 9b
    move.w  (sp)+, d6
    move.w  (sp)+, d4
    subq.w  #1, bg_uploads_left
    tst.w   d4
    rts

| d0 = arcade red and green word, d1 = blue word. Returns the console colour in d2.
colour9:
    move.w  d0, d2
    lsr.w   #4, d2
    andi.w  #0x00e, d2
    lsr.w   #8, d0
    andi.w  #0x0e0, d0
    or.w    d0, d2
    andi.w  #0x0e0, d1
    lsl.w   #4, d1
    or.w    d1, d2
    rts

| d0 = palette number (0-15 layer 2, 16-31 layer 3, 32 up the text, which uses the line
| of the layer whose plane it is on, or line 2 when it is drawn with sprites).
| Returns a3 = the layer's line, a4 = its owner table, a5 = its count, and sets bg_first and bg_capacity.
bg_line_for:
    lea     BG_LINE, a3
    lea     BG_OWNER, a4
    lea     bg_line_used, a5
    move.l  #BG_FULL, bg_full_base
    move.w  #1, bg_first
    move.w  #15, bg_capacity
    cmpi.w  #32, d0
    blo.s   3f
    cmpi.w  #0xe000, text_plane
    bne.s   1f
    lea     32(a3), a3
    lea     32(a4), a4
    addq.l  #2, a5
    move.l  #BG_FULL + 64, bg_full_base
    rts
3:  cmpi.w  #16, d0
    blo.s   1f
    lea     32(a3), a3
    lea     32(a4), a4
    addq.l  #2, a5
    move.l  #BG_FULL + 64, bg_full_base
    clr.w   bg_first
    move.w  #16, bg_capacity
1:  rts

| d0 = palette number. Fills its 16 pens' colour numbers.
bg_lut_build:
    movem.l d0-d7/a0-a6, -(sp)
    bsr.w   bg_line_for
    cmpi.w  #32, d0
    blo.s   1f
    move.w  d0, d7
    subi.w  #64, d7
    lsl.w   #5, d7
    lea     BG_PALETTES, a0
    adda.w  d7, a0
    lea     BG_BLUES, a1
    adda.w  d7, a1
    move.w  d0, d7
    subi.w  #32, d7
    lsl.w   #4, d7
    lea     TEXT_LUT, a2
    adda.w  d7, a2
    bra.s   2f
1:  lea     BG_LUT_OK, a2
    st      (a2, d0.w)
    lea     BG_KNOWN, a2
    move.w  d0, d7
    lsr.w   #3, d7
    andi.w  #2, d7
    move.w  (a2, d7.w), d7
    move.w  d0, d6
    andi.w  #15, d6
    btst    d6, d7
    bne.s   3f
    tst.w   bg_bad
    bne.s   3f
    move.w  #2, bg_bad
3:  move.w  d0, d7
    lsl.w   #5, d7
    lea     BG_PALETTES, a0
    adda.w  d7, a0
    lea     BG_BLUES, a1
    adda.w  d7, a1
    lsr.w   #1, d7
    lea     BG_LUT, a2
    adda.w  d7, a2
2:  moveq   #0, d6
bg_lut_pen:
    move.w  (a0)+, d0
    move.w  (a1)+, d1
    move.w  d0, d7
    swap    d7
    move.w  d1, d7
    andi.w  #0x00ff, d7
    bsr.w   colour9
    tst.w   d6
    bne.s   1f
    tst.w   bg_first
    beq.s   1f
    clr.b   (a2)+
    bra.w   bg_lut_next
1:  move.l  a0, d0
    subi.l  #BG_PALETTES + 2, d0
    move.w  bg_first, d4
    move.w  d4, d1
    add.w   d1, d1
    lea     (a4, d1.w), a6
    move.w  (a5), d3
    bra.s   3f
2:  cmp.w   (a6)+, d0
    beq.w   bg_lut_got
    addq.w  #1, d4
3:  dbra    d3, 2b
    move.w  bg_first, d4
    move.w  d4, d0
    lsl.w   #2, d0
    movea.l bg_full_base, a6
    adda.w  d0, a6
    move.w  (a5), d3
    bra.s   3f
2:  cmp.l   (a6)+, d7
    beq.w   bg_lut_got
    addq.w  #1, d4
3:  dbra    d3, 2b
    bsr.w   bg_nearest
    cmpi.w  #32, 2(sp)
    blo.w   bg_lut_near
    cmpi.w  #NEAR, d5
    bls.w   bg_lut_near
    move.w  (a5), d0
    cmp.w   bg_capacity, d0
    bhs.w   bg_lut_near
    move.w  (a5), d4
    add.w   bg_first, d4
    move.w  d4, d0
    lsl.w   #2, d0
    movea.l bg_full_base, a6
    adda.w  d0, a6
    addq.w  #1, (a5)
    cmpi.w  #32, 2(sp)
    blo.s   2f
    addq.w  #1, bg_text_colours
2:  move.l  d7, (a6)
    move.w  d4, d1
    add.w   d1, d1
    move.w  d2, (a3, d1.w)
    move.l  a0, d0
    subi.l  #BG_PALETTES + 2, d0
    move.w  d4, d1
    add.w   d1, d1
    move.w  d0, (a4, d1.w)
    move.w  #1, bg_line_dirty
    bra.s   bg_lut_got
bg_lut_near:
    addq.w  #1, bg_inexact
bg_lut_got:
    move.b  d4, (a2)+
bg_lut_next:
    addq.w  #1, d6
    cmpi.w  #16, d6
    bne.w   bg_lut_pen
    movem.l (sp)+, d0-d7/a0-a6
    rts

| d0 = 0 (layer 2) or 16 (layer 3). Returns in d5 the arcade palettes that layer's
| map uses (blank tiles apart) and in d4 a checksum of the map.
bg_map_signature:
    lea     L2_MAP, a2
    tst.w   d0
    beq.s   1f
    lea     L3_MAP, a2
1:  moveq   #0, d5
    moveq   #0, d4
    lea     GFX_BLANK, a6
    move.w  #1023, d3
2:  move.w  (a2)+, d1
    add.w   d1, d4
    rol.w   #1, d4
    move.w  d1, d2
    andi.w  #0x07ff, d2
    tst.w   d0
    beq.s   3f
    andi.w  #0x03ff, d2
    addi.w  #L3_TILES, d2
3:  tst.b   (a6, d2.w)
    bne.s   4f
    rol.w   #4, d1
    andi.w  #15, d1
    bset    d1, d5
4:  dbra    d3, 2b
    rts

| Z set when both maps are as they were when their colours were chosen.
bg_scene_same:
    moveq   #0, d0
    bsr.s   bg_map_signature
    lea     BG_SIGNATURE, a0
    cmp.w   (a0), d5
    bne.s   1f
    cmp.w   2(a0), d4
    bne.s   1f
    moveq   #16, d0
    bsr.s   bg_map_signature
    lea     BG_SIGNATURE, a0
    cmp.w   4(a0), d5
    bne.s   1f
    cmp.w   6(a0), d4
1:  rts

| d0 = 0 (layer 2) or 16 (layer 3). Fills that layer's palette line from the
| arcade palettes its map uses. If their pens fit on the line each gets a colour
| of its own, whatever it is at the moment: such a scene follows any fade or
| palette animation exactly. Otherwise, starting from black if there is one, the
| colour farthest from all those already chosen is added until the line is
| full: hues that stand apart get a place however late their tiles come into
| view, close shades share.
bg_choose_colours:
    bsr.w   bg_line_for
    move.w  #15, bg_capacity
    tst.w   text_plane
    bne.s   9f
    move.w  #15 - TEXT_RESERVE, bg_capacity
9:  lea     BG_PALETTES, a0
    lea     BG_BLUES, a1
    tst.w   d0
    beq.s   1f
    move.w  #16, bg_capacity
    lea     0x200(a0), a0
    lea     0x200(a1), a1
1:  bsr.w   bg_map_signature
    lea     BG_SIGNATURE, a2
    move.w  d0, d1
    lsr.w   #2, d1
    move.w  d5, (a2, d1.w)
    move.w  d4, 2(a2, d1.w)
    lea     CANDIDATES, a2
    lea     FARNESS, a6
    moveq   #0, d6
    moveq   #0, d7
3:  move.w  (a0)+, d0
    move.w  (a1)+, d1
    bsr.w   colour9
    move.w  d2, (a2)+
    moveq   #0, d1
    move.w  d7, d0
    lsr.w   #4, d0
    btst    d0, d5
    beq.s   5f
    move.w  d7, d0
    andi.w  #15, d0
    bne.s   4f
    tst.w   bg_first
    bne.s   5f
4:  moveq   #0x7f, d1
    addq.w  #1, d6
5:  move.b  d1, (a6)+
    addq.w  #1, d7
    cmpi.w  #256, d7
    bne.s   3b
    clr.w   (a5)
    lea     BG_KNOWN, a2
    tst.w   bg_first
    bne.s   6f
    addq.l  #2, a2
6:  move.w  #-1, (a2)
    cmp.w   bg_capacity, d6
    bhi.s   bg_choose_far
    move.w  d5, (a2)
    moveq   #0, d4
7:  lea     FARNESS, a6
    tst.b   (a6, d4.w)
    beq.s   8f
    bsr.w   bg_choose_take
8:  addq.w  #1, d4
    cmpi.w  #256, d4
    bne.s   7b
    bra.w   bg_choose_done
bg_choose_far:
    lea     CANDIDATES, a2
    lea     FARNESS, a6
    moveq   #-1, d4
    moveq   #0, d3
1:  tst.b   (a6)+
    beq.s   3f
    tst.w   d4
    bpl.s   2f
    move.w  d3, d4
2:  tst.w   (a2)
    bne.s   3f
    move.w  d3, d4
    bra.s   bg_choose_next
3:  addq.l  #2, a2
    addq.w  #1, d3
    cmpi.w  #256, d3
    bne.s   1b
    tst.w   d4
    bmi.w   bg_choose_done
bg_choose_next:
    move.w  (a5), d0
    cmp.w   bg_capacity, d0
    bhs.w   bg_choose_done
    bsr.w   bg_choose_take
    move.w  d2, d5
    andi.w  #0x00e, d5
    move.w  d2, d6
    lsr.w   #4, d6
    andi.w  #0x00e, d6
    move.w  d2, d7
    lsr.w   #8, d7
    andi.w  #0x00e, d7
    lea     CANDIDATES, a2
    moveq   #0, d4
    suba.l  a1, a1
    moveq   #0, d2
2:  move.w  (a2)+, d0
    tst.b   (a6)
    beq.s   6f
    move.w  d0, d1
    andi.w  #0x00e, d1
    sub.w   d5, d1
    bpl.s   3f
    neg.w   d1
3:  move.w  d0, d3
    lsr.w   #4, d3
    andi.w  #0x00e, d3
    sub.w   d6, d3
    bpl.s   4f
    neg.w   d3
4:  add.w   d3, d1
    lsr.w   #8, d0
    andi.w  #0x00e, d0
    sub.w   d7, d0
    bpl.s   5f
    neg.w   d0
5:  add.w   d0, d1
    cmp.b   (a6), d1
    bhs.s   7f
    move.b  d1, (a6)
7:  cmp.b   (a6), d4
    bhs.s   6f
    move.b  (a6), d4
    movea.w d2, a1
6:  addq.l  #1, a6
    addq.w  #1, d2
    cmpi.w  #256, d2
    bne.s   2b
    tst.b   d4
    beq.s   bg_choose_done
    move.w  a1, d4
    bra.w   bg_choose_next
bg_choose_done:
    move.w  #1, bg_line_dirty
    rts

| d4 = a colour's place in the palette block. Puts it on the line as the next colour; returns it in d2.
bg_choose_take:
    move.w  (a5), d0
    add.w   bg_first, d0
    addq.w  #1, (a5)
    move.w  d4, d1
    add.w   d1, d1
    lea     CANDIDATES, a2
    move.w  (a2, d1.w), d2
    move.w  d0, d3
    add.w   d3, d3
    move.w  d2, (a3, d3.w)
    tst.w   bg_first
    bne.s   1f
    addi.w  #0x200, d1
1:  move.w  d1, (a4, d3.w)
    lea     BG_PALETTES, a0
    lea     BG_BLUES, a1
    movea.l bg_full_base, a2
    add.w   d3, d3
    move.w  (a0, d1.w), (a2, d3.w)
    move.w  (a1, d1.w), d0
    andi.w  #0x00ff, d0
    move.w  d0, 2(a2, d3.w)
    lea     FARNESS, a6
    clr.b   (a6, d4.w)
    rts

| d2 = console colour, a3 = the layer's line, a5 = its count. Returns the closest
| colour already on the line in d4 and how far it is in d5 (999 when the line is empty).
bg_nearest:
    move.l  d7, -(sp)
    move.w  bg_first, d3
    move.w  d3, d0
    add.w   d0, d0
    lea     (a3, d0.w), a6
    move.w  (a5), d1
    add.w   d3, d1
    move.w  d1, -(sp)
    move.w  #999, d5
4:  cmp.w   (sp), d3
    bhs.s   3f
5:  moveq   #0, d1
    move.w  (a6), d0
    andi.w  #0x00e, d0
    move.w  d2, d7
    andi.w  #0x00e, d7
    sub.w   d0, d7
    bpl.s   6f
    neg.w   d7
6:  add.w   d7, d1
    move.w  (a6), d0
    andi.w  #0x0e0, d0
    move.w  d2, d7
    andi.w  #0x0e0, d7
    sub.w   d0, d7
    bpl.s   7f
    neg.w   d7
7:  lsr.w   #4, d7
    add.w   d7, d1
    move.w  (a6)+, d0
    andi.w  #0xe00, d0
    move.w  d2, d7
    andi.w  #0xe00, d7
    sub.w   d0, d7
    bpl.s   8f
    neg.w   d7
8:  lsr.w   #8, d7
    add.w   d7, d1
    cmp.w   d5, d1
    bhs.s   9f
    move.w  d1, d5
    move.w  d3, d4
9:  addq.w  #1, d3
    bra.s   4b
3:  addq.l  #2, sp
    move.l  (sp)+, d7
    rts

| While the arcade's palettes are changing, lines 2 and 3 follow the entries
| their colours came from (so fades work) and a scene not yet drawn waits. Once
| they have been still for a few latches the pen tables are checked against
| them, and if they no longer agree everything is thrown away and drawn again.
bg_palette_check:
    tst.w   bg_pal_flag
    beq.w   bg_palette_quiet
    subq.w  #1, bg_pal_flag
    lea     BG_PALETTES, a0
    lea     BG_BLUES, a1
    moveq   #0, d0
    moveq   #0, d3
    move.w  #511, d1
1:  move.w  (a0)+, d2
    or.w    d2, d3
    add.w   d2, d0
    rol.w   #1, d0
    move.w  (a1)+, d2
    or.b    d2, d3
    add.w   d2, d0
    dbra    d1, 1b
    lea     PALETTE_RG, a0
    lea     PALETTE_B, a1
    move.w  #255, d1
9:  add.w   (a0)+, d0
    rol.w   #1, d0
    add.w   (a1)+, d0
    dbra    d1, 9b
    cmp.w   bg_pal_sum, d0
    beq.w   bg_palette_quiet
    move.w  d0, bg_pal_sum
    move.w  #SETTLE_LATCHES, bg_settle
    tst.w   d3
    bne.s   1f
    tst.w   bg_dark
    bne.w   bg_palette_same
    move.w  #1, bg_dark
    moveq   #0, d0
    bsr.w   bg_line_refresh
    moveq   #16, d0
    bsr.w   bg_line_refresh
    move.w  #1, bg_line_dirty
    rts
1:  move.w  bg_dark, d4
    beq.s   2f
    clr.w   bg_dark
    tst.w   bg_hold
    bne.w   bg_palette_same
    cmpi.w  #DARK_TEARDOWN, d4
    bhs.s   3f
    bsr.w   bg_scene_same
    beq.s   2f
3:  move.w  #HOLD_LATCHES, bg_hold
    rts
2:  tst.w   bg_hold
    bne.w   bg_palette_same
    moveq   #0, d0
    bsr.w   bg_line_refresh
    moveq   #16, d0
    bsr.w   bg_line_refresh
    move.w  #1, bg_line_dirty
    bsr.w   text_validate
    bsr.w   bg_validate
    bls.w   bg_palette_same
    tst.w   bg_bad
    bne.w   bg_palette_same
    move.w  #HOLD_LATCHES, bg_bad
    rts
bg_palette_quiet:
    tst.w   bg_settle
    beq.w   bg_palette_same
    subq.w  #1, bg_settle
    rts

| A scene whose palette has just arrived, or whose colour tables have gone
| wrong, is built afresh once the palette has been still for a few latches, or
| after HOLD_LATCHES if it never is (some scenes animate their palettes).
bg_palette_wait:
    tst.w   bg_hold
    beq.s   1f
    subq.w  #1, bg_hold
    beq.s   2f
    tst.w   bg_settle
    bne.s   bg_palette_same
2:  clr.w   bg_hold
    clr.w   bg_bad
    bra.w   bg_reset
1:  tst.w   bg_bad
    beq.s   bg_palette_same
    subq.w  #1, bg_bad
    beq.s   2b
    tst.w   bg_settle
    beq.s   2b
bg_palette_same:
    rts

| Counts the pens whose arcade colour is not the one their line colour stands
| for. Returns higher when that is more than when the tables were built.
bg_validate:
    moveq   #0, d7
    moveq   #0, d6
4:  lea     BG_LUT_OK, a2
    tst.b   (a2, d6.w)
    beq.s   8f
    move.w  d6, d0
    bsr.w   bg_line_for
    move.w  d6, d4
    lsl.w   #5, d4
    lea     BG_PALETTES, a0
    adda.w  d4, a0
    lea     BG_BLUES, a1
    adda.w  d4, a1
    lsr.w   #1, d4
    lea     BG_LUT, a2
    adda.w  d4, a2
    moveq   #15, d5
5:  move.w  (a0)+, d2
    swap    d2
    move.w  (a1)+, d2
    andi.w  #0x00ff, d2
    moveq   #0, d0
    move.b  (a2)+, d0
    bne.s   6f
    tst.w   bg_first
    bne.s   7f
6:  lsl.w   #2, d0
    movea.l bg_full_base, a6
    cmp.l   (a6, d0.w), d2
    beq.s   7f
    addq.w  #1, d7
7:  dbra    d5, 5b
8:  addq.w  #1, d6
    cmpi.w  #32, d6
    bne.s   4b
    move.w  bg_inexact, d0
    addq.w  #4, d0
    cmp.w   d0, d7
    rts

| d0 = 0 or 16: recomputes that layer's line from the arcade entries its colours follow.
bg_line_refresh:
    bsr.w   bg_line_for
    move.w  bg_first, d0
    add.w   d0, d0
    adda.w  d0, a3
    adda.w  d0, a4
    movea.l bg_full_base, a2
    adda.w  d0, a2
    adda.w  d0, a2
    move.w  (a5), d3
    bra.s   2f
1:  move.w  (a4)+, d4
    lea     BG_PALETTES, a0
    move.w  (a0, d4.w), d0
    lea     BG_BLUES, a1
    move.w  (a1, d4.w), d1
    move.w  d0, (a2)+
    move.w  d1, d2
    andi.w  #0x00ff, d2
    move.w  d2, (a2)+
    bsr.w   colour9
    move.w  d2, (a3)+
2:  dbra    d3, 1b
    rts

| a5 = layer. Forgets everything drawn for it, so that it is drawn again.
bg_layer_invalidate:
    movea.l LAYER_DRAWN(a5), a1
    movea.l LAYER_VALID(a5), a6
    move.w  LAYER_BIT(a5), d5
    moveq   #0, d6
1:  move.w  d6, d0
    add.w   d0, d0
    move.w  (a1, d0.w), d0
    bsr.w   bg_release
    addq.w  #1, d6
    cmpi.w  #1024, d6
    bne.s   1b
    move.w  #1, LAYER_REDRAW(a5)
    rts

bg_scroll:
    move.l  #0x7c000002, VDP_CTRL
    move.w  PF2_REGS + 0x10, d0
    neg.w   d0
    cmpi.w  #0xc000, text_plane
    bne.s   1f
    move.w  PF1_REGS + 0x10, d0
    neg.w   d0
1:  move.w  d0, VDP_DATA
    move.w  PF3_REGS + 0x10, d0
    neg.w   d0
    cmpi.w  #0xe000, text_plane
    bne.s   2f
    move.w  PF1_REGS + 0x10, d0
    neg.w   d0
2:  move.w  d0, VDP_DATA
    move.l  #0x40000010, VDP_CTRL
    move.w  PF2_REGS + 0x12, d0
    cmpi.w  #0xc000, text_plane
    bne.s   3f
    move.w  PF1_REGS + 0x12, d0
3:  addi.w  #TOP_LINE, d0
    move.w  d0, VDP_DATA
    move.w  PF3_REGS + 0x12, d0
    cmpi.w  #0xe000, text_plane
    bne.s   4f
    move.w  PF1_REGS + 0x12, d0
4:  addi.w  #TOP_LINE, d0
    move.w  d0, VDP_DATA
    rts
