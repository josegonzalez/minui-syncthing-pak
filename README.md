# minui-syncthing.pak

A MinUI app wrapping [`syncthing`](https://syncthing.net/), a continuous file synchronization program.

> [!NOTE]
> This pak does not rename files on disk before or after syncing, and cannot be used
> as a compatibility layer between MinUI and Retroarch-compatible handhelds. Files
> are synced as written to disk by other tools.

## Requirements

This pak is designed and tested on the following MinUI Platforms and devices:

- `h700`: Anbernic RG34XX, RG34XX SP, RG35XX Plus, RG35XX 2024, RG35XX H, RG35XX Pro, RG35XX SP, RG40XX H, RG40XX V, RG CubeXX and RG SP, running NextUI on BaseOS
- `miyoomini`: Miyoo Mini Plus (_not_ the Miyoo Mini)
- `my282`: Miyoo A30
- `my355`: Miyoo Flip
- `rg35xxplus`: RG-35XX Plus, RG-34XX, RG-35XX H, RG-35XX SP
- `tg5040`: Trimui Brick (formerly `tg3040`), Trimui Smart Pro
- `tg5050`: Trimui Smart Pro S

Use the correct platform for your device.

## Installation

1. Mount your device's SD card.
2. Download the latest release from Github. It will be named `Syncthing.pak.zip`.
3. Copy the zip file to `/Tools/$PLATFORM/Syncthing.pak.zip`.
4. Extract the zip in place, then delete the zip file.
5. Confirm that there is a `/Tools/$PLATFORM/Syncthing.pak/launch.sh` file on your SD card.
6. Unmount your SD Card and insert it into your device.

## Usage

Browse to `Tools > Syncthing` and press `A` to turn on the syncthing server.

This pak runs on port 8384 (HTTP UI).

The default credentials are:

- `minui:minui`

### Database Storage

Syncthing 2.x keeps its file index in SQLite, which requires a filesystem that can
host a write-ahead log and its shared-memory file. MinUI and NextUI require the SD
card to be exFAT or FAT32, and neither can provide that, so the pak keeps the
database on a small ext4 image instead, loop-mounted from
`$USERDATA_PATH/Syncthing/data.ext4` and created on first run. Configuration and the
device key stay on the card, so the device ID is unaffected.

Upgrading from a release that kept the database on the card costs one rescan, since
the old index is left where it is and a new one is built.

The image is a fixed 128 MB and cannot be grown in place. A full one makes SQLite
report the same `disk I/O error` as a filesystem it cannot use at all, so the pak
warns in its log when it starts with less than 16 MB free. Note that it only checks
at startup, so an image that fills during a session is reported on the next start.

Recovering means installing a pak built with a larger `DATA_IMAGE_SIZE`, deleting
`$USERDATA_PATH/Syncthing/data.ext4`, and then **rebooting the device** -- the
filesystem is left mounted while the device is up, so a deleted image stays in use
until reboot.

### Debug Logging

Debug logs are written to the`$SDCARD_PATH/.userdata/$PLATFORM/logs/` folder.

## Development

- `make build` downloads the bundled binaries for every platform and builds the
  empty ext4 database image. Requires `mkfs.ext4` from `e2fsprogs`; override the
  size with `make clean && make DATA_IMAGE_SIZE=256M build`, keeping it under 4G so
  it still fits on a FAT32-formatted card. The `clean` matters: the image target has
  no dependency on the size, so an existing `share/data.ext4.gz` would be packaged
  unchanged.
- `make test` runs the [bats](https://github.com/bats-core/bats-core) suite in `tests/`.

A scheduled workflow opens a pull request when Syncthing publishes a new stable release, named and laid out like the dependabot pull requests for GitHub Actions. Each release gets its own `deps/github_releases/syncthing/syncthing-<version>` branch, an older open bump is closed as superseded by the newer one, and a bump closed without merging is not reopened. The workflow needs a `GH_ACCESS_TOKEN` repository secret with read and write access to contents and pull requests. Without it, the default workflow token can only open pull requests when "Allow GitHub Actions to create and approve pull requests" is enabled in the repository's Actions settings, and the pull requests it opens do not trigger CI.
