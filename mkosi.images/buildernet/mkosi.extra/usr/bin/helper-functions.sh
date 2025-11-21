#!/bin/bash

function log() {
  if [ $# -gt 0 ]; then
    # Case 1: called with an argument
    echo "$*" | tee >(systemd-cat -t operator-api-pipe)
  else
    # Case 2: used in a pipeline
    tee >(systemd-cat -t operator-api-pipe)
  fi
}
