local done = false
emu.register_frame_done(function()
  if done then return end
  done = true
  for tag, dev in pairs(manager.machine.devices) do
    local sp = {}
    for n, s in pairs(dev.spaces) do sp[#sp + 1] = n end
    if #sp > 0 then print("device", tag, table.concat(sp, ",")) end
  end
  for tag, sh in pairs(manager.machine.memory.shares) do print("share", tag, sh.size) end
  for tag, r in pairs(manager.machine.memory.regions) do print("region", tag, r.size) end
  for tag, p in pairs(manager.machine.ioport.ports) do
    local f = {}
    for n, _ in pairs(p.fields) do f[#f + 1] = n end
    print("port", tag, table.concat(f, " | "))
  end
  manager.machine:exit()
end)
