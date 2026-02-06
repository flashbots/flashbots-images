template {
  left_delimiter  = "(("
  right_delimiter = "))"

  destination = "/var/opt/optimism/jwtsecret"

  user  = "root"
  group = "optimism"
  perms = "0440"

  contents = <<-EOT
    ((- with secret "[[ gcp.Meta "attributes/vault_kv_path" ]]/node/[[ gcp.Meta "name" ]]" -))
    (( .Data.data.jwt_secret ))
    ((- end -))
  EOT
}
