template {
  left_delimiter  = "(("
  right_delimiter = "))"

  destination = "/var/opt/optimism/simulator/genesis.json.tar.gz.base64"

  user  = "simulator"
  group = "optimism"
  perms = "0640"

  exec {
    timeout = "60s"

    command = ["/bin/sh", "-c",
      <<-EOT
        # genesis.json
        chown simulator:optimism /var/opt/optimism/simulator
        chmod 0750 /var/opt/optimism/simulator
        systemctl restart simulator
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
