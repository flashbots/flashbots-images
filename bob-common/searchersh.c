#include <stdio.h>      // For fprintf, perror
#include <stdlib.h>     // For exit, malloc/free, strdup, atoi
#include <string.h>     // For strcmp, strtok
#include <unistd.h>     // For execl
#include <ctype.h>      // For isdigit
#include <sys/stat.h>   // For stat

#define MAX_LINES 10000000

// Check if initialization is complete (persistent is mounted)
int is_initialized() {
    struct stat st_mount, st_parent;
    
    if (stat("/persistent", &st_mount) != 0) {
        return 0;
    }
    
    if (stat("/persistent/..", &st_parent) != 0) {
        return 0;
    }
    
    // Different device IDs mean it's a mount point
    return (st_mount.st_dev != st_parent.st_dev);
}

// argc is the number of command-line arguments
// argv is an array of C-strings (character pointers)
int main(int argc, char *argv[]) {

    // We expect exactly 3 arguments: 
    // Example: ssh -i ~/.ssh/yocto-searcher -p 8084 searcher@localhost hello 5
    // argv[0] = 'searchersh'
    // argv[1] = '-c'
    // argv[2] = 'hello 5'

    if (argc != 3) {
        fprintf(stderr, "Invalid number of arguments\n");
        return 1; // return error code 1
    }

    // Verify argv[0] is "searchersh"
    if (strcmp(argv[0], "searchersh") != 0) {
        fprintf(stderr, "Error: This program must be invoked as 'searchersh'\n");
        return 1;
    }

    // Verify argv[1] is "-c"
    if (strcmp(argv[1], "-c") != 0) {
        fprintf(stderr, "Error: Second argument must be '-c'\n");
        return 1;
    }

    // Make a copy of argv[2], because strtok will modify the string
    // strdup() allocates memory and copies the entire string.
    // We must free() this memory later.
    char *arg_copy = strdup(argv[2]);
    if (!arg_copy) {
        perror("strdup failed"); 
        return 1; // return error code 1
    }

    // Use strtok() to split the string in arg_copy by spaces (" ")
    // strtok modifies the string by inserting '\0' to separate tokens.
    // 'command' will point to the first token, if it exists.
    char *command = strtok(arg_copy, " ");
    if (command == NULL) {
        // If there's no token at all (e.g., empty or whitespace-only string),
        // we print an error and quit.
        fprintf(stderr, "No command provided. Valid commands are: toggle, status, logs, tail-the-logs, restart-lighthouse, initialize\n");
        free(arg_copy); // free the memory
        return 1;       // return error code 1
    }

    // If the first token (command) is not NULL, we try to get the next token
    // 'arg' is needed when the command is "logs <number_of_lines>"
    // e.g., if argv[2] = "logs 3", then:
    //   command = "logs"
    //   arg     = "3"
    char *arg = strtok(NULL, " ");

    // If command == "initialize", run the tdx-init program with set-passphrase command
    if (strcmp(command, "initialize") == 0) {
        execl("/usr/bin/sudo", "sudo", "/usr/bin/tdx-init", "set-passphrase", NULL);
        
        perror("execl failed (initialize)");
        free(arg_copy);
        return 1;
    }
    
    // Check if system is initialized before allowing other commands
    if (!is_initialized()) {
        fprintf(stderr, "System not initialized. Please run 'initialize' command first.\n");
        free(arg_copy);
        return 1;
    }

    // Compare the first token to see which command we want.
    // 1) "toggle"
    // 2) "status"
    // 3) "logs"
    // 4) "restart-lighthouse"
    // Anything else -> invalid.
    
    // If command == "toggle", call /usr/bin/toggle via sudo
    if (strcmp(command, "toggle") == 0) {
        // execl() replaces the current process with the new program
        // Arguments to execl:
        //   1) path to executable: "/usr/bin/sudo"
        //   2) argv[0] for new program: "sudo"
        //   3) "-S" accept password from stdin
        //   4) "/usr/bin/toggle" (the program we actually want to run via sudo)
        //   5) NULL terminator for argument list
        // execl("/usr/bin/sudo", "sudo", "-S", "/usr/bin/toggle", NULL);
        execl("/usr/bin/sudo", "sudo", "/usr/bin/toggle", NULL);
        
        // If execl fails, we reach here. perror prints error details.
        perror("execl failed (toggle)");
        
        // We must free the copied string before exiting
        free(arg_copy);
        return 1;
    }

    // If command == "status", print the contents of /etc/searcher-network.state
    else if (strcmp(command, "status") == 0) {
        // runs: cat /etc/searcher-network.state
        execl("/bin/cat", "cat", "/etc/searcher-network.state", NULL);
        
        perror("execl failed (status)");
        free(arg_copy);
        return 1;
    }

    // If command == "tail-the-logs", print the contents of /persistent/delayed_logs/output.log
    else if (strcmp(command, "tail-the-logs") == 0) {
        execl("/usr/bin/tail", "tail", "-f", "/persistent/delayed_logs/output.log", NULL);
        perror("execl failed (tail-the-logs)");
        free(arg_copy);
        return 1;
    }

    // If command == "logs", we expect a second token representing number of lines
    else if (strcmp(command, "logs") == 0) {
        // If no second token, user didn't specify how many lines
        if (arg == NULL) {
            fprintf(stderr, "Usage: logs <number_of_lines>\n");
            free(arg_copy);
            return 1; // return error code 1
        }

        // 1) Check that 'arg' is strictly numeric
        for (int i = 0; arg[i] != '\0'; i++) {
            if (!isdigit((unsigned char)arg[i])) {
                fprintf(stderr, "Invalid line count (non-digit characters detected): %s\n", arg);
                free(arg_copy);
                return 1;
            }
        }

        // 2) Convert to int
        int lines = atoi(arg);

        // 3) Check the range
        if (lines < 1 || lines > MAX_LINES) {
            fprintf(stderr, "Number of lines must be between 1 and %d\n", MAX_LINES);
            free(arg_copy);
            return 1;
        }

        // Call tail with the specified number of lines, e.g.:
        // tail -n <arg> /persistent/delayed_logs/output.log
        // If arg = "3", that's tail -n 3 /persistent/delayed_logs/output.log
        execl("/usr/bin/tail", "tail", "-n", arg, "/persistent/delayed_logs/output.log", (char *)NULL);
        
        perror("execl failed (logs)");
        free(arg_copy);
        return 1; // return error code 1
    }

    // If command == "restart-lighthouse", restart the lighthouse systemd service
    else if (strcmp(command, "restart-lighthouse") == 0) {
        execl("/usr/bin/sudo", "sudo", "/usr/bin/systemctl", "restart", "lighthouse", NULL);
        
        perror("execl failed (restart-lighthouse)");
        free(arg_copy);
        return 1;
    }

    // If we reach here, the command didn't match any of the valid commands
    fprintf(stderr, "Invalid command. Valid commands are: toggle, status, logs, tail-the-logs, restart-lighthouse, initialize\n");
    free(arg_copy); // Clean up allocated memory
    return 1;       // Return error code 1
}
