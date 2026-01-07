template {
  left_delimiter  = "(("
  right_delimiter = "))"

  destination = "/var/opt/optimism/unichain-builder/discovery-secret"

  user  = "unichain-builder"
  group = "optimism"
  perms = "0600"

  exec {
    timeout = "60s"

    command = ["/bin/sh", "-c",
      <<-EOT
        # discovery-secret
        chown unichain-builder:optimism /var/opt/optimism/unichain-builder
        chmod 0750 /var/opt/optimism/unichain-builder
        systemctl restart unichain-builder
      EOT
    ]
  }

  contents = <<-EOT
    ((- $node := ( secret "[[ gcp.Meta "attributes/vault_kv_path" ]]/node/[[ gcp.Meta "name" ]]" ).Data.data -))

    ((- $node.el_nodekey -))
  EOT
}
