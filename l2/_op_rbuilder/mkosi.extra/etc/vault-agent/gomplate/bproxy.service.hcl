template {
  left_delimiter  = "(("
  right_delimiter = "))"

  source      = "/etc/vault-agent/bproxy.service.ctmpl"
  destination = "/etc/systemd/system/bproxy.service"

  user  = "root"
  group = "root"
  perms = "0644"

  exec {
    timeout = "60s"

    command = ["/bin/sh", "-c",
      <<-EOT
        systemctl daemon-reload
        systemctl enable bproxy
        systemctl restart bproxy
      EOT
    ]
  }
}
