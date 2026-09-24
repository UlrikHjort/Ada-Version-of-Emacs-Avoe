# Changelog

Versions follow [semantic versioning](https://semver.org): 1.x.y releases
stay compatible with your init file and scripts, y is for fixes, x for new
features.

## Unreleased

- Man page added.
- A build no longer formats the C sources (`AUTOFORMAT=no` by default), so it
  never changes the source tree; `make format` still does it on request.
- `make dist` makes a release tarball with its SHA-256, and `make distcheck`
  unpacks it elsewhere, builds it and runs a test.
- `GPRFLAGS` passes switches to gprbuild (a package build uses `-R`, which
  keeps library paths out of the binary).
- .github/workflows/ci.yml: build, test, install and distcheck on x86-64 and
  on arm64.

## 1.0.0 - 2026-09-20

The first release.

- **Editing:** Emacs keys, undo, kill ring, keyboard macros, M-/ word
  completion, comments, filling, bracket matching, case, transposing and
  paragraph commands.
- **Files and buffers:** multiple buffers and windows, safe saving, backups,
  auto-save with recovery, and detection of files changed by other programs.
- **Search:** incremental and regexp search, query replace.
- **Modes:** Ada, Avoe script, C, Python and shell, with highlighting and
  indentation. The C, Python and shell modes are written in Avoe script.
- **Tools:** background compile with error navigation, grep, shell commands
  and formatters.
- **Avoe script:** a lightweight Ada-flavoured extension language with
  vectors, records and exceptions.
- **Display:** Emacs-style line numbers, and a startup screen with version
  and key hints.
- **Settings:** confirm exit (yes or no), startup screen, backups, auto-save,
  line numbers.
- **Installation:** `make install` or `alr install`.
- **Documentation:** README with screenshots (made by `make screenshots`) and
  the limits of a buffer, a script reference, a man page and an example init
  file.
- **Tests:** 22 files driving the editor in a pseudo-terminal and in batch
  mode. They check data integrity (files survive loading and saving byte for
  byte, thousands of random edits and undo on large files are compared with a
  model, as is random keyboard editing in two windows), crash recovery,
  pasting into the terminal, and include repeatable script and key fuzzing.
- **Source:** the C helper is formatted with clang-format in K&R style
  (`.clang-format`, `make format`); a build formats it too when clang-format
  is installed (`make AUTOFORMAT=no` turns that off).
