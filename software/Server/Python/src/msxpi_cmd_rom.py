# MSXPi Interface
# Version 1.6.1
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

from typing import Optional

# Standard library imports
import time
import subprocess
import struct
import logging
import os
import platform
import math
import re
from html.parser import HTMLParser
from urllib.parse import unquote

# Third-party imports
import requests
import shutil

from msxpi_settings import TMPDIR

logger = logging.getLogger("msxpi")

from msxpi_const import (
    CommandResult,
    HTTP_TIMEOUT,
    MAPPER_ASCII16,
    MAPPER_ASCII8,
    MAPPER_KONAMI,
    MAPPER_PLAIN,
    MAPPER_REJECTED,
    PLAIN_ROM_MAX_SIZE,
    RC_FAILED,
    RC_READY,
    RC_SUCCESS,
    RC_TERMINATE,
    ROM_HEADER_MAGIC,
    ROM_HEADER_VERSION,
    ROM_MAX_SIZE,
)
import msxpi_transport as transport
import msxpi_settings as settings
from msxpi_blocks import readParameters, recvdata2, senddata, sendmultiblock
from msxpi_cmd_files import pathExpander
from msxpi_settings import getMSXPiVar


def build_rom_header(
    mapper_type: int, bank_size_kb: int, bank_count: int, total_size: int
) -> bytes:
    """Pack the fixed 16-byte ROM header: magic, protocol version, mapper
    type, bank size (KB), bank count, and total ROM size in bytes.
    mapper_type MAPPER_PLAIN keeps today's client behavior unchanged;
    the other values are reserved for mapper-aware loading (not yet
    implemented client-side)."""
    # Konami SCC only differs in where the cartridge decodes its bank writes,
    # which the server has already patched; on the MSX it loads exactly like
    # Konami, and the clients only know types 1-3.
    if mapper_type == MAPPER_KONAMI_SCC:
        mapper_type = MAPPER_KONAMI
    return struct.pack(
        "<BBBBHI6x",
        ROM_HEADER_MAGIC,
        ROM_HEADER_VERSION,
        mapper_type,
        bank_size_kb,
        bank_count,
        total_size,
    )


# Bank-select write addresses (as LD (nn),A / 0x32 lo hi) each mapper type
# responds to. ASCII8 and ASCII16 both use 0x6000/0x7000, so those two
# addresses alone don't distinguish them - 0x6800/0x7800 are ASCII8-only,
# 0x8000/0xA000 are Konami-only, and 0x5000/0x9000/0xB000 are Konami SCC
# only (SCC also uses 0x7000, which overlaps ASCII8/16). Konami SCC is
# reported as plain MAPPER_KONAMI (same 8K banks, same LD (nn),A bank-select
# mechanism the wire protocol/transfer cares about - the SCC sound chip's
# own registers don't affect bank-switch addresses or chunking at all).
# The client (EXECROM's /W option) detects SCC-ness itself from the ROM's
# own content via its existing disk-load signature table (checkon/konatab -
# the same lookup a disk-sourced Konami SCC load already used), so nothing
# server-side needs to flag it specially.
# This is a heuristic (opcode-pattern scan, not a hash database), so it
# can misidentify unusual/hand-rolled ROMs - good enough for the common
# commercial mapper layouts.
from mapper_detect import (
    detect_mapper as _detect_mapper_v2,
    patch_bank_switches,
    patch_indexed_switches,
    patch_page2_slot_selects,
    PATCH_WINDOWS,
    neutralise_rom_writes,
    neutralise_scc_writes,
    MAPPER_KONAMI_SCC,
    load_romdb,
    romdb_lookup,
)

# Handler addresses the MSX will have relocated its resident bank-switch code
# to. The client sends its own with the selection so the two sides cannot
# drift; these are only the fallback for an older client that sends none, in
# which case the MSX patches the image itself as it used to.
DEFAULT_HANDLERS = (0xF9C0, 0xFA00, 0xFA40, 0xFA80, 0xFAC0, 0xFB00)


def handlers_for(mapper_type, h):
    """Pick the handler list for this mapper, in PATCH_WINDOWS order.
    h is (win1, win2, win3, win4, page1, page2)."""
    if mapper_type == MAPPER_ASCII8:
        return [h[0], h[1], h[2], h[3]]
    if mapper_type == MAPPER_ASCII16:
        return [h[4], h[5]]
    if mapper_type == MAPPER_KONAMI:
        return [h[1], h[2], h[3]]  # 6000/8000/A000 ranges
    if mapper_type == MAPPER_KONAMI_SCC:
        return [h[0], h[1], h[2], h[3]]  # 5000/7000/9000/B000
    return None


def patch_for_msx(buf, mapper_type, handlers, slot_handlers=None):
    """Convert the ROM's bank-switch writes into CALLs to the MSX-side
    handlers, so the MSX only has to store blocks and run. Scanning a 128KB ROM
    on a 3.58MHz Z80 cost 16KB per storage segment before the game started."""
    if not handlers or mapper_type not in PATCH_WINDOWS:
        return buf, 0
    hs = handlers_for(mapper_type, handlers)
    if not hs:
        return buf, 0
    buf, n = patch_bank_switches(buf, mapper_type, hs)
    if mapper_type == MAPPER_KONAMI_SCC:
        buf, m = neutralise_scc_writes(buf)
        if m:
            print(f"neutralised {m} SCC sound-register writes")
        n += m
    # A seventh address is the MSX's window dispatcher, for games that compute
    # the register instead of storing to it directly (HYDLIDE3.ROM).
    if len(handlers) >= 7:
        buf, m = patch_indexed_switches(buf, mapper_type, handlers[6])
        if m:
            print(f"patched {m} computed window selects")
        n += m
    # Ninth and tenth addresses: the ASCII16 page-2 work-RAM and cartridge
    # selects, for games that page their RAM into 8000h with ENASLT
    # (ARCTIC.ROM) - see patch_page2_slot_selects.
    if slot_handlers and mapper_type == MAPPER_ASCII16:
        buf, m = patch_page2_slot_selects(buf, *slot_handlers)
        if m:
            print(f"patched {m} page-2 slot selects")
        n += m
    return buf, n


KONAMI_SCC_UNIQUE_ADDRS = (0x5000, 0x9000, 0xB000)
KONAMI_UNIQUE_ADDRS = (0x8000, 0xA000)
ASCII8_UNIQUE_ADDRS = (0x6800, 0x7800)
ASCII16_ADDRS = (0x6000, 0x7000)


def detect_mapper(rom_bytes):
    """Scan rom_bytes for bank-select write patterns and guess the mapper
    type. Returns (mapper_type, bank_size_kb) or (None, None) if nothing
    recognizable/supported was found (caller should treat the ROM as
    unsupported)."""
    write_addrs = set()
    for i in range(len(rom_bytes) - 2):
        if rom_bytes[i] == 0x32:  # LD (nn),A
            write_addrs.add(rom_bytes[i + 1] | (rom_bytes[i + 2] << 8))

    # Delegated to mapper_detect: same exact-address chain as before, plus a
    # repetition-based fallback for ROMs it rejects outright (BUBBLE.ROM and
    # ISHTAR.ROM bank at 6FF8h/77F8h/7FF8h and 67FFh/77FFh respectively, so
    # they never matched the exact addresses). See MEGAROM_MAPPER_NOTES.md.
    del write_addrs
    return _detect_mapper_v2(rom_bytes)


ROMDB_DEFAULT_URL = (
    "https://raw.githubusercontent.com/costarc/openMSX/master/share/softwaredb.xml"
)
ROMDB_CACHE_DAYS = 30
_romdb = None


def get_romdb():
    """openMSX's share/softwaredb.xml, indexed by SHA-1 (see load_romdb in
    mapper_detect.py). ROMDB in msxpi.ini may be a URL or a local path; a URL
    is cached as MSXPIHOME/softwaredb.xml and refreshed every ROMDB_CACHE_DAYS,
    and a failed refresh keeps using the cached copy. With no database at all
    the caller falls back to detect_mapper()."""
    global _romdb
    if _romdb:
        return _romdb
    src = getMSXPiVar("ROMDB") or ROMDB_DEFAULT_URL
    text = None
    try:
        if src.startswith(("http://", "https://")):
            cache = os.path.join(settings.MSXPIHOME, "softwaredb.xml")
            fresh = (
                os.path.exists(cache)
                and time.time() - os.path.getmtime(cache) < ROMDB_CACHE_DAYS * 86400
            )
            if not fresh:
                try:
                    r = requests.get(src, timeout=30)
                    r.raise_for_status()
                    os.makedirs(settings.MSXPIHOME, exist_ok=True)
                    with open(cache, "wb") as f:
                        f.write(r.content)
                except Exception as e:
                    print(
                        f"ROM database download failed ({e}); using the cached copy if any"
                    )
            if os.path.exists(cache):
                with open(cache, encoding="utf-8", errors="ignore") as f:
                    text = f.read()
        else:
            with open(src, encoding="utf-8", errors="ignore") as f:
                text = f.read()
    except Exception as e:
        print(f"ROM database unavailable ({e}); falling back to mapper detection")
    _romdb = load_romdb(text) if text else {}
    print(f"ROM database: {len(_romdb)} entries from {src}")
    return _romdb


def is_local_path(s: str) -> bool:
    """A repository entry is a local filesystem path (e.g. /home/roms or
    C:\\Users\\roniv\\Dev\\MSX\\gameroms) rather than an HTTP(S) archive URL
    if it doesn't start with a scheme. Lets msxarchive() browse/load ROMs
    straight off disk where the server runs, with no local web server
    needed."""
    return not (s.startswith("http://") or s.startswith("https://"))


def _rmtree_force(path):
    """shutil.rmtree that also removes read-only files (Windows refuses to
    delete them with 'Access is denied'). Missing path is not an error."""

    def _onerror(func, p, exc_info):
        os.chmod(p, 0o666)
        func(p)

    if os.path.exists(path):
        shutil.rmtree(path, onerror=_onerror)


def fetch_and_uncompress(url: str):
    """
    Download a compressed file from URL into /tmp/msxpi (cache), or - if
    url is a local filesystem path - copy it into the same cache instead.
    Detect compression type by extension and uncompress.
    Return (rc, buf) where rc is RC_SUCCESS or RC_FAILED,
    and buf is the resulting .rom file contents as bytes.
    """
    tmpdir = TMPDIR + "/msxpi"

    filename = os.path.basename(url)
    cached_path = os.path.join(tmpdir, filename)

    # Download/copy only if not cached
    if not os.path.exists(cached_path):
        if is_local_path(url):
            try:
                os.makedirs(tmpdir, exist_ok=True)
                shutil.copyfile(url, cached_path)
            except Exception as e:
                print(f"Local read failed: {e}")
                return RC_FAILED, f"Local read failed: {e}"
        else:
            try:
                resp = requests.get(url, stream=True, timeout=HTTP_TIMEOUT)
                resp.raise_for_status()
                with open(cached_path, "wb") as f:
                    for chunk in resp.iter_content(chunk_size=8192):
                        f.write(chunk)
            except Exception as e:
                print(f"Download failed: {e}")
                return RC_FAILED, f"Download failed: {e}"
    else:
        print(f"Using cached file: {cached_path}")

    # Handle plain .rom files directly
    ext = filename.lower().split(".")[-1]
    if ext == "rom":
        try:
            with open(cached_path, "rb") as f:
                buf = f.read()
            return RC_SUCCESS, buf
        except Exception as e:
            print(f"Failed to read ROM file: {e}")
            return RC_FAILED, f"Failed to read ROM file: {e}"

    # Otherwise, prepare extraction. Start from an empty extract dir every
    # time: archives may carry read-only files (e.g. 1942.zip), which a plain
    # shutil.rmtree cannot delete on Windows, and any leftover ROM would be
    # picked up instead of the one just extracted.
    extract_dir = os.path.join(tmpdir, "extract")
    try:
        _rmtree_force(extract_dir)
    except Exception as e:
        print(f"Cannot clean extract dir: {e}")
        return RC_FAILED, f"Cannot clean extract dir: {e}"
    os.makedirs(extract_dir, exist_ok=True)
    system = platform.system().lower()

    if ext == "zip":
        if system == "windows":
            cmd = ["7z.exe", "e", cached_path, "-aoa", f"-o{extract_dir}"]
        else:
            cmd = ["unzip", "-o", cached_path, "-d", extract_dir]

    elif ext == "lzh":
        if system == "windows":
            cmd = ["7z.exe", "e", cached_path, "-aoa", f"-o{extract_dir}"]
        else:
            cmd = ["lha", "xq", cached_path]

    elif ext == "pma":
        if system == "windows":
            cmd = ["7z.exe", "e", cached_path, "-aoa", f"-o{extract_dir}"]
        else:
            cmd = ["pma", "x", cached_path]

    elif ext == "arj":
        if system == "windows":
            cmd = ["7z.exe", "e", cached_path, "-aoa", f"-o{extract_dir}"]
        else:
            cmd = ["arj", "x", cached_path, extract_dir]

    else:
        print(f"Unsupported extension: {ext}")
        return RC_FAILED, f"Unsupported extension: {ext}"

    try:
        # Run extraction
        try:
            print(f"Extrating file with command: {cmd}")
            subprocess.run(cmd, cwd=extract_dir, check=True)
        except subprocess.CalledProcessError as e:
            print(f"Extraction failed: {e}")
            return RC_FAILED, f"Extraction failed: {e}"

        # Find the resulting .rom file; prefer one named like the archive
        roms = sorted(
            os.path.join(root, f)
            for root, _, files in os.walk(extract_dir)
            for f in files
            if f.lower().endswith(".rom")
        )
        if not roms:
            print("No .rom file found after extraction")
            return RC_FAILED, "No .rom file found after extraction"
        base = os.path.splitext(filename)[0].lower()
        rom_file = next(
            (
                r
                for r in roms
                if os.path.splitext(os.path.basename(r))[0].lower() == base
            ),
            roms[0],
        )

        # Load into buf
        try:
            with open(rom_file, "rb") as f:
                buf = f.read()
        except Exception as e:
            print(f"Failed to read ROM file: {e}")
            return RC_FAILED, f"Failed to read ROM file: {e}"

        return RC_SUCCESS, buf
    finally:
        # Clean up extracted files, keep cache
        try:
            _rmtree_force(extract_dir)
        except Exception as e:
            print(f"Cannot clean extract dir: {e}")


_ploadr_cache = None  # (filepath, rom bytes) of the transfer in progress


def ploadr(parms: Optional[str] = None) -> CommandResult:
    """Fetch a single ROM by filename (resolved against the current MSXPi
    path - same convention as pcopy/pdir/pcd, see cd()'s own basepath =
    getMSXPiVar('PATH')) and send it back using the mapper-aware ROM header
    protocol (see build_rom_header/detect_mapper). This is the direct,
    non-interactive counterpart to msxarchive's browse-and-select flow -
    used by ploadr.com and by EXECROM.MAC's /W option (as "execrom", kept
    as an alias below for backward compatibility), e.g. "ploadr
    zanacex.rom" resolves against whatever path was last set via
    "p cd <path>"."""
    basepath = getMSXPiVar("PATH")
    parts = (parms or "").strip().split()
    filename = parts[0] if parts else ""

    def reject(reason):
        print(reason)
        header = build_rom_header(MAPPER_REJECTED, 0, 0, 0)
        return sendmultiblock(header + reason.encode())

    if not filename:
        return reject("Pi:Error - no filename given")

    # filename arrives already uppercased by MS-DOS's own FCB parsing (the
    # original typed case is gone by the time this command runs, not
    # something this patch can recover) - lowercase it before resolving
    # against a network path, since remote archives conventionally use
    # lowercase filenames and would 404 on a case-sensitive host otherwise.
    # Local filesystem paths are left alone - those may be genuinely
    # case-sensitive in the other direction (a real lowercase-only file
    # living under a path a user typed in whatever case).
    pathType, filepath = pathExpander(filename, basepath)
    if pathType == 1 and filename != filename.lower():
        pathType, filepath = pathExpander(filename.lower(), basepath)

    # Per-block requests reuse the ROM held in memory from this transfer's
    # header request instead of re-fetching/re-extracting it for every
    # 16K block (which ran 7z and wrote the whole extracted ROM to disk
    # once per block). Replaced by the next header/legacy request, dropped
    # after the last block.
    global _ploadr_cache
    is_block_req = len(parts) >= 3
    if is_block_req and _ploadr_cache and _ploadr_cache[0] == filepath:
        buf = _ploadr_cache[1]
        block_index = int(parts[1])
        block_size = int(parts[2])
        offset = block_index * block_size
        chunk = buf[offset : offset + block_size]
        is_last = (offset + len(chunk)) >= len(buf)
        if is_last:
            _ploadr_cache = None
        return sendmultiblock(chunk, header_rc=RC_SUCCESS if is_last else RC_READY)
    _ploadr_cache = None

    rc, buf = fetch_and_uncompress(filepath)
    if rc != RC_SUCCESS:
        reason = buf if isinstance(buf, str) else "Pi:Error - fetch failed"
        return reject(reason)

    if len(buf) <= PLAIN_ROM_MAX_SIZE:
        header = build_rom_header(MAPPER_PLAIN, 0, 0, len(buf))
    else:
        mapper_type, bank_size_kb = detect_mapper(buf)
        if mapper_type is None:
            return reject(
                f"{filename} ({len(buf)} bytes): unrecognized "
                f"mapper - not supported yet."
            )
        if len(buf) > ROM_MAX_SIZE:
            return reject(
                f"{filename} ({len(buf)} bytes) exceeds the "
                f"{ROM_MAX_SIZE} byte cap."
            )
        bank_count = len(buf) // (bank_size_kb * 1024)
        print(
            f"{filename}: detected mapper type {mapper_type}, "
            f"{bank_size_kb}KB banks, {bank_count} banks"
        )
        header = build_rom_header(mapper_type, bank_size_kb, bank_count, len(buf))

    # Per-block body request: "ploadr <file> <index> <blocksize>" - slices
    # the already-cached buffer and sends exactly one block, then returns,
    # so the dispatch loop is back at "Waiting Command" between every
    # block instead of staying monolithically inside one ploadr() call for
    # the whole transfer. That matters because msxpi-server.py's command
    # dispatch is single-threaded/synchronous (see the main loop) - while
    # ploadr() used to hold the conversation open across the entire body,
    # any real disk access the DOS kernel needed mid-transfer (its DSKCHG
    # contract requires re-validating on disk-related calls) had nowhere
    # correct to land and would desync the wire. Per-block requests close
    # that window entirely, the same way dskiords/dskiosct already do.
    if len(parts) >= 3:
        block_index = int(parts[1])
        block_size = int(parts[2])
        offset = block_index * block_size
        chunk = buf[offset : offset + block_size]
        is_last = (offset + len(chunk)) >= len(buf)
        header_rc = RC_SUCCESS if is_last else RC_READY
        return sendmultiblock(chunk, header_rc=header_rc)

    # Header-only request: "ploadr <file> H" - used by LOADRPI.COM's
    # searchpatch_first, which needs just the header to decide plain-vs-
    # mapped routing and block count before requesting the body above,
    # one block at a time.
    if len(parts) == 2 and parts[1].upper() == "H":
        _ploadr_cache = (filepath, buf)
        return sendmultiblock(header)

    # Legacy whole-file request: "ploadr <file>" (no extra params) -
    # unchanged, still used by ploadr.c's plain-ROM path.
    rc = sendmultiblock(header)
    if rc != RC_SUCCESS:
        return rc
    rc = sendmultiblock(buf)
    return RC_SUCCESS


# Backward-compatible alias - EXECROM.MAC's /W option and msxarch.c still
# send "execrom <filename>"; the command dispatcher (globals()[cmd.lower()])
# resolves purely by name, so this keeps them working under ploadr()'s
# renamed implementation without needing their own changes.
execrom = ploadr


def msxarchive(parms: Optional[str] = None) -> CommandResult:
    stored_screen = ""  # local variable inside ploadr
    nrows = 22
    ncolumns = 80
    columnwidth = 14
    indexFile = "00index.txt"

    ROM_FILE_EXTENSIONS = (".rom", ".zip", ".lzh", ".pma", ".arj")

    # File size in KB per file name, shown next to each game in the listing.
    # Every source finds sizes its own way (see fetch_file_list); a name with
    # no entry has not been looked up yet, None means the size is unknown.
    sizes = {}

    def _listing_size_kb(text):
        """KB from the size column of an HTTP directory listing: Apache shows
        "128K" / "1.2M", nginx the byte count, Python's http.server nothing."""
        m = re.fullmatch(r"(\d+(?:\.\d+)?)([KMG]?)", text.strip(), re.I)
        if not m:
            return None
        n = float(m.group(1))
        unit = m.group(2).upper()
        if unit == "":
            return math.ceil(n / 1024)
        return math.ceil(n * {"K": 1, "M": 1024, "G": 1024 * 1024}[unit])

    def fetch_file_list(url: str, index: str):
        """Fetch file list from the given URL and return filenames without extensions.
        Skip header (first line) and empty lines."""

        def request_failed(fetch_url, exc):
            if isinstance(exc, requests.exceptions.Timeout):
                detail = "Timed out waiting for the server."
            elif isinstance(exc, requests.exceptions.ConnectionError):
                detail = "Connection refused or server offline."
            elif isinstance(exc, requests.exceptions.TooManyRedirects):
                detail = "Too many redirects."
            else:
                detail = "Network request failed."

            print(f"MSX Archive request failed for {fetch_url}: {exc}")
            return RC_FAILED, (
                "Pi:Error - Cannot open archive URL.\n" f"{fetch_url}\n" f"{detail}"
            )

        def local_path_failed(path, exc):
            if isinstance(exc, PermissionError):
                detail = "Permission denied."
            elif isinstance(exc, (FileNotFoundError, NotADirectoryError)):
                detail = "File or directory does not exist."
            else:
                detail = "Cannot read this directory."

            print(f"MSX Archive directory failed for {path}: {exc}")
            return RC_FAILED, (
                "Pi:Error - Cannot open archive directory.\n" f"{path}\n" f"{detail}"
            )

        if is_local_path(url):
            try:
                entries = os.listdir(url)
            except Exception as e:
                return local_path_failed(url, e)
            files = sorted(
                f for f in entries if f.lower().endswith(ROM_FILE_EXTENSIONS)
            )
            for f in files:
                try:
                    sizes[f] = math.ceil(os.path.getsize(os.path.join(url, f)) / 1024)
                except OSError:
                    sizes[f] = None
            return RC_SUCCESS, files

        CACHE_TTL_SECONDS = 3600

        index_url = url + "/" + index
        cached_file = TMPDIR + "/msxpi/" + index_url.replace(":", "_").replace("/", "+")

        cache_exists = os.path.exists(cached_file)
        cache_expired = (
            cache_exists
            and (time.time() - os.path.getmtime(cached_file)) > CACHE_TTL_SECONDS
        )

        if not cache_exists or cache_expired:
            print(
                f"cache expired: {cached_file}"
                if cache_expired
                else f"not cached: {cached_file}"
            )
            # Download from the URL
            try:
                response = requests.get(index_url, timeout=HTTP_TIMEOUT)
            except requests.exceptions.RequestException as e:
                return request_failed(index_url, e)

            if response.status_code == 200:
                # Success: parse the content
                lines = response.text.splitlines()
            elif response.status_code == 404:
                # No index file published (e.g. a plain directory server with
                # no 00index.txt, like a local test HTTP server): fall back to
                # the server's own auto-generated directory listing instead.
                print(
                    f"{index} not found, falling back to directory listing at: {url}/"
                )
                try:
                    dir_response = requests.get(url + "/", timeout=HTTP_TIMEOUT)
                except requests.exceptions.RequestException as e:
                    return request_failed(url + "/", e)
                if dir_response.status_code != 200:
                    print(
                        f"Download failed: HTTP {dir_response.status_code} - {dir_response.reason}"
                    )
                    files = f"Download failed: HTTP {dir_response.status_code} - {dir_response.reason}"
                    return RC_FAILED, files

                class DirListingParser(HTMLParser):
                    def __init__(self):
                        super().__init__()
                        self.hrefs = []

                    def handle_starttag(self, tag, attrs):
                        if tag == "a":
                            href = dict(attrs).get("href")
                            if href:
                                self.hrefs.append(href)

                parser = DirListingParser()
                parser.feed(dir_response.text)
                entries = [
                    unquote(h)
                    for h in parser.hrefs
                    if h != ".." and not h.endswith("/")
                ]

                # Servers that show a size print it on the same line, after
                # the link. It is kept as a second column so it survives the
                # cache; the parsing loop below reads the last column.
                listed = {}
                for m in re.finditer(
                    r'<a\s[^>]*href="([^"]+)"[^>]*>.*?</a>([^\n<]*)',
                    dir_response.text,
                    re.I | re.S,
                ):
                    cols = m.group(2).split()
                    kb = _listing_size_kb(cols[-1]) if cols else None
                    if kb is not None:
                        listed[unquote(m.group(1))] = kb
                entries = [f"{e} {listed[e]}" if e in listed else e for e in entries]

                # Prepend a placeholder header line since the parsing loop
                # below always skips line 0 (matches the plain-text index format).
                lines = ["# directory listing"] + entries
            else:
                # Failure: print error message
                print(
                    f"Download failed: HTTP {response.status_code} - {response.reason}"
                )
                files = (
                    f"Download failed: HTTP {response.status_code} - {response.reason}"
                )
                return RC_FAILED, files

            # Save to cache for future use
            os.makedirs(os.path.dirname(cached_file), exist_ok=True)
            with open(cached_file, "w", encoding="utf-8") as f:
                f.write("\n".join(lines))

        else:
            # Read from cache
            print(f"Reading from cache: {index_url}")
            with open(cached_file, "r", encoding="utf-8") as f:
                lines = f.read().splitlines()

        files = []
        for i, line in enumerate(lines):
            line = line.strip()
            if (
                i == 0 or not line or line.startswith("#")
            ):  # skip header + empty + comments
                continue
            # Drop extension
            cols = line.split()
            name = cols[0]
            files.append(name)
            # 00index.txt ends each line with the size in KB ("div" for
            # archives of many ROMs); a directory listing line carries it as
            # the second column when the server showed one. Unknown sizes are
            # asked for with HEAD when their page is shown - see size_label.
            if len(cols) > 1 and cols[-1].isdigit():
                sizes[name] = int(cols[-1])
            elif len(cols) > 1:
                sizes[name] = None
        return RC_SUCCESS, files

    def size_label(name):
        """ "128K" / "12M", or blank when the size is unknown."""
        kb = sizes.get(name)
        if kb is None:
            return ""
        return f"{kb}K" if kb < 10000 else f"{kb // 1024}M"

    def lookup_sizes(names):
        """HEAD the files whose size no listing gave, only for the page being
        shown - a request per file for a whole archive would take minutes."""
        missing = [n for n in names if n not in sizes]
        if not missing or is_local_path(url):
            return
        from concurrent.futures import ThreadPoolExecutor
        from urllib.parse import urlsplit, urlunsplit

        # On Windows "localhost" tries IPv6 (::1) first and falls back to IPv4
        # after a delay, paid by every request: a page of 25 HEADs to a local
        # IPv4-only http.server took 6 seconds. 127.0.0.1 skips that.
        base = urlsplit(url)
        if base.hostname == "localhost":
            netloc = "127.0.0.1" + (f":{base.port}" if base.port else "")
            base = base._replace(netloc=netloc)
        base = urlunsplit(base).rstrip("/")

        # One session keeps connections open between requests instead of
        # connecting again for every file; pool sized to the worker count.
        session = requests.Session()
        adapter = requests.adapters.HTTPAdapter(pool_connections=1, pool_maxsize=8)
        session.mount("http://", adapter)
        session.mount("https://", adapter)

        def head(name):
            try:
                r = session.head(f"{base}/{name}", timeout=3, allow_redirects=True)
                n = int(r.headers.get("Content-Length", ""))
                return name, math.ceil(n / 1024)
            except Exception:
                return name, None

        with session, ThreadPoolExecutor(max_workers=8) as pool:
            for name, kb in pool.map(head, missing):
                sizes[name] = kb

    def paginate_files(files, rows=nrows, cols=ncolumns, col_width=None):
        """
        Arrange files into pages of rows x cols with horizontal indexing.
        Column width is determined by the longest filename (plus index prefix),
        unless explicitly provided. Pads the last page with spaces so all pages
        have equal size. Ensures a space between columns.
        """
        if not files:
            return []

        # Compute max column width if not provided
        max_index_len = len(str(len(files)))  # e.g. "650" → 3
        if col_width is None:
            max_name_len = max(len(f) for f in files)
            # +1 for the colon, +6 for " 1234K"
            col_width = max_name_len + max_index_len + 1 + SIZE_FIELD

        # At least three columns: the size field would otherwise push a long
        # name like GOODMSX1_0.999.2.ZIP down to two columns. Such names are
        # truncated on screen only; selection still uses the full name.
        col_width = min(col_width, cols // 3 - 1, cols)

        # Ensure at least one column
        cols_count = max(1, cols // (col_width + 1))  # +1 for spacing
        items_per_page = cols_count * rows
        total_pages = max(1, math.ceil(len(files) / items_per_page))

        # Pages hold 0-based file indices, laid out row by row; the text is
        # made in get_page, once the sizes for that page are known.
        pages = []
        for p in range(total_pages):
            start = p * items_per_page
            pages.append(
                (
                    list(range(start, min(start + items_per_page, len(files)))),
                    cols_count,
                    col_width,
                )
            )
        return pages

    SIZE_FIELD = 6  # " 1234K"

    def format_entry(files, i, col_width):
        prefix = f"{i+1}:"
        room = max(1, col_width - len(prefix) - SIZE_FIELD)
        return (
            prefix
            + files[i][:room].ljust(room)
            + size_label(files[i]).rjust(SIZE_FIELD)
        )

    def get_page(files, pages, page_number, width=ncolumns):
        """
        Return only the requested page as plain text, update stored_screen.
        Each line is padded with spaces to 'width' and concatenated without newlines.
        """
        nonlocal stored_screen  # use nonlocal to modify outer variable
        total_pages = len(pages)
        lines = []
        if 1 <= page_number <= total_pages:
            indices, cols_count, col_width = pages[page_number - 1]
            lookup_sizes([files[i] for i in indices])
            entries = [format_entry(files, i, col_width) for i in indices]
            for r in range(nrows):
                row = entries[r * cols_count : (r + 1) * cols_count]
                # Add one space after each column, trim to exactly 'width'
                lines.append("".join(e.ljust(col_width) + " " for e in row)[:width])

        # Pad each line to the full width with spaces
        padded_lines = [line.ljust(width) for line in lines]

        # Concatenate into one continuous string (no '\n')
        stored_screen = "".join(padded_lines)
        return stored_screen

    def get_total_files(files):
        """Return the total number of files."""
        return len(files)

    def get_total_pages(pages):
        """Return the total number of pages."""
        return len(pages)

    def get_fileName(files, index):
        """
        Return the filename at the given 1-based index.
        If the index is out of range, return None.
        """
        if 1 <= index <= len(files):
            return files[index - 1]  # convert from 1-based to 0-based
        else:
            return None

    # This command requires parameter
    rc, url = readParameters("This command requires a parameter", True)
    if rc == RC_FAILED:
        return RC_FAILED

    PAGESIZE = nrows * ncolumns

    print(f"Fetching MSX Archive file list from: {url + '/'  + indexFile}")
    rc, files = fetch_file_list(url, indexFile)

    if rc == RC_FAILED:
        senddata(RC_FAILED, files.encode().ljust(PAGESIZE, b"\x00"))
        return RC_FAILED

    pages = paginate_files(files, nrows, ncolumns, None)

    print(
        f"total files = {get_total_files(files)}, total pages = {get_total_pages(pages)}"
    )
    # text = get_page(files, pages, 1)

    page = 1
    current_page = 1
    transport.DISABLETIMEOUT = (
        True  # Disable transfers timeout for MSX Archive browsing
    )
    cmd = "1"
    text = get_page(files, pages, page, ncolumns)
    rc = sendmultiblock(text.encode().ljust(PAGESIZE, b"\x00"))

    try:
        while True:
            rc, parm = recvdata2()
            parm = parm.decode(errors="ignore").split("\x00", 1)[0]
            cmd = str(parm).lower()  # normalize to string for command checks

            if cmd == "n" or cmd == "N":
                # go to next page
                page = int(current_page) + 1
                if page > get_total_pages(pages):
                    page = 1

                current_page = page
                text = get_page(files, pages, page, ncolumns)

            elif cmd == "p" or cmd == "P":
                # go to previous page
                page = int(current_page) - 1
                if page < 1:
                    page = get_total_pages(pages)
                current_page = page
                text = get_page(files, pages, page, ncolumns)

            elif cmd == "q" or cmd == "Q":
                break
            else:
                # Every outcome of a numeric selection (load, or reject with a
                # reason) ends the archive session, so each one always sends the
                # 16-byte ROM header first - the client now unconditionally
                # expects it right after sending a file number. Rejections carry
                # MAPPER_REJECTED plus a short reason string instead of a ROM body,
                # so the client never mistakes a plain-text reply for ROM data.
                # A rejection is FATAL: its header block goes out with
                # RC_TERMINATE instead of RC_SUCCESS, so the MSX knows the
                # conversation is over and nothing else will be sent, whatever
                # it reads in the header.
                def reject(reason):
                    print(reason)
                    header = build_rom_header(MAPPER_REJECTED, 0, 0, 0)
                    sendmultiblock(header + reason.encode(), RC_TERMINATE)
                    return RC_FAILED

                # The MSX appends the addresses it relocated its resident
                # bank-switch handlers to, so this side can patch the image and
                # the MSX does not have to scan it. Absent => old client, which
                # patches for itself. An eighth value is the number of mapper
                # segments free for the game; absent => not checked here.
                msx_handlers = None
                msx_free_segments = None
                msx_slot_handlers = None
                try:
                    fields = str(parm).split()
                    file_num = int(fields[0])
                    if len(fields) >= 7:
                        msx_handlers = tuple(int(f, 16) for f in fields[1:8])
                    if len(fields) >= 9:
                        msx_free_segments = int(fields[8], 16)
                    if len(fields) >= 11:
                        msx_slot_handlers = (int(fields[9], 16), int(fields[10], 16))
                except (ValueError, TypeError, IndexError):
                    return reject(f"Invalid input: {cmd}")

                if file_num < 1 or file_num > get_total_files(files):
                    return reject(f"File {file_num} does not exist.")

                filename = get_fileName(files, file_num)
                print(f"Selected file: {filename}")
                filepath = (
                    os.path.join(url, filename)
                    if is_local_path(url)
                    else f"{url}/{filename}"
                )
                rc, buf = fetch_and_uncompress(filepath)
                if rc != RC_SUCCESS:
                    return reject(buf)

                # openMSX's softwaredb.xml decides how the ROM is loaded;
                # detect_mapper() is only the fallback for unlisted ROMs.
                dbinfo = romdb_lookup(buf, get_romdb())
                if dbinfo:
                    # ASCII only: titles such as "Akumajō Dracula" raised
                    # UnicodeEncodeError on a cp1252 Windows console, which
                    # aborted the load and left the MSX without a ROM header.
                    title = dbinfo[3].encode("ascii", "replace").decode("ascii")
                    print(f"{filename}: ROM database: {dbinfo[2]} ({title})")
                    if dbinfo[0] == "unsupported":
                        return reject(
                            f"{filename}: {dbinfo[2]} mapper is not " f"supported."
                        )
                plain = (
                    (dbinfo[0] == "plain") if dbinfo else len(buf) <= PLAIN_ROM_MAX_SIZE
                )
                if plain and len(buf) > PLAIN_ROM_MAX_SIZE:
                    return reject(
                        f"{filename} ({len(buf)} bytes): plain ROM "
                        f"larger than {PLAIN_ROM_MAX_SIZE} bytes."
                    )
                if plain:
                    # The MSX runs the image from RAM, where stores into the
                    # ROM window succeed instead of being discarded - see
                    # neutralise_rom_writes in mapper_detect.py.
                    # A 16KB cartridge that decodes only 14 address bits appears
                    # at 4000h AND 8000h, and may be built to run from 8000h:
                    # ICEWORLD.ROM ("Mirrored" in softwaredb.xml) has INIT
                    # 8010h, which pointed into empty RAM when only 4000h was
                    # loaded. Its code is traced from 8000h, and the image is
                    # sent twice to fill both pages.
                    init = buf[2] | (buf[3] << 8) if len(buf) >= 4 else 0
                    page2 = len(buf) == 0x4000 and 0x8000 <= init < 0xC000
                    buf, nstore = neutralise_rom_writes(
                        buf, 0x8000 if page2 else 0x4000
                    )
                    print(f"{filename}: neutralised {nstore} stores into ROM")
                    if page2:
                        buf = buf + buf
                    # An 8KB cartridge decodes only 13 address bits, so the
                    # image also appears at 6000h; FROGGER.ROM jumps there and
                    # showed a black screen when only 4000h was loaded.
                    if len(buf) == 0x2000:
                        buf = buf + buf
                    header = build_rom_header(MAPPER_PLAIN, 0, 0, len(buf))
                else:
                    if dbinfo:
                        mapper_type, bank_size_kb = dbinfo[1]
                    else:
                        mapper_type, bank_size_kb = detect_mapper(buf)
                        print(
                            f"{filename}: not in the ROM database - "
                            f"detected mapper type {mapper_type}"
                        )
                    if mapper_type is not None and msx_handlers:
                        buf, npatch = patch_for_msx(
                            buf, mapper_type, msx_handlers, msx_slot_handlers
                        )
                        print(
                            f"{filename}: patched {npatch} bank-switch sites "
                            f"server-side"
                        )
                    if mapper_type is None:
                        return reject(
                            f"{filename} ({len(buf)} bytes): unrecognized "
                            f"mapper - not supported yet."
                        )
                    if len(buf) > ROM_MAX_SIZE:
                        return reject(
                            f"{filename} ({len(buf)} bytes) exceeds the "
                            f"{ROM_MAX_SIZE} byte cap."
                        )
                    # Rounded up: a patched ROM may end part-way into its last
                    # bank (ARCTIC_MSXPI.ROM is 128KB + an 8KB runtime) rather
                    # than being padded to a power of two. The MSX allocates
                    # whole banks but receives only total_size bytes.
                    bank_bytes = bank_size_kb * 1024
                    bank_count = (len(buf) + bank_bytes - 1) // bank_bytes
                    print(
                        f"{filename}: detected mapper type {mapper_type}, "
                        f"{bank_size_kb}KB banks, {bank_count} banks"
                    )
                    # Refuse a ROM the MSX has no room for BEFORE sending it:
                    # the MSX used to find out only after the header, print its
                    # error and stop while this side was still waiting to send
                    # the image, and both hung. Storage is one 16K segment per
                    # 16K bank or per two 8K banks, plus msxarch's two exec
                    # segments and safe zone (MAPPER_WORK_SEGMENTS in msxarch.c).
                    if msx_free_segments is not None:
                        storage = (
                            bank_count if bank_size_kb == 16 else (bank_count + 1) // 2
                        )
                        need = storage + 3
                        if msx_free_segments < need:
                            return reject(
                                f"{filename}: not enough RAM - needs "
                                f"{need * 16}KB ({need} segments), the "
                                f"MSX has {msx_free_segments * 16}KB free."
                            )
                    header = build_rom_header(
                        mapper_type, bank_size_kb, bank_count, len(buf)
                    )

                # The file name follows the header so the MSX can show what
                # it is loading; a client that does not use it ignores it,
                # like the reason text of a rejection.
                name = filename.encode("ascii", "replace")[:64]
                rc = sendmultiblock(header + name)
                if rc != RC_SUCCESS:
                    return rc
                rc = sendmultiblock(buf)
                return RC_SUCCESS

            rc = senddata(RC_SUCCESS, text.encode().ljust(PAGESIZE, b"\x00"))

    finally:
        transport.DISABLETIMEOUT = False  # Restore timeout setting
