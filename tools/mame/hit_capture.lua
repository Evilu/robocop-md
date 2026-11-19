-- Captures the hit detection's inputs and outputs, once per game step, on the
-- arcade (robocop: the dual-port RAM before the HuC6280's interrupt and after it
-- has finished) or on the Mega Drive build (genesis: the player's values in the stand-in
-- at SHARED, the object records in work RAM, where the build's routine works on them).
-- env: TRACE_OUT, TRACE_FRAMES, HOLD
-- out: hit_capture.bin: per step, 1,218 bytes in (dual-port offsets 0 to 0x4c1) then 1,218 bytes out
-- Plays the same blind script as the other traces.

local out_dir = os.getenv("TRACE_OUT") or "."
local max_frames = tonumber(os.getenv("TRACE_FRAMES") or "5400")
local arcade = manager.machine.system.name == "robocop"
local cpu = manager.machine.devices[":maincpu"]
local prog = cpu.spaces["program"]
local base = arcade and 0x180000 or 0xff1000
local size = 0x12 + 1200
local holds = {}
for a, v in string.gmatch(os.getenv("HOLD") or "", "(%x+)=(%x+)") do holds[#holds + 1] = { tonumber(a, 16), tonumber(v, 16) } end

local out = io.open(out_dir .. "/hit_capture.bin", "wb")
local function snapshot(flag)
  local t = {}
  for i = 0, size - 1 do
    local v
    if i == 4 then v = flag
    elseif not arcade and i >= 0x12 then v = prog:read_u8(0xff983c + i - 0x12)
    else v = prog:read_u8(base + 2 * i + 1) end
    t[#t + 1] = string.char(v)
  end
  return table.concat(t)
end
local before, steps = nil, 0
local function finished()
  if not before then return end
  out:write(before, snapshot(0))
  before = nil
  steps = steps + 1
end
taps = {}
if arcade then
  taps[#taps + 1] = prog:install_write_tap(0x180ffe, 0x180fff, "irq", function() before = snapshot(0xff) end)
  local sub = manager.machine.devices[":sub"].spaces["program"]
  taps[#taps + 1] = sub:install_write_tap(0x1f2004, 0x1f2004, "done", function(offset, data)
    if data == 0 then finished() end
  end)
else
  taps[#taps + 1] = prog:install_write_tap(base + 8, base + 9, "flag", function(offset, data, mask)
    if mask & 0xff == 0 then return end
    if data & 0xff == 0xff then before = snapshot(0xff) else finished() end
  end)
end

local function field(names)
  for _, p in pairs(manager.machine.ioport.ports) do
    for _, n in ipairs(names) do
      if p.fields[n] then return p.fields[n] end
    end
  end
end
local inputs = {
  coin = field({ "Coin 1", "P1 A" }), start = field({ "1 Player Start", "P1 Start" }), right = field({ "P1 Right" }),
  left = field({ "P1 Left" }), up = field({ "P1 Up" }), down = field({ "P1 Down" }),
  attack = field({ "P1 Attack", "P1 B" }), jump = field({ "P1 Jump", "P1 C" }),
}
local function press(n, on) if inputs[n] then inputs[n]:set_value(on and 1 or 0) end end

local frame = 0
sub_frames = emu.add_machine_frame_notifier(function()
  frame = frame + 1
  for _, h in ipairs(holds) do prog:write_u8(h[1], h[2]) end
  local t = frame % 1800
  press("coin", t >= 60 and t < 66)
  press("start", t >= 120 and t < 126)
  local cyc = frame % 300
  press("right", cyc < 200)
  press("left", cyc >= 280)
  press("up", cyc >= 200 and cyc < 280 and frame % 80 < 20)
  press("down", cyc >= 200 and cyc < 280 and frame % 80 >= 40 and frame % 80 < 55)
  press("attack", frame % 12 < 4)
  press("jump", cyc < 200 and frame % 140 >= 70 and frame % 140 < 76)
  if frame >= max_frames then
    out:close()
    print("steps captured", steps)
    manager.machine:exit()
  end
end)
