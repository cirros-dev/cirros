#!/bin/bash

DEBUG=0
QUIET=${QUIET:-}

error() { echo "$@" 1>&2; }

debug() {
	[ "${DEBUG}" -ge "${1:-0}" ] && shift || return 0;
	error "$@";
}

fail() { [ $# -eq 0 ] || error "$@"; exit 1; }

bad_Usage() { Usage 1>&2; fail "$@"; }

dl() {
    local url="$1" target="$2" tfile="" t=""
    [ -f "$target" ] && return
    t=$(dirname "$target")
    tfile=$(mktemp "$t/.${0##*/}.XXXXXX") || return
    wget_quiet=
    if [ ! -z $QUIET ]; then
        wget_quiet="-q"
    fi
    wget $wget_quiet "$url" -O "$tfile" &&
        mv "$tfile" "$target" ||
        { t=$?; rm -f "$tfile"; return $t; }
}

sec2human() {
    local delta=$1 fmt="${2:-full}" year day hour min sec rem=0
    rem=$delta
    year=$(($rem/(365*24*60*60))) || return
    rem=$(($rem-($year*365*24*60*60)))
    day=$(($rem/(24*60*60)))
    rem=$(($rem-($day*24*60*60)))
    hour=$(($rem/(60*60)))
    rem=$(($rem-($hour*60*60)))
    min=$(($rem/(60)))
    rem=$(($rem-($min*60)))
    sec=$rem
    local t="" unit short long
    local full="" tfull="" brev="" tbrev=""
    for t in "$year y year" "$day d day" "$hour h hour" \
            "$min m minute" "$sec s second"; do
        set -- $t
        unit=$1; short=$2; long=$3
        [ "$1" = "1" ] || long="${long}s"
        full="$full $unit $long"
        brev="$brev $unit$short"
        if [ "$unit" != "0" ] || [ -n "$tfull" ]; then
            tfull="$tfull $unit $long"
            tbrev="$tbrev $unit$short"
        fi
    done
    tfull=${tfull# }
    full=${full# }
    tbrev=${tbrev# }
    brev=${brev# }
    [ -z "$tbrev" ] && tbrev="0s"
    [ -z "$tfull" ] && tfull="0 seconds"
    case "$fmt" in
        full) _RET="$full";;    # full words with leading
        tfull) _RET="$tfull";;  # full words, no leading 0
        short) _RET="$brev";;   # abbreviated with leading
        tshort) _RET="$tbrev";; # abbreviated no leading 0
        *) echo "bad format '$fmt'"; return 1;;
    esac
    return
}

datefortag_bzr() {
    local loginfo ts out repo="${CIRROS_BZR:-.}"
    local spec="tag:$1" fmt="${2:-+%Y%m%d}"
    loginfo=$(bzr log "$repo" --log-format=long --revision "$spec") ||
        { error "couldn't bzr log tag:$i"; return 1; }
    ts=$(echo "$loginfo" | sed -n '/^timestamp:/s,.*: ,,p') &&
        [ -n "$ts" ] || {
            error "failed to get timestamp from log for $spec";
            return 1;
        }
    out=$(date --date="$ts" "$fmt") ||
        { error "failed convert of '$ts' to format=$fmt"; return 1; }
    _RET="$out"
}

datefortag() {
    local spec="$1" fmt="${2:-+%Y%m%d}"
    local repo="${CIRROS_GIT:-${CIRROS_BZR:-.}}"
    if [ ! -d "$repo/.git" -a -d "$repo/.bzr" ]; then
        datefortag_bzr "$@"
        return
    fi
    spec=${spec//"~"/_} # git tags cannot contain ~
    ts=$( cd "$repo" &&
        git show --no-patch "--pretty=format:%ct" "$spec") ||
        { error "failed to 'git show $spec' in $repo"; return 1; }
    out=$(date --utc --date="@$ts" "$fmt") ||
        { error "failed to convert seconds '$ts' to format $fmt"; return 1; }
    _RET="$out"
}


# vi: tabstop=4 noexpandtab
