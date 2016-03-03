#!/bin/sh

# wait for rancher-metadata
sleep 5

# wait for all hosts to come up before starting
/bin/giddyup service wait scale --timeout 600

ACTION=${1:-agent}
ADVERTISE_IP=`curl -s http://rancher-metadata/latest/self/container/primary_ip`
STACK_NAME=`curl -s http://rancher-metadata/latest/self/stack/name`
SERVERS=`/bin/giddyup ip stringify ${STACK_NAME}/consul-server | tr ',' ' '`
SERVER_COUNT=`curl -s http://rancher-metadata/latest/self/service/scale`

CONSUL_CMD="/bin/consul agent -config-dir=/config -advertise=${ADVERTISE_IP}"

check_servers() {
  local rc=1
  for s in ${SERVERS}; do
    if [ `curl -w %{http_code} -s -o /dev/null http://${s}:8500/v1/status/leader` -eq 200 ]; then
      rc=0
      break
    fi
  done
  return $rc
}

wait_for_server() {
  while ! check_servers; do
    echo "Waiting for a member in '${SERVERS}' to come up..."
    sleep 10
  done
}

wait_for_leader() {
  while [[ `curl -s http://consul-lb:8500/v1/status/leader` == "" ]]; do
    echo "Waiting for leader to come up..."
    sleep 10
  done
}

force_cleanup() {
  while sleep 60; do
    [ -d /tmp/failed ] || mkdir /tmp/failed
    for m in `consul members | grep failed | awk '{ print $1 }'`; do
      echo $m >> /tmp/failed/$m
    done
    for f in `ls /tmp/failed`; do
      if [ `wc -l /tmp/failed/$f | awk '{ print $1 }'` -eq 3 ]; then
        echo "Forcing $f to leave the members due to timeout"
        consul force-leave $f && rm -f /tmp/failed/$f
      fi
    done
  done
}

reset_raft() {
  local peers=""
  if [ -f /data/raft/peers.json ]; then
    peers=$(/bin/giddyup ip stringify --prefix '"' --suffix ':8300"')
    echo "[${peers}]" > /data/raft/peers.json
  fi
}

if [[ $ACTION == "server" ]]; then
  CONSUL_CMD="${CONSUL_CMD} -server -ui-dir=/ui -bootstrap-expect ${SERVER_COUNT}"
  JOIN_CMD=$(/bin/giddyup ip stringify --delimiter " " --prefix "--join ")
  if ! check_servers; then
    echo "No leader could be found, checking if I should bootstrap..."
    if /bin/giddyup leader check; then
      echo "Going to bootstrap..."
      CONSUL_CMD="${CONSUL_CMD}"
    else
      wait_for_server
      echo "Member came up, attempting to join..."
      CONSUL_CMD="${CONSUL_CMD} -rejoin ${JOIN_CMD}"
    fi
  else
    echo "Joining existing cluster with '${SERVERS}'..."
    CONSUL_CMD="${CONSUL_CMD} -rejoin ${JOIN_CMD}"
  fi
  echo "Backgrounding force-leave cleanup task"
  force_cleanup &
  reset_raft
else
  wait_for_leader
  CONSUL_CMD="${CONSUL_CMD} -rejoin -join consul-lb"
  reset_raft
fi

echo "Starting consul as ${ACTION} with ${CONSUL_CMD}"
exec $CONSUL_CMD
