-- Let the 1985 driver relocate itself once, and take the result away.
--
--   DRV=payload RELOC=reloc.bin OUT=blob ./mame.sh cpc6128 -autoboot_script grab_blob.lua
--
-- DRV is the 6016-byte driver, headerless; RELOC is tools/reloc.asm assembled,
-- headerless. Both are written straight into RAM above &4000, where the
-- emulator can reach them -- below that it sees the lower ROM, which is why
-- the driver is copied down to &0200 by the Z80 and back up again afterwards
-- rather than being read there. Then BASIC is asked to CALL it.
--
-- This used to go through a BASIC loader on a disc, which was one more thing
-- to get wrong: an ASCII .BAS needs CRLF and a 1Ah or BASIC RUNs it, finds
-- nothing, and says Ready -- which looks exactly like success.
NK   = manager.machine.natkeyboard; NK.in_use = true
PROG = manager.machine.devices[":maincpu"].spaces["program"]

local function slurp(path)
  local f = assert(io.open(path, "rb"), "cannot read " .. path)
  local d = f:read("*a"); f:close(); return d
end
local function poke(addr, data)
  for i = 1, #data do PROG:write_u8(addr + i - 1, data:byte(i)) end
end

local drv, reloc = slurp(os.getenv("DRV")), slurp(os.getenv("RELOC"))
local F, called = 0, false

N = emu.add_machine_frame_notifier(function()
  F = F + 1
  if F == 300 then
    poke(0x4000, drv)                               -- the driver, as it came
    poke(0x8000, reloc)                             -- and the relocator
    PROG:write_u8(0x7FFF, 0)
    NK:post_coded('CALL &8000{ENTER}')
    called = true
  end
  if called and F > 320 and PROG:read_u8(0x7FFF) == 0xAA then
    local f = io.open(os.getenv("OUT"), "wb")
    for i = 0x4000, 0x4000 + 6015 do f:write(string.char(PROG:read_u8(i))) end
    f:close()
    print("=== relocated blob dumped")
    manager.machine:exit()
  end
  if F == 1800 then print("=== gave up"); manager.machine:exit() end
end)
