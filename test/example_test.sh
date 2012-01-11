#!/bin/bash
. ${0%/$(basename "$0")}/helper.sh

#
# assert_equal test
#

setup () {
  mkdir -p "$TEST_DIR"
  cd "$TEST_DIR"
  git init > /dev/null
}

teardown () {
  cd "$USER_DIR"
}

test_make_a_commit () {
  echo "You don't exist. Go away!" > file.txt

  assert_output_equal "$(
git hash-object -w file.txt
)" $LINENO <<stdout
0d2a0a3954c9b7e872d77653cc60d7584da24033
stdout

  assert_output_equal "$(
git mktree <<tree
100644 blob 0d2a0a3954c9b7e872d77653cc60d7584da24033	file.txt
tree
)" $LINENO <<stdout
9ac809b29ab6361871600e90a566a56c52ae5f41
stdout

  export GIT_AUTHOR_NAME="John Doe"
  export GIT_AUTHOR_EMAIL="john.doe@example.com"
  export GIT_AUTHOR_DATE="2005-04-07T22:13:13  -0600"
  export GIT_COMMITTER_NAME="Jane Doe"
  export GIT_COMMITTER_EMAIL="jane.doe@example.com"
  export GIT_COMMITTER_DATE="2005-04-07T22:13:13 -0700"

  assert_output_equal "$(
git commit-tree 9ac809b29ab6361871600e90a566a56c52ae5f41 <<msg
Your sysadmin must hate you!
msg
)" $LINENO <<stdout
a025c527236ea29ef0d99ec8d99a21804f7d3dab
stdout

  assert_output_equal "$(
git show --pretty=raw 0d2a0a3954c9b7e872d77653cc60d7584da24033
)" $LINENO <<stdout
You don't exist. Go away!
stdout

  assert_output_equal "$(
git ls-tree 9ac809b29ab6361871600e90a566a56c52ae5f41
)" $LINENO <<stdout
100644 blob 0d2a0a3954c9b7e872d77653cc60d7584da24033	file.txt
stdout

  assert_output_equal "$(
git log -n1 --format=raw a025c527236ea29ef0d99ec8d99a21804f7d3dab
)" $LINENO <<stdout
commit a025c527236ea29ef0d99ec8d99a21804f7d3dab
tree 9ac809b29ab6361871600e90a566a56c52ae5f41
author John Doe <john.doe@example.com> 1112933593 -0600
committer Jane Doe <jane.doe@example.com> 1112937193 -0700

    Your sysadmin must hate you!
stdout
}

run_test_cases