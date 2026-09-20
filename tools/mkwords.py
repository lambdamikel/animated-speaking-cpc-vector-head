"""words.inc from a list on the command line or in words.txt."""
import sys
ws = sys.argv[1:] or [w.strip() for w in open('words.txt') if w.strip()]
with open('words.inc','w') as f:
    f.write("words:\n")
    for w in ws:
        f.write(f'    defb {len(w)},"{w}"\n')
    f.write("    defb 0\n")
print(len(ws), "words")
