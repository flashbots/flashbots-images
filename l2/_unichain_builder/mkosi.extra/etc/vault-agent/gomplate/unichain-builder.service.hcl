template {
  left_delimiter  = "(("
  right_delimiter = "))"

  source      = "/etc/vault-agent/unichain-builder.service.ctmpl"
  destination = "/etc/systemd/system/unichain-builder.service"

  user  = "root"
  group = "root"
  perms = "0644"

  exec {
    timeout = "60s"

    command = ["/bin/sh", "-c",
      <<-EOT
        # unichain-builder

        systemctl daemon-reload
        systemctl enable unichain-builder

        # patterns longer than 15 chars result in 0 matches
        PID=$( pgrep node-health ); if [ 0${PID} -gt 0 ]; then kill -1 ${PID} | true; fi
        sleep 5

        PID=$( pgrep bproxy ); if [ 0${PID} -gt 0 ]; then kill -1 ${PID} | true; fi

        systemctl restart unichain-builder
        systemctl restart node-healthchecker
      EOT
    ]
  }
}
