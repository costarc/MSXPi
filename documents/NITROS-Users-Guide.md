# NitrOS-9 for MSX User Guide

NitrOS-9 for MSX lets you use an MSX as the keyboard and screen for NitrOS-9, the
6809 operating system running in the XRoar CoCo emulator. The host computer
runs XRoar and the MSXPi server. The server starts XRoar only when you run
`NITROS` on the MSX and closes it when you press ESC, run `msxexit` in the
NitrOS-9 shell, or lose the MSX connection.

The MSX display shows a text shell. This is a terminal session, not a CoCo
graphics display. The guest system disk and a second exchange disk are held
on the host. You can copy files between the guest disk and the MSX through
the host staging directory.

## Choose how to run it

| Setup | What runs where | Needs MSXPi hardware? |
|---|---|---|
| Windows | MSXPi server, XRoar and the virtual MSX in openMSX run on Windows | No |
| Linux | MSXPi server, XRoar and openMSX run on Linux | No |
| Real MSX | MSXPi server and XRoar run on a Raspberry Pi connected to the MSXPi interface | Yes |

The Windows and Linux setups are useful for trying NitrOS-9 for MSX with an
emulated MSX. The virtual MSX uses the MSXPi device supplied with openMSX.
The hardware setup connects an actual MSX keyboard and VDP to the Pi through
the MSXPi board. A PC running Windows or Linux cannot replace that GPIO
connection to a physical MSX.

## Prepare the NitrOS-9 for MSX files

The MSX-DOS client is `NITROS.COM`. The host files are `boot.bin`, `boot.dsk`,
`exchange.dsk`, the `files` staging folder, and `nitros.json`. You can use the
[prebuilt runtime package](../../outputs/nitros-msx-runtime.zip), or build a
new runtime using the [image build instructions](NITROS-build.md). Copy the
runtime files to a new host folder. Keep `boot.dsk` and `exchange.dsk`
writable; NitrOS-9 updates the system disk as it runs.

You also need XRoar and the CoCo ROM files `bas13.rom`, `extbas11.rom` and
`disk11.rom`. These firmware images are not included. Use ROMs you are
entitled to use. NitrOS-9 itself is open source and its upstream project is
linked below.

Edit `nitros.json` for the computer that will run XRoar. Set `xroar` to an
argument list for your XRoar executable, the CoCo ROM folder, and the **full
path** to `boot.bin`. Set `boot_disk`, `exchange_disk`, `exchange_dir` and
`os9` to the actual runtime files and ToolShed `os9` utility. Relative disk
and staging paths are resolved beside `nitros.json`; paths inside the `xroar`
argument list must be absolute. For example, the sample is configured for a
Raspberry Pi. Replace its executable, ROM and boot paths when using Windows or
Linux.

Do not add `boot.dsk` or `exchange.dsk` as XRoar disk images. XRoar boots from
`boot.bin` and the MSXPi server presents both images to the guest over its
DriveWire connection.

## Windows: emulated MSX with openMSX

This setup runs the MSXPi server, openMSX and XRoar on the Windows PC. It is a
software test setup and does not attach to a physical MSXPi board.

1. Install the MSXPi openMSX package from the repository's
   [Windows setup script](../Server/Setup/msxpi-windows-setup.ps1). It installs
   Python, the MSXPi server and the project's MSXPi-enabled openMSX build.
   From PowerShell in the project, run `powershell -ExecutionPolicy Bypass
   -File .\software\Server\Setup\msxpi-windows-setup.ps1`. The setup script
   keeps its server under `C:\home\pi\msxpi` by default. The
   project's current main README has the complete first-time setup and
   network-option steps.
2. Install [XRoar for Windows](https://www.6809.org.uk/xroar/dl/) and ToolShed. Install or copy the three CoCo
   ROM images into a known folder. Extract the NitrOS-9 for MSX runtime files into,
   for example, `C:\home\pi\msxpi\nitros`.
3. Edit `C:\home\pi\msxpi\nitros\nitros.json`. Example values are
   `C:\Apps\XRoar\xroar.exe`, `C:\Apps\CoCoROMs`,
   `C:\home\pi\msxpi\nitros\boot.bin`, and
   `C:\Apps\ToolShed\os9.exe`. In JSON strings, write each backslash twice,
   for example `C:\\Apps\\XRoar\\xroar.exe`.
4. Copy `NITROS.COM` to a DOS drive in the openMSX emulated MSX. Start the
   `start-openmsx.bat` shortcut created by the installer. At the MSX-DOS
   prompt, set the runtime path in the host's `msxpi.ini` by typing
   `p set NITROS_CONFIG C:\home\pi\msxpi\nitros\nitros.json`. Then type
   `NITROS`.

The `C:\Apps\LibreOffice` install is not needed to run NitrOS-9 for MSX; use it to
open or print this guide. XRoar runs without a visible window during the MSX
session. It writes diagnostics to `xroar.log` beside the configured log file.

## Linux: emulated MSX with openMSX

These instructions are for Debian or Ubuntu. Install openMSX, XRoar, Python,
and ToolShed. The [XRoar manual](https://www.6809.org.uk/xroar/doc/xroar.shtml)
lists Linux installation options; on supported apt setups XRoar can be
installed with `sudo apt install xroar`.

1. Install the project's MSXPi openMSX build and configure the virtual MSX
   using the [MSXPi Windows and openMSX instructions](../../README.md#quick-start-2---openmsx-no-hardware-needed)
   or your Linux openMSX package. Put `NITROS.COM` on its DOS disk.
2. Extract the runtime files to a writable folder such as
   `~/msxpi/nitros/`. Install CoCo ROMs in `~/.xroar/roms/`, or use another
   ROM folder in your JSON configuration.
3. Edit `nitros.json`: set the Linux XRoar executable (often `xroar`), ROM
   folder, full path to `boot.bin`, and the path to the `os9` utility.
4. Start the MSXPi server from the MSXPi Python source directory:

   ```sh
   python3 -u msxpi-server.py
   ```

   Keep this process running while using the virtual MSX. In its MSX-DOS
   prompt, type `p set NITROS_CONFIG /home/pi/msxpi/nitros/nitros.json`
   (substitute the actual full Linux path if different); this saves the path
   in the server's `msxpi.ini`. The openMSX MSXPi
   device connects to its TCP server on port 5000 by default. Start openMSX
   with the MSXPi extension and boot its MSX-DOS disk.
5. At the emulated MSX-DOS prompt, type `NITROS`. Press ESC to leave the
   guest and return to MSX-DOS.

## Real MSX hardware: Raspberry Pi

For a physical MSX, the Raspberry Pi must be connected to the MSX through a
compatible MSXPi interface. Use a Raspberry Pi Zero W or Zero 2 W with a
40-pin header that matches the board. The Pi provides the MSXPi server, XRoar,
the disk images and the files staging folder. The existing MSXPi setup guide
in the [main README](../../README.md#quick-start-1---real-hardware-msxpi-interface--raspberry-pi)
covers Raspberry Pi OS, board programming, ROM installation, jumper settings
and initial hardware checks. Complete those steps before installing the
NitrOS-9 for MSX files below.

1. Install Raspberry Pi OS and the MSXPi software on the Pi. Confirm the
   MSXPi interface works with the existing `pver` command before adding
   NitrOS-9 for MSX.
2. Install XRoar with Becker-port support, ToolShed's `os9` tools, LWTOOLS
   and `make`. The [NitrOS-9 for MSX image build instructions](NITROS-build.md)
   list the tested versions and build command. CoCo ROM images must be supplied
   separately.
3. Copy `boot.bin`, `boot.dsk`, `exchange.dsk`, `files/` and the sample JSON
   into `/home/pi/msxpi/nitros/`. Edit `nitros.json` with the paths on the Pi.
   The default example uses `/home/pi/msxpi/nitros/` and
   `/home/pi/roms/coco/`.
4. Install the new `msxpi_nitros.py` module with the updated MSXPi server. In
   the MSX-DOS prompt, type `p set NITROS_CONFIG
   /home/pi/msxpi/nitros/nitros.json`. This stores the runtime path in the
   server's `msxpi.ini`; no service environment change or restart is needed.
   The setup and update scripts in this branch already include the new module.
5. Copy `NITROS.COM` to an MSX-DOS disk or Nextor volume. Insert the MSXPi
   interface and start the Pi. After the MSXPi ready indicator is active, run
   `NITROS` on the physical MSX.

XRoar starts only after the MSX sends the `nitros start` command. It listens
for the DriveWire connection on the Pi's loopback interface, so the Becker
port is not exposed to the LAN. Keep the Pi running while NitrOS-9 is open.

## Using the console

At the MSX-DOS prompt, run:

```text
A> NITROS
```

The shell prompt appears on the MSX screen. Type NitrOS-9 commands as usual.
The shell echoes typed characters and handles line editing. The MSX keyboard
sends ordinary text and Enter to the guest. Press **ESC** to close XRoar and
return to MSX-DOS. Ctrl-C goes to NitrOS-9; it does not close the emulator.

To exit from inside NitrOS-9, type:

```text
OS9: msxexit
```

Use `msxexit` rather than `ex`: `ex` exits the current shell and the NitrOS-9
startup normally opens another one. If the MSX resets or loses its link,
XRoar exits after the 15-second console lease expires. Run `NITROS stop` from
MSX-DOS to recover a session that has stopped responding.

## Move files between the MSX and NitrOS-9

There are two steps in each direction: PCOPY moves a file between the MSX and
the host staging folder; a NITROS subcommand copies it between that folder
and the guest exchange disk. The examples use MSX 8.3 filenames and
`/home/pi/msxpi/nitros/files` as the host staging folder. Change the host path
to match `exchange_dir` in your `nitros.json`.

**MSX to NitrOS-9:**

```text
A> PCOPY A:HELLO.TXT /home/pi/msxpi/nitros/files/HELLO.TXT
A> NITROS put HELLO.TXT HELLO.TXT
A> NITROS
OS9: dir /x1
OS9: copy /x1/HELLO.TXT /x1/HELLO.BAK
OS9: msxexit
A> NITROS get HELLO.BAK HELLO.BAK
A> PCOPY /home/pi/msxpi/nitros/files/HELLO.BAK A:HELLO.BAK
```

**Host to NitrOS-9:** put the file in the configured `files` folder, exit
NitrOS-9 if it is running, then type `NITROS put HOSTNAME GUESTNAME`. Inside
the shell, guest files live on `/x1`. Copy them to `/dd` if you want them on
the persistent boot disk.

`NITROS list` shows files on the exchange disk. If the listing is long, use
the next `NITROS list N` command printed at the end. Exports refuse to
overwrite a file already in the host staging folder; remove or rename that
file before copying a replacement. The bridge locks the images while XRoar
is running and releases them when the session ends, so do file transfers
while NitrOS-9 is stopped.

## Troubleshooting

| Symptom | What to check |
|---|---|
| `NITROS` says MSXPi connection error | Start the MSXPi server, check `p set NITROS_CONFIG` and verify that the emulator's MSXPi device is connected or the physical MSXPi ready indicator is active. |
| XRoar reports a missing ROM | Check all three CoCo ROMs and the `-rompath` in `nitros.json`. |
| NitrOS-9 stops while opening a disk | Check the disk paths and write permissions; close any other process that has mounted the disk images. |
| XRoar will not start on Linux | Check the `xroar` command and Becker-port support. Confirm the configured `-run` path points to `boot.bin`. |
| ESC was not pressed and the MSX restarted | Wait for the 15-second lease to close XRoar, then launch `NITROS` again. |
| Copy says the guest disk is busy | Exit NitrOS-9 completely with `msxexit` or ESC, then repeat the host file transfer. |

## Build the guest images from source

See [NITROS-build.md](NITROS-build.md) for the pinned NitrOS-9 checkout,
image creation command and runtime layout. The historical
[NitrOS-9 SourceForge releases](https://sourceforge.net/projects/nitros9/files/releases/)
are useful project archives; the tested disk recipe builds from the current
NitrOS-9 source instead.

## References

- [MSXPi project and real-hardware/openMSX setup](../../README.md)
- [MSXPi Windows setup script](../Server/Setup/msxpi-windows-setup.ps1)
- [XRoar Windows and Linux downloads](https://www.6809.org.uk/xroar/dl/)
- [XRoar manual](https://www.6809.org.uk/xroar/doc/xroar.shtml)
- [NitrOS-9 project](https://github.com/nitros9project/nitros9)
- [NitrOS-9 historical releases](https://sourceforge.net/projects/nitros9/files/releases/)
