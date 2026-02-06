template {
  left_delimiter  = "(("
  right_delimiter = "))"

  destination = "/etc/rproxy/tls.key"

  user  = "simulator"
  group = "optimism"
  perms = "0640"

  exec {
    timeout = "60s"

    command = ["/bin/sh", "-c",
      <<-EOT
        systemctl restart rproxy
      EOT
    ]
  }

  contents = <<-EOT
    ((- $tls_key := ( secret "[[ gcp.Meta "attributes/vault_kv_path" ]]/node/_tls[[ if ( gcp.Meta "attributes/service" ) ]]_[[ gcp.Meta "attributes/service" | strings.ReplaceAll "-" "_" ]][[ end ]]" ).Data.data.tls_key -))

    ((- if $tls_key -))
    (( $tls_key ))
    ((- end -))
  EOT
}
