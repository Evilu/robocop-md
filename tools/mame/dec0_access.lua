-- Hardware access and work RAM usage map for the robocop 68000 program under MAME.
-- Records every instruction address that reads or writes arcade hardware and
-- every work RAM byte written.
-- env: TRACE_OUT, TRACE_FRAMES, BOOT_CLEAR (PC range of the reset RAM clear, hex "lo-hi", not counted;
--      robocop 14e-15e), RAM_FROM_FRAME (ignore RAM writes before this frame), HOLD (as in dec0_trace.lua)
-- out: access_pcs.csv (pc, region, reads, writes, lowest address, highest address)
--      ram_written.bin (18432 bytes: 1 where the byte at 0xFF8000+i was written; work RAM then sprite RAM)
--      shared_written.bin (2048 bytes: 1 where the 68000 wrote the dual-port RAM byte i)

local out_dir = os.getenv("TRACE_OUT") or "."
local max_frames = tonumber(os.getenv("TRACE_FRAMES") or "10800")
local cpu = manager.machine.devices[":maincpu"]
local prog = cpu.spaces["program"]
local curpc = cpu.state["CURPC"]

local clear_lo, clear_hi = 1, 0
if os.getenv("BOOT_CLEAR") then
  local lo, hi = os.getenv("BOOT_CLEAR"):match("(%x+)-(%x+)")
  clear_lo, clear_hi = tonumber(lo, 16), tonumber(hi, 16)
end
local holds = {}
for a, v in string.gmatch(os.getenv("HOLD") or "", "(%x+)=(%x+)") do holds[#holds + 1] = { tonumber(a, 16), tonumber(v, 16) } end

local ram_from = tonumber(os.getenv("RAM_FROM_FRAME") or "0")
local frame = 0

local regions = {
  { 0x180000, 0x180fff, "shared" },
  { 0x240000, 0x24001f, "pf1_reg" }, { 0x242000, 0x2427ff, "pf1_scroll" }, { 0x242800, 0x243fff, "ram_242800" },
  { 0x244000, 0x245fff, "pf1_map" },
  { 0x246000, 0x24601f, "pf2_reg" }, { 0x248000, 0x2487ff, "pf2_scroll" }, { 0x24a000, 0x24a7ff, "pf2_map" },
  { 0x24c000, 0x24c01f, "pf3_reg" }, { 0x24c800, 0x24cfff, "pf3_scroll" }, { 0x24d000, 0x24d7ff, "pf3_map" },
  { 0x30c000, 0x30c00f, "inputs" }, { 0x30c010, 0x30c01f, "control" },
  { 0x310000, 0x3107ff, "pal_rg" }, { 0x314000, 0x3147ff, "pal_b" },
  { 0xffc000, 0xffc7ff, "sprite_ram" },
}
local acc = {}
local shared = {}
local function note(region, write)
  return function(offset, data, mask)
    local key = (curpc.value & 0xffffff) * 32 + region
    local e = acc[key]
    if not e then
      e = { 0, 0, offset, offset }
      acc[key] = e
    end
    if write then e[2] = e[2] + 1 else e[1] = e[1] + 1 end
    if offset < e[3] then e[3] = offset end
    if offset > e[4] then e[4] = offset end
    if region == 1 and write then shared[(offset - 0x180000) // 2] = true end
  end
end
taps = {}
for i, r in ipairs(regions) do
  taps[#taps + 1] = prog:install_read_tap(r[1], r[2], "r" .. i, note(i, false))
  taps[#taps + 1] = prog:install_write_tap(r[1], r[2], "w" .. i, note(i, true))
end

local written = {}
taps[#taps + 1] = prog:install_write_tap(0xff8000, 0xffc7ff, "ram", function(offset, data, mask)
  if frame < ram_from then return end
  local pc = curpc.value & 0xffffff
  if pc >= clear_lo and pc < clear_hi then return end
  local a = (offset - 0xff8000) & 0xfffe
  if mask & 0xff00 ~= 0 then written[a] = true end
  if mask & 0x00ff ~= 0 then written[a + 1] = true end
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

local function bitmap(name, t, size)
  local parts = {}
  for i = 0, size - 1 do parts[#parts + 1] = t[i] and "\1" or "\0" end
  local b = io.open(out_dir .. "/" .. name, "wb")
  b:write(table.concat(parts))
  b:close()
end

sub = emu.add_machine_frame_notifier(function()
  frame = frame + 1
  for _, h in ipairs(holds) do prog:write_u8(h[1], h[2]) end
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
    local f = io.open(out_dir .. "/access_pcs.csv", "w")
    f:write("pc,region,reads,writes,low,high\n")
    for key, e in pairs(acc) do
      f:write(string.format("%06x,%s,%d,%d,%06x,%06x\n", key // 32, regions[key % 32][3], e[1], e[2], e[3], e[4]))
    end
    f:close()
    bitmap("ram_written.bin", written, 0x4800)
    bitmap("shared_written.bin", shared, 0x800)
    manager.machine:exit()
  end
end)
