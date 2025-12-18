template {
  left_delimiter  = "(("
  right_delimiter = "))"

  source      = "/etc/vault-agent/rproxy.service.ctmpl"
  destination = "/etc/systemd/system/rproxy.service"

  user  = "root"
  group = "root"
  perms = "0644"

  exec {
    timeout = "60s"

    command = ["/bin/sh", "-c",
      <<-EOT
        systemctl daemon-reload
        systemctl enable rproxy
        systemctl restart rproxy
      EOT
    ]
  }
}
