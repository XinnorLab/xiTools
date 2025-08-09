#!/usr/bin/env python3
"""Simple curses-based menu used across xiTools."""
import argparse
import curses
import sys


def run_menu(options, title="Menu"):
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
        print(options[selected])
        return 0
    return 1


def main():
    parser = argparse.ArgumentParser(description="Display a simple curses menu")
    parser.add_argument("options", nargs="+", help="Menu options")
    parser.add_argument("--title", default="Menu", help="Menu title")
    args = parser.parse_args()
    sys.exit(run_menu(args.options, args.title))


if __name__ == "__main__":
    main()
