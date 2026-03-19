template {
  left_delimiter  = "(("
  right_delimiter = "))"

  destination = "/etc/sysconfig/op-rbuilder.env"

  user  = "root"
  group = "optimism"
  perms = "0640"

  exec {
    timeout = "60s"

    command = ["/bin/sh", "-c",
      <<-EOT
        # op-rbuilder.env
        systemctl restart op-rbuilder
      EOT
    ]
  }

  contents = <<-EOT
    ((- printf "# %s\n\n" "op-rbuilder" -))

    ((- $node    := ( secret "[[ gcp.Meta "attributes/vault_kv_path" ]]/node/[[ gcp.Meta "name" ]]" ).Data.data -))
    ((- $service := ( secret "[[ gcp.Meta "attributes/vault_kv_path" ]]/node/_common[[ if ( gcp.Meta "attributes/service" ) ]]_[[ gcp.Meta "attributes/service" | strings.ReplaceAll "-" "_" ]][[ end ]]" ).Data.data -))

    ((- if $node.builder_secret_key -))
    BUILDER_SECRET_KEY=(( $node.builder_secret_key ))(( "\n" ))
    ((- end -))

    ((- if $node.coinbase_secret_key -))
    COINBASE_SECRET_KEY=(( $node.coinbase_secret_key ))(( "\n" ))
    ((- end -))

    ((- if $service.otel_exporter_otlp_endpoint -))
    OTEL_EXPORTER_OTLP_ENDPOINT=(( $service.otel_exporter_otlp_endpoint ))(( "\n" ))
    ((- end -))

    ((- if $node.otel_exporter_otlp_headers -))
    OTEL_EXPORTER_OTLP_HEADERS=(( $node.otel_exporter_otlp_headers ))(( "\n" ))
    ((- end -))

    ((- if $service.otel_service_name -))
    OTEL_SERVICE_NAME=(( $service.otel_service_name ))(( "\n" ))
    ((- end -))
  EOT
}
