NK=manager.machine.natkeyboard; NK.in_use=true
PROG=manager.machine.devices[":maincpu"].spaces["program"]
F=0; started=nil
N=emu.add_machine_frame_notifier(function()
  F=F+1
  if F==220 then NK:post_coded('{ENTER}') end
  if not started and F>300 and F%150==0 then
    if PROG:read_u8(0x8000)~=0 then started=F else NK:post_coded('RUN"VH{ENTER}') end
  end
  if started and F==started+900 then NK:post_coded(' ') end
  if started and F==started+1050 then
    local p=PROG:read_u8(0x91A6)+PROG:read_u8(0x91A7)*256
    io.write("=== nlptr "..string.format("%04X",p).."  pairs(col,row):")
    for a=0xA800,p-1,2 do io.write(" ("..PROG:read_u8(a)..","..PROG:read_u8(a+1)..")") end
    print("")
    manager.machine:exit()
  end
  if F==8000 then print("=== gave up"); manager.machine:exit() end
end)
