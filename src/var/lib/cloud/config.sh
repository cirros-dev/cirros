#BURL="http://169.254.169.254/2009-04-04"
#MDURL="${BURL}/meta-data"
#UDURL="${BURL}/user-data"
#MD_DEBUG_COUNT=30
#MD_MAX_TRIES=30
#RESIZE_FS=0
#IS_NOCLOUD=0

# put your local changes in config.local.sh
lfile=/var/lib/cloud/config.local.sh;
[ ! -e "$lfile" ] || . "$lfile"
