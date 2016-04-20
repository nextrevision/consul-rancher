#!/bin/sh -x

ACTION=${1:-agent}

# wait for rancher-metadata
echo "Waiting for rancher metadata..."
sleep 5

ADVERTISE_IP=`curl -s http://rancher-metadata/latest/self/host/agent_ip`
SERVERS=`/bin/giddyup ip stringify consul/consul-server | tr ',' ' '`
SCALE=`curl -s http://rancher-metadata/latest/services/consul-server/scale`

CONSUL_CMD="/bin/consul agent -config-dir=/config -advertise=${ADVERTISE_IP}"

wait_for_scale() {
  local count=$1
  local url=http://rancher-metadata/latest/services/consul-server/containers/
  while [ `curl -s $url | wc -l` -lt $count ]; do
    echo "Waiting for remaining consul servers to come up..."
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
    peers=$(/bin/giddyup ip stringify --prefix '"' --suffix ':8300"' consul/consul-server)
    echo "[${peers}]" > /data/raft/peers.json
  fi
}

if [[ $ACTION == "server" ]]; then
  echo "Ensuring all consul-server containers are up (expecting ${SCALE})..."
  wait_for_scale $SCALE
  JOIN_CMD=$(/bin/giddyup ip stringify --delimiter ' ' --prefix '--join ' consul/consul-server)
  CONSUL_CMD="${CONSUL_CMD} -server -ui-dir=/ui -bootstrap-expect 3 -rejoin ${JOIN_CMD}"
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

echo "Joining cluster with '${SERVERS}'..."
echo "Starting consul as '${ACTION}' with command:"
echo "  ${CONSUL_CMD}"
exec $CONSUL_CMD
