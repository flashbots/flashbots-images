[[- if ( file.Exists "/home/ubuntu/.ssh/authorized_keys" ) ]]
template {
  left_delimiter  = "(("
  right_delimiter = "))"

  source      = "/etc/vault-agent/authorized_keys.ctmpl"
  destination = "/home/ubuntu/.ssh/authorized_keys"

  user  = "ubuntu"
  group = "ubuntu"
  perms = "0600"
}
[[- end ]]
