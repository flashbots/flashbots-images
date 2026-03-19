pid_file = "/var/run/vault-agent.pid"

vault {
  address = "[[ gcp.Meta "attributes/vault_addr" ]]"

  retry {
    num_retries = 5
  }
}

auto_auth {
  method "gcp" {
    mount_path = "[[ gcp.Meta "attributes/vault_auth_mount_gcp" ]]"

    config = {
      type = "gce"
      role = "[[ gcp.Meta "name" ]]"
    }
  }
}
