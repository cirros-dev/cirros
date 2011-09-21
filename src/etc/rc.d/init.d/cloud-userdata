#!/bin/sh
# vi: ts=4 noexpandtab

XN=cloud-userdata
. /etc/rc.d/init.d/cloud-functions

start() {
	local iid="" shebang="" a="" udf="${STATE_D}/userdata"
	is_nocloud && return 0
	mdget instance-id ||
		{ msg "failed to read instance id"; return 1; }

	iid=${_RET}
	[ -n "${iid}" -a "${iid#i-}" != "${iid}" ] ||
		{ echo "failed to read instance-id, found ${iid}"; return 1; }

	marked ${iid} &&
		{ msg "user data previously read"; return 0; }

	mark ${iid}

	wget -q -O - "${UDURL}" > "${udf}" ||
		{ msg "failed to read user data url: ${UDURL}"; return 1; }

	shebang="#!"
	read a < "${udf}"
	[ "${a#${shebang}}" = "${a}" ] &&
		{ msg "user data not a script"; return 0; }

	chmod 755 "${udf}"
	exec "${udf}"
}

case "$1" in
	start) start;;
	*) msg "unknown argument ${1}";;
esac
