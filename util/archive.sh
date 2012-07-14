#!/bin/bash
############################################################################
progname="${0##*/}"
author="Simon Chiang"
usage="usage: %s [-h] GROUP [PAGE...]\n"
opt="       %s   %s\n"

while getopts "h" option
do
  case $option in
    h  )  printf "$usage" "$progname"
          printf '
  Download pages from gmane.  Combine with parse to view pages as text.

    ./archive.sh gmane.comp.version-control.git 0 1 2 | ./parse_archive

  Produces output like:

    1205 -- Colorized git log
    `- 1208 -- Colorized git log
     `- 1224 -- [PATCH] Colorized git log
      `- 1225 -- [PATCH] Colorized git log
       |- 1227 -- [PATCH] Colorized git log
       `- 1226 -- [PATCH] Colorized git log

'
          printf "options:\n\n"
          printf "$opt" "-h" "prints this help"
          printf "\n"
          exit 0 ;;
    \? )  printf "$usage" "$progname"
          exit 2 ;;
  esac
done
shift $(($OPTIND - 1))

group="${1}"
shift 1

############################################################################

for page
do curl -s "http://news.gmane.org/group/$group?page=${page}"
done
