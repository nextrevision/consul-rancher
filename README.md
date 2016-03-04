# consul-rancher

[![](https://badge.imagelayers.io/nextrevision/consul-rancher:latest.svg)](https://imagelayers.io/?images=nextrevision/consul-rancher:latest 'Get your own badge on imagelayers.io')

Uses [Rancher](https://rancher.com) to deploy a HA Consul cluster (3 nodes) with agents and registrator on all hosts in an environment.

## Deploying

There are two good options for deploying this as a stack. You can either create a new stack from the web UI and copy and paste the contents of the `docker-compose.yml` and `rancher-compose.yml` files into the relevant fields or you can deploy via the `rancher-compose` CLI:

```
rancher-compose --url http://rancher-server:8080 --access-key XXXXXXX --secret-key XXXXXX up -d
```

You can then access http://<host_ip>:8500/ui/ from your workstation, replacing `host_ip` with the IP address of one of the hosts in your Rancher environment.

## Upgrading

You can perform rolling upgrades of the entire cluster with the following command:

```
rancher-compose --url http://rancher-server:8080 --access-key XXXXXXX --secret-key XXXXXX up -d \
  -u --interval 300000 --batch-size 1
```

This is set to be conservative, upgrading one service at a time every 5 minutes.
