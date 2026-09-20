import sys; sys.path.insert(0,'.')
from dz80 import disasm
d = open('SSA1.BIN','rb').read()[128:]
B = 0x0AE0                      # driver offset 0 lives here in the file

def f(off): return B + off      # driver offset -> file offset

code, labels, calls = set(), set(), {}
def walk(off, why):
    stack=[off]
    while stack:
        o = stack.pop()
        while True:
            a = f(o)
            if a < 0 or a+4 >= len(d): break
            if a in code: break
            n, t, tg, stop = disasm(d, a)
            for i in range(n): code.add(a+i)
            if tg is not None and ('jp' in t or 'jr' in t or 'call' in t or 'djnz' in t):
                # relative jumps come back as file offsets, absolute ones as
                # the operand - which is already a driver offset
                to = tg - B if (t.startswith('jr') or t.startswith('djnz')) else tg
                labels.add(to)
                calls.setdefault(o, set()).add(to)
                if 0 <= f(to) < len(d):
                    stack.append(to)
            o += n
            if stop: break

ENTRY = 0x02BA                  # what SAY calls to convert and speak
walk(ENTRY, 'convert')
print('entry 0x%04X' % ENTRY)
print('code bytes reached: %d' % len(code))
runs=[]; cur=None
for a in range(len(d)):
    if a in code:
        if cur is None: cur=a
    else:
        if cur is not None: runs.append((cur,a)); cur=None
if cur is not None: runs.append((cur,len(d)))
print('code runs (driver offsets):')
for s,e in runs: print('   %04X..%04X  (%d bytes)' % (s-B, e-B, e-s))
print('total %d bytes of code, over %d runs' % (sum(e-s for s,e in runs), len(runs)))
