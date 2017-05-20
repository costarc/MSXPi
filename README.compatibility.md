Compatibility Notes
-------------------

General notes:
1. If your MSX starts booting from MSXPi and hang, try pressing RESET. I noticed that in some situations, such as using a MegaFlashRom made with a SCC, the MSXPi won't boot form a cold start. After RESET, it will boot.
2. You can also try boot the MSX with Control key pressed. This will reduce number of drives available when using MSXPi in MSX systems that contain a disk drive, or has another IDE interface connected.
3. When using the MSXPi ROM in a MegaFlashRom (MFR), it behaves differently depending on the MFR. for example, using a SCC MFR (custom built), and booting from Turbor R, I got 2 x MSXPi drives (A,B) and (C,D) from the TurboR internal drives. When boot form MegaFlashRom-SD-SCC+, I got 4 MSXPi drives (A,B,C,D being two of them phamtom drives) plus one MFR-SD-SCC+ drive (the ROM drive, and the SD is not available). 
4. EXECROM does not work properly on release v0.8.1. Loadrom does, I don't know the reason. For example, I can run Metal Gear Solid using loadrom, but EXECROM will hang after download 1/4 of the game. Use what ever works for you.
