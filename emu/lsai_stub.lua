-- A LambdaSpeak AI, as far as the vector head can tell.
--
-- MAME has an SSA-1 but not this card, so the ROM's &E9 exchange -- the one
-- that replaces Amstrad's letter-to-sound engine -- had no way of being run
-- anywhere. This stands in for the card: it watches &FBEE, collects the text
-- after an &E9, and answers the way the firmware does, with a sync byte, a
-- count and that many allophones.
--
-- It deliberately does NOT implement the rules. Those are tested on the host
-- against say_rules, byte for byte; what has never been exercised is the
-- protocol, so this returns a fixed, recognisable answer and the test checks
-- that exactly those allophones reach the head's buffer.
--
--     DUMP=... mame cpc6128 -exp rom -rom1 rom/VHLSAI.ROM \
--         -autoboot_script emu/lsai_stub.lua

NK  = manager.machine.natkeyboard; NK.in_use = true
CPU = manager.machine.devices[":maincpu"]
PROG, IO = CPU.spaces["program"], CPU.spaces["io"]

PORT    = 0xEE                      -- &FBEE, low byte
IDLE    = 0xBF                      -- what an idle SSA-1 SP0 mode reads
SYNC    = 0xAA
ANSWER  = { 27, 7, 45, 53, 4 }      -- HH1 EH LL OW PA5

-- From the LSAI build's own symbols, and they are build-specific: the plain
-- build puts all three 0x29 lower, because -DLSAI swaps CONVERT for the port
-- exchange and the head shrinks. Regenerate with
--     cd src && rasm head.asm -DLSAI=1 -s && grep -E '^(HOOKED|PHONBUF|SAYTAIL) ' rasmoutput.sym
-- and do not read the rasmoutput.sym left at the repo root, which is whatever
-- was assembled last.
HOOKED, PHONBUF, SAYTAIL = 0x9C53, 0x9AC2, 0x9969

state, reply, asked = "idle", {}, 0

-- Every one of these three returns a subscription token, and dropping it
-- unsubscribes: Lua collects the token, MAME quietly stops calling back, and
-- nothing says so. That is what made this script look like a hang -- the
-- frame notifier fired until the first garbage collection, somewhere around
-- frame 150, and then the machine ran on forever with no one watching it.
-- `romtest.lua` keeps its notifier in a global and has always worked. So:
-- hold all three, and never write `emu.add_machine_frame_notifier(f)` as a
-- bare statement.
TAPW = IO:install_write_tap(0xFBEE, 0xFBEE, "w", function(offset, data, mask)
  if (offset % 256) == PORT then
    if state == "idle" then
      if data == 0xE9 then state = "text" end
    elseif state == "text" then
      if data == 13 then              -- the carriage return sets it going
        reply = { SYNC, #ANSWER }
        for _, a in ipairs(ANSWER) do reply[#reply + 1] = a end
        state, asked = "idle", asked + 1
      end
    end
  end
  return data
end)

TAPR = IO:install_read_tap(0xFBEE, 0xFBEE, "r", function(offset, data, mask)
  if (offset % 256) == PORT then
    if #reply > 0 then return table.remove(reply, 1) end
    return IDLE                       -- reads before the reply advance nothing
  end
  return data
end)

F, sent, done = 0, nil, nil
NOTIFY = emu.add_machine_frame_notifier(function()
  F = F + 1
  if F == 260 then NK:post_coded('{ENTER}') end
  if F == 340 then NK:post_coded('|VH{ENTER}'); sent = F end
  if sent and F == sent + 300 and not done then
    done = 1
    local hooked = PROG:read_u8(HOOKED)
    local tail   = PROG:read_u8(SAYTAIL) + PROG:read_u8(SAYTAIL + 1) * 256
    local n      = tail - PHONBUF
    io.write(string.format("=== &E9 exchanges seen: %d\n", asked))
    io.write(string.format("=== hooked = %d  (1 means the card answered)\n", hooked))

    -- Diagnose in the order that tells the reader the most. "No &E9 arrived"
    -- is the useful answer when the ROM is absent or never ran; a nonsense
    -- buffer length only means the addresses are wrong once the exchange has
    -- demonstrably happened. Either way n is clamped, so a wrong address
    -- cannot print 20,000 bytes of the machine.
    local bad = nil
    if asked == 0 then      bad = "the ROM never sent an &E9"
    elseif hooked ~= 1 then bad = "the head did not hook the card's engine"
    elseif n < 0 or n > 64 then
      bad = string.format("say buffer length is %d -- HOOKED/PHONBUF/SAYTAIL "
                          .. "do not match this ROM", n)
    end
    if n < 0 or n > 64 then n = 0 end
    io.write(string.format("=== say buffer holds %d allophones:", n))
    local got = {}
    for i = 0, n - 1 do
      got[#got + 1] = PROG:read_u8(PHONBUF + i)
      io.write(string.format(" %d", got[#got]))
    end
    io.write("\n")

    -- Verify, rather than leaving it to whoever reads the numbers.
    if not bad then
      if #got ~= #ANSWER then
        bad = string.format("expected %d allophones, got %d", #ANSWER, #got)
      else
        for i = 1, #ANSWER do
          if got[i] ~= ANSWER[i] then
            bad = string.format("allophone %d is %d, expected %d",
                                i, got[i], ANSWER[i])
            break
          end
        end
      end
    end
    if bad then io.write("=== FAIL: " .. bad .. "\n")
    else        io.write("=== PASS: the &E9 exchange works end to end\n") end
    if os.getenv("DUMP") then
      local f = io.open(os.getenv("DUMP"), "wb")
      for i = 0, 16383 do f:write(string.char(PROG:read_u8(0xC000 + i))) end
      f:close()
    end
    manager.machine:exit()
  end
  if F == 1200 then print("=== gave up"); manager.machine:exit() end
end)
