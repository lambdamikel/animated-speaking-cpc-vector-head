# Where the toolchain is.  Sourced by build.sh and dist.sh; tools/run_words.sh
# uses it too.  Each may be overridden from the environment; otherwise PATH is
# searched, and then the place they happen to live on the machine this was
# written on.
RASM=${RASM:-$(command -v rasm  || echo ~/claude/midi80/toolchain/rasm/rasm)}
IDSK=${IDSK:-$(command -v iDSK  || echo ~/claude/midi80/toolchain/idsk/iDSK)}
HXCFE=${HXCFE:-$(command -v hxcfe || echo ~/claude/midi80/toolchain/hxc/build/hxcfe)}
MAME=${MAME:-$(command -v mame  || echo mame)}
CPCROMS=${CPCROMS:-~/claude/cpc/mame-roms}

need () {                       # need RASM rasm  -> complain usefully if missing
  local var=$1 what=$2 path=${!1}
  [ -x "$path" ] || { command -v "$path" >/dev/null && return 0; }
  [ -x "$path" ] || {
    echo "$what not found at '$path'." >&2
    echo "Put it on PATH, or run:  $var=/path/to/$what $0" >&2
    exit 1
  }
}
