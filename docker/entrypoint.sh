#!/bin/bash

# Copyright 2021 Alibaba Group Holding Limited.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

source /etc/profile

sudo chown -R polarx:polarx $BUILD_PATH

RUN_PATH=$1
POLARDBX_SQL_HOME="$RUN_PATH"/polardbx-sql
POLARDBX_CDC_HOME="$RUN_PATH"/polardbx-cdc/polardbx-binlog.standalone

if [ x"$mode" = "x" ]; then
    mode="play"
fi

function cn_pid() {
  ps auxf | grep java | grep TddlLauncher | cut -d ' ' -f 1
}

function cdc_pid() {
  ps auxf | grep java | grep DaemonBootstrap | cut -d ' ' -f 1
}

function dn_pid() {
  ps aux | grep mysqld | grep -v "grep" | awk '{print $2}'
}

function get_pid() {
  if [ x"$mode" = x"play" ]; then
      cn_pid
  elif [ x"$mode" = x"dev" ]; then
      dn_pid
  else
      echo "mode=$mode does not support yet."
      echo ""
  fi
}

function stop_all() {
  polardb-x.sh stop
  rm -f $POLARDBX_SQL_HOME/bin/*.pid
  rm -f $POLARDBX_CDC_HOME/bin/*.pid
}

function start_polardb_x() {
  echo "start polardb-x"

  polardb-x.sh start
}

function start_gms_and_dn() {
  echo "start gms and dn"

  polardb-x.sh start_dn
}

function start_process() {
  echo "start with mode=$mode"
  if [ x"$mode" = x"play" ]; then
      start_polardb_x
  elif [ x"$mode" = x"dev" ]; then
      start_gms_and_dn
  else
      echo "mode=$mode does not support yet."
  fi
}

last_pid=0
function report_pid() {
  pid=$(get_pid)
  if [ -z "$pid" ]; then
    echo "Process dead. Exit."
    last_pid=0
    return 1
  else
    if [[ $pid -ne $last_pid ]]; then
      echo "Process alive: " "$pid"
    fi
    last_pid=pid
  fi
  return 0
}

function watch() {
  while report_pid; do
    sleep 5
  done
}

function start() {
  # Start
  stop_all
  start_process
}

function waitterm() {
  local PID
  # any process to block
  tail -f /dev/null &
  PID="$!"
  # setup trap, could do nothing, or just kill the blocker
  trap "kill -TERM ${PID}" TERM INT
  # wait for signal, ignore wait exit code
  wait "${PID}" || true
  # clear trap
  trap - TERM INT
  # wait blocker, ignore blocker exit code
  wait "${PID}" 2>/dev/null || true
}

# Retry start and watch

retry_interval=30
retry_cnt=0
retry_limit=10
if [[ "$#" -ge 2 ]]; then
  retry_limit=$2
fi

while [[ $retry_cnt -lt $retry_limit ]]; do
  start

  if report_pid; then
    break 
  fi

  ((retry_cnt++))

  if [[ $retry_cnt -lt $retry_limit ]]; then
    sleep $retry_interval
  fi
done

waitterm

stop_all

# Abort.
exit 1
