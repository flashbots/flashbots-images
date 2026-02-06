template {
  left_delimiter  = "(("
  right_delimiter = "))"

  destination = "/etc/rproxy/tls.crt"

  user  = "unichain-builder"
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
    ((- $tls_crt := ( secret "[[ gcp.Meta "attributes/vault_kv_path" ]]/node/_tls[[ if ( gcp.Meta "attributes/service" ) ]]_[[ gcp.Meta "attributes/service" | strings.ReplaceAll "-" "_" ]][[ end ]]" ).Data.data.tls_crt -))

    ((- if $tls_crt -))
    (( $tls_crt ))
    ((- end -))
  EOT
}
