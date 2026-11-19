-- Data East MEC-M1 (dec0) video trace for MAME's robocop driver.
-- Reads the buffered sprite list, the three BAC06 tilemaps and the palette every
-- frame and logs what the Mega Drive would have to reproduce to dec0_frames.csv.
-- env: TRACE_OUT, TRACE_FRAMES, TRACE_SNAP_EVERY,
--      IDLE_FLAG (address the frame wait loop polls, hex; robocop ff8004),
--      HOLD (hex address=value[,address=value] bytes rewritten every frame, e.g. energy),
--      TRACE_INPUT=none disables the play script

local out_dir = os.getenv("TRACE_OUT") or "."
local max_frames = tonumber(os.getenv("TRACE_FRAMES") or "18000")
local snap_every = tonumber(os.getenv("TRACE_SNAP_EVERY") or "0")
local idle_flag = tonumber(os.getenv("IDLE_FLAG") or "ff8004", 16)
local play = os.getenv("TRACE_INPUT") ~= "none"

local mem = manager.machine.memory
local cpu = manager.machine.devices[":maincpu"]
local prog = cpu.spaces["program"]
local spriteram = mem.shares[":spriteram"]
local pal_rg, pal_b = mem.shares[":palette"], mem.shares[":palette_ext"]
local vram = { mem.shares[":tilegen1:vram"], mem.shares[":tilegen2:vram"], mem.shares[":tilegen3:vram"] }
local rom = { char = mem.regions[":char"], [2] = mem.regions[":tiles1"], [3] = mem.regions[":tiles2"],
  spr = mem.regions[":sprites"] }

local holds = {}
for a, v in string.gmatch(os.getenv("HOLD") or "", "(%x+)=(%x+)") do holds[#holds + 1] = { tonumber(a, 16), tonumber(v, 16) } end

-- registers are write-only on the board: keep copies of what the game writes
local ctrl = { { 0, 0, 0, 0 }, { 0, 0, 0, 0 }, { 0, 0, 0, 0 } }
local scroll = { { 0, 0, 0, 0 }, { 0, 0, 0, 0 }, { 0, 0, 0, 0 } }
local pri, snd_cmds, sub_irqs, idle_reads, dma = 0, 0, 0, 0, 0
taps = {}
local bases = { 0x240000, 0x246000, 0x24c000 }
for L = 1, 3 do
  taps[#taps + 1] = prog:install_write_tap(bases[L], bases[L] + 0x17, "bac" .. L, function(offset, data, mask)
    local r = offset - bases[L]
    if r < 8 then
      local old = ctrl[L][r // 2 + 1]
      ctrl[L][r // 2 + 1] = (old & ~mask) | (data & mask)
    elseif r >= 0x10 then
      local old = scroll[L][(r - 0x10) // 2 + 1]
      scroll[L][(r - 0x10) // 2 + 1] = (old & ~mask) | (data & mask)
    end
  end)
end
taps[#taps + 1] = prog:install_write_tap(0x30c010, 0x30c01f, "ctl", function(offset, data, mask)
  local r = offset - 0x30c010
  if r == 0 then pri = (pri & ~mask) | (data & mask)
  elseif r == 2 then dma = dma + 1
  elseif r == 4 then snd_cmds = snd_cmds + 1 end
end)
taps[#taps + 1] = prog:install_write_tap(0x180ffe, 0x180fff, "subirq", function() sub_irqs = sub_irqs + 1 end)
taps[#taps + 1] = prog:install_read_tap(idle_flag & ~1, idle_flag | 1, "idle", function() idle_reads = idle_reads + 1 end)

-- 16x16 tiles: 32 bytes per plane, four planes in quarters of the region;
-- bytes 0-15 are the right half, 16-31 the left half, one byte per row.
local memo = {}
local function quads(region, key, code)
  local k = key * 8192 + code
  local v = memo[k]
  if v then return v end
  local q = region.size // 4
  v = 0
  local base = (code * 32) % q
  for n = 0, 3 do
    local off = base + ((n % 2 == 0) and 16 or 0) + (n // 2) * 8
    local blank = true
    for p = 0, 3 do
      for b = 0, 7 do
        if region:read_u8(p * q + off + b) ~= 0 then blank = false break end
      end
      if not blank then break end
    end
    if not blank then v = v + 1 end
  end
  memo[k] = v
  return v
end
local function char_used(code)
  local k = 7 * 8192 + code
  local v = memo[k]
  if v ~= nil then return v end
  local q = rom.char.size // 4
  v = 0
  for p = 0, 3 do
    for b = 0, 7 do
      if rom.char:read_u8(p * q + (code * 8) % q + b) ~= 0 then v = 1 end
    end
  end
  memo[k] = v
  return v
end

local function index16(shape, col, row)
  if shape == 0 then return (col & 0xf) + ((row & 0xf) << 4) + ((col & 0x30) << 4), 64, 16
  elseif shape == 1 then return (col & 0xf) + ((row & 0x1f) << 4) + ((col & 0x10) << 5), 32, 32
  else return (col & 0xf) + ((row & 0x3f) << 4), 16, 64 end
end
local function index8(shape, col, row)
  if shape == 0 then return (col & 0x1f) + ((row & 0x1f) << 5) + ((col & 0x60) << 5)
  elseif shape == 1 then return (col & 0x1f) + ((row & 0x1f) << 5) + ((row & 0x20) << 5) + ((col & 0x20) << 6)
  else return (col & 0x1f) + ((row & 0x7f) << 5) end
end

local prev_visible = {}

local function frame_stats()
  local visible = {}
  local colours, colours9, pal_used = {}, {}, {}
  local layer9 = { [0] = {}, [256] = {}, [512] = {}, [768] = {} }
  local function use_pal(base, pal)
    local k = base + pal * 16
    if pal_used[k] then return end
    pal_used[k] = true
    for pen = 1, 15 do
      local rg, b = pal_rg:read_u16((k + pen) * 2), pal_b:read_u16((k + pen) * 2) & 0xff
      colours[rg * 256 + b] = true
      local c9 = ((rg & 0xe0) << 1) | ((rg >> 13) << 3) | (b >> 5)
      colours9[c9] = true
      layer9[base][c9] = true
    end
  end
  local function count(t)
    local c = 0
    for _ in pairs(t) do c = c + 1 end
    return c
  end

  local entries, tiles, md_sprites, ncodes, flash, behind = 0, 0, 0, 0, 0, 0
  local line_tiles, codes, spr_pals = {}, {}, 0
  local seen_pal = {}
  local hash = 0
  local offs = 0
  while offs < 0x400 do
    local d0, d1, d2 = spriteram:read_u16(offs * 2), spriteram:read_u16(offs * 2 + 2), spriteram:read_u16(offs * 2 + 4)
    local h = 1 << ((d0 >> 11) & 3)
    local w = 1 << ((d0 >> 9) & 3)
    if d0 & 0x8000 == 0 then
      offs = offs + 4
    else
      local sx, sy = d2 & 0x1ff, d0 & 0x1ff
      if sx >= 256 then sx = sx - 512 end
      if sy >= 256 then sy = sy - 512 end
      sx, sy = 240 - sx, 240 - sy
      local colour = d2 >> 12
      local any = false
      local blocks = {}
      for x = 0, w - 1 do
        if offs < 0x400 then
          local code = (spriteram:read_u16(offs * 2 + 2) & 0x1fff) & ~(h - 1)
          for y = 0, h - 1 do
            local c = (d0 & 0x4000 ~= 0) and (code + y) or (code + h - 1 - y)
            local px, py = sx - 16 * x, sy - 16 * y
            local np = quads(rom.spr, 1, c)
            if np > 0 and px > -16 and px < 256 and py > -8 and py < 248 then
              any = true
              tiles = tiles + 1
              local key = "o" .. c
              if not codes[c] then codes[c] = true ncodes = ncodes + 1 end
              visible[key] = np
              blocks[(x // 2) * 8 + (y // 2)] = true
              for l = math.max(py, 8), math.min(py + 15, 247) do line_tiles[l] = (line_tiles[l] or 0) + 1 end
            end
          end
        end
        offs = offs + 4
      end
      if any then
        entries = entries + 1
        hash = (hash * 31 + d0 * 7 + d1 * 13 + d2) % 1000000007
        for _ in pairs(blocks) do md_sprites = md_sprites + 1 end
        if d2 & 0x800 ~= 0 then flash = flash + 1 end
        if colour & 8 ~= 0 then behind = behind + 1 end
        if not seen_pal[colour] then seen_pal[colour] = true spr_pals = spr_pals + 1 end
        use_pal(256, colour)
      end
    end
  end
  local line_max, over = 0, 0
  for l = 8, 247 do
    local n = line_tiles[l] or 0
    if n > line_max then line_max = n end
    if n > 20 then over = over + 1 end
  end

  local lay = {}
  for L = 1, 3 do
    local c0, shape = ctrl[L][1], ctrl[L][4] & 3
    local sx, sy = scroll[L][1], scroll[L][2]
    local r = { uniq = 0, pals = 0, cells = 0, pat = 0, ctrl = c0, shape = shape, sx = sx, sy = sy }
    local seen, pals = {}, {}
    if c0 & 1 ~= 0 then
      for row = 0, 30 do
        for col = 0, 32 do
          local idx = index8(shape, (sx // 8) + col, ((sy + 8) // 8) + row)
          local t = vram[L]:read_u16((idx & 0x1fff) * 2)
          local code, colour = t & 0xfff, t >> 12
          if char_used(code) == 1 then
            r.cells = r.cells + 1
            if not seen[code] then seen[code] = true r.uniq = r.uniq + 1 r.pat = r.pat + 1 end
            visible["c" .. code] = 1
            if not pals[colour] then pals[colour] = true r.pals = r.pals + 1 use_pal(0, colour) end
          end
        end
      end
    else
      for row = 0, 15 do
        for col = 0, 16 do
          local idx = index16(shape, (sx // 16) + col, ((sy + 8) // 16) + row)
          local t = vram[L]:read_u16((idx & 0x1fff) * 2)
          local code, colour = t & 0xfff, t >> 12
          local np = quads(rom[L] or rom[2], L, code)
          if np > 0 then
            r.cells = r.cells + 1
            if not seen[code] then seen[code] = true r.uniq = r.uniq + 1 r.pat = r.pat + np end
            visible["t" .. L .. ":" .. code] = np
            if not pals[colour] then pals[colour] = true r.pals = r.pals + 1 use_pal(L == 2 and 512 or 768, colour) end
          end
        end
      end
    end
    lay[L] = r
  end

  local delta, ws = 0, 0
  for k, c in pairs(visible) do
    ws = ws + c
    if not prev_visible[k] then delta = delta + c end
  end
  prev_visible = visible

  local ncol, ncol9, npal = 0, 0, 0
  for _ in pairs(colours) do ncol = ncol + 1 end
  for _ in pairs(colours9) do ncol9 = ncol9 + 1 end
  for _ in pairs(pal_used) do npal = npal + 1 end
  local s = string.format("%d,%d,%d,%d,%d,%d,%d,%d,%d", entries, tiles, ncodes, md_sprites, line_max, over, spr_pals, flash, behind)
  for L = 1, 3 do
    local r = lay[L]
    s = s .. string.format(",%x,%d,%d,%d,%d,%d,%d,%d", r.ctrl, r.shape, r.sx, r.sy, r.cells, r.uniq, r.pat, r.pals)
  end
  local both = {}
  for c in pairs(layer9[512]) do both[c] = true end
  for c in pairs(layer9[768]) do both[c] = true end
  return s .. string.format(",%d,%d,%d,%d,%d,%x,%d,%d,%d,%d,%d,%x,%d,%d,%d,%d,%d", npal, ncol, ncol9, ws, delta, pri,
    snd_cmds, sub_irqs, dma, idle_reads, hash, cpu.state["PC"].value,
    count(layer9[256]), count(layer9[0]), count(layer9[512]), count(layer9[768]), count(both))
end

local function field(name)
  for _, p in pairs(manager.machine.ioport.ports) do
    if p.fields[name] then return p.fields[name] end
  end
end
local inputs = {}
for _, n in ipairs({ "Coin 1", "1 Player Start", "P1 Right", "P1 Left", "P1 Up", "P1 Down", "P1 Attack", "P1 Jump" }) do
  inputs[n] = field(n)
end
local function press(n, on)
  if inputs[n] then inputs[n]:set_value(on and 1 or 0) end
end

local csv = io.open(out_dir .. "/dec0_frames.csv", "w")
csv:write("frame,obj_entries,obj_tiles,obj_unique,md_sprites_est,obj_line_tiles_max,obj_lines_over_320px,obj_pals,obj_flash,obj_colour8")
for L = 1, 3 do
  local p = "pf" .. L
  csv:write(",", p, "_ctrl,", p, "_shape,", p, "_sx,", p, "_sy,", p, "_cells,", p, "_unique,", p, "_patterns,", p, "_pals")
end
csv:write(",palettes,colours,colours_9bit,working_set_patterns,new_patterns_vs_prev,priority,sound_cmds,sub_irqs,sprite_dma,idle_reads,obj_hash,pc,obj_colours9,pf1_colours9,pf2_colours9,pf3_colours9,pf23_colours9\n")

local frame = 0
local errs = 0
local function on_frame()
  frame = frame + 1
  for _, h in ipairs(holds) do prog:write_u8(h[1], h[2]) end
  csv:write(frame, ",", frame_stats(), "\n")
  snd_cmds, sub_irqs, idle_reads, dma = 0, 0, 0, 0
  if play then
    local t = frame % 1800
    press("Coin 1", t >= 60 and t < 66)
    press("1 Player Start", t >= 120 and t < 126)
    local cyc = frame % 300
    local walk = cyc < 200
    local fight = cyc >= 200 and cyc < 280
    local back = cyc >= 280
    press("P1 Right", walk)
    press("P1 Left", back)
    press("P1 Up", fight and frame % 80 < 20)
    press("P1 Down", fight and frame % 80 >= 40 and frame % 80 < 55)
    press("P1 Attack", frame % 12 < 4)
    press("P1 Jump", walk and frame % 140 >= 70 and frame % 140 < 76)
  end
  if snap_every > 0 and frame % snap_every == 0 then manager.machine.video:snapshot() end
  if frame >= max_frames then
    csv:close()
    manager.machine:exit()
  end
end
sub = emu.add_machine_frame_notifier(function()
  local ok, e = pcall(on_frame)
  if not ok and errs < 5 then errs = errs + 1 print("trace error: " .. tostring(e)) end
end)
