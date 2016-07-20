#!/bin/bash
#
#	Copyright (C) 2010 Canonical Ltd.
#
#	Authors: Scott Moser <smoser@canonical.com>
#			 Marcin Juszkiewicz <marcin.juszkiewicz@linaro.org>
#
#	This program is free software: you can redistribute it and/or modify
#	it under the terms of the GNU General Public License as published by
#	the Free Software Foundation, version 3 of the License.
#
#	This program is distributed in the hope that it will be useful,
#	but WITHOUT ANY WARRANTY; without even the implied warranty of
#	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#	GNU General Public License for more details.
#
#	You should have received a copy of the GNU General Public License
#	along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
# vi: ts=4 noexpandtab
#

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
