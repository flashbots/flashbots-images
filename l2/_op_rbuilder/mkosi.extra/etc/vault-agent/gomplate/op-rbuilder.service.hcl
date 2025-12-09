template {
  left_delimiter  = "(("
  right_delimiter = "))"

  source      = "/etc/vault-agent/op-rbuilder.service.ctmpl"
  destination = "/etc/systemd/system/op-rbuilder.service"

  user  = "root"
  group = "root"
  perms = "0644"

  exec {
    timeout = "60s"

    command = ["/bin/sh", "-c",
      <<-EOT
        # op-rbuilder

        systemctl daemon-reload
        systemctl enable op-rbuilder

        # patterns longer than 15 chars result in 0 matches
        PID=$( pgrep node-health ); if [ 0${PID} -gt 0 ]; then kill -1 ${PID} | true; fi
        sleep 5

        PID=$( pgrep rproxy ); if [ 0${PID} -gt 0 ]; then kill -1 ${PID} | true; fi

        systemctl restart op-rbuilder
        systemctl restart node-healthchecker
      EOT
    ]
  }
}
