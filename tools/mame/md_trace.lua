-- Mega Drive VDP trace for MAME's genesis driver.
-- Decodes every 68000 write to the VDP ports and logs per-frame transfer, palette
-- and sprite statistics to md_frames.csv. Optional pad script drives the game.
-- env: TRACE_OUT (directory), TRACE_FRAMES (frames to run), TRACE_SNAP_EVERY (frames),
--      TRACE_INPUT=none to leave the pads alone, TRACE_INPUT=arcade for the port
--      (A = coin at frame 700, Start at 800, then walk and fight), TRACE_INPUT=start for a
--      game that starts on Start alone (Start every 240 frames, walk right, B and C)
--      RAM_WATCH=lo-hi (hex): report the lowest address written in that range (stack depth)
--      WATCH_FROM: first frame counted by RAM_WATCH and md_vram_free.txt (default 300, after boot)
--      HOLD: hex address=value[,address=value] bytes rewritten every frame (for example the player's energy)
-- Also writes md_vram_free.txt: the VRAM patterns never written during the run.

local out_dir = os.getenv("TRACE_OUT") or "."
local max_frames = tonumber(os.getenv("TRACE_FRAMES") or "18000")
local snap_every = tonumber(os.getenv("TRACE_SNAP_EVERY") or "0")

local holds = {}
for a, v in string.gmatch(os.getenv("HOLD") or "", "(%x+)=(%x+)") do holds[#holds + 1] = { tonumber(a, 16), tonumber(v, 16) } end
local watch_lo, watch_hi, watch_min
local watch_from = tonumber(os.getenv("WATCH_FROM") or "300")
do
  local lo, hi = string.match(os.getenv("RAM_WATCH") or "", "(%x+)-(%x+)")
  if lo then watch_lo, watch_hi = tonumber(lo, 16), tonumber(hi, 16) end
end
local cpu = manager.machine.devices[":maincpu"]
local prog = cpu.spaces["program"]
local vw = {}
for i = 0, 0x7fff do vw[i] = 0 end
local touched = {}
local vram = {}
function vram:read_u16(a) return vw[(a >> 1) & 0x7fff] end
local function vram_byte(a, b)
  local i = (a >> 1) & 0x7fff
  touched[i >> 4] = true
  if a & 1 == 0 then vw[i] = (vw[i] & 0x00ff) | (b << 8) else vw[i] = (vw[i] & 0xff00) | b end
end
local function vram_get_byte(a)
  local w = vw[(a >> 1) & 0x7fff]
  if a & 1 == 0 then return w >> 8 end
  return w & 0xff
end

local reg = {}
for i = 0, 31 do reg[i] = 0 end
local cram = {}
for i = 0, 63 do cram[i] = 0 end
local pending, first = false, 0
local code, addr = 0, 0
local fill_pending = false

local f = {}
local function reset_frame()
  f = { dma_vram = 0, dma_cram = 0, dma_vsram = 0, dma_active = 0, dma_ops = 0,
        cpu_vram = 0, cpu_cram = 0, cpu_vsram = 0, fill = 0, copy = 0,
        cram_active = 0, reg_active = 0, sat_dma = 0, mapper = 0, src_rom = 0, src_ram = 0 }
end
reset_frame()

local reg_hist = {}
local function note_reg(r, v)
  local key = string.format("%02x=%02x", r, v)
  reg_hist[key] = (reg_hist[key] or 0) + 1
end

local function active()
  return (prog:read_u16(0xc00008) >> 8) < 0xe0
end

local function sat_base()
  if reg[12] & 0x81 ~= 0 then return (reg[5] & 0x7e) << 9 end
  return (reg[5] & 0x7f) << 9
end

local function do_dma()
  local mode = reg[0x17] >> 6
  local len = reg[0x13] | (reg[0x14] << 8)
  if len == 0 then len = 0x10000 end
  local target = code & 0x0f
  if mode < 2 then
    local src = ((reg[0x17] & 0x7f) << 17) | (reg[0x16] << 9) | (reg[0x15] << 1)
    local bytes = len * 2
    f.dma_ops = f.dma_ops + 1
    if active() then f.dma_active = f.dma_active + bytes end
    if target == 1 then
      f.dma_vram = f.dma_vram + bytes
      if src >= 0xe00000 then f.src_ram = f.src_ram + bytes else f.src_rom = f.src_rom + bytes end
      local a = addr
      for i = 0, len - 1 do
        vw[(a >> 1) & 0x7fff] = prog:read_u16((src + i * 2) & 0xffffff)
        touched[((a >> 1) & 0x7fff) >> 4] = true
        a = a + reg[0x0f]
      end
      local sb = sat_base()
      if addr <= sb + 0x280 and addr + bytes > sb then f.sat_dma = f.sat_dma + 1 end
    elseif target == 3 then
      f.dma_cram = f.dma_cram + bytes
      local a = addr
      for i = 0, len - 1 do
        cram[(a >> 1) & 63] = prog:read_u16((src + i * 2) & 0xffffff)
        a = a + reg[0x0f]
      end
    elseif target == 5 then
      f.dma_vsram = f.dma_vsram + bytes
    end
  elseif mode == 2 then
    fill_pending = len
  else
    f.copy = f.copy + len
    local src = reg[0x15] | (reg[0x16] << 8)
    local a = addr
    for i = 0, len - 1 do
      vram_byte(a, vram_get_byte(src + i))
      a = (a + reg[0x0f]) & 0xffff
    end
  end
end

local function ctrl_write(w)
  if not pending and (w & 0xc000) == 0x8000 then
    local r, v = (w >> 8) & 0x1f, w & 0xff
    reg[r] = v
    note_reg(r, v)
    if active() then f.reg_active = f.reg_active + 1 end
    code = 0
    return
  end
  if not pending then
    first = w
    pending = true
    code = (code & 0x3c) | ((w >> 14) & 3)
    addr = (addr & 0xc000) | (w & 0x3fff)
    return
  end
  pending = false
  code = ((first >> 14) & 3) | ((w >> 2) & 0x3c)
  addr = (first & 0x3fff) | ((w & 3) << 14)
  if (code & 0x20) ~= 0 and (reg[1] & 0x10) ~= 0 then do_dma() end
end

local function data_write(w)
  pending = false
  if fill_pending then
    f.fill = f.fill + fill_pending
    local a = addr
    for i = 0, fill_pending - 1 do
      vram_byte(a, w >> 8)
      a = (a + reg[0x0f]) & 0xffff
    end
    fill_pending = false
    return
  end
  local target = code & 0x0f
  if target == 1 then
    f.cpu_vram = f.cpu_vram + 2
    vw[(addr >> 1) & 0x7fff] = w
    touched[((addr >> 1) & 0x7fff) >> 4] = true
  elseif target == 3 then
    f.cpu_cram = f.cpu_cram + 2
    cram[(addr >> 1) & 63] = w
    if active() then f.cram_active = f.cram_active + 1 end
  elseif target == 5 then
    f.cpu_vsram = f.cpu_vsram + 2
  end
  addr = (addr + reg[0x0f]) & 0xffff
end

local function on_vdp(offset, data, mask)
  if offset & 4 == 0 then data_write(data & 0xffff) else ctrl_write(data & 0xffff) end
end
local function on_map()
  f.mapper = f.mapper + 1
end

local function sprite_stats()
  local base = sat_base()
  local line_n, line_px = {}, {}
  local n, vis, cells = 0, 0, 0
  local pals = {}
  local i = 0
  local seen = {}
  repeat
    if seen[i] then break end
    seen[i] = true
    local e = base + i * 8
    local y = vram:read_u16(e) & 0x3ff
    local sz = vram:read_u16(e + 2)
    local link = sz & 0x7f
    local w = ((sz >> 10) & 3) + 1
    local h = ((sz >> 8) & 3) + 1
    local attr = vram:read_u16(e + 4)
    local x = vram:read_u16(e + 6) & 0x1ff
    n = n + 1
    local sy, sx = y - 128, x - 128
    if sx < 320 and sx + w * 8 > 0 and sy < 224 and sy + h * 8 > 0 then
      vis = vis + 1
      cells = cells + w * h
      pals[(attr >> 13) & 3] = true
      for l = math.max(sy, 0), math.min(sy + h * 8 - 1, 223) do
        line_n[l] = (line_n[l] or 0) + 1
        line_px[l] = (line_px[l] or 0) + w * 8
      end
    end
    i = link
  until i == 0 or n >= 80
  local mn, mp, over = 0, 0, 0
  for l = 0, 223 do
    local c, p = line_n[l] or 0, line_px[l] or 0
    if c > mn then mn = c end
    if p > mp then mp = p end
    if c > 20 or p > 320 then over = over + 1 end
  end
  local np = 0
  for _ in pairs(pals) do np = np + 1 end
  return n, vis, cells, mn, mp, over, np
end

local function cram_colours()
  local set, n = {}, 0
  for i = 0, 63 do
    if i % 16 ~= 0 then
      local c = cram[i] & 0x0eee
      if not set[c] then set[c] = true n = n + 1 end
    end
  end
  return n
end

local last_cram = {}
local function cram_changed()
  local c = 0
  for i = 0, 63 do
    if last_cram[i] ~= cram[i] then c = c + 1 end
    last_cram[i] = cram[i]
  end
  return c
end

local pad = manager.machine.ioport.ports[":ctrl1:mdpad:PAD"]
local function press(name, on)
  local fld = pad and pad.fields[name]
  if fld then fld:set_value(on and 1 or 0) end
end

local csv = io.open(out_dir .. "/md_frames.csv", "w")
csv:write("frame,dma_vram,dma_cram,dma_vsram,dma_active,dma_ops,cpu_vram,cpu_cram,cpu_vsram,fill,copy," ..
  "cram_active,reg_active,sat_dma,mapper,spr_chain,spr_visible,spr_cells,spr_line_max,spr_line_px_max," ..
  "spr_over_lines,spr_pals,cram_colours,cram_changed,hint,hscroll_mode,vscroll_mode,width,in_game,pc,dma_src_rom,dma_src_ram\n")

local frame = 0
local busy, quiet, in_game, game_frames = 0, 0, false, 0
local scripted = os.getenv("TRACE_INPUT") ~= "none"
local function on_frame()
  frame = frame + 1
  local n, vis, cells, mn, mp, over, np = sprite_stats()
  csv:write(string.format("%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%x,%d,%d\n",
    frame, f.dma_vram, f.dma_cram, f.dma_vsram, f.dma_active, f.dma_ops, f.cpu_vram, f.cpu_cram, f.cpu_vsram,
    f.fill, f.copy, f.cram_active, f.reg_active, f.sat_dma, f.mapper, n, vis, cells, mn, mp, over, np,
    cram_colours(), cram_changed(), (reg[0] >> 4) & 1, reg[0x0b] & 3, (reg[0x0b] >> 2) & 1,
    (reg[12] & 0x81) ~= 0 and 320 or 256, in_game and 1 or 0, cpu.state["PC"].value, f.src_rom, f.src_ram))
  local moving = f.dma_vram > 0
  reset_frame()

  local t = frame
  if vis > 3 and moving then busy = busy + 1 else busy = 0 end
  if busy > 60 and scripted then in_game = true quiet = 0 end
  if in_game then
    if vis == 0 then quiet = quiet + 1 else quiet = 0 end
    if quiet > 600 then in_game = false end
  end
  if os.getenv("TRACE_INPUT") == "arcade" then
    in_game = t > 900
    press("P1 A", t >= 700 and t < 708)
    press("P1 Start", t >= 800 and t < 808)
    local cyc = t % 300
    press("P1 Right", in_game and cyc < 150)
    press("P1 Left", in_game and cyc >= 270)
    press("P1 Up", in_game and cyc >= 150 and cyc < 270 and t % 80 < 10)
    press("P1 Down", in_game and cyc >= 150 and cyc < 270 and t % 80 >= 40 and t % 80 < 50)
    press("P1 B", in_game and cyc >= 150 and cyc < 270 and t % 12 < 3)
    press("P1 C", in_game and cyc < 150 and t % 140 == 70)
    scripted = false
  end
  if os.getenv("TRACE_INPUT") == "start" then
    press("P1 Start", t > 240 and t % 240 < 8)
    local cyc = t % 300
    press("P1 Right", cyc < 200)
    press("P1 Left", cyc >= 280)
    press("P1 Up", cyc >= 200 and cyc < 280 and t % 80 < 20)
    press("P1 Down", cyc >= 200 and cyc < 280 and t % 80 >= 40 and t % 80 < 55)
    press("P1 B", t % 12 < 4)
    press("P1 C", cyc < 200 and t % 140 >= 70 and t % 140 < 76)
    in_game = t > 900
    scripted = false
  elseif os.getenv("TRACE_INPUT") ~= "arcade" then
    local menu = not in_game and t > 240 and scripted
    press("P1 Start", menu and t % 150 < 6)
    press("P1 A", menu and t % 150 >= 70 and t % 150 < 74)
    local cyc = t % 300
    local walk, fight, back = cyc < 150, cyc >= 150 and cyc < 270, cyc >= 270
    press("P1 Right", in_game and walk)
    press("P1 Left", in_game and back)
    press("P1 Up", in_game and fight and t % 80 < 10)
    press("P1 Down", in_game and fight and t % 80 >= 40 and t % 80 < 50)
    press("P1 B", in_game and fight and t % 12 < 3)
    press("P1 C", in_game and walk and t % 140 == 70)
  end
  game_frames = game_frames + (in_game and 1 or 0)

  if snap_every > 0 and t % snap_every == 0 then
    manager.machine.video:snapshot()
    local d = io.open(string.format("%s/vdp_%06d.bin", out_dir, t), "wb")
    local parts = {}
    for i = 0, 0x7fff do parts[#parts + 1] = string.pack(">I2", vw[i]) end
    for i = 0, 63 do parts[#parts + 1] = string.pack(">I2", cram[i]) end
    for i = 0, 31 do parts[#parts + 1] = string.pack("B", reg[i]) end
    d:write(table.concat(parts))
    d:close()
  end
  for _, h in ipairs(holds) do prog:write_u8(h[1], h[2]) end
  if t == watch_from then
    touched = {}
    watch_min = nil
  end
  if t >= max_frames then
    csv:close()
    local vf = io.open(out_dir .. "/md_vram_free.txt", "w")
    local start = nil
    for p = 0, 0x800 do
      if p < 0x800 and not touched[p] then
        start = start or p
      elseif start then
        vf:write(string.format("patterns %03x-%03x (%d)\n", start, p - 1, p - start))
        start = nil
      end
    end
    if watch_lo then vf:write(string.format("lowest write in %06x-%06x: %s\n", watch_lo, watch_hi,
      watch_min and string.format("%06x", watch_min) or "none")) end
    vf:close()
    local h = io.open(out_dir .. "/md_regs.txt", "w")
    local keys = {}
    for k in pairs(reg_hist) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do h:write(k, " ", reg_hist[k], "\n") end
    h:close()
    local z = manager.machine.devices[":genesis_snd_z80"].spaces["program"]
    local zf = io.open(out_dir .. "/md_z80ram.bin", "wb")
    for a = 0, 0x1fff do zf:write(string.char(z:read_u8(a))) end
    zf:close()
    manager.machine:exit()
  end
end

local errs = 0
local function guard(fn)
  return function(...)
    local ok, e = pcall(fn, ...)
    if not ok and errs < 5 then errs = errs + 1 print("trace error: " .. tostring(e)) end
  end
end
sub = emu.add_machine_frame_notifier(guard(on_frame))
tap_vdp = prog:install_write_tap(0xc00000, 0xc00007, "vdp", guard(on_vdp))
tap_map = prog:install_write_tap(0xa130f0, 0xa130ff, "mapper", guard(on_map))
if watch_lo then
  tap_watch = prog:install_write_tap(watch_lo, watch_hi, "watch", function(offset)
    if not watch_min or offset < watch_min then watch_min = offset end
  end)
end
