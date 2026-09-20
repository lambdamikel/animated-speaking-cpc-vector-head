NK=manager.machine.natkeyboard; NK.in_use=true
PROG=manager.machine.devices[":maincpu"].spaces["program"]
F=0
N=emu.add_machine_frame_notifier(function()
  F=F+1
  if F==220 then NK:post_coded('{ENTER}') end
  if F>300 and F%150==0 and PROG:read_u8(0x8007)~=0xAA then NK:post_coded('RUN"NW{ENTER}') end
  if F>300 and PROG:read_u8(0x8007)==0xAA then
    local out={}
    for a=0x9000,0x9FFF do
      local b=PROG:read_u8(a)
      if b==0xFE then break end
      out[#out+1]=b
    end
    print("=== "..table.concat(out,","))
    manager.machine:exit()
  end
  if F==4000 then print("=== gave up"); manager.machine:exit() end
end)
