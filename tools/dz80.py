"""A small Z80 disassembler, written for one job: reading the letter-to-sound
engine out of the 1985 SSA-1 driver so it can be assembled from source.

It walks code from entry points, follows calls and jumps, and keeps a note of
which bytes it has proved to be code - so the rule tables, which are data,
are left alone rather than being disassembled into nonsense."""

R  = ['b','c','d','e','h','l','(hl)','a']
RP = ['bc','de','hl','sp']
RP2= ['bc','de','hl','af']
CC = ['nz','z','nc','c','po','pe','p','m']
ALU= ['add a,','adc a,','sub ','sbc a,','and ','xor ','or ','cp ']
ROT= ['rlc','rrc','rl','rr','sla','sra','sll','srl']

def hx(v, n=2):
    return ('#%0'+str(n)+'X') % v

def disasm(m, a):
    """-> (length, text, target or None, stop) for the instruction at a."""
    op = m[a]
    def b8(o=1):  return m[a+o]
    def b16(o=1): return m[a+o] | (m[a+o+1] << 8)
    def rel(o=1):
        d = m[a+o]
        return (a + o + 1 + (d - 256 if d > 127 else d)) & 0xFFFF

    if op == 0xCB:
        x = m[a+1]
        r = R[x & 7]
        if x < 0x40:  return 2, '%s %s' % (ROT[x >> 3], r), None, False
        n = (x >> 3) & 7
        k = ['bit','res','set'][(x >> 6) - 1]
        return 2, '%s %d,%s' % (k, n, r), None, False

    if op == 0xED:
        x = m[a+1]
        t = {0x44:'neg',0x45:'retn',0x4D:'reti',0x46:'im 0',0x56:'im 1',0x5E:'im 2',
             0x57:'ld a,i',0x5F:'ld a,r',0x47:'ld i,a',0x4F:'ld r,a',
             0x67:'rrd',0x6F:'rld',0xA0:'ldi',0xA1:'cpi',0xA2:'ini',0xA3:'outi',
             0xA8:'ldd',0xA9:'cpd',0xAA:'ind',0xAB:'outd',0xB0:'ldir',0xB1:'cpir',
             0xB2:'inir',0xB3:'otir',0xB8:'lddr',0xB9:'cpdr',0xBA:'indr',0xBB:'otdr'}
        if x in t:   return 2, t[x], None, x in (0x45,0x4D)
        if x & 0xC7 == 0x40: return 2, 'in %s,(c)' % R[(x>>3)&7], None, False
        if x & 0xC7 == 0x41: return 2, 'out (c),%s' % R[(x>>3)&7], None, False
        if x & 0xCF == 0x42: return 2, 'sbc hl,%s' % RP[(x>>4)&3], None, False
        if x & 0xCF == 0x4A: return 2, 'adc hl,%s' % RP[(x>>4)&3], None, False
        if x & 0xCF == 0x43: return 4, 'ld (%s),%s' % (hx(b16(2),4), RP[(x>>4)&3]), b16(2), False
        if x & 0xCF == 0x4B: return 4, 'ld %s,(%s)' % (RP[(x>>4)&3], hx(b16(2),4)), b16(2), False
        return 2, 'defb #ED,%s' % hx(x), None, False

    if op in (0xDD, 0xFD):
        ix = 'ix' if op == 0xDD else 'iy'
        x = m[a+1]
        if x == 0xCB:
            d = m[a+2]; y = m[a+3]
            d = d - 256 if d > 127 else d
            if y < 0x40: return 4, '%s (%s%+d)' % (ROT[y >> 3], ix, d), None, False
            k = ['bit','res','set'][(y >> 6) - 1]
            return 4, '%s %d,(%s%+d)' % (k, (y >> 3) & 7, ix, d), None, False
        sub = {0x21:('ld %s,%%s' % ix, 3), 0x22:('ld (%%s),%s' % ix, 3),
               0x2A:('ld %s,(%%s)' % ix, 3), 0x36:None, 0xE5:('push %s' % ix, 1),
               0xE1:('pop %s' % ix, 1), 0xE9:('jp (%s)' % ix, 1), 0xF9:('ld sp,%s' % ix, 1),
               0x23:('inc %s' % ix, 1), 0x2B:('dec %s' % ix, 1), 0xE3:('ex (sp),%s' % ix, 1)}
        if x == 0x36:
            d = m[a+2]; d = d - 256 if d > 127 else d
            return 4, 'ld (%s%+d),%s' % (ix, d, hx(m[a+3])), None, False
        if x in sub and sub[x]:
            txt, ln = sub[x]
            if ln == 3: return 4, txt % hx(b16(2), 4), b16(2), False
            return 2, txt, None, x == 0xE9
        if x & 0xC0 == 0x40 or x & 0xC0 == 0x80 or x in (0x34,0x35) or x & 0xC7 == 0x06:
            d = m[a+2]; d = d - 256 if d > 127 else d
            ind = '(%s%+d)' % (ix, d)
            if x in (0x34,0x35): return 3, '%s %s' % ('inc' if x == 0x34 else 'dec', ind), None, False
            if x & 0xC0 == 0x40:
                dst, src = R[(x>>3)&7], R[x&7]
                if src == '(hl)': return 3, 'ld %s,%s' % (dst, ind), None, False
                if dst == '(hl)': return 3, 'ld %s,%s' % (ind, src), None, False
            if x & 0xC0 == 0x80 and x & 7 == 6:
                return 3, '%s%s' % (ALU[(x>>3)&7], ind), None, False
        return 2, 'defb %s,%s' % (hx(op), hx(x)), None, False

    if op == 0x00: return 1,'nop',None,False
    if op == 0x76: return 1,'halt',None,False
    if op & 0xC0 == 0x40:
        return 1, 'ld %s,%s' % (R[(op>>3)&7], R[op&7]), None, False
    if op & 0xC0 == 0x80:
        return 1, '%s%s' % (ALU[(op>>3)&7], R[op&7]), None, False
    if op & 0xC7 == 0x06:
        return 2, 'ld %s,%s' % (R[(op>>3)&7], hx(b8())), None, False
    if op & 0xCF == 0x01:
        return 3, 'ld %s,%s' % (RP[(op>>4)&3], hx(b16(),4)), b16(), False
    if op & 0xCF == 0x09: return 1, 'add hl,%s' % RP[(op>>4)&3], None, False
    if op & 0xCF == 0x03: return 1, 'inc %s' % RP[(op>>4)&3], None, False
    if op & 0xCF == 0x0B: return 1, 'dec %s' % RP[(op>>4)&3], None, False
    if op & 0xC7 == 0x04: return 1, 'inc %s' % R[(op>>3)&7], None, False
    if op & 0xC7 == 0x05: return 1, 'dec %s' % R[(op>>3)&7], None, False
    one = {0x07:'rlca',0x0F:'rrca',0x17:'rla',0x1F:'rra',0x27:'daa',0x2F:'cpl',
           0x37:'scf',0x3F:'ccf',0x08:"ex af,af'",0xEB:'ex de,hl',0xE3:'ex (sp),hl',
           0xF3:'di',0xFB:'ei',0xD9:'exx',0xE9:'jp (hl)',0xF9:'ld sp,hl',0xC9:'ret'}
    if op in one: return 1, one[op], None, op in (0xC9,0xE9)
    if op in (0x02,0x12): return 1, 'ld (%s),a' % ('bc' if op==0x02 else 'de'), None, False
    if op in (0x0A,0x1A): return 1, 'ld a,(%s)' % ('bc' if op==0x0A else 'de'), None, False
    if op == 0x22: return 3, 'ld (%s),hl' % hx(b16(),4), b16(), False
    if op == 0x2A: return 3, 'ld hl,(%s)' % hx(b16(),4), b16(), False
    if op == 0x32: return 3, 'ld (%s),a' % hx(b16(),4), b16(), False
    if op == 0x3A: return 3, 'ld a,(%s)' % hx(b16(),4), b16(), False
    if op == 0x10: return 2, 'djnz %s', rel(), False
    if op == 0x18: return 2, 'jr %s', rel(), True
    if op & 0xE7 == 0x20: return 2, 'jr %s,%%s' % CC[(op>>3)&3], rel(), False
    if op == 0xC3: return 3, 'jp %s', b16(), True
    if op & 0xC7 == 0xC2: return 3, 'jp %s,%%s' % CC[(op>>3)&7], b16(), False
    if op == 0xCD: return 3, 'call %s', b16(), False
    if op & 0xC7 == 0xC4: return 3, 'call %s,%%s' % CC[(op>>3)&7], b16(), False
    if op & 0xC7 == 0xC0: return 1, 'ret %s' % CC[(op>>3)&7], None, False
    if op & 0xCF == 0xC5: return 1, 'push %s' % RP2[(op>>4)&3], None, False
    if op & 0xCF == 0xC1: return 1, 'pop %s' % RP2[(op>>4)&3], None, False
    if op & 0xC7 == 0xC7: return 1, 'rst %s' % hx(op & 0x38), None, False
    if op & 0xC7 == 0xC6: return 2, '%s%s' % (ALU[(op>>3)&7], hx(b8())), None, False
    if op == 0xD3: return 2, 'out (%s),a' % hx(b8()), None, False
    if op == 0xDB: return 2, 'in a,(%s)' % hx(b8()), None, False
    return 1, 'defb %s' % hx(op), None, False
