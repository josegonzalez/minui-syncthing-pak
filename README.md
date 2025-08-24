# minui-syncthing.pak

A MinUI app wrapping [`syncthing`](https://syncthing.net/), a continuous file synchronization program.

> [!NOTE]
> This pak does not rename files on disk before or after syncing, and cannot be used
> as a compatibility layer between MinUI and Retroarch-compatible handhelds. Files
> are synced as written to disk by other tools.

## Requirements

This pak is designed and tested on the following MinUI Platforms and devices:

- `miyoomini`: Miyoo Mini Plus (_not_ the Miyoo Mini)
- `my282`: Miyoo A30
- `my355`: Miyoo Flip
- `tg5040`: Trimui Brick (formerly `tg3040`), Trimui Smart Pro
- `rg35xxplus`: RG-35XX Plus, RG-34XX, RG-35XX H, RG-35XX SP

Use the correct platform for your device.

## Installation

1. Mount your TrimUI Brick SD card.
2. Download the latest release from Github. It will be named `Syncthing.pak.zip`.
3. Copy the zip file to `/Tools/$PLATFORM/Syncthing.pak.zip`.
4. Extract the zip in place, then delete the zip file.
5. Confirm that there is a `/Tools/$PLATFORM/Syncthing.pak/launch.sh` file on your SD card.
6. Unmount your SD Card and insert it into your TrimUI Brick.

## Usage

Browse to `Tools > Syncthing` and press `A` to turn on the syncthing server.

This pak runs on port 8384 (HTTP UI).

The default credentials are:

- `minui:minui`

### Debug Logging

Debug logs are written to the`$SDCARD_PATH/.userdata/$PLATFORM/logs/` folder.
