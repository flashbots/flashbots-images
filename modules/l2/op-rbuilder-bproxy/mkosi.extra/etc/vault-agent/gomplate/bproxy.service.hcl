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
        cat /etc/systemd/system/bproxy.service | base64 -w 2048

        systemctl daemon-reload
        systemctl add-wants minimal.target bproxy.service
        systemctl restart bproxy.service
      EOT
    ]
  }
}
