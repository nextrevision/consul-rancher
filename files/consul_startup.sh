#!/bin/sh

ACTION=${1:-agent}

# wait for rancher-metadata
echo "Waiting for rancher metadata..."
sleep 5

# wait for all hosts to come up before starting
echo "Waiting for all containers to become available..."
/bin/giddyup service wait scale --timeout 600

ADVERTISE_IP=`curl -s http://rancher-metadata/latest/self/host/agent_ip`
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
  while [[ `curl -s http://consul:8500/v1/status/leader` == "" ]]; do
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
  JOIN_CMD=$(/bin/giddyup ip stringify --delimiter " " --prefix "--join ")
  CONSUL_CMD="${CONSUL_CMD} -server -ui-dir=/ui -bootstrap-expect ${SERVER_COUNT} -rejoin ${JOIN_CMD}"

  if ! check_servers && ! /bin/giddyup leader check; then
    "Waiting for bootstrap server to come up..."
    wait_for_server
  else
    echo "Joining existing cluster with '${SERVERS}'..."
  fi
  echo "Backgrounding force-leave cleanup task..."
  force_cleanup &
  echo "Resetting raft peers..."
  reset_raft
else
  CONSUL_CMD="${CONSUL_CMD} -rejoin -join consul"
  echo "Waiting for a leader to be elected..."
  wait_for_leader
  echo "Resetting raft peers..."
  reset_raft
fi

echo "Starting consul as '${ACTION}' with command:"
echo "  ${CONSUL_CMD}"
exec $CONSUL_CMD
