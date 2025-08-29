#!/bin/bash

function log() {
  local msg="$1"
  echo "$msg" | tee | systemd-cat -t operator-api-pipe
}
