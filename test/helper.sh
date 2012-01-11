#
#  Defines assertions and other functions needed
#  to run the tests.
#

setup () {
  return 0
}

teardown () {
  return 0
}

flunk () {
  printf "[$TEST_FILE:$lineno] $TEST_NAME\n$1\n\n" 1>&2
  return 1
}

assert_status_equal () {
  expected=$1; actual=$2; lineno=$3

  if [ $actual -ne $expected ]
  then
    flunk "expected exit status $expected but was $actual"
  fi
}

assert_output_equal () {
  expected=$(cat); actual=$1; lineno=$2

  if [ "$actual" != "$expected" ]
  then
    echo -e "$expected" > "$TEST_DIR.expect"
    echo -e "$actual"   > "$TEST_DIR.actual"

    flunk "unequal stdout:\n$(diff "$TEST_DIR.expect" "$TEST_DIR.actual")"

    rm "$TEST_DIR.expect" "$TEST_DIR.actual"
    return 1
  fi
}

assert_equal () {
  assert_status_equal $1 $? $3 &&
  assert_output_equal "$2" $3
}

run_test_cases () {
  USER_DIR="$(pwd)"
  TEST_FILE="$0"
  TEST_BASE_DIR="$USER_DIR/${TEST_FILE%\.*}"

  mkdir -p "$TEST_BASE_DIR"
  for TEST_NAME in $(grep -oE "^ *${NAME:-test_\w+} +\(\)" "$TEST_FILE" | tr -d " ()")
  do
    TEST_DIR="$TEST_BASE_DIR/$TEST_NAME"
    rm -rf "$TEST_DIR"
    setup

    if "$TEST_NAME"
    then printf '.'
    else printf 'F'
    fi

    teardown
    if [ "${KEEP_OUTPUTS:-false}" != "true" ]
    then rm -rf "$TEST_DIR"
    fi
  done
  rmdir "$TEST_BASE_DIR" 2> /dev/null
}