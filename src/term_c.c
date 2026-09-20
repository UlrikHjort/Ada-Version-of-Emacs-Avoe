/* ***************************************************************************
 *                               Avoe - term_c
 *
 *           Copyright (C) 2026 By Ulrik Hørlyk Hjort
 *
 * Permission is hereby granted, free of charge, to any person obtaining
 * a copy of this software and associated documentation files (the
 * "Software"), to deal in the Software without restriction, including
 * without limitation the rights to use, copy, modify, merge, publish,
 * distribute, sublicense, and/or sell copies of the Software, and to
 * permit persons to whom the Software is furnished to do so, subject to
 * the following conditions:
 *
 * The above copyright notice and this permission notice shall be
 * included in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 * NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
 * LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
 * OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
 * WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 *************************************************************************** */

/* Thin POSIX terminal helpers for Avoe.  Everything else lives in Ada. */

#define _DEFAULT_SOURCE

#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <sys/wait.h>
#include <signal.h>
#include <string.h>
#include <sys/ioctl.h>
#include <termios.h>
#include <unistd.h>

static struct termios orig_termios;
static int raw_enabled = 0;
static volatile sig_atomic_t resized_flag = 0;

static void on_winch (int sig) {
  (void) sig;
  resized_flag = 1;
}

int avoe_term_raw_on (void) {
  struct termios raw;

  if (!isatty (0) || !isatty (1))
    return -1;
  if (tcgetattr (0, &orig_termios) < 0)
    return -1;

  raw = orig_termios;
  raw.c_iflag &= ~(BRKINT | ICRNL | INPCK | ISTRIP | IXON);
  raw.c_oflag &= ~(OPOST);
  raw.c_cflag |= CS8;
  raw.c_lflag &= ~(ECHO | ICANON | IEXTEN | ISIG);
  raw.c_cc[VMIN] = 1;
  raw.c_cc[VTIME] = 0;

  if (tcsetattr (0, TCSAFLUSH, &raw) < 0)
    return -1;
  raw_enabled = 1;
  return 0;
}

void avoe_term_raw_off (void) {
  if (raw_enabled) {
    tcsetattr (0, TCSAFLUSH, &orig_termios);
    raw_enabled = 0;
  }
}

void avoe_term_install_winch (void) {
  struct sigaction sa;

  memset (&sa, 0, sizeof sa);
  sa.sa_handler = on_winch;
  sigemptyset (&sa.sa_mask);
  sa.sa_flags = 0; /* no SA_RESTART: poll() must see EINTR */
  sigaction (SIGWINCH, &sa, NULL);
}

void avoe_term_size (int *rows, int *cols) {
  struct winsize ws;

  if (ioctl (1, TIOCGWINSZ, &ws) < 0 || ws.ws_col == 0 || ws.ws_row == 0) {
    *rows = 24;
    *cols = 80;
  } else {
    *rows = ws.ws_row;
    *cols = ws.ws_col;
  }
}

/* Returns a byte 0..255, -1 on timeout, -2 when interrupted by a signal
   (or a resize is pending), -3 on end of input or a read error.
   A negative timeout blocks indefinitely. */
int avoe_term_read_byte (int timeout_ms) {
  struct pollfd pfd;
  unsigned char c;
  int r;

  if (resized_flag)
    return -2;

  pfd.fd = 0;
  pfd.events = POLLIN;
  pfd.revents = 0;

  r = poll (&pfd, 1, timeout_ms);
  if (r < 0)
    return errno == EINTR ? -2 : -3;
  if (r == 0)
    return -1;

  r = (int) read (0, &c, 1);
  if (r == 1)
    return c;
  if (r < 0 && errno == EINTR)
    return -2;
  return -3;
}

int avoe_term_take_resized (void) {
  int r = resized_flag;
  resized_flag = 0;
  return r;
}

int avoe_term_input_pending (void) {
  struct pollfd pfd;

  pfd.fd = 0;
  pfd.events = POLLIN;
  pfd.revents = 0;
  return poll (&pfd, 1, 0) > 0;
}

int avoe_term_write (const char *buf, int len) {
  int done = 0;

  while (done < len) {
    ssize_t n = write (1, buf + done, (size_t) (len - done));
    if (n < 0) {
      if (errno == EINTR)
        continue;
      return -1;
    }
    done += (int) n;
  }
  return done;
}

void avoe_term_suspend (void) {
  avoe_term_raw_off ();
  kill (getpid (), SIGTSTP);
  avoe_term_raw_on ();
}

/* ---- Subprocesses (compile buffer) ---- */

/* Run "sh -c cmd" in dir with stdout and stderr connected to a
   non-blocking pipe.  *fd_out is -1 on failure. */
void avoe_spawn (const char *cmd, const char *dir, int *pid_out, int *fd_out) {
  int fds[2];
  pid_t pid;

  *pid_out = -1;
  *fd_out = -1;
  if (pipe (fds) < 0)
    return;

  pid = fork ();
  if (pid < 0) {
    close (fds[0]);
    close (fds[1]);
    return;
  }
  if (pid == 0) {
    int devnull = open ("/dev/null", O_RDONLY);
    if (devnull >= 0) {
      dup2 (devnull, 0);
      close (devnull);
    }
    dup2 (fds[1], 1);
    dup2 (fds[1], 2);
    close (fds[0]);
    close (fds[1]);
    setpgid (0, 0); /* own group, so the whole build can be killed */
    if (dir != NULL && *dir != '\0' && chdir (dir) < 0)
      _exit (127);
    execl ("/bin/sh", "sh", "-c", cmd, (char *) NULL);
    _exit (127);
  }

  setpgid (pid, pid);
  close (fds[1]);
  fcntl (fds[0], F_SETFL, O_NONBLOCK);
  *pid_out = pid;
  *fd_out = fds[0];
}

/* Wait for keyboard input (bit 0) or output on fd (bit 1).  0 on
   timeout, -1 when interrupted (e.g. by a resize).  fd may be -1. */
int avoe_poll_input (int fd, int timeout_ms) {
  struct pollfd p[2];
  int r, result = 0;

  if (resized_flag)
    return -1;
  p[0].fd = 0;
  p[0].events = POLLIN;
  p[0].revents = 0;
  p[1].fd = fd;
  p[1].events = POLLIN;
  p[1].revents = 0;

  r = poll (p, fd >= 0 ? 2 : 1, timeout_ms);
  if (r < 0)
    return -1;
  if (p[0].revents != 0)
    result |= 1;
  if (fd >= 0 && p[1].revents != 0)
    result |= 2;
  return result;
}

/* > 0: bytes read, 0: end of output, -1: nothing available now */
int avoe_read_fd (int fd, char *buf, int len) {
  ssize_t n = read (fd, buf, (size_t) len);
  if (n > 0)
    return (int) n;
  if (n == 0)
    return 0;
  if (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR)
    return -1;
  return 0;
}

/* Reap the process: its exit code, 128 + signal, or -1 */
int avoe_wait_process (int pid) {
  int status;
  while (waitpid (pid, &status, 0) < 0)
    if (errno != EINTR)
      return -1;
  if (WIFEXITED (status))
    return WEXITSTATUS (status);
  if (WIFSIGNALED (status))
    return 128 + WTERMSIG (status);
  return -1;
}

void avoe_kill_process (int pid) {
  kill (-pid, SIGTERM);
}

void avoe_close_fd (int fd) {
  close (fd);
}

/* Path of the running executable, or -1 */
int avoe_exe_path (char *buf, int len) {
  ssize_t n = readlink ("/proc/self/exe", buf, (size_t) len - 1);
  if (n < 0)
    return -1;
  buf[n] = '\0';
  return (int) n;
}

/* ---- Files ---- */

#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/stat.h>

/* stat PATH (following symlinks): 1 regular file, 2 something else, 0 missing */
int avoe_file_info (const char *path, long long *mtime_ns, long long *size, int *mode) {
  struct stat st;

  if (stat (path, &st) < 0)
    return 0;
  *mtime_ns = (long long) st.st_mtim.tv_sec * 1000000000LL + st.st_mtim.tv_nsec;
  *size = (long long) st.st_size;
  *mode = (int) (st.st_mode & 07777);
  return S_ISREG (st.st_mode) ? 1 : 2;
}

int avoe_chmod (const char *path, int mode) {
  return chmod (path, (mode_t) mode);
}

int avoe_rename (const char *from, const char *to) {
  return rename (from, to);
}

int avoe_unlink (const char *path) {
  return unlink (path);
}

int avoe_fsync_path (const char *path) {
  int r, fd = open (path, O_RDONLY);
  if (fd < 0)
    return -1;
  r = fsync (fd);
  close (fd);
  return r;
}

/* The canonical path (symlinks resolved) in buf; its length or -1 */
int avoe_realpath (const char *path, char *buf, int len) {
  char tmp[PATH_MAX];
  size_t n;

  if (realpath (path, tmp) == NULL)
    return -1;
  n = strlen (tmp);
  if ((int) n >= len)
    return -1;
  memcpy (buf, tmp, n + 1);
  return (int) n;
}

int avoe_mkdir (const char *path, int mode) {
  return (mkdir (path, (mode_t) mode) == 0 || errno == EEXIST) ? 0 : -1;
}
