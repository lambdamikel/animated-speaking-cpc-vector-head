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

-- What the head's buffer should hold once the intro has been through the
-- card: the stub's answer for each of the three intro lines, with the three
-- PA5s `breathe` puts between them. It used to expect one answer, from when
-- the ROM started the head at boot and `|VH` then restarted it mid-intro --
-- so the check landed after one line instead of after all three.
EXPECT = {}
for _, line in ipairs({ 1, 2, 3 }) do
  for _, a in ipairs(ANSWER) do EXPECT[#EXPECT + 1] = a end
  if line < 3 then for _ = 1, 3 do EXPECT[#EXPECT + 1] = 4 end end  -- breathe
end

-- Read from the LSAI build's own symbol file rather than written down here.
--
-- They were written down here, twice, and went stale twice. They are
-- build-specific -- the plain build puts all three 0x29 lower, because -DLSAI
-- swaps CONVERT for the port exchange -- and they also move whenever anything
-- before them in the source changes size: shortening the intro line by eleven
-- characters moved all three down by eleven bytes, and the test then reported
-- that the head had not hooked the card, which was true of nothing except the
-- addresses being wrong.
--
-- SYMS names the file; run_lsai.sh regenerates it for the LSAI build first, so
-- it cannot be whatever was assembled last. The constants stay as a fallback
-- for a hand-run MAME, and the script prints which it used either way.
local function read_syms(path)
  local f = path and io.open(path, "r")
  if not f then return nil end
  local t = {}
  for line in f:lines() do
    local name, hex = line:match("^(%S+)%s+#(%x+)")
    if name then t[name] = tonumber(hex, 16) end
  end
  f:close()
  return (t.HOOKED and t.PHONBUF and t.SAYTAIL) and t or nil
end

HOOKED, PHONBUF, SAYTAIL = 0x9C48, 0x9AB7, 0x995E
SYMSRC = "the constants in this script"
do
  local t = read_syms(os.getenv("SYMS") or "../src/rasmoutput.sym")
  if t then
    HOOKED, PHONBUF, SAYTAIL = t.HOOKED, t.PHONBUF, t.SAYTAIL
    SYMSRC = os.getenv("SYMS") or "../src/rasmoutput.sym"
  end
end
io.write(string.format("=== symbols from %s: HOOKED=%04X PHONBUF=%04X SAYTAIL=%04X\n",
                       SYMSRC, HOOKED, PHONBUF, SAYTAIL))

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
  -- Whatever the ROM has done before anyone types anything. It must be
  -- nothing: entry 0 of the jump block is the firmware's ROM-walk init, and
  -- an init that runs the head is an autorun.
  if F == 339 then ASKED_BEFORE = asked end
  if F == 340 then NK:post_coded('|VH{ENTER}'); sent = F end
  if sent and F == sent + 300 and not done then
    done = 1
    local hooked = PROG:read_u8(HOOKED)
    local tail   = PROG:read_u8(SAYTAIL) + PROG:read_u8(SAYTAIL + 1) * 256
    local n      = tail - PHONBUF
    io.write(string.format("=== &E9 exchanges seen: %d, of them before |VH: %d\n",
                           asked, ASKED_BEFORE or -1))
    io.write(string.format("=== hooked = %d  (1 means the card answered)\n", hooked))

    -- Diagnose in the order that tells the reader the most. "No &E9 arrived"
    -- is the useful answer when the ROM is absent or never ran; a nonsense
    -- buffer length only means the addresses are wrong once the exchange has
    -- demonstrably happened. Either way n is clamped, so a wrong address
    -- cannot print 20,000 bytes of the machine.
    local bad = nil
    if (ASKED_BEFORE or 0) ~= 0 then
      bad = string.format("the ROM ran the head by itself -- %d exchanges "
                          .. "before |VH was typed, so autorun is back",
                          ASKED_BEFORE)
    elseif asked == 0 then  bad = "the ROM never sent an &E9"
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
      if #got ~= #EXPECT then
        bad = string.format("expected %d allophones, got %d", #EXPECT, #got)
      else
        for i = 1, #EXPECT do
          if got[i] ~= EXPECT[i] then
            bad = string.format("allophone %d is %d, expected %d",
                                i, got[i], EXPECT[i])
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
