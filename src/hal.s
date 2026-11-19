| Hardware layer for the Mega Drive build, linked after the arcade program.

    .equ PALETTE_RG,    0xff0000    | arcade 0x310000
    .equ PF1_REGS,      0xff0800    | arcade 0x240000
    .equ PF2_REGS,      0xff0820    | arcade 0x246000
    .equ PF3_REGS,      0xff0840    | arcade 0x24c000
    .equ IO,            0xff0860    | arcade 0x30c000
    .equ SHARED,        0xff1000    | arcade 0x180000, one byte per word
    .equ PALETTE_B,     0xff4000    | arcade 0x314000

    .equ HAL_VARS,      0xffd000
    .equ hal_frames,    HAL_VARS
    .equ seq_index,     HAL_VARS + 4

    .equ WORK_RAM,      0xff8000
    .equ WORK_RAM_END,  0xffc000

    .equ SUB_ROM,       0x00b570    | HuC6280 address + SUB_ROM = address in the 68000 ROM
    .equ SEQ_TABLE,     0x224f + SUB_ROM
    .equ SEQ_LENGTH,    18
    .equ ROUTINES,      0x003f38
    .equ DAMAGE,        0x2335 + SUB_ROM
    .equ PLAYER_BOXES,  0x248a + SUB_ROM
    .equ OBJECT_BOXES,  0x24da + SUB_ROM
    .equ RECORDS,       30

    .equ VDP_DATA,      0xc00000
    .equ VDP_CTRL,      0xc00004
    .equ PAD1_DATA,     0xa10003
    .equ PAD1_CTRL,     0xa10009

    .macro le16 off, areg, dreg
    move.b  \off+1(\areg), \dreg
    lsl.w   #8, \dreg
    move.b  \off(\areg), \dreg
    .endm

    .text
hal_ignore:
    rte

hal_boot:
    move.w  #0x2700, sr
    move.b  0xa10001, d0
    andi.b  #0x0f, d0
    beq.s   1f
    move.l  #0x53454741, 0xa14000
1:  move.w  #0x0100, 0xa11100
    move.w  #0x0100, 0xa11200
    lea     vdp_init(pc), a0
    moveq   #(vdp_init_end - vdp_init) / 2 - 1, d0
2:  move.w  (a0)+, VDP_CTRL
    dbra    d0, 2b
    move.l  #0xc0000000, VDP_CTRL
    moveq   #63, d0
3:  move.w  #0, VDP_DATA
    dbra    d0, 3b
    move.l  #0x40000000, VDP_CTRL
    move.w  #0x3fff, d0
6:  move.l  #0, VDP_DATA
    dbra    d0, 6b
    move.b  #0x40, PAD1_CTRL
    move.b  #0x40, PAD1_DATA

    moveq   #0, d0
    lea     0xff0000, a0
4:  move.l  d0, (a0)+
    cmpa.l  #WORK_RAM_END, a0
    bne.s   4b
    lea     0xffc000, a0
5:  move.l  d0, (a0)+
    cmpa.l  #0xfffffc, a0
    bne.s   5b
    bsr.w   idle_inputs
    bsr.w   sprites_init

    moveq   #0, d7
    move.b  #1, IO + 0x15
    jsr     0x2516
    move.w  #0x8174, VDP_CTRL
    move.w  #0x2500, sr
    jsr     0x1b04
    move.w  #0x1111, d0
    jsr     0x1ae8
    jsr     0x0ef2
    jsr     0x19d2
    move.l  #0x50000, 0xffb522
    jsr     0x29cc
    jsr     0x29a0
    jsr     0x29cc
    move.b  #0x28, 0xffb243
    move.b  #1, SHARED + 1
hal_restart:
    jsr     0x022c
    jmp     0x359a

idle_inputs:
    move.w  #0xffff, IO
    move.w  #0xff7f, IO + 2
    move.w  #0xff7f, IO + 4
    rts

hal_vblank:
    movem.l d0-d4/a0-a1, -(sp)
    move.w  VDP_CTRL, d0
    bsr.w   sprites_flush
    addq.l  #1, hal_frames
    bsr.w   read_pad
    movem.l (sp)+, d0-d4/a0-a1
    jmp     0x1002

| The HuC6280 hands the main loop 18 routine numbers per game step, in the
| order of the table in its program; the last one, 2, ends the step.
hal_sequence:
    clr.w   seq_index
1:  move.w  seq_index, d0
    lea     SEQ_TABLE, a0
    move.b  (a0, d0.w), d0
    move.b  d0, SHARED + 5
    andi.w  #0xff, d0
    lsl.w   #2, d0
    lea     ROUTINES, a0
    movea.l (a0, d0.w), a0
    jsr     (a0)
    addq.w  #1, seq_index
    cmpi.w  #SEQ_LENGTH, seq_index
    bne.s   1b
    moveq   #2, d0
    rts

| The HuC6280's interrupt routine (0x2261 in its program), on the object
| records the game has just copied into the dual-port RAM's stand-in.
hal_hit:
    movem.l d0-d7/a0-a6, -(sp)
    lea     SHARED, a6
    moveq   #0, d7
    move.b  0x23(a6), d7
    lea     0x25(a6), a2
    moveq   #RECORDS - 1, d6
hit_record:
    tst.w   d7
    beq.w   hit_done
    tst.b   (a2)
    beq.w   hit_skip
    btst    #0, 0x4e(a2)
    bne.w   hit_counted
    tst.b   0x3e(a2)
    bne.w   hit_counted
    moveq   #0, d0
    move.b  (a2), d0
    add.b   d0, d0
    lea     OBJECT_BOXES, a0
    adda.w  d0, a0
    moveq   #0, d1
    le16    0, a0, d1
    lea     SUB_ROM, a0
    adda.l  d1, a0
    moveq   #0, d0
    move.b  0x2c(a2), d0
    add.b   d0, d0
    adda.w  d0, a0
    moveq   #0, d1
    le16    0, a0, d1
    lea     SUB_ROM, a3
    adda.l  d1, a3
    move.b  4(a2), d2
    lsl.w   #8, d2
    move.b  6(a2), d2
    move.b  12(a2), d3
    lsl.w   #8, d3
    move.b  14(a2), d3
    moveq   #0, d0
    move.b  0x0d(a6), d0
    add.b   d0, d0
    lea     PLAYER_BOXES, a0
    adda.w  d0, a0
    moveq   #0, d1
    le16    0, a0, d1
    lea     SUB_ROM, a4
    adda.l  d1, a4
    move.b  0x0f(a6), d4
    lsl.w   #8, d4
    move.b  0x11(a6), d4
    move.b  0x13(a6), d5
    lsl.w   #8, d5
    move.b  0x15(a6), d5
    bsr.s   overlap
    beq.s   hit_counted
    cmpi.b  #6, (a2)
    beq.s   1f
    move.b  #4, 0x3e(a2)
    bra.s   2f
1:  bset    #0, 0x4e(a2)
2:  moveq   #0, d0
    move.b  (a2), d0
    lea     DAMAGE, a0
    move.b  (a0, d0.w), d1
    bsr.w   damage
hit_counted:
    subq.w  #1, d7
hit_skip:
    lea     0x50(a2), a2
    dbra    d6, hit_record
hit_done:
    clr.b   9(a6)
    movem.l (sp)+, d0-d7/a0-a6
    rts

| a3 = the object's box list, a4 = the player's, d2/d3 = object X/Y, d4/d5 = player X/Y.
| Returns with Z clear when any pair of boxes overlaps.
overlap:
    movem.l d6-d7, -(sp)
    move.b  (a3), d6
    addq.l  #2, a3
    movea.l a4, a5
overlap_object_box:
    move.b  (a4), d7
    addq.l  #2, a4
overlap_player_box:
    le16    0, a3, d0
    add.w   d2, d0
    le16    0, a4, d1
    add.w   d4, d1
    sub.w   d1, d0
    bcc.s   1f
    neg.w   d0
1:  le16    4, a3, d1
    movea.w d1, a1
    le16    4, a4, d1
    add.w   a1, d1
    sub.w   d1, d0
    bcc.s   overlap_miss
    le16    2, a3, d0
    add.w   d3, d0
    le16    2, a4, d1
    add.w   d5, d1
    sub.w   d1, d0
    bcc.s   2f
    neg.w   d0
2:  le16    6, a3, d1
    movea.w d1, a1
    le16    6, a4, d1
    add.w   a1, d1
    sub.w   d1, d0
    bcs.s   overlap_hit
overlap_miss:
    addq.l  #8, a4
    subq.b  #1, d7
    bpl.w   overlap_player_box
    addq.l  #8, a3
    movea.l a5, a4
    subq.b  #1, d6
    bpl.w   overlap_object_box
    movem.l (sp)+, d6-d7
    moveq   #0, d0
    rts
overlap_hit:
    movem.l (sp)+, d6-d7
    moveq   #1, d0
    rts

| d1 = energy to take off, unless the player is invulnerable or not in play.
damage:
    move.b  0x1d(a6), d0
    or.b    0x1f(a6), d0
    bne.s   1f
    move.b  #8, 0x17(a6)
    tst.b   0x19(a6)
    bpl.s   1f
    btst    #1, 0x1b(a6)
    beq.s   1f
    move.b  0x0b(a6), d0
    sub.b   d1, d0
    bcc.s   2f
    moveq   #0, d0
2:  move.b  d0, 0x0b(a6)
1:  rts

| Pad 1 -> arcade player 1 and system inputs (all active low).
| B = attack, C = jump, A = coin, Start = start.
read_pad:
    lea     PAD1_DATA, a0
    move.b  #0x40, (a0)
    nop
    nop
    move.b  (a0), d0
    move.b  #0x00, (a0)
    nop
    nop
    move.b  (a0), d1
    move.b  #0x40, (a0)
    ori.b   #0xc0, d0
    move.b  d0, IO + 1
    moveq   #0x7f, d2
    btst    #4, d1
    bne.s   1f
    bclr    #4, d2
1:  btst    #5, d1
    bne.s   2f
    bclr    #2, d2
2:  move.b  d2, IO + 3
    rts

    .include "sprites.s"

hal_crash:
    move.w  #0x2700, sr
    move.w  #0x8700, VDP_CTRL
    move.l  #0xc0000000, VDP_CTRL
    move.w  #0x000e, VDP_DATA
1:  bra.s   1b

vdp_init:
    .word   0x8004, 0x8134, 0x8230, 0x8334, 0x8407, 0x855c, 0x8600, 0x8700
    .word   0x8800, 0x8900, 0x8a00, 0x8b00, 0x8c00, 0x8d2f, 0x8e00, 0x8f02
    .word   0x9001, 0x9100, 0x9200
vdp_init_end:
