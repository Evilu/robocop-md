-- Sampling profiler for the robocop 68000 program under MAME.
-- Samples the PC and a heuristic call stack many times per frame.
-- env: TRACE_OUT, TRACE_FRAMES, PROFILE_FROM (first frame counted in the per-address totals),
--      PROFILE_HZ (samples per second, default 12000), ROM_SIZE (hex, default 40000),
--      IDLE (PC ranges of the frame wait loops, hex "lo-hi,lo-hi"; robocop 17ba-17cc,17e8-17fa),
--      SUBWAIT (PC ranges of loops that wait for the HuC6280), HOLD (as in dec0_trace.lua)
-- out: profile_frames.csv (frame, samples, idle, waiting for the sub CPU, in the VBlank handler),
--      profile_leaf.csv (pc, samples), profile_incl.csv (call target, samples with it on the stack)

local out_dir = os.getenv("TRACE_OUT") or "."
local max_frames = tonumber(os.getenv("TRACE_FRAMES") or "10800")
local from = tonumber(os.getenv("PROFILE_FROM") or "0")
local hz = tonumber(os.getenv("PROFILE_HZ") or "12000")
local rom_size = tonumber(os.getenv("ROM_SIZE") or "40000", 16)

local function ranges(name, default)
  local t = {}
  for lo, hi in string.gmatch(os.getenv(name) or default, "(%x+)-(%x+)") do t[#t + 1] = { tonumber(lo, 16), tonumber(hi, 16) } end
  return t
end
local function within(t, pc)
  for _, r in ipairs(t) do
    if pc >= r[1] and pc < r[2] then return true end
  end
  return false
end
local idle = ranges("IDLE", "17ba-17cc,17e8-17fa")
local subwait = ranges("SUBWAIT", "")
local holds = {}
for a, v in string.gmatch(os.getenv("HOLD") or "", "(%x+)=(%x+)") do holds[#holds + 1] = { tonumber(a, 16), tonumber(v, 16) } end

local cpu = manager.machine.devices[":maincpu"]
local prog = cpu.spaces["program"]
local f_samples, f_idle, f_sub, f_irq = 0, 0, 0, 0
local frames_csv = io.open(out_dir .. "/profile_frames.csv", "w")
frames_csv:write("frame,samples,idle,subwait,vblank\n")

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

local frame = 0
local done = false
sub = emu.add_machine_frame_notifier(function()
  frame = frame + 1
  for _, h in ipairs(holds) do prog:write_u8(h[1], h[2]) end
  frames_csv:write(frame, ",", f_samples, ",", f_idle, ",", f_sub, ",", f_irq, "\n")
  f_samples, f_idle, f_sub, f_irq = 0, 0, 0, 0
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
  if frame >= max_frames then done = true end
end)

local leaf, incl = {}, {}
local samples = 0

local function s16(v) if v >= 0x8000 then return v - 0x10000 end return v end

local function callee(ret)
  if ret & 1 ~= 0 or ret < 0x100 or ret >= rom_size then return nil end
  if prog:read_u16(ret - 6) == 0x4eb9 then
    local t = prog:read_u32(ret - 4)
    if t < rom_size then return t end
  end
  local w4 = prog:read_u16(ret - 4)
  if w4 == 0x4eba or w4 == 0x6100 then return (ret - 2 + s16(prog:read_u16(ret - 2))) & 0xffffff end
  local w2 = prog:read_u16(ret - 2)
  if (w2 & 0xff00) == 0x6100 and (w2 & 0xff) ~= 0 and (w2 & 0xff) ~= 0xff then
    local d = w2 & 0xff
    if d >= 0x80 then d = d - 0x100 end
    return ret + d
  end
  if w2 >= 0x4e90 and w2 <= 0x4e97 then return -(ret - 2) end
  return nil
end

local function sample()
  local pc = cpu.state["PC"].value & 0xffffff
  local sr = cpu.state["SR"].value
  f_samples = f_samples + 1
  if within(idle, pc) then f_idle = f_idle + 1
  elseif within(subwait, pc) then f_sub = f_sub + 1 end
  if sr & 0x0700 >= 0x0600 then f_irq = f_irq + 1 end
  if frame < from then return end
  samples = samples + 1
  leaf[pc] = (leaf[pc] or 0) + 1
  local sp = cpu.state["SP"].value & 0xffffff
  if sp < 0xff8000 then return end
  local seen = {}
  for i = 0, 47 do
    local a = sp + i * 2
    if a > 0xffbffc then break end
    local v = prog:read_u32(a)
    if v >= 0x100 and v < rom_size and v & 1 == 0 then
      local t = callee(v)
      if t and not seen[t] then
        seen[t] = true
        incl[t] = (incl[t] or 0) + 1
      end
    end
  end
end

local function dump(name, t)
  local f = io.open(out_dir .. "/" .. name, "w")
  for k, v in pairs(t) do f:write(tostring(k), ",", v, "\n") end
  f:close()
end

local step = 1 / hz
while not done do
  emu.wait(step)
  local ok, e = pcall(sample)
  if not ok then print("profile error: " .. tostring(e)) break end
end
frames_csv:close()
dump("profile_leaf.csv", leaf)
dump("profile_incl.csv", incl)
manager.machine:exit()
