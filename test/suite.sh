#!/bin/bash

#
#  Test Suite Setup
#

messages=${MESSAGES:-$TMPDIR/messages}
results=${RESULTS:-$TMPDIR/results}
mkdir -p "$(dirname "$messages")" "$(dirname "$results")"

#
#  Run the test cases
#

printf "Started\n"
start_time=$SECONDS
for test in $(dirname $0)/*_test.sh
do
  if [ -f "$test" ]
  then
    "$test" 2>>"$messages" | tee -a "$results"
  fi
done
end_time=$SECONDS
printf "\nFinished in $(($end_time - $start_time))s\n"

#
#  Print results
#

if [ -f "$messages" ] && [ -f "$results" ]
then
  count_char () {
    grep -o "$1" "$2" | wc -l | tr -d " "
  }

  printf "\n"
  cat "$messages"
  printf "$(count_char '\.' "$results") pass, $(count_char 'F' "$results") fail\n"
  rm "$messages" "$results"
fi
