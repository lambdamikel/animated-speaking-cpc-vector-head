-- time the sentence exactly: from the first allophone written to the chip
-- to the last, at a forced speed setting
NK=manager.machine.natkeyboard; NK.in_use=true
CPU=manager.machine.devices[":maincpu"]; PROG=CPU.spaces["program"]
IO=CPU.spaces["io"]
SPEED=0x8FEF; PMAP=0x8FDE
MAPS={[0]=0x8FE0,[1]=0x8FE5,[2]=0x8FEA}
WANT=tonumber(os.getenv("SPD"))
F=0; started=nil; typed=nil; first=nil; last=nil; n=0
TAP=IO:install_write_tap(0xF800,0xFFFF,"w",function(offset,data,mask)
  if typed and (offset % 256)==0xEE then
    if not first then first=F end
    last=F; n=n+1
  end
  return data
end)
N=emu.add_machine_frame_notifier(function()
  F=F+1
  if F==220 then NK:post_coded('{ENTER}') end
  if not started and F>300 and F%150==0 then
    if PROG:read_u8(0x8000)~=0 then started=F else NK:post_coded('RUN"VH{ENTER}') end
  end
  if started and F==started+900 then NK:post_coded(' ') end
  if started and F==started+1000 then
    PROG:write_u8(SPEED,WANT)
    PROG:write_u8(PMAP,MAPS[WANT]%256)
    PROG:write_u8(PMAP+1,math.floor(MAPS[WANT]/256))
    typed=F
    NK:post_coded('THE QUICK BROWN FOX JUMPS OVER IT{ENTER}')
  end
  if started and F==started+1900 then
    if first then
      print(string.format("=== speed %d: %d allophones over %.1f s", WANT, n, (last-first)/50))
    else print("=== speed "..WANT..": nothing sent") end
    manager.machine:exit()
  end
end)
