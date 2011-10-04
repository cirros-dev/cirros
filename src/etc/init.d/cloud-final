#!/bin/sh
# vi: ts=4 noexpandtab

XN=cloud-final
. /etc/rc.d/init.d/cloud-functions

start() {
	local iid="" iip="" eip="" uptime=""
	read uptime cputime < /proc/uptime
	echo "===== ${XN}: system completely up in ${uptime} seconds ===="
	is_nocloud && return 0
	mdget instance-id && iid=${_RET}
	mdget public-ipv4 && eip=${_RET}
	mdget local-ipv4 && iip=${_RET}
	cat <<EOF
  instance-id: ${iid}
  public-ipv4: ${eip}
  local-ipv4 : ${iip}
EOF
}

case "$1" in
	start) start;;
	*) msg "unknown argument ${1}";;
esac
