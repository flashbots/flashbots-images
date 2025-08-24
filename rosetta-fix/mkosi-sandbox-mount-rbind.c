#include <errno.h>
#include <linux/fcntl.h>
#include <linux/mount.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/syscall.h>
#include <unistd.h>

static void die_with_error(const char *syscall_name, const char *path) {
  fprintf(stderr, "Error in %s for path '%s': %s\n", syscall_name, path,
          strerror(errno));
  exit(1);
}

/* Syscall wrappers */
static long sys_open_tree(int dfd, const char *pathname, unsigned int flags) {
  return syscall(SYS_open_tree, dfd, pathname, flags);
}

static long sys_mount_setattr(int dfd, const char *path, unsigned int flags,
                              struct mount_attr *attr, size_t size) {
  return syscall(SYS_mount_setattr, dfd, path, flags, attr, size);
}

static long sys_move_mount(int from_dfd, const char *from_pathname, int to_dfd,
                           const char *to_pathname, unsigned int flags) {
  return syscall(SYS_move_mount, from_dfd, from_pathname, to_dfd, to_pathname,
                 flags);
}

static void mount_rbind(const char *src, const char *dst, uint64_t attrs) {
  int fd;
  int r;
  unsigned int flags;

  flags =
      AT_NO_AUTOMOUNT | AT_RECURSIVE | AT_SYMLINK_NOFOLLOW | OPEN_TREE_CLONE;
  fd = sys_open_tree(AT_FDCWD, src, flags);
  if (fd < 0) {
    die_with_error("open_tree", src);
  }

  struct mount_attr attr = {0};
  attr.attr_set = attrs;
  flags = AT_EMPTY_PATH | AT_RECURSIVE;
  r = sys_mount_setattr(fd, "", flags, &attr, MOUNT_ATTR_SIZE_VER0);
  if (r < 0) {
    close(fd);
    die_with_error("mount_setattr", src);
  }

  r = sys_move_mount(fd, "", AT_FDCWD, dst, MOVE_MOUNT_F_EMPTY_PATH);
  if (r < 0) {
    close(fd);
    die_with_error("move_mount", dst);
  }

  close(fd);
}

static void usage(const char *progname) {
  fprintf(stderr, "Usage: %s <src> <dst> <attrs>\n", progname);
  fprintf(stderr, "  src:   source path to bind mount\n");
  fprintf(stderr, "  dst:   destination path for the mount\n");
  fprintf(stderr, "  attrs: mount attributes as integer\n");
  exit(1);
}

int main(int argc, char *argv[]) {
  if (argc != 4) {
    usage(argv[0]);
  }

  const char *src = argv[1];
  const char *dst = argv[2];
  char *endptr;
  uint64_t attrs = strtoull(argv[3], &endptr, 0);

  if (*endptr != '\0') {
    fprintf(stderr, "Error: attrs must be a valid integer\n");
    usage(argv[0]);
  }

  mount_rbind(src, dst, attrs);

  return 0;
}
