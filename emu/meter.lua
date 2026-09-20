-- how long the head takes, and how often the mouth changes while it talks
NK=manager.machine.natkeyboard; NK.in_use=true
PROG=manager.machine.devices[":maincpu"].spaces["program"]
F=0; started=nil; last=nil; flips=0; first=nil; lastflip=nil
N=emu.add_machine_frame_notifier(function()
  F=F+1
  if F==220 then NK:post_coded('{ENTER}') end
  if not started and F>300 and F%150==0 then
    if PROG:read_u8(0x8000)~=0 then started=F else NK:post_coded('RUN"VH{ENTER}') end
  end
  if not started then return end
  local vb=PROG:read_u8(0x999A)
  if last and vb~=last then
    flips=flips+1; first=first or F; lastflip=F
  end
  last=vb
  if F==started+60 then
    print(string.format("=== head drawn in %d ticks of 1/300 s = %.3f s",
      PROG:read_u8(0x99A9)+PROG:read_u8(0x99AA)*256,
      (PROG:read_u8(0x99A9)+PROG:read_u8(0x99AA)*256)/300))
  end
  if F==started+860 then
    print(string.format("=== %d page flips over %.2f s while speaking = %.1f/s",
      flips,(lastflip-first)/50,flips/((lastflip-first)/50)))
    manager.machine:exit()
  end
  if F==8000 then print("=== gave up"); manager.machine:exit() end
end)
