-- Sampling profiler for the Mega Drive build: where the 68000's time goes, by routine
-- of the hardware layer (from the .sym file the build writes beside the ROM) and, for
-- the arcade program, waiting against working.
-- env: SYMBOLS (the .sym file), LEVEL (scene to start in) or LOAD (save state),
--      TRACE_FRAMES (default 2400), PROFILE_FROM (default 600), PROFILE_HZ (default 20000),
--      HOLD (hex address=value)
local cpu = manager.machine.devices[":maincpu"]
local prog = cpu.spaces["program"]
local max_frames = tonumber(os.getenv("TRACE_FRAMES") or "2400")
local from = tonumber(os.getenv("PROFILE_FROM") or "600")
local hz = tonumber(os.getenv("PROFILE_HZ") or "20000")
local level = tonumber(os.getenv("LEVEL") or "")
local load_name = os.getenv("LOAD")
local holds = {}
for a, v in string.gmatch(os.getenv("HOLD") or "ffb242=28", "(%x+)=(%x+)") do holds[#holds + 1] = { tonumber(a, 16), tonumber(v, 16) } end

local syms = {}
for line in io.lines(os.getenv("SYMBOLS")) do
  local a, n = line:match("^(%x+) (%S+)")
  syms[#syms + 1] = { tonumber(a, 16), n }
end
local function routine(pc)
  local lo, hi = 1, #syms
  while lo < hi do
    local mid = (lo + hi + 1) // 2
    if syms[mid][1] <= pc then lo = mid else hi = mid - 1 end
  end
  return syms[lo][2]
end
local idle = { { 0x17ba, 0x17ce }, { 0x17e8, 0x17fc }, { 0x1156, 0x1168 } }

local function field(name)
  for _, p in pairs(manager.machine.ioport.ports) do
    for fname, f in pairs(p.fields) do if fname == name then return f end end
  end
end
local pad = { coin = field("P1 A"), start = field("P1 Start"), right = field("P1 Right"), attack = field("P1 B"), jump = field("P1 C") }

local counts, total, frame, steps0 = {}, 0, 0, nil
local done = false
local function sample()
  if frame < from then return end
  local pc = cpu.state["PC"].value & 0xffffff
  local key
  if pc >= 0x40000 and pc < 0x80000 then key = routine(pc)
  else
    key = "game: work"
    for _, r in ipairs(idle) do if pc >= r[1] and pc < r[2] then key = "game: frame wait" end end
    if (cpu.state["SR"].value & 0x0700) >= 0x0600 and key == "game: work" then key = "game: VBlank handler" end
  end
  counts[key] = (counts[key] or 0) + 1
  total = total + 1
end
local t = emu.add_machine_frame_notifier(function()
  frame = frame + 1
  if frame == 1 and load_name then manager.machine:load(load_name) return end
  for _, h in ipairs(holds) do prog:write_u8(h[1], h[2]) end
  if not load_name then
    pad.coin:set_value((frame >= 60 and frame < 66) and 1 or 0)
    pad.start:set_value((frame >= 120 and frame < 126) and 1 or 0)
    if level and frame >= 100 and frame <= 400 then
      prog:write_u8(0xffb21d, level)
      prog:write_u8(0xffb218, prog:read_u8(0x3ee2 + level))
    end
  end
  if load_name or frame > 400 then
    pad.right:set_value((frame % 300 < 200) and 1 or 0)
    pad.attack:set_value((frame % 12 < 4) and 1 or 0)
    pad.jump:set_value((frame % 140 >= 70 and frame % 140 < 76) and 1 or 0)
  end
  if frame == from then steps0 = prog:read_u16(0xff800a) end
  if frame >= max_frames then
    local rows = {}
    for k, v in pairs(counts) do rows[#rows + 1] = { k, v } end
    table.sort(rows, function(a, b) return a[2] > b[2] end)
    local frames = max_frames - from
    local steps = prog:read_u16(0xff800a) - steps0
    print(string.format("profile: %d frames, %d game steps (%.0f%% of one every second frame), %d samples", frames, steps, steps * 200 / frames, total))
    for i = 1, math.min(#rows, 28) do
      print(string.format("profile: %5.1f%%  %6.0f cycles a frame  %s", rows[i][2] * 100 / total, rows[i][2] / total * 128012, rows[i][1]))
    end
    done = true
  end
end)
while not done do
  emu.wait(1 / hz)
  local ok, e = pcall(sample)
  if not ok then print("profile error: " .. tostring(e)) break end
end
manager.machine:exit()
