-- Does the vector head run from an expansion ROM?  Posts |VH and checks that
-- the RSX copied both payloads into RAM, then dumps the screen.
NK=manager.machine.natkeyboard; NK.in_use=true
PROG=manager.machine.devices[":maincpu"].spaces["program"]
F=0; sent=nil; done=nil
N=emu.add_machine_frame_notifier(function()
  F=F+1
  if F==260 then NK:post_coded('{ENTER}') end
  if F==340 then print("=== posting |VH"); NK:post_coded('|VH{ENTER}'); sent=F end
  if sent and F==sent+200 then
    -- the head's first byte is JP start; the rules begin with their own bytes
    print(string.format("=== #8000 = %02X  (C3 means the head was copied)",
                        PROG:read_u8(0x8000)))
    print(string.format("=== #2000 = %02X %02X %02X  (the NRL rules)",
                        PROG:read_u8(0x2000), PROG:read_u8(0x2001),
                        PROG:read_u8(0x2002)))
    print(string.format("=== #2BB8 = %02X  (installnrl wants F5)",
                        PROG:read_u8(0x2BB8)))
  end
  if sent and F==sent+230 and not done then
    done=1
    local f=io.open(os.getenv("DUMP"),"wb")
    for i=0,16383 do f:write(string.char(PROG:read_u8(0xC000+i))) end
    f:close()
    print("=== screen dumped"); manager.machine:exit()
  end
  if F==4000 then print("=== gave up"); manager.machine:exit() end
end)
