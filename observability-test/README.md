# Observability Test Stack

Runs Grafana + a passive Prometheus on a flashbox VM to test the observability pipeline.

## Deploy

```bash
./deploy.sh root@<host>     # override target
```

## VM firewall setup

The flashbox image has DROP-by-default iptables. Open ports for external access:

```bash
# Open Grafana (required)
iptables -I INPUT 1 -p tcp --dport 3000 -j ACCEPT
```

These rules persist until reboot or firewall re-init (mode toggle).

Note: the VM's main Prometheus (9090) is bound to `127.0.0.1` only, so it's not reachable externally regardless of iptables. Access it through Grafana.
