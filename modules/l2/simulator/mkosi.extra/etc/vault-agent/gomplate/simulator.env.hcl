template {
  left_delimiter  = "(("
  right_delimiter = "))"

  source      = "/etc/vault-agent/simulator.env.ctmpl"
  destination = "/etc/sysconfig/simulator.env"

  user  = "root"
  group = "optimism"
  perms = "0640"

  exec {
    timeout = "60s"

    command = ["/bin/sh", "-c",
      <<-EOT
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
