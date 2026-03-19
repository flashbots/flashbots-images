[[- if ( file.Exists "/home/debian/.ssh/authorized_keys" ) ]]
template {
  left_delimiter  = "(("
  right_delimiter = "))"

  source      = "/etc/vault-agent/authorized_keys.ctmpl"
  destination = "/home/debian/.ssh/authorized_keys"

  user  = "debian"
  group = "debian"
  perms = "0600"
}
[[- end ]]
