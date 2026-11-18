-- Sound chip usage for MAME's robocop driver: what the 6502 writes to the YM2203,
-- the YM3812 and the OKI M6295, and which commands the 68000 sends.
-- env: TRACE_OUT, TRACE_FRAMES, HOLD (as in dec0_trace.lua)
-- out: sound_summary.txt

local out_dir = os.getenv("TRACE_OUT") or "."
local max_frames = tonumber(os.getenv("TRACE_FRAMES") or "10800")
local main = manager.machine.devices[":maincpu"].spaces["program"]
local snd = manager.machine.devices[":audiocpu"].spaces["program"]
local holds = {}
for a, v in string.gmatch(os.getenv("HOLD") or "", "(%x+)=(%x+)") do holds[#holds + 1] = { tonumber(a, 16), tonumber(v, 16) } end

local opn_reg, opl_reg = 0, 0
local opn, opl, oki, cmds = {}, {}, {}, {}
local opn_keyon, opl_keyon, ssg_on = {}, {}, {}
local opl_prev = {}
local oki_pending = nil
local function bump(t, k) t[k] = (t[k] or 0) + 1 end
taps = {}
taps[#taps + 1] = snd:install_write_tap(0x0800, 0x0801, "opn", function(offset, data)
  if offset == 0x0800 then opn_reg = data return end
  bump(opn, opn_reg)
  if opn_reg == 0x28 and data & 0xf0 ~= 0 then bump(opn_keyon, data & 3) end
  if opn_reg >= 8 and opn_reg <= 10 and data & 0x1f ~= 0 then bump(ssg_on, opn_reg - 8) end
end)
taps[#taps + 1] = snd:install_write_tap(0x1000, 0x1001, "opl", function(offset, data)
  if offset == 0x1000 then opl_reg = data return end
  bump(opl, opl_reg)
  if opl_reg >= 0xb0 and opl_reg <= 0xb8 then
    if data & 0x20 ~= 0 and not opl_prev[opl_reg] then bump(opl_keyon, opl_reg - 0xb0) end
    opl_prev[opl_reg] = data & 0x20 ~= 0
  end
  if opl_reg == 0xbd and data & 0x20 ~= 0 then bump(opl_keyon, "rhythm") end
end)
taps[#taps + 1] = snd:install_write_tap(0x3800, 0x3800, "oki", function(offset, data)
  if oki_pending then
    bump(oki, string.format("sample %02x on voices %x", oki_pending, data >> 4))
    oki_pending = nil
  elseif data & 0x80 ~= 0 then
    oki_pending = data & 0x7f
  else
    bump(oki, "stop")
  end
end)
taps[#taps + 1] = main:install_write_tap(0x30c014, 0x30c015, "cmd", function(offset, data, mask)
  if mask & 0xff ~= 0 then bump(cmds, data & 0xff) end
end)

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

local function list(f, title, t, fmt)
  local keys = {}
  for k in pairs(t) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  f:write(title, ":")
  for _, k in ipairs(keys) do f:write(" ", type(k) == "number" and string.format(fmt, k) or k, "=", t[k]) end
  f:write("\n")
end

local frame = 0
sub = emu.add_machine_frame_notifier(function()
  frame = frame + 1
  for _, h in ipairs(holds) do main:write_u8(h[1], h[2]) end
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
  if frame >= max_frames then
    local f = io.open(out_dir .. "/sound_summary.txt", "w")
    f:write("frames ", frame, "\n")
    list(f, "commands from the 68000 (value=count)", cmds, "%02x")
    list(f, "YM2203 register writes", opn, "%02x")
    list(f, "YM2203 FM key-ons per channel", opn_keyon, "%d")
    list(f, "YM2203 SSG channels given volume", ssg_on, "%d")
    list(f, "YM3812 register writes", opl, "%02x")
    list(f, "YM3812 key-ons per channel", opl_keyon, "%d")
    list(f, "OKI M6295", oki, "%s")
    f:close()
    manager.machine:exit()
  end
end)
