template {
  left_delimiter  = "(("
  right_delimiter = "))"

  destination = "/var/opt/optimism/rbuilder/discovery-secret"

  user  = "op-rbuilder"
  group = "optimism"
  perms = "0600"

  exec {
    timeout = "60s"

    command = ["/bin/sh", "-c",
      <<-EOT
        # discovery-secret
        chown op-rbuilder:optimism /var/opt/optimism/rbuilder
        chmod 0750 /var/opt/optimism/rbuilder
        systemctl restart op-rbuilder
      EOT
    ]
  }

  contents = <<-EOT
    ((- $node := ( secret "[[ gcp.Meta "attributes/vault_kv_path" ]]/node/[[ gcp.Meta "name" ]]" ).Data.data -))

    ((- $node.el_nodekey -))
  EOT
}
