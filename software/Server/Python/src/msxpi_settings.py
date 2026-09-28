# MSXPi Interface
# Version 1.6
# ------------------------------------------------------------------------------
# MIT License
#
# Copyright (c) 2015-2026 Ronivon Costa
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
# ------------------------------------------------------------------------------

from __future__ import annotations

# Standard library imports
from typing import Dict, Iterable, List, Tuple
import logging
import os
import threading

# Third-party imports

logger = logging.getLogger("msxpi")

from msxpi_const import (
    RC_SUCCESS,
)

# msxpi-server.py sets both at start-up. MSXPIHOME stays defined there as a
# literal because the openMSX test harnesses patch that line.
MSXPIHOME = "/home/pi/msxpi"
# Scratch files (pcopy session, archive extraction). MSXPI_TMP overrides it;
# "/tmp" is C:	mp on Windows.
TMPDIR = os.environ.get("MSXPI_TMP", "/tmp")

# Never printed, in p set listings or in the server log.
SECRET_VARS = {"IRCPASSWORD"}


def shown_value(name: str, value: str) -> str:
    return "[hidden]" if name.upper() in SECRET_VARS else value


_config = None


class MSXPiConfig:
    """The msxpi.ini variables: case-insensitive names, original spelling and
    file order kept for listing and saving."""

    def __init__(self, ini_path: str, pairs: Iterable[Tuple[str, str]] = ()):
        self.ini_path = ini_path
        self._vars: Dict[str, List[str]] = {}
        self._lock = threading.RLock()
        for name, value in pairs:
            # The first definition wins, as the old list lookup did.
            self._vars.setdefault(name.upper(), [name, value])

    @classmethod
    def load(cls, ini_path: str) -> "MSXPiConfig":
        pairs = []
        with open(ini_path, "r") as f:
            for line in f:
                # A "var" line without "=" (say "var RPI_SHUTDOWN") used to
                # raise IndexError here and kill the server; skip it instead.
                if line.startswith("var") and "=" in line:
                    name = line.split(" ")[1].split("=")[0].strip()
                    value = line.split("=", 1)[1].strip()
                    pairs.append((name, value))
        return cls(ini_path, pairs)

    def get(self, name: str, default: str = "") -> str:
        with self._lock:
            entry = self._vars.get(name.upper())
            return entry[1] if entry else default

    def has(self, name: str) -> bool:
        with self._lock:
            return name.upper() in self._vars

    def items(self) -> List[Tuple[str, str]]:
        with self._lock:
            return [(n, v) for n, v in self._vars.values()]

    def setdefault(self, name: str, value: str) -> None:
        """Add a variable only if missing, without saving the file."""
        with self._lock:
            self._vars.setdefault(name.upper(), [name, value])

    def set(self, name: str, value: str) -> None:
        """Set a variable and save; an empty value deletes it."""
        with self._lock:
            key = name.upper()
            if value == "":
                if self._vars.pop(key, None) is None:
                    return
                print(f"Deleting variable {name}")
            elif key in self._vars:
                print(f"Updating variable {name}")
                self._vars[key][1] = value
            else:
                print(f"Adding new variable {name}")
                self._vars[key] = [name, value]
            self.save()

    def save(self) -> None:
        with self._lock:
            updateIniFile(self.ini_path, self.items())


def setMSXPiVar(pvar: str = "", pvalue: str = "") -> int:
    _config.set(pvar, pvalue)
    return RC_SUCCESS


def getMSXPiVar(devname: str = "PATH") -> str:
    return _config.get(devname)


def updateIniFile(fname, memvar):
    f = open(fname, "w")
    for v in memvar:
        f.writelines("var " + v[0] + "=" + v[1] + "\n")
    f.close()
