-- Logs every write the robocop sound CPU makes to its three chips, and every
-- command the 68000 sends it, with the time of each.
-- env: TRACE_OUT, TRACE_FRAMES, HOLD, TRACE_INPUT=none to leave the game in attract mode
-- out: sound_log.csv (seconds, chip, register or port, value)
--      chip: c = command from the 68000, n = YM2203, l = YM3812, o = OKI M6295

local out_dir = os.getenv("TRACE_OUT") or "."
local max_frames = tonumber(os.getenv("TRACE_FRAMES") or "10800")
local play = os.getenv("TRACE_INPUT") ~= "none"
local main = manager.machine.devices[":maincpu"].spaces["program"]
local snd = manager.machine.devices[":audiocpu"].spaces["program"]
local holds = {}
for a, v in string.gmatch(os.getenv("HOLD") or "", "(%x+)=(%x+)") do holds[#holds + 1] = { tonumber(a, 16), tonumber(v, 16) } end

local log = io.open(out_dir .. "/sound_log.csv", "w")
local opn_reg, opl_reg = 0, 0
local function now() return manager.machine.time:as_double() end
taps = {}
taps[#taps + 1] = snd:install_write_tap(0x0800, 0x0801, "opn", function(offset, data)
  if offset == 0x0800 then opn_reg = data else log:write(string.format("%.6f,n,%02x,%02x\n", now(), opn_reg, data)) end
end)
taps[#taps + 1] = snd:install_write_tap(0x1000, 0x1001, "opl", function(offset, data)
  if offset == 0x1000 then opl_reg = data else log:write(string.format("%.6f,l,%02x,%02x\n", now(), opl_reg, data)) end
end)
taps[#taps + 1] = snd:install_write_tap(0x3800, 0x3800, "oki", function(offset, data)
  log:write(string.format("%.6f,o,00,%02x\n", now(), data))
end)
taps[#taps + 1] = main:install_write_tap(0x30c014, 0x30c015, "cmd", function(offset, data, mask)
  if mask & 0xff ~= 0 then log:write(string.format("%.6f,c,00,%02x\n", now(), data & 0xff)) end
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

local frame = 0
sub = emu.add_machine_frame_notifier(function()
  frame = frame + 1
  for _, h in ipairs(holds) do main:write_u8(h[1], h[2]) end
  if play then
    local t = frame % 1800
    press("Coin 1", t >= 60 and t < 66)
    press("1 Player Start", t >= 120 and t < 126)
    local cyc = frame % 300
    press("P1 Right", cyc < 200)
    press("P1 Left", cyc >= 280)
    press("P1 Up", cyc >= 200 and cyc < 280 and frame % 80 < 20)
    press("P1 Down", cyc >= 200 and cyc < 280 and frame % 80 >= 40 and frame % 80 < 55)
    press("P1 Attack", frame % 12 < 4)
    press("P1 Jump", cyc < 200 and frame % 140 >= 70 and frame % 140 < 76)
  end
  if frame >= max_frames then
    log:close()
    manager.machine:exit()
  end
end)
