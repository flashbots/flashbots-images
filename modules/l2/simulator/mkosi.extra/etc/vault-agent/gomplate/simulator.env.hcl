template {
  left_delimiter  = "(("
  right_delimiter = "))"

  destination = "/etc/sysconfig/simulator.env"

  user  = "root"
  group = "optimism"
  perms = "0640"

  exec {
    timeout = "60s"

    command = ["/bin/sh", "-c",
      <<-EOT
        # simulator.env
        systemctl restart simulator
      EOT
    ]
  }

  contents = <<-EOT
    GOOGLE_CLOUD_QUOTA_PROJECT="[[ include "gcp" "project/project-id" ]]"
    OTEL_EXPORTER_OTLP_ENDPOINT="https://telemetry.googleapis.com"
    OTEL_EXPORTER_OTLP_HEADERS="x-goog-user-project=[[ include "gcp" "project/project-id" ]]"
    OTEL_RESOURCE_ATTRIBUTES="gcp.project_id=[[ include "gcp" "project/project-id" ]]"

    ((- $node := ( secret "[[ gcp.Meta "attributes/vault_kv_path" ]]/node/[[ gcp.Meta "name" ]]" ).Data.data -))(( "\n" ))

    ((- if $node.clickhouse_password -))
    CLICKHOUSE_PASSWORD="(( $node.clickhouse_password ))"(( "\n" ))
    ((- end -))
  EOT
}
