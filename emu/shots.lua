-- three moments of the running program, dumped as raw 16K screen pages
NK=manager.machine.natkeyboard; NK.in_use=true
PROG=manager.machine.devices[":maincpu"].spaces["program"]
F=0; started=nil
local function grab(name)
  local base=PROG:read_u8(0x999A)*256
  local f=io.open(os.getenv("SHOTDIR").."/"..name..".bin","wb")
  for i=0,16383 do f:write(string.char(PROG:read_u8(base+i))) end
  f:close(); print("=== "..name.." from "..string.format("%04X",base))
end
N=emu.add_machine_frame_notifier(function()
  F=F+1
  if F==220 then NK:post_coded('{ENTER}') end
  if not started and F>300 and F%150==0 then
    if PROG:read_u8(0x8000)~=0 then started=F else NK:post_coded('RUN"VH{ENTER}') end
  end
  if not started then return end
  if F==started+60  then grab("credits") end
  if F==started+330 then grab("speaking1") end
  if F==started+430 then grab("speaking2") end
  if F==started+900 then NK:post_coded(' ') end
  if F==started+960 then NK:post_coded('THIS IS THE VECTOR HEAD{ENTER}') end
  if F==started+1050 then grab("typed") end
  if F==started+1250 then grab("allophones") end
  if F==started+1330 then grab("speaking2b") end
  if F==started+1600 then grab("prompt"); manager.machine:exit() end
  if F==8000 then print("=== gave up"); manager.machine:exit() end
end)
