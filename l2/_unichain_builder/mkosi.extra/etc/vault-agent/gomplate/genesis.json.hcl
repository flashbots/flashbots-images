template {
  left_delimiter  = "(("
  right_delimiter = "))"

  destination = "/var/opt/optimism/unichain-builder/genesis.json.tar.gz.base64"

  user  = "unichain-builder"
  group = "optimism"
  perms = "0640"

  exec {
    timeout = "60s"

    command = ["/bin/sh", "-c",
      <<-EOT
        # genesis.json
        chown unichain-builder:optimism /var/opt/optimism/unichain-builder
        chmod 0750 /var/opt/optimism/unichain-builder
        systemctl restart unichain-builder
      EOT
    ]
  }

  contents = <<-EOT
    ((- $service := ( secret "[[ gcp.Meta "attributes/vault_kv_path" ]]/node/_common[[ if ( gcp.Meta "attributes/service" ) ]]_[[ gcp.Meta "attributes/service" | strings.ReplaceAll "-" "_" ]][[ end ]]" ).Data.data -))

    ((- if $service.genesis_json -))
    ((- $service.genesis_json -))
    ((- end -))
  EOT
}
