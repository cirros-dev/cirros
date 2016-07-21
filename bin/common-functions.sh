#!/bin/bash

DEBUG=0

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
    wget "$url" -O "$tfile" &&
        mv "$tfile" "$target" ||
        { t=$?; rm -f "$tfile"; return $t; }
}

# vi: tabstop=4 noexpandtab
