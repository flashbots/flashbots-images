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
        printf "rproxy: %s\n" "$( cat /etc/systemd/system/rproxy.service | base64 -w 0 )"

        systemctl daemon-reload
        systemctl add-wants minimal.target rproxy.service
        systemctl restart rproxy.service
      EOT
    ]
  }
}
