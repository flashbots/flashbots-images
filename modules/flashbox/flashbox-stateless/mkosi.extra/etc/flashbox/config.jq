.root.path = "rootfs"
| .hostname = "flashbox"
| del(.linux.cgroupsPath, .annotations)
| .mounts |= [
    {destination: "/flashbox", type: "bind", source: "flashbox", options: ["rbind", "nosuid", "nodev"]},
    {destination: "/flashbox/log", type: "bind", source: "log", options: ["bind", "nosuid", "nodev", "noexec"]},
    {destination: "/data", type: "bind", source: "/persistent/searcher/data", options: ["rbind", "ro", "nosuid", "nodev"]}
  ] + map(select(.type != "bind")) + [
    {destination: "/dev/shm", type: "tmpfs", source: "shm", options: ["nosuid", "noexec", "nodev", "mode=1777", "size=65536k"]}
  ]
