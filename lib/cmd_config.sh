#!/usr/bin/env bash

cmd_config() {
  [ $# -ge 1 ] || gl_die "usage: greenlyt config <jq-path> [default]"
  gl_config_get "$@"
  echo
}
