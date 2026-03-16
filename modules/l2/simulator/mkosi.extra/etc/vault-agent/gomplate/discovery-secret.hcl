template {
  left_delimiter  = "(("
  right_delimiter = "))"

  destination = "/var/opt/optimism/simulator/discovery-secret"

  user  = "simulator"
  group = "optimism"
  perms = "0600"

  exec {
    timeout = "60s"

    command = ["/bin/sh", "-c",
      <<-EOT
        # discovery-secret
        chown simulator:optimism /var/opt/optimism/simulator
        chmod 0750 /var/opt/optimism/simulator
        systemctl restart simulator
      EOT
    ]
  }

  contents = <<-EOT
    ((- $node := ( secret "[[ gcp.Meta "attributes/vault_kv_path" ]]/node/[[ gcp.Meta "name" ]]" ).Data.data -))

    ((- $node.el_nodekey -))
  EOT
}
