
NK=manager.machine.natkeyboard; NK.in_use=true
PROG=manager.machine.devices[":maincpu"].spaces["program"]
F=0; started=nil; typed=nil; OUT=nil
N=emu.add_machine_frame_notifier(function()
  F=F+1
  if F==220 then NK:post_coded('{ENTER}') end
  if not started and F>300 and F%150==0 then
    if PROG:read_u8(0x8000)~=0 then started=F else NK:post_coded('RUN"VH{ENTER}') end
  end
  if started and not typed and F>started+300 then typed=F; NK:post_coded(os.getenv("TEXT")..'{ENTER}') end
  if typed and F==typed+40 then OUT=io.open(os.getenv("FILM"),"wb") end
  if OUT and F>=typed+40 and F<=typed+400 then
    local base=PROG:read_u8(0x9364)*256
    if base<0x4000 then base=0xC000 end
    local t={}
    for i=0,16383 do t[#t+1]=string.char(PROG:read_u8(base+i)) end
    OUT:write(table.concat(t))
  end
  if typed and F==typed+401 then OUT:close(); print("=== filmed"); manager.machine:exit() end
  if F==6000 then print("=== gave up"); manager.machine:exit() end
end)
