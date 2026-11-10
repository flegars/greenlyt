#!/usr/bin/env bash

cmd_config() {
  [ $# -ge 1 ] || gl_die "usage: greenlyt config <chemin-jq> [défaut]"
  gl_config_get "$@"
  echo
}
