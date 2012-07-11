#!/bin/sh
# Download a snapshot of the Git mailing list archive from [gmane](http://gmane.org/).
# From project root:
#
#   sh ./util/archive.sh
#

start=1849
stop=1856
page=$start
archive_dir="archive"

mkdir -p "${archive_dir}"
while [ ${page} -lt $((stop + 1)) ]
do
	curl "http://news.gmane.org/group/gmane.comp.version-control.git/last=0/force_load=very/?page=${page}&action=--Action--" > ${archive_dir}/${page}.html
	page=$(( page + 1 ))
done
