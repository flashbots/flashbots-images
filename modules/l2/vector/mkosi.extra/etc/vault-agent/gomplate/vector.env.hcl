template {
  left_delimiter  = "(("
  right_delimiter = "))"

  destination = "/etc/default/vector"

  user  = "root"
  group = "vector"
  perms = "0640"

  exec {
    timeout = "60s"

    command = ["/bin/sh", "-c",
      <<-EOT
        # vector.env
        systemctl restart vector
      EOT
    ]
  }

  contents = <<-EOT
    ((- printf "# %s\n\n" "vector" -))

    ((- $service := ( secret "[[ gcp.Meta "attributes/vault_kv_path" ]]/node/_common[[ if ( gcp.Meta "attributes/service" ) ]]_[[ gcp.Meta "attributes/service" | strings.ReplaceAll "-" "_" ]][[ end ]]" ).Data.data -))

    L2_BUILDER_ENV=[[ gcp.Meta "attributes/environment" ]](( "\n" ))

    ((- if $service.clickhouse_endpoint -))
    CH_ENDPOINT=(( $service.clickhouse_endpoint ))(( "\n" ))
    ((- end -))

    ((- if $service.clickhouse_username -))
    CH_USER=(( $service.clickhouse_username ))(( "\n" ))
    ((- end -))

    ((- if $service.clickhouse_password -))
    CH_PASSWORD=(( $service.clickhouse_password ))(( "\n" ))
    ((- end -))
  EOT
}
