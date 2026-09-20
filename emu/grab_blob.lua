NK=manager.machine.natkeyboard; NK.in_use=true
PROG=manager.machine.devices[":maincpu"].spaces["program"]
F=0; started=nil
N=emu.add_machine_frame_notifier(function()
  F=F+1
  if F==220 then NK:post_coded('{ENTER}') end
  if not started and F>300 and F%150==0 then
    if PROG:read_u8(0x7FFF)==0xAA then started=F else NK:post_coded('RUN"RL{ENTER}') end
  end
  if started and F==started+20 then
    local f=io.open(os.getenv("OUT"),"wb")
    for i=0x4000,0x4000+6015 do f:write(string.char(PROG:read_u8(i))) end
    f:close()
    print("=== relocated blob dumped")
    manager.machine:exit()
  end
  if F==4000 then print("=== gave up"); manager.machine:exit() end
end)
