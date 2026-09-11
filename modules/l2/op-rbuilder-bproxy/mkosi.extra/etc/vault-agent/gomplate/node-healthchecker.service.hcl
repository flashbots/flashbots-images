template {
  left_delimiter  = "(("
  right_delimiter = "))"

  source      = "/etc/vault-agent/node-healthchecker.service.ctmpl"
  destination = "/etc/systemd/system/node-healthchecker.service"

  user  = "root"
  group = "root"
  perms = "0644"

  exec {
    timeout = "60s"

    command = ["/bin/sh", "-c",
      <<-EOT
        cat /etc/systemd/system/node-healthchecker.service | base64 -w 2048

        systemctl daemon-reload
        systemctl add-wants minimal.target node-healthchecker.service
        systemctl restart node-healthchecker.service
      EOT
    ]
  }
}
