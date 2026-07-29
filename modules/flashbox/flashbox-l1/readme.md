TEE Searcher
===

Using Intel TDX, Flashbots has built a way for searchers to trustlessly backrun transactions with full information, without exposing frontrunning risks. This product is currently live on Ethereum mainnet for searching on Flashbots Protect and BuilderNet's bottom of block.

- [TDX Mental Model](#tdx-mental-model)
- [Image Overview](#image-overview)
- [Firewall Rules](#firewall-rules)
- [Machine Specs and Cost](#machine-specs-and-cost)
- [Attestation Walkthrough](#attestation-walkthrough)
- [Order Flow APIs](#order-flow-apis)
  - [Flashbots Protect](#searching-on-flashbots-protect-transactions)
  - [BuilderNet](#searching-on-buildernets-bottom-of-block)
- [Disk Persistence](#disk-persistence)
- [Searcher Commands and Services](#searcher-commands-and-services)
- [Developer Notes](#developer-notes)
- [Security](#security)

TDX Mental Model
------------------------

First, searchers verify that the TDX operator, in this case Flashbots, cannot access or observe code inside a TDX machine through a process called **attestation:**

- Searchers audit the TDX image that only their public SSH key can access the machine, and then build and measure (hash) the image locally.
- Then, searchers request and verify the measurement from the cloud provider (in our case Google Cloud Platform) is the same to confirm the exact image they audited is running on the TDX machine they will upload their code to.

But, in the TDX image, the searcher is also restricted to its own user group without root privileges. This allows us to implement sandboxing and log delays on the host safely, without the searcher being able to override or interfere with these restrictions. So, even though the searcher is given SSH access to the machine, the searcher is sufficiently restricted to guarantee they would not be able to expose any sensitive data submitted by the order flow provider.

**Importantly, implementing searcher sandboxing, log delays, and mode toggling inside the TDX VM also allows order flow providers and their users to verify their orders cannot be frontrun using TDX attestation.**

Image Overview
------------------------
There are three key features of the image:

1. **Network namespaces and firewall rules** that enforce a searcher cannot SSH into the container while transactions are being streamed in, and the only way information can leave is through the order flow provider's endpoints.
2. A **log delay** script that enforces a 5 minute (~25 block) delay until the searcher can view their machine logs.
3. **Mode switching** which allows a searcher to toggle between production and maintenance modes, where the SSH connection is cut and restored respectively.

Together, they provide the “no-frontrunning” guarantee to order flow providers while balancing searcher bot visibility and maintenance.

<img alt="tee-searcher" src="https://github.com/user-attachments/assets/de71d2ab-5a99-4ade-a9d9-cececd987e70" />

- The image will provide one rootless podman container running Ubuntu 24.04 that installs and runs OpenSSH with only the searcher’s SSH public key added to the `authorized_keys` file. The searcher will upload and manage their bot here, which typically contains a modified geth node.
- There are two modes — production and maintenance — with the following [firewall rules](#firewall-rules). During production mode, SSH connection to the container is cut, and transaction streaming begins. When searchers need to fix their bot, searchers can switch to maintenance mode, and the SSH connection is restored after a 5 minute delay.
- Mode switching is implemented using SSH and `execl`. A separate dropbear SSH server is run on the host, and upon SSH connection, we use `execl` to replace the SSH program with another program that executes and ends immediately, without continuing to execute SSH. Searchers will use this SSH connection to:
    1. Encrypt and decrypt their persistent disk
    2. Toggle between production and maintenance modes
    2. Check which mode the machine is in
    3. Print delayed logs during production mode without triggering maintenance mode
- Searchers write logs to a file from their container which is also mounted on the host. The host runs ncat to forward and delay logs from this file to another file on the host, which can be accessed externally by the searcher via the dropbear SSH command above. The delay is currently configured to be five minutes.
    - The host will also run logrotate to maintain storage usage, compressing .log files daily and deleting .log files older than five days.
- The searcher’s proprietary EL node communicates with a Lighthouse CL node run on the host over a shared JWT secret file mount and the engine API on port 8551.

To recap, searchers have two access points to the machine, both via SSH:
1. Data plane: accessing the rootless podman container through OpenSSH server
2. Control plane: executing small pre-defined scripts on the host through Dropbear SSH server

Firewall Rules
------------------------
<img alt="tee-searcher-networking" src="https://github.com/user-attachments/assets/8dd72ece-44de-4907-9d2d-1dd32b7c1468" />

**IMPORTANT: Searchers, you will not have DNS access during production mode!**

**<u>Host Network Namespace iptables</u>**

| Port  | Rule                      | Source                          | Destination          | Protocol  | Production Mode | Maintenance Mode |
|-------|---------------------------|---------------------------------|----------------------|-----------|-----------------|------------------|
| 8080  | Input + Output            | SSH Registration                | Host                 | TCP       | DISABLED        | ENABLED          |
| 22    | Input                     | Control Plane: Dropbear SSH     | Host                 | TCP       | ENABLED         | ENABLED          |
| 10022 | Input                     | Data Plane: Open SSH            | Podman               | TCP       | DISABLED        | ENABLED          |
| 27017 | Input                     | Searcher Input Channel          | Podman               | UDP       | ENABLED         | ENABLED          |
| 30303 | Input + Output            | Execution Client P2P            | Podman               | TCP + UDP | DISABLED        | ENABLED          |
| 9000  | Input + Output            | Consensus Client P2P            | Podman               | TCP + UDP | ENABLED         | ENABLED          |
| 443   | Output **IP WHITELISTED** | Flashbots Protect Tx Stream     | Podman               | TCP       | ENABLED         | DISABLED         |
| 443   | Output **IP WHITELISTED** | BuilderNet State Diff Stream + Bundle RPC | BuilderNet RPC | TCP   | ENABLED         | DISABLED         |
| 443   | Output **IP WHITELISTED** | Flashbots Bundle RPC            | Flashbots Bundle RPC | TCP       | ENABLED         | ENABLED          |
| 53    | Output                    | DNS                             | DNS                  | TCP + UDP | DISABLED        | ENABLED          |
| 80    | Output                    | HTTP                            | HTTP                 | TCP       | DISABLED        | ENABLED          |
| 443   | Output                    | HTTPS                           | HTTPS                | TCP       | DISABLED        | ENABLED          |
| 8745  | Input                     | attested-tls-proxy              | Host                 | TCP       | ENABLED         | ENABLED          |
| 123   | Output                    | NTP                             | Host                 | UDP       | ENABLED         | ENABLED          |

**<u>Searcher Network Namespace iptables</u>**

In production mode, all outgoing connections are IP whitelisted to builders except port 9000, which is necessary for the CL client p2p to stay in sync with the network, and port 123, which is necessary to maintain time synchronization.

But, we don’t want the searcher container to be able to send state diff information out through the open ports on the host, so we block this at the searcher network namespace with iptables.

```
iptables -A OUTPUT -p tcp --dport 9000 -j DROP
iptables -A OUTPUT -p udp --dport 9000 -j DROP
iptables -A OUTPUT -p udp --dport 123 -j DROP
```

**<u>ipv6</u>**

iptables only covers ipv4. For security purposes, we block ipv6 with a kernel flag!

Machine Specs and Cost
------------------------

We deploy GCP [Confidential VMs](https://cloud.google.com/confidential-computing/confidential-vm/docs/confidential-vm-overview) on the **c3-standard** machine series (Intel Sapphire Rapids) with Intel TDX support, in **`us-east4` (Northern Virginia)** to colocate with builders. Lighthouse (consensus) runs on the host, while the searcher runs their own execution client (modified Geth or Reth) and bot inside the container.

In the future, we hope to add bare metal support, which will lower this cost dramatically.

**<u>Machine</u>** (base price, VM only)

`c3-standard-22` is the minimum recommended size.

| Name           | vCPU | Mem (GB) | Price (USD/mo) |
|----------------|------|----------|----------------|
| c3-standard-8  | 8    | 32       | ~$294          |
| c3-standard-22 | 22   | 88       | ~$810          |
| c3-standard-44 | 44   | 176      | ~$1,619        |
| c3-standard-88 | 88   | 352      | ~$3,239        |

**<u>Disk</u>** (price per TB / month, billed on top of the machine)

| Type        | Price (USD/TB) | Per GB    |
|-------------|----------------|-----------|
| pd-balanced | ~$110          | ~$0.11/GB |
| pd-ssd      | ~$190          | ~$0.19/GB |

Total monthly cost is machine + disk — e.g. a `c3-standard-22` with 4 TB pd-balanced ≈ $810 + $440 = **~$1,250/mo**.

**<u>Egress</u>**

Networking/egress and the TDX premium are excluded from the estimates above for now.

Attestation Walkthrough
------------------------

Once searchers receive the IP for their TDX Machine deployed by Flashbots, they should first perform the process of attestation.

*At a high level, searchers will audit the minimal VM image prepared by Flashbots does not introduce malicious code and contains the right SSH configuration. Builders will audit the firewall rules and log delay. Then they will confirm that exact image is running on the TDX VM Flashbots deployed by “measuring” the image (by hashing its files) and comparing their local measurement to that measured by GCP.*

### 1. build the VM image

Searchers will need to build the image locally in order to produce the measurement in step 3, which will take around 30 minutes depending on hardware. Searchers will need Nix and a few other [prerequisites](https://github.com/flashbots/flashbots-images/tree/main?tab=readme-ov-file#prerequisites).

```bash
umask 0022
git clone https://github.com/flashbots/flashbots-images.git
cd flashbots-images

# build the Flashbox (TEE searcher sandbox) image
make build IMAGE=flashbox-l1
```

### 2. audit the VM image

There are two key components for searchers to verify: the privacy of their code on the machine (through understanding SSH access) and the privacy of their data on the attached disk (through understanding disk encryption).

**<u>Searcher SSH Key Storage and Authorization Process</u>**

*Overview*: On the first boot, the `tdx-init` program waits for a searcher SSH key, then stores it locally and embeds it in the LUKS header of the encrypted disk for persistence. On subsequent boots, the key is extracted from LUKS and placed in the `authorized_keys` file of both the Dropbear SSH server on the host (control plane) and OpenSSH server in the container (data plane).

1. **Initial Key Input**

The VM boots and runs `wait-for-key.service` which executes [`tdx-init waitForKey()`](https://github.com/flashbots/tdx-init/blob/c357e1b5d9bc386c3446e87bddb6dd53ac01ea97/keys.go#L42). This listens on HTTP port 8080 for POST requests containing the searcher's ed25519 public key, which is inputted by Flashbots after machine deployment. It then stores the key in two locations:
  - [`/home/searcher/.ssh/authorized_keys`](https://github.com/flashbots/tdx-init/blob/c357e1b5d9bc386c3446e87bddb6dd53ac01ea97/keys.go#L85) for Dropbear
  - [`/etc/searcher_key`](https://github.com/flashbots/tdx-init/blob/c357e1b5d9bc386c3446e87bddb6dd53ac01ea97/keys.go#L103) for OpenSSH

Critically, `tdx-init` enforces that the SSH key can only be provided once, and [only one key](https://github.com/flashbots/tdx-init/blob/c357e1b5d9bc386c3446e87bddb6dd53ac01ea97/keys.go#L61) can be provided. So if a searcher can successfully SSH into the machine, they can be confident that only their SSH key can be used to access and control the machine.

2. **Dropbear SSH Configuration** (Host SSH Access)

Dropbear is installed as a [base system package](https://github.com/flashbots/flashbots-images/blob/main/modules/flashbox/common/mkosi.conf#L12) during the image build process.

The standard default location for Dropbear to look for `authorized_keys` is in the user's home directory under the .ssh subdirectory ([~/.ssh/authorized_keys](https://linux.die.net/man/8/dropbear)). The `authorized_keys` file and its containing ~/.ssh directory must only be writable by the user, otherwise Dropbear will not allow a login using public key authentication.

On each startup, `tdx-init` retrieves the SSH key from the LUKS header, writes it to [`/home/searcher/.ssh/authorized_keys`](https://github.com/flashbots/tdx-init/blob/c357e1b5d9bc386c3446e87bddb6dd53ac01ea97/keys.go#L85), and ensures the directory is owned by the searcher user.

Note: The image overrides the default configuration with [extra security flags](https://github.com/flashbots/flashbots-images/blob/main/modules/flashbox/common/mkosi.extra/etc/default/dropbear). Systemd's [drop-in configuration mechanism](https://github.com/flashbots/flashbots-images/blob/main/modules/flashbox/common/mkosi.extra/etc/systemd/system/dropbear.service.d/dropbear-prereq.conf) is also used to ensure dropbear runs after `wait-for-key.service`, sets proper ownership of the .ssh files, and generates the dropbear host key if it doesn't exist.

3. **OpenSSH Authorization** (Container SSH Access)

On each startup, `tdx-init` retrieves the SSH key from the LUKS header, and writes it to
[`/etc/searcher_key`](https://github.com/flashbots/tdx-init/blob/c357e1b5d9bc386c3446e87bddb6dd53ac01ea97/keys.go#L103).

During container startup, OpenSSH is installed and the SSH key is copied from `etc/searcher_key` to [`/root/.ssh/authorized_keys`](https://github.com/flashbots/flashbots-images/blob/main/modules/flashbox/common/mkosi.extra/usr/bin/init-container.sh#L30) with the correct permissions.

**<u>Searcher Disk Encryption</u>**

On the first startup, after the searcher's SSH key is received and stored, the searcher must SSH into the machine and run the `initialize` command to encrypt their disk. Before this first SSH, complete the [Attestation Walkthrough](#attestation-walkthrough) and bind the host key served at `/pubkey` — the attested channel is up at boot, so this initial connection is verified rather than trust-on-first-use.

`Tdx-init` prompts the searcher for a passphrase via stdin, [formats]((https://github.com/flashbots/tdx-init/blob/c357e1b5d9bc386c3446e87bddb6dd53ac01ea97/passphrase.go#L43)) the disk with LUKS2 encryption using this passphrase, and [embeds]((https://github.com/flashbots/tdx-init/blob/c357e1b5d9bc386c3446e87bddb6dd53ac01ea97/passphrase.go#L77)) the searcher's SSH key as metadata in the LUKS header.

**This design ensures that only the searcher whose SSH key initialized the disk can decrypt it across image reboots.**

### 2. audit and run the local measurement and remote attestation software

In order to leverage attestation, Flashbots:
1. uses MKOSI to ensure reproducible builds, such that each time anyone builds the image, the measurement will be the same, even on different hardware
2. packages the entire image inside the initramfs, such that any change to the image will result in a different measurement

Instructions for measuring OS images and checking they match remote attestation from the deployment are on the [Flashbox documentation site](https://flashbox.flashbots.dev/build-and-attest).

Order Flow APIs
------------------------

### Searching on Flashbots Protect Transactions

All Flashbots Protect transactions with [fast mode](https://docs.flashbots.net/flashbots-protect/settings-guide#fast) enabled will be shared with TEE searchers.

Flashbots Protect transactions will be shared using the [`full` hint](https://docs.flashbots.net/flashbots-protect/settings-guide#hints), which shares all fields of individual pending transactions except for the signature (missing `v`, `r`, and `s` fields).

The MEV-Share Order Flow Auction uses the [`mev_sendBundle` format](https://docs.flashbots.net/flashbots-auction/advanced/rpc-endpoint#mev_sendbundle) for bundle submission.

For more information, please visit the [Flashbots Protect and MEV-Share Order Flow Auction documentation](https://docs.flashbots.net/flashbots-mev-share/introduction), which has instructions and libraries for subscribing to Flashbots Protect Transactions and submitting backrun bundles.

To subscribe to transactions, connect to the server:
```
https://tx.tee-searcher.flashbots.net
```

To submit bundles, connect to the server:
```
https://backruns.tee-searcher.flashbots.net
```

### Searching on BuilderNet's Bottom of Block

BuilderNet serves both the state diff stream and bundle submission over the same HTTPS endpoint (`rpc.buildernet.org`). Because they share one endpoint, both are reachable only in **production mode** — unlike the Flashbots bundle RPC, which is always on.

**<u>Subscribing to BuilderNet's State Diff Stream</u>**

**Connecting**

Connect to the server located at:
```
wss://rpc.buildernet.org/bob
```

Use the `eth_subscribe` method to subscribe to state diffs:

```json
{"method":"eth_subscribe","params":["flashbots_stateDiffs"]}
```

**Response**

```json
{
  "jsonrpc": "2.0",
  "result": "whzoOReHirSJxxF8Z0bqvbghmXjD3hWRW0",
  "id": 1
}
```

You'll start receiving state diffs:

```
{
  "jsonrpc": "2.0",
  "method": "eth_subscription",
  "params": {
    "subscription": "whzoOReHirSJxxF8Z0bqvbghmXjD3hWRW0",
    "result": {
      "blockNumber": "String",  // hex encoded block number the block builder is currently building for
      "blockTimestamp": "String",  // hex encoded seconds since the unix epoch
      "blockUuid": "String",  // a UUID V4 that is used to identify the current block being streamed
      "stateOverrides": "Object" {  // a nested object of changed addresses to changed storage slot keys and their updated value
        "address": {
          "balance": "String"
          "code": "String"  // ONLY IF CONTRACT IS DEPLOYED IN THIS BLOCK
          "nonce": "String"
          "stateDiff": {
            "<storage slot>": "String"
          }
        }
      }
    }
  }
}
```
<details>
<summary>Example Output</summary>

    ```json
    2024-12-03 23:46:27,370 - __main__ - INFO - Initializing WebSocket connection to ws://127.0.0.1:8547
    2024-12-03 23:46:27,375 - __main__ - INFO - Subscribed to state diffs
    2024-12-03 23:46:27,377 - __main__ - INFO - Subscription response: {"jsonrpc":"2.0","result":"aYF2ehyZ8I4fz3rxkkRiOxtnfFqWosI9HC","id":1}
    2024-12-03 23:46:33,108 - __main__ - INFO - Parsed state diff: {
      "jsonrpc": "2.0",
      "method": "eth_subscription",
      "params": {
        "subscription": "aYF2ehyZ8I4fz3rxkkRiOxtnfFqWosI9HC",
        "result": {
          "blockNumber": "0x1456624",
          "blockTimestamp": "0x674f985b",
          "blockUuid": "b3041804-c0ff-4628-9581-29910f78593e",
          "stateOverrides": {
            "0x0000000000a39bb272e79075ade125fd351887ac": {
              "balance": "0x35c9406dfc78d4448d9",
              "nonce": "0x1",
              "stateDiff": {
                "0xffc5f4bf805d0f20d7ba2d180bf4492e98716db6def51fb60972294b5ba556cf": "0x0000000000000000000000000000000000000000000000000905438e60010000"
              }
            },
            "0x111111111117dc0aa78b770fa6a738034120c302": {
              "stateDiff": {
                "0xc0ec8fbf02d70b2873f5a76f503e97bd1b0ca8048ab517fad231214a74ebe459": "0x0000000000000000000000000000000000000000000ebc80f5e0cbee39cca338",
                "0xcb4547a880ed764ae6e3838e74f0795915d3b91357e4852c97ce6e0cdcf6c023": "0x0000000000000000000000000000000000000000000000000000000000000000"
              }
            },
            "0x1a44076050125825900e736c501f859c50fe728c": {
              "stateDiff": {
                "0xe988aa870f58bb597aadbc090e6f5508b7e93c0ad1d3effac7f5825387d9975e": "0x05626211c42f691c213286fd1cc93859d96b1e96d1e919cd2738013a25857823"
              }
            },
            "0x9355d11cb5c6e8a301d131c5ee1c7fdc032dbb9a": {
              "balance": "0x0",
              "code": "0x363d3d373d3d3d363d735397d0869aba0d55e96d5716d383f6e1d8695ed75af43d82803e903d91602b57fd5bf3000000000000000000000000000000000000000000000000000000000000000000",
              "nonce": "0x1",
              "stateDiff": {
                "0x0000000000000000000000000000000000000000000000000000000000000000": "0x000000000000000000000101679fb19dec9d66c34450a8563ffdfd29c04e615a"
              }
            }
          }
        }
      }
    }
    ```
</details>


**<u>Sending Bottom of Block Bundles to BuilderNet RPC</u>**

Connect to the server located at:
```
https://rpc.buildernet.org
```

Use the `eth_sendBobBundle` method to submit bundles:

```
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "eth_sendBobBundle",
  "params": [
    { // regular eth_sendBundle fields
      txs,
      blockNumber,
    },
    targetUuid, // String, block UUID that this bundle is targeting eg 123e4567-e89b-12d3-a456-426614174000
    targetPools // Array[String], A list of pool addresses that this bundle is targeting
  ]
}
```

Note: `targetUuid` and `targetPools` are currently accepted but ignored by BuilderNet. When support for them is added, their placement in the request may differ from what is shown above.

Disk Persistence
------------------------

This universal, Mkosi-based version implements additional capabilities which allow searchers to persist data across restarts and version upgrades without sacrificing data privacy and integrity.
When the image boots up, it will open an HTTP server at port 8080 and wait for the searcher's ed25519 public key to be submitted by the TDX Operator, Flashbots. For example, Flashbots will POST the key to the forwarded port like so:

```
ubuntu@ns5018742:~/Angela/bobgela/keys$ curl -X POST -d "AAAAC3NzaC1lZDI1NTE5AAAAIMPdKdQZip5rYQAhuKTbhI09HM9aFSU/erbUWXb4i4nR" http://localhost:8080
```

This step is done only once, when the persistent disk has not yet been initialized.

Then, using the dropbear SSH port, searchers initialize or decrypt an existing disk by running the "initialize" command. (This step is necessary on each boot.) On the first boot, this will prompt the searcher for a password via stdin. When searchers initialize a disk, it will store the previously supplied public key in plaintext inside of the LUKS header so it can be retrieved automatically on subsequent boots.

```
ssh -i /path/to/.ssh/id_ed25519 searcher@<machine IP> initialize
```

Searcher Commands and Services
---
On the first login after deployment or image upgrade, remember to initialize and decrypt the persistent disk.
```
ssh -i /path/to/.ssh/id_ed25519 searcher@<machine IP> initialize
```

The control plane is served on port 22, where searchers can switch modes, check status, and print logs during production mode.

```bash
# switch mode
ssh searcher@<machine ip> toggle

# what mode is it in?
ssh searcher@<machine ip> status

# print out last 100 logs from today
ssh searcher@<machine ip> logs 100

# tail the logs
ssh searcher@<machine ip> tail-the-logs

# restart lighthouse on the host
ssh searcher@<machine ip> restart-lighthouse

# reboot the host virtual machine. Optional: --force
ssh searcher@<machine ip> reboot [--force] 
```

The data plane is served on port 10022, where searchers can SSH inside their rootless podman container to configure their bot.

```bash
# ssh inside podman container
ssh -p 10022 root@<machine IP>

# write logs to this file for log output service to pick up
/var/log/searcher/bob.log

# configure EL to use this shared mount to communicate with lighthouse on the host
/secrets/jwt.hex

# disk
/persistent

# working geth config
geth --datadir /persistent \
  --authrpc.jwtsecret /secrets/jwt.hex \
  --authrpc.port 8551 \
  --authrpc.addr 0.0.0.0 \ # important!
  --http \
  --ws \
  --http.api eth,web3,net,txpool,admin \
  --ws.api eth,web3,net,txpool,admin \
  --syncmode snap \

# view lighthouse logs
tail -f /var/log/lighthouse/beacon.log
```

### **lighthouse**

Lighthouse is run on the host with the following configuration:

```bash
--network mainnet \
--execution-endpoint http://localhost:8551 \
--execution-jwt /tmp/jwt.hex \
--checkpoint-sync-url https://mainnet.checkpoint.sigp.io \
--disable-deposit-contract-sync \
--datadir "/persistent/lighthouse" \
--disable-optimistic-finalized-sync \
--disable-quic
```

### **logrotate**

The image is configured to automatically delete logs that are more than 5 days old to limit resource usage. How it works:

- Any file ending in `.log` in `/var/log/searcher/` (which maps to `/persistent/searcher_logs/` on the host) will be rotated daily. Log files are truncated and compressed copies are kept for 5 days.

    ```bash
    root@6d9ced6e8a16:~# ls /var/log/searcher
    bob.log  bob.log-20250127.gz
    ```

- The delayed log file (`/persistent/delayed_logs/output.log`) that searchers read via SSH commands is also rotated daily, meaning you can only see logs from the current day when accessing them externally.

Developer Notes
-------------

### Service Order

1. Initialize network via `systemd-networkd.service`
2. Get searcher key from LUKS partition or wait for key on port 8080 (**name:** `wait-for-key.service`) (**after:** `network-online.target`)
3. Setup firewall (**name:** `searcher-firewall.service`) (**after:** `network-online.target`)
4. Start dropbear server for `initialize`, `toggle`, etc. (**name:** `dropbear.service`) (**after:** `wait-for-key.service`, `searcher-firewall.service`)
5. Open a log socket and forward text from it to the delayed log file after 300s (**name:** searcher-log-reader.service) (**after:** `/persistent` is mounted)
6. Write new text in `bob.log` to the log socket (**name:** searcher-log-writer.service) (**after:** searcher-log-reader.service)
7. Lighthouse (**name:** `lighthouse.service`) (**after:** `/persistent` is mounted)
8. Start the podman container (**name:** `searcher-container.service`) (**after:** `dropbear.service`, `lighthouse.service`, `searcher-firewall.service`, `/persistent` is mounted)
9. SSH pubkey server (**name:** `ssh-pubkey-server.service`) (**after:** `dropbear.service`) — starts at boot and no longer waits for `searcher-container.service`, so `/pubkey` serves the host (dropbear) key before disk init. The container key is served by `/pubkey` lazily once the container writes it.
10. Attested TLS proxy for SSH pubkey server (**name:** `attested-tls-proxy.service`) (**after:** `ssh-pubkey-server.service`) — consequently the attested `:8745` channel is also available at boot, before the searcher's first SSH.

### Testing

```shell
ssh-keygen -t ed25519
curl -X POST -d "$(cut -d" " -f2 /root/.ssh/id_ed25519.pub)" http://localhost:8080
sleep 1
# start here if recovering existing persistent disk (assumes searcher key is in /root/.ssh)
ssh -4 -i /root/.ssh/id_ed25519 searcher@127.0.0.1 initialize
journalctl -fu searcher-container
ssh -4 -i /root/.ssh/id_ed25519 -p 10022 root@127.0.0.1
ssh -4 -i /root/.ssh/id_ed25519 searcher@127.0.0.1 toggle
```

### Security

Flashbots may temporarily pause orderflow to a TEE searcher instance if we identify a security issue that may affect the host configuration or running instance. This is a precautionary measure while we investigate, assess impact, and prepare mitigations, and does not necessarily mean that the searcher instance, data, or credentials were compromised. During a pause, transaction streaming may be disabled and login access may be unavailable until the instance is remediated or migrated to an updated image. Once remediation is complete, Flashbots will share next steps for restoring access and safely resuming order flow.
