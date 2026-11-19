-- Starts a game in a chosen scene, plays it with the scripted pad, and saves or loads
-- MAME save states. Works on robocop and on the Mega Drive build: both run the same
-- program on the same work RAM.
-- env: TRACE_OUT       folder for level.csv, RAM dumps and snapshots
--      TRACE_FRAMES    frames to run (default 1800)
--      LEVEL           scene index 0-9: forced while the game starts (see docs/05)
--      SAVE            name@frame[,name@frame]: save states written at those frames
--      LOAD            name: save state loaded on the first frame
--      SNAP_EVERY      snapshot and level.csv row every N frames (default 300)
--      DUMP_RAM=1      also write work RAM beside each snapshot
--      HOLD            hex address=value bytes rewritten every frame (ffb242=28 keeps energy full)
--      POKE            hex address=value@frame, written once
--      PLAY=none       no pad after the coin and start
local out_dir = os.getenv("TRACE_OUT") or "."
local max_frames = tonumber(os.getenv("TRACE_FRAMES") or "1800")
local every = tonumber(os.getenv("SNAP_EVERY") or "300")
local level = tonumber(os.getenv("LEVEL") or "")
local load_name = os.getenv("LOAD")
local dump_ram = os.getenv("DUMP_RAM") == "1"
local play = os.getenv("PLAY") ~= "none"
local prog = manager.machine.devices[":maincpu"].spaces["program"]

local SCENE, STAGE, SCENE_TABLE = 0xffb21d, 0xffb218, 0x3ee2
local FORCE_FROM, FORCE_UNTIL = 100, 400

local holds, pokes, saves = {}, {}, {}
for a, v in string.gmatch(os.getenv("HOLD") or "", "(%x+)=(%x+)") do holds[#holds + 1] = { tonumber(a, 16), tonumber(v, 16) } end
for a, v, f in string.gmatch(os.getenv("POKE") or "", "(%x+)=(%x+)@(%d+)") do pokes[#pokes + 1] = { tonumber(a, 16), tonumber(v, 16), tonumber(f) } end
for n, f in string.gmatch(os.getenv("SAVE") or "", "([%w_]+)@(%d+)") do saves[#saves + 1] = { n, tonumber(f) } end

local arcade = { coin = "Coin 1", start = "1 Player Start", right = "P1 Right", left = "P1 Left", up = "P1 Up", down = "P1 Down", attack = "P1 Attack", jump = "P1 Jump" }
local md = { coin = "P1 A", start = "P1 Start", right = "P1 Right", left = "P1 Left", up = "P1 Up", down = "P1 Down", attack = "P1 B", jump = "P1 C" }
local function field(name)
  for _, p in pairs(manager.machine.ioport.ports) do
    for fname, f in pairs(p.fields) do
      if fname == name then return f end
    end
  end
end
local names = field("Coin 1") and arcade or md
local inputs = {}
for k, n in pairs(names) do inputs[k] = field(n) end
local function press(k, on)
  if inputs[k] then inputs[k]:set_value(on and 1 or 0) end
end

local csv = io.open(out_dir .. "/level.csv", "w")
csv:write("frame,scene,stage,steps,energy,player_x,player_y,scroll,objects\n")
local function row(frame)
  csv:write(string.format("%d,%d,%d,%d,%d,%d,%d,%d,%d\n", frame, prog:read_u8(SCENE), prog:read_u8(STAGE),
    prog:read_u16(0xff800a), prog:read_u8(0xffb242), prog:read_u16(0xffb238), prog:read_u16(0xffb23c),
    prog:read_u16(0xff8f7c), prog:read_u8(0xff983b)))
end

local frame = 0
local base = 0
sub = emu.add_machine_frame_notifier(function()
  frame = frame + 1
  if frame == 1 and load_name then
    manager.machine:load(load_name)
    return
  end
  local t = frame
  for _, h in ipairs(holds) do prog:write_u8(h[1], h[2]) end
  for _, p in ipairs(pokes) do if p[3] == frame then prog:write_u8(p[1], p[2]) end end
  if not load_name then
    press("coin", t >= 60 and t < 66)
    press("start", t >= 120 and t < 126)
    if level and t >= FORCE_FROM and t <= FORCE_UNTIL then
      prog:write_u8(SCENE, level)
      prog:write_u8(STAGE, prog:read_u8(SCENE_TABLE + level))
    end
  end
  if play and (load_name or t > 400) then
    local cyc = frame % 300
    local walk = cyc < 200
    local fight = cyc >= 200 and cyc < 280
    press("right", walk)
    press("left", cyc >= 280)
    press("up", fight and frame % 80 < 20)
    press("down", fight and frame % 80 >= 40 and frame % 80 < 55)
    press("attack", frame % 12 < 4)
    press("jump", walk and frame % 140 >= 70 and frame % 140 < 76)
  end
  for _, s in ipairs(saves) do if s[2] == frame then manager.machine:save(s[1]) end end
  if frame % every == 0 then
    row(frame)
    if dump_ram then
      local f = io.open(string.format("%s/ram_%06d.ram", out_dir, frame), "wb")
      f:write(prog:read_range(0xff8000, 0xffbfff, 8))
      f:close()
    end
    manager.machine.video:snapshot()
  end
  if frame >= max_frames then
    csv:close()
    manager.machine:exit()
  end
end)
