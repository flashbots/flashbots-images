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
    ((- printf "# %s\n\n" "simulator" -))

    ((- $node := ( secret "[[ gcp.Meta "attributes/vault_kv_path" ]]/node/[[ gcp.Meta "name" ]]" ).Data.data -))

    ((- if $node.clickhouse_password -))
    CLICKHOUSE_PASSWORD=(( $node.clickhouse_password ))(( "\n" ))
    ((- end -))
  EOT
}
