-- Game-state probe for the Mega Drive build under MAME's genesis driver.
-- Prints the arcade program's own counters and player state while pressing pad
-- buttons, and records any access to an arcade hardware address the build did
-- not redirect (on the Mega Drive those are cartridge space).
-- env: TRACE_FRAMES, STATE_EVERY (frames between state lines), TRACE_OUT,
--      PRESS ("frame:button,frame:button", button held 8 frames; e.g. "700:A,800:Start"),
--      TRACE_INPUT=play adds the arcade trace's blind play script (A = coin, Start, walk, B, C),
--      HOLD (hex address=value bytes rewritten every frame), TRACE_SNAP_EVERY
-- out: stray_access.csv (pc, address, reads, writes)

local out_dir = os.getenv("TRACE_OUT") or "."
local max_frames = tonumber(os.getenv("TRACE_FRAMES") or "3600")
local every = tonumber(os.getenv("STATE_EVERY") or "300")
local snap_every = tonumber(os.getenv("TRACE_SNAP_EVERY") or "0")
local cpu = manager.machine.devices[":maincpu"]
local prog = cpu.spaces["program"]
local curpc = cpu.state["CURPC"]
local pad = manager.machine.ioport.ports[":ctrl1:mdpad:PAD"]
local holds = {}
for a, v in string.gmatch(os.getenv("HOLD") or "", "(%x+)=(%x+)") do holds[#holds + 1] = { tonumber(a, 16), tonumber(v, 16) } end
local presses = {}
for f, b in string.gmatch(os.getenv("PRESS") or "", "(%d+):(%a+)") do presses[#presses + 1] = { tonumber(f), "P1 " .. b } end

local stray = {}
local function note(write)
  return function(offset)
    local key = (curpc.value & 0xffffff) * 0x1000000 + offset
    local e = stray[key]
    if not e then e = { 0, 0 } stray[key] = e end
    e[write and 2 or 1] = e[write and 2 or 1] + 1
  end
end
taps = {}
for i, r in ipairs({ { 0x180000, 0x180fff }, { 0x240000, 0x24ffff }, { 0x30c000, 0x30c01f }, { 0x310000, 0x3147ff } }) do
  taps[#taps + 1] = prog:install_read_tap(r[1], r[2], "sr" .. i, note(false))
  taps[#taps + 1] = prog:install_write_tap(r[1], r[2], "sw" .. i, note(true))
end

local function press(name, on)
  local fld = pad and pad.fields[name]
  if fld then fld:set_value(on and 1 or 0) end
end

local frame = 0
sub = emu.add_machine_frame_notifier(function()
  frame = frame + 1
  for _, h in ipairs(holds) do prog:write_u8(h[1], h[2]) end
  if os.getenv("TRACE_INPUT") == "play" then
    local t = frame % 1800
    press("P1 A", t >= 60 and t < 66)
    press("P1 Start", t >= 120 and t < 126)
    local cyc = frame % 300
    press("P1 Right", cyc < 200)
    press("P1 Left", cyc >= 280)
    press("P1 Up", cyc >= 200 and cyc < 280 and frame % 80 < 20)
    press("P1 Down", cyc >= 200 and cyc < 280 and frame % 80 >= 40 and frame % 80 < 55)
    press("P1 B", frame % 12 < 4)
    press("P1 C", cyc < 200 and frame % 140 >= 70 and frame % 140 < 76)
  end
  for _, p in ipairs(presses) do
    if frame == p[1] then press(p[2], true) elseif frame == p[1] + 8 then press(p[2], false) end
  end
  if frame % every == 0 then
    local n = 0
    for _ in pairs(stray) do n = n + 1 end
    print(string.format("frame %5d pc %06x sr %04x  hal frames %d  steps %04x  flags %02x  credits/mode %02x  energy %02x  player x %04x y %04x  objects %d  scroll %04x  stray %d  sprites dropped %d",
      frame, cpu.state["PC"].value & 0xffffff, cpu.state["SR"].value, prog:read_u32(0xffd000), prog:read_u16(0xff800a),
      prog:read_u8(0xff8000), prog:read_u8(0xffb235), prog:read_u8(0xffb242), prog:read_u16(0xffb238), prog:read_u16(0xffb23c),
      prog:read_u8(0xff983b), prog:read_u16(0xff8f7c), n, prog:read_u16(0xffd026)))
  end
  if snap_every > 0 and frame % snap_every == 0 then manager.machine.video:snapshot() end
  if frame >= max_frames then
    local f = io.open(out_dir .. "/stray_access.csv", "w")
    f:write("pc,address,reads,writes\n")
    for key, e in pairs(stray) do
      f:write(string.format("%06x,%06x,%d,%d\n", key // 0x1000000, key % 0x1000000, e[1], e[2]))
    end
    f:close()
    manager.machine:exit()
  end
end)
