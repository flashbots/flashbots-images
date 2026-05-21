// cvm-shell: restricted login shell for the cvm-base operator account.
//
// The user logs in over SSH (with the pubkey delivered via tdx-init wait-for-key)
// and can only invoke a fixed set of commands:
//
//   initialize  -> sudo /usr/bin/tdx-init set-passphrase
//   status      -> /usr/local/bin/cvm-status.sh
//   reboot      -> sudo /sbin/reboot
//   help        -> print this list
//
// Modelled on flashbox's searchersh, but trimmed to commands that are
// meaningful for a generalized base CVM (no lighthouse, no input-cert, etc).
//
// SSH invokes a login shell as `cvm-shell -c "<argv>"` for non-interactive
// commands and as `cvm-shell` (no args) for interactive logins. The latter
// prints the help text and exits — there is intentionally no REPL.

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static int print_help(void) {
    fprintf(stderr,
        "cvm-shell -- restricted operator shell for cvm-base\n"
        "\n"
        "Valid commands:\n"
        "  initialize    Unlock and mount /persistent (LUKS bring-up via tdx-init)\n"
        "  status        Show /persistent mount, RTMR3 value, cvm-provisioner state\n"
        "  reboot        Reboot the CVM\n"
        "  help          Show this message\n");
    return 1;
}

int main(int argc, char *argv[]) {
    // Interactive login: print help and exit. No REPL by design.
    if (argc == 1) {
        return print_help();
    }
    if (argc != 3 || strcmp(argv[1], "-c") != 0) {
        fprintf(stderr, "Usage: cvm-shell -c <command>\n");
        return 1;
    }

    char *line = strdup(argv[2]);
    if (line == NULL) {
        perror("strdup");
        return 1;
    }

    // Only the first token is used; extra args are ignored (no command takes args today).
    char *cmd = strtok(line, " ");
    if (cmd == NULL) {
        free(line);
        return print_help();
    }

    if (strcmp(cmd, "initialize") == 0) {
        execl("/usr/bin/sudo", "sudo", "/usr/bin/tdx-init", "set-passphrase", (char *)NULL);
        perror("exec tdx-init");
        free(line);
        return 1;
    }
    if (strcmp(cmd, "status") == 0) {
        execl("/usr/local/bin/cvm-status.sh", "cvm-status.sh", (char *)NULL);
        perror("exec cvm-status.sh");
        free(line);
        return 1;
    }
    if (strcmp(cmd, "reboot") == 0) {
        execl("/usr/bin/sudo", "sudo", "/sbin/reboot", (char *)NULL);
        perror("exec reboot");
        free(line);
        return 1;
    }
    if (strcmp(cmd, "help") == 0) {
        free(line);
        return print_help();
    }

    fprintf(stderr, "Unknown command: %s\n", cmd);
    free(line);
    print_help();
    return 1;
}
