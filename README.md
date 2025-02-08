# minui-syncthing.pak

A MinUI app wrapping [`syncthing`](https://syncthing.net/), a continuous file synchronization program.

## Requirements

This pak is designed and tested on the following MinUI Platforms and devices:

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

To enable debug logging, create a file named `debug` in the pak folder. Logs will be written to the `$SDCARD_PATH/.userdata/$PLATFORM/logs/` folder.
