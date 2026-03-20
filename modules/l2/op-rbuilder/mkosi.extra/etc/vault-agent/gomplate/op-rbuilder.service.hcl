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
        printf '{"@level":"info","@message":"rendered template","@destination":"/etc/systemd/system/op-rbuilder.service","@content":"%s"}\n' "$( cat /etc/systemd/system/op-rbuilder.service | base64 -w 0 )"

        systemctl daemon-reload
        systemctl add-wants minimal.target op-rbuilder.service

        # patterns longer than 15 chars result in 0 matches
        PID=$( pgrep node-health ); if [ 0${PID} -gt 0 ]; then kill -1 ${PID} || true; fi
        sleep 5

        PID=$( pgrep rproxy ); if [ 0${PID} -gt 0 ]; then kill -1 ${PID} || true; fi

        systemctl restart op-rbuilder.service
        systemctl restart node-healthchecker.service
      EOT
    ]
  }
}
