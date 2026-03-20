template {
  left_delimiter  = "(("
  right_delimiter = "))"

  source      = "/etc/vault-agent/simulator.service.ctmpl"
  destination = "/etc/systemd/system/simulator.service"

  user  = "root"
  group = "root"
  perms = "0644"

  exec {
    timeout = "60s"

    command = ["/bin/sh", "-c",
      <<-EOT
        printf "simulator: %s\n" "$( cat /etc/systemd/system/simulator.service | base64 -w 0 )"

        systemctl daemon-reload
        systemctl add-wants minimal.target simulator.service

        # patterns longer than 15 chars result in 0 matches
        PID=$( pgrep node-health ); if [ 0${PID} -gt 0 ]; then kill -1 ${PID} || true; fi
        sleep 5

        PID=$( pgrep rproxy ); if [ 0${PID} -gt 0 ]; then kill -1 ${PID} || true; fi

        systemctl restart simulator.service
        systemctl restart node-healthchecker.service
      EOT
    ]
  }
}
