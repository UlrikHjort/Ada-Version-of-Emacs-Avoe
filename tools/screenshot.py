#!/usr/bin/env python3
"""Make the screenshots for the README, without opening a window.

avoe runs in a pseudo-terminal; what it prints is interpreted by pyte and
drawn to a PNG with PIL, so the pictures show the real colours and can be
made again after a change:

    python3 tools/screenshot.py

Needs python3-pyte, python3-pil and the DejaVu fonts.
"""

import os
import pty
import select
import struct
import sys
import termios
import fcntl
import tempfile
import time

import pyte
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
AVOE = os.path.join(ROOT, "bin", "avoe")
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"
BOLD = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf"
SIZE = 17
PAD = 14

BACKGROUND = "#161a1f"
FOREGROUND = "#d6dbe2"
PALETTE = {
    "black": "#20242b", "red": "#e2544a", "green": "#8cc265", "brown": "#d5a44b",
    "blue": "#5aa9e6", "magenta": "#c67ad6", "cyan": "#4fb8bf", "white": "#d6dbe2",
}
BRIGHT = {
    "black": "#5a626f", "red": "#ff6b61", "green": "#a5e075", "brown": "#f0c674",
    "blue": "#77c2ff", "magenta": "#e08bf0", "cyan": "#63d8df", "white": "#f2f5f8",
}

DEMO = '''--  A short Ada example, to show highlighting and indentation.

with Ada.Text_IO; use Ada.Text_IO;

procedure Greet (Times : Positive := 3) is

   Greeting : constant String := "Hello from avoe!";
   Count    : Natural := 0;

begin
   for I in 1 .. Times loop
      if I mod 2 = 0 then
         Put_Line (Integer'Image (I) & ": " & Greeting);
      else
         Put_Line ("  odd turn, skipping");
      end if;
      Count := Count + 1;
   end loop;

   Put_Line ("Done after" & Natural'Image (Count) & " turns.");
end Greet;
'''


def capture(args, keys, rows=24, cols=84, splash=False, env=None, cwd=None):
    """Run avoe, type keys, and return the screen as pyte cells."""
    screen = pyte.Screen(cols, rows)
    stream = pyte.Stream(screen)
    env = dict(env or os.environ, TERM="xterm-256color", LANG="C.UTF-8")
    pid, fd = pty.fork()
    if pid == 0:
        if cwd:
            os.chdir(cwd)
        os.execve(AVOE, [AVOE] + ([] if splash else ["--no-splash"]) + list(args), env)
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))

    def pump(seconds):
        end = time.time() + seconds
        while time.time() < end:
            r, _, _ = select.select([fd], [], [], 0.02)
            if r:
                try:
                    data = os.read(fd, 65536)
                except OSError:
                    return
                stream.feed(data.decode("utf-8", "replace"))

    pump(0.4)
    for k in keys:
        os.write(fd, k)
        pump(0.15)
    pump(0.3)
    os.kill(pid, 9)
    os.waitpid(pid, 0)
    return screen


def render(screen, out_path):
    font = ImageFont.truetype(FONT, SIZE)
    bold = ImageFont.truetype(BOLD, SIZE)
    cw = int(font.getlength("M"))
    ch = SIZE + 6
    rows, cols = screen.lines, screen.columns
    image = Image.new("RGB", (cols * cw + 2 * PAD, rows * ch + 2 * PAD), BACKGROUND)
    draw = ImageDraw.Draw(image)

    for y in range(rows):
        for x in range(cols):
            cell = screen.buffer[y][x]
            fg = PALETTE.get(cell.fg, FOREGROUND) if cell.fg != "default" else FOREGROUND
            bg = PALETTE.get(cell.bg, BACKGROUND) if cell.bg != "default" else BACKGROUND
            if cell.bold and cell.fg != "default":
                fg = BRIGHT.get(cell.fg, fg)
            if cell.reverse:
                fg, bg = bg, fg
            px, py = PAD + x * cw, PAD + y * ch
            if bg != BACKGROUND:
                draw.rectangle([px, py, px + cw - 1, py + ch - 1], fill=bg)
            if cell.data.strip():
                draw.text((px, py + 2), cell.data, font=bold if cell.bold else font, fill=fg)
            if cell.underscore:
                draw.line([px, py + ch - 2, px + cw - 1, py + ch - 2], fill=fg)

    image.save(out_path)
    print("wrote", out_path, image.size)


def ctl(c):
    return bytes([ord(c) & 31])


def meta(c):
    return b"\x1b" + c.encode()


def main():
    work = tempfile.mkdtemp(prefix="avoe-shot-")
    home = os.path.join(work, "home")
    os.makedirs(home)
    env = dict(os.environ, HOME=home, XDG_CONFIG_HOME=os.path.join(home, ".config"),
               XDG_STATE_HOME=os.path.join(home, "state"))
    demo = os.path.join(work, "greet.adb")
    with open(demo, "w") as f:
        f.write(DEMO)

    # Editing an Ada file: syntax highlighting, line numbers, mode line
    # Put the cursor on a bracket: its partner is underlined, and C-x =
    # describes the character in the echo area
    keys = ([meta("x"), b"display_line_numbers_mode\r"] + [ctl("n")] * 12
            + [ctl("a")] + [ctl("f")] * 18 + [ctl("x"), b"="])
    screen = capture([demo], keys, env=env)
    render(screen, os.path.join(ROOT, "docs", "screenshot.png"))

    # The startup screen
    screen = capture([demo], [], splash=True, env=env)
    render(screen, os.path.join(ROOT, "docs", "startup.png"))


if __name__ == "__main__":
    sys.exit(main())
