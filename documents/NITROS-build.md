# Build NitrOS-9 for MSX guest images

This builds the host runtime. It does not install the MSXPi server, XRoar,
openMSX or CoCo ROMs. See [NITROS-Users-Guide.md](NITROS-Users-Guide.md)
for Windows, Linux and Raspberry Pi installation.

## Build on Linux, Windows with WSL, or Raspberry Pi OS

Use a recent NitrOS-9 source tree with its supported `coco/dw` recipe and
these tools on `PATH`: `make`, LWTOOLS (`lwasm`, `lwlink`, `lwar`) and
ToolShed (`os9`). Build commands in this guide are for Ubuntu/Debian, including
Ubuntu 24.04 under WSL:

```sh
sudo apt update
sudo apt install build-essential git make
```

Install LWTOOLS and ToolShed using their upstream build instructions and add
their `lwasm`, `lwlink`, `lwar` and `os9` programs to `PATH`. The recipes and
versions tested for this port are NitrOS-9 commit
`f470fa52eb172b59b22c1b722074998cb42de9b1`, LWTOOLS 4.24 and ToolShed 2.6.1.

Clone NitrOS-9 and check out the tested source revision:

```sh
mkdir -p ~/src
cd ~/src
git clone https://github.com/nitros9project/nitros9.git
cd nitros9
git checkout f470fa52eb172b59b22c1b722074998cb42de9b1
```

From the MSXPi checkout, run the image build script. The output directory
must be new; the script refuses to overwrite it. The script runs `make clean`
in the NitrOS-9 `recipes/coco/dw` folder, so use a dedicated NitrOS-9 checkout
if you also keep active builds there.

```sh
export NITROS9DIR="$HOME/src/nitros9"
/path/to/MSXPi/software/nitros/build-image.sh "$HOME/msxpi/nitros"
```

The output folder contains:

| File | Purpose |
|---|---|
| `boot.bin` | XRoar's direct boot-track loader input |
| `boot.dsk` | Writable NitrOS-9 system disk (`/dd`) |
| `exchange.dsk` | Writable OS-9 transfer disk (`/x1`) |
| `msxexit` | Guest command to end the emulator session |
| `files/` | Host staging directory for `NITROS put/get/list` |

Copy `NITROS.COM` from `software/target` to the emulated MSX-DOS disk or
physical MSX-DOS volume. The runtime package includes a prebuilt `NITROS.COM`.
The sample `nitros.json` is in the package and in `software/nitros`.
The running MSXPi server reads its location from `NITROS_CONFIG` in
`msxpi.ini`; set it from the MSX-DOS prompt with
`p set NITROS_CONFIG /home/pi/msxpi/nitros/nitros.json` (use the actual
absolute path on your host). This setting is saved by the normal `p set`
command and does not require a shell environment variable.

### Windows build notes

Run the image build inside Ubuntu 24.04 WSL; Windows-native image building is
not part of this recipe. Install LWTOOLS and ToolShed inside WSL, clone both
repositories in the WSL Linux filesystem (for example, under `~/src`), then
pass an output directory under `/mnt/c/Users/<you>/...` if you want the images
on a Windows folder. WSL path names belong in the Linux shell command.
Windows XRoar and ToolShed paths belong in `nitros.json` when the runtime is
later used by the Windows MSXPi server.

### ROM files

XRoar's `coco2bus` machine needs three CoCo ROMs: `bas13.rom`, `extbas11.rom`
and `disk11.rom`. The NitrOS-9 source and runtime package do not include them.
Place user-supplied ROMs in the folder configured with XRoar's `-rompath`.
XRoar reports a missing or unrecognized ROM in the configured log file.

The runtime package is made from this recipe; it includes the output image
files, the exit command, `NITROS.COM` and a starter JSON configuration, but
never includes CoCo ROMs. Rebuild images into a new directory if you want a
clean guest disk; copy files aside first if you need to retain guest changes.

### Console regression tests (Ubuntu 24.04 WSL)

After building `software/target/nitros.com`, run these from the repository root.
Use a Linux runtime configuration with absolute XRoar, ROM and boot-loader
paths. The emulator tests copy the guest disks to temporary directories.

```sh
python3 -m unittest discover -s software/Server/Python/tests -p test_nitros.py
python3 software/Server/Python/tests/nitros_xroar.py /path/to/nitros.json
xvfb-run -a python3 software/Server/Python/tests/nitros_openmsx.py /path/to/nitros.json openmsx esc
xvfb-run -a python3 software/Server/Python/tests/nitros_openmsx.py /path/to/nitros.json openmsx guest
```

The openMSX tests require its MSXPi device extension and the Panasonic
FS-A1WSX machine ROMs. They launch the built MSX executable, submit `dir` and
`echo` with Enter, inspect VDP output, and check that ESC or guest `msxexit`
closes XRoar. Server-only tests cannot detect a client stuck before it sends
a command. In particular, BIOS output through CALSLT must restore interrupts
before the client waits for the interrupt-driven JIFFY clock.
