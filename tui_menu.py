#!/usr/bin/env python3
"""Simple curses-based menu used across xiTools."""
import argparse
import curses
import sys


def run_menu(options, title="Menu", output=None):
    """Run a simple curses menu.

    Parameters
    ----------
    options: list[str]
        List of options to present to the user.
    title: str
        Title displayed at the top of the menu.
    output: file-like object or None
        When provided, the selected option will be written to this file
        instead of standard output. This allows callers to keep stdout
        attached to the terminal for curses while capturing the result
        via a different file descriptor.
    """
    selected = 0

    def draw(stdscr):
        nonlocal selected
        curses.curs_set(0)
        stdscr.keypad(True)
        while True:
            max_y, max_x = stdscr.getmaxyx()
            stdscr.erase()
            stdscr.addnstr(0, 0, title.ljust(max_x), max_x, curses.A_REVERSE)
            for idx, opt in enumerate(options):
                attr = curses.A_REVERSE if idx == selected else curses.A_NORMAL
                stdscr.addnstr(idx + 1, 0, opt.ljust(max_x), max_x, attr)
            try:
                ch = stdscr.getch()
            except KeyboardInterrupt:
                selected = -1
                break
            if ch in (curses.KEY_UP, ord('k')) and selected > 0:
                selected -= 1
            elif ch in (curses.KEY_DOWN, ord('j')) and selected < len(options) - 1:
                selected += 1
            elif ch in (curses.KEY_ENTER, 10, 13):
                break
            elif ch in (27, ord('q')):
                selected = -1
                break

    try:
        curses.wrapper(draw)
    except KeyboardInterrupt:
        selected = -1
    if selected >= 0:
        target = output if output is not None else sys.stdout
        print(options[selected], file=target)
        return 0
    return 1


def main():
    parser = argparse.ArgumentParser(description="Display a simple curses menu")
    parser.add_argument("options", nargs="+", help="Menu options")
    parser.add_argument("--title", default="Menu", help="Menu title")
    parser.add_argument("--output", help="File to write the selected option to")
    args = parser.parse_args()

    out_file = open(args.output, "w") if args.output else None
    try:
        rc = run_menu(args.options, args.title, out_file)
    finally:
        if out_file is not None:
            out_file.close()
    sys.exit(rc)


if __name__ == "__main__":
    main()
