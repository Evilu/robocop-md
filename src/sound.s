| Sound. The arcade's sound commands are queued where the game sends them and
| played in VBlank from streams made at build time (tools/build/sound.py): one
| stream for the tune, one for the effect, each a list of YM2612 and PSG writes
| per frame. Tunes use channels 1-4, effects channel 5 and the PSG. Channel 6 is
| the DAC: the Z80 plays the arcade's samples through it, one at a time, and the
| 68000 takes the bus from it only while it writes its own registers.

    .equ YM_STATUS,     0xa04000
    .equ PSG_PORT,      0xc00011
    .equ SND_QUEUE,     0xff1620    | 16 commands
    .equ snd_put,       0xff1630
    .equ snd_take,      0xff1632
    .equ TUNE,          0xff1640    | stream: position, start, frames to wait
    .equ EFFECT,        0xff1650
    .equ STREAM_AT,     0
    .equ STREAM_START,  4
    .equ STREAM_WAIT,   8

    .equ FIRST_EFFECT,  0x05
    .equ FIRST_TUNE,    0x31
    .equ LAST_TUNE,     0x3d
    .equ SAMPLE_STOP,   0x3e
    .equ LAST_SAMPLE,   0x4f
    .equ Z80_RAM,       0xa00000
    .equ Z80_MAILBOX,   0xa01f00
    .equ Z80_BUS,       0xa11100
    .equ Z80_RESET,     0xa11200
    .equ Z80_DRIVER,    SAMPLE_TABLE + 256

| Loads the Z80's program and turns channel 6 into the DAC.
sound_init:
    bsr.w   z80_stop
    lea     Z80_DRIVER, a0
    lea     Z80_RAM, a1
    move.w  (a0)+, d0
    subq.w  #1, d0
1:  move.b  (a0)+, (a1)+
    dbra    d0, 1b
    clr.b   Z80_MAILBOX
    move.w  #0x0000, Z80_RESET
    move.w  #0x0000, Z80_BUS
    moveq   #127, d0
2:  dbra    d0, 2b
    move.w  #0x0100, Z80_RESET
    bsr.w   z80_stop
    lea     YM_STATUS, a1
    moveq   #0x2b, d0
    move.b  #0x80, d1
    bsr.w   ym_write
    moveq   #0x2a, d0
    move.b  #0x80, d1
    bsr.w   ym_write
    bsr.w   sound_quiet
    bra.w   z80_start

z80_stop:
    move.w  #0x0100, Z80_BUS
1:  btst    #0, Z80_BUS
    bne.w   1b
    rts

| Before the Z80 gets the bus back the address port is left on the DAC register:
| if the Z80 was stopped between choosing that register and writing the sample, its write still lands there.
z80_start:
    move.b  #0x2a, YM_STATUS
    move.w  #0x0000, Z80_BUS
    rts

hal_sound_01:
    move.w  d0, -(sp)
    moveq   #0x01, d0
    bra.w   sound_fixed
hal_sound_04:
    move.w  d0, -(sp)
    moveq   #0x04, d0
    bra.w   sound_fixed
hal_sound_05:
    move.w  d0, -(sp)
    moveq   #0x05, d0
    bra.w   sound_fixed
hal_sound_c0:
    move.w  d0, -(sp)
    move.w  #0xc0, d0
sound_fixed:
    bsr.w   hal_sound
    move.w  (sp)+, d0
    rts

| d0 = the command the game is sending to the sound board.
hal_sound:
    movem.l d1/a0, -(sp)
    move.w  snd_put, d1
    lea     SND_QUEUE, a0
    move.b  d0, (a0, d1.w)
    addq.w  #1, d1
    andi.w  #15, d1
    move.w  d1, snd_put
    movem.l (sp)+, d1/a0
    rts

sound_frame:
    movem.l d0-d3/a0-a2/a5, -(sp)
    bsr.w   z80_stop
1:  move.w  snd_take, d1
    cmp.w   snd_put, d1
    beq.w   4f
    lea     SND_QUEUE, a0
    moveq   #0, d0
    move.b  (a0, d1.w), d0
    addq.w  #1, d1
    andi.w  #15, d1
    move.w  d1, snd_take
    cmpi.w  #1, d0
    beq.w   2f
    cmpi.w  #3, d0
    bne.w   3f
2:  bsr.w   sound_quiet
    bra.w   1b
3:  cmpi.w  #FIRST_EFFECT, d0
    blo.w   1b
    cmpi.w  #LAST_SAMPLE, d0
    bhi.w   1b
    cmpi.w  #LAST_TUNE, d0
    bhi.w   6f
    lea     EFFECT, a5
    cmpi.w  #FIRST_TUNE, d0
    blo.w   5f
    lea     TUNE, a5
5:  lsl.w   #2, d0
    lea     SOUND_TABLE, a0
    move.l  (a0, d0.w), d1
    beq.w   1b
    move.l  d1, STREAM_AT(a5)
    move.l  d1, STREAM_START(a5)
    clr.w   STREAM_WAIT(a5)
    bra.w   1b
6:  subi.w  #SAMPLE_STOP, d0
    lsl.w   #3, d0
    lea     SAMPLE_TABLE, a0
    adda.w  d0, a0
    lea     Z80_MAILBOX, a1
    tst.w   4(a0)
    beq.w   1b
    move.b  3(a0), 1(a1)
    move.b  2(a0), 2(a1)
    move.b  1(a0), 3(a1)
    move.b  5(a0), 4(a1)
    move.b  4(a0), 5(a1)
    move.b  #1, (a1)
    bra.w   1b
4:  lea     TUNE, a5
    bsr.w   sound_stream
    lea     EFFECT, a5
    bsr.w   sound_stream
    bsr.w   z80_start
    movem.l (sp)+, d0-d3/a0-a2/a5
    rts

| a5 = stream. Plays its writes for this frame.
sound_stream:
    tst.l   STREAM_AT(a5)
    beq.w   9f
    tst.w   STREAM_WAIT(a5)
    beq.w   1f
    subq.w  #1, STREAM_WAIT(a5)
9:  rts
1:  movea.l STREAM_AT(a5), a0
2:  moveq   #0, d0
    move.b  (a0)+, d0
    cmpi.w  #0x20, d0
    blo.w   3f
    move.b  (a0)+, d1
    lea     YM_STATUS, a1
    bsr.w   ym_write
    bra.w   2b
3:  add.w   d0, d0
    move.w  4f(pc, d0.w), d0
    jmp     4f(pc, d0.w)
4:  .word   sound_end_frame - 4b, sound_wait - 4b, sound_stop - 4b
    .word   sound_loop - 4b, sound_psg - 4b, sound_part2 - 4b
sound_wait:
    move.b  (a0)+, d0
    move.w  d0, STREAM_WAIT(a5)
sound_end_frame:
    move.l  a0, STREAM_AT(a5)
    rts
sound_stop:
    clr.l   STREAM_AT(a5)
    rts
sound_loop:
    moveq   #0, d0
    move.b  (a0)+, d0
    swap    d0
    move.b  (a0)+, d0
    lsl.w   #8, d0
    move.b  (a0)+, d0
    movea.l STREAM_START(a5), a0
    adda.l  d0, a0
    bra.w   2b
sound_psg:
    move.b  (a0)+, PSG_PORT
    bra.w   2b
sound_part2:
    move.b  (a0)+, d0
    move.b  (a0)+, d1
    lea     YM_STATUS + 2, a1
    bsr.w   ym_write
    bra.w   2b

| d0 = register, d1 = value, a1 = the part's address port.
ym_write:
    btst    #7, YM_STATUS
    bne.w   ym_write
    move.b  d0, (a1)
    nop
1:  btst    #7, YM_STATUS
    bne.w   1b
    move.b  d1, 1(a1)
    rts

| Stops both streams and silences every channel.
sound_quiet:
    clr.l   TUNE + STREAM_AT
    clr.l   EFFECT + STREAM_AT
    lea     YM_STATUS, a1
    lea     1f(pc), a2
    moveq   #5, d2
2:  moveq   #0x28, d0
    move.b  (a2)+, d1
    bsr.w   ym_write
    dbra    d2, 2b
    move.b  #0x9f, PSG_PORT
    move.b  #0xbf, PSG_PORT
    move.b  #0xdf, PSG_PORT
    move.b  #0xff, PSG_PORT
    rts
1:  .byte   0, 1, 2, 4, 5, 6
