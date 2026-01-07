template {
  left_delimiter  = "(("
  right_delimiter = "))"

  destination = "/etc/sysconfig/unichain-builder.env"

  user  = "root"
  group = "optimism"
  perms = "0640"

  exec {
    timeout = "60s"

    command = ["/bin/sh", "-c",
      <<-EOT
        # unichain-builder.env
        systemctl restart unichain-builder
      EOT
    ]
  }

  contents = <<-EOT
    ((- printf "# %s\n\n" "unichain-builder" -))

    ((- $node := ( secret "[[ gcp.Meta "attributes/vault_kv_path" ]]/node/[[ gcp.Meta "name" ]]" ).Data.data -))

    ((- if $node.builder_secret_key -))
    BUILDER_SECRET_KEY=(( $node.builder_secret_key ))(( "\n" ))
    ((- end -))

    ((- if $node.coinbase_secret_key -))
    COINBASE_SECRET_KEY=(( $node.coinbase_secret_key ))(( "\n" ))
    ((- end -))
  EOT
}
