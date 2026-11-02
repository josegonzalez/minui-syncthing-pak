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

### Syncthing version

The `Syncthing version` setting chooses between Syncthing 2.x, the default, and
Syncthing 1.x.

Syncthing 2.x keeps its index in an SQLite database, and SQLite cannot run on a
FAT filesystem. MinUI and NextUI require the card to be exFAT or FAT32, so on
`h700` Syncthing 2.x reports `disk I/O error: input/output error` every few
seconds, and each failure drops a peer connection. Selecting `1.x` avoids this:
Syncthing 1.x keeps its index in LevelDB, which is unaffected. The pak shows a
note on `h700` while 2.x is selected.

Other platforms are less affected. On `tg5040` Syncthing 2.x produces no errors
in testing; its index journal simply never consolidates, so the database grows
larger than it should.

Worth knowing before switching:

- **Switching to 1.x costs a rescan. Switching back does not.** Syncthing 1.x
  cannot read 2.x's SQLite index, so it builds its own from scratch and
  re-exchanges index data with every peer; expect that to take a while over
  handheld WiFi. In the other direction Syncthing 2.x migrates the 1.x index
  itself, which on an h700 with 510 files took under a second with no rescan and
  no re-exchange. It leaves the old index behind as `index-v0.14.0.db-migrated`,
  which is safe to delete. Your device ID does not change either way and no peer
  needs re-approving.
- **Switching to 1.x rewrites `config.xml` and can drop settings.** The two
  versions know different configuration options, so 1.x re-saves the file through
  its own schema. The version number is left alone rather than converted, but
  options that exist only in 2.x are dropped, and options 2.x had retired come
  back at their defaults. Switching from 2.1.7 to 1.30.0 removed `pullerDelayS`
  and `blockIndexing` from each folder along with `sessionCookieDurationS` and
  `sessionCookiePath`, and added `disableTempIndexes`, `weakHashThresholdPct`,
  `urPostInsecurely`, `cacheIgnoredFiles` and `databaseTuning`. Your folders,
  devices and paths are not touched. Switching back to 2.x does not undo this:
  the file is left exactly as 1.x wrote it and the dropped options simply take
  their defaults. The original is kept beside it as `config.xml.v52`, which is
  the only way back to a 2.x-only value you had set deliberately.
- **Syncthing 1.x is no longer maintained.** v1.30.0, from July 2025, is the final
  1.x release and will receive no further fixes, including security fixes. It
  remains protocol compatible with 2.x, so it still syncs with up-to-date peers.

### Debug Logging

Debug logs are written to the`$SDCARD_PATH/.userdata/$PLATFORM/logs/` folder.

## Development

- `make build` downloads the bundled binaries for every platform.
- `make test` runs the [bats](https://github.com/bats-core/bats-core) suite in `tests/`.

Both Syncthing versions are bundled: 2.x in `bin/<arch>/syncthing` and 1.x in
`bin/v1/<arch>/syncthing`. The 1.x build keeps the same filename deliberately, so
the running process is still called `syncthing` and `bin/service-off` can stop it
with `killall`, which matches process names exactly. The 1.x pin is final, because
v1.30.0 is the last release of that line.

A scheduled workflow opens a pull request when Syncthing publishes a new stable release, named and laid out like the dependabot pull requests for GitHub Actions. Each release gets its own `deps/github_releases/syncthing/syncthing-<version>` branch, an older open bump is closed as superseded by the newer one, and a bump closed without merging is not reopened. The workflow needs a `GH_ACCESS_TOKEN` repository secret with read and write access to contents and pull requests. Without it, the default workflow token can only open pull requests when "Allow GitHub Actions to create and approve pull requests" is enabled in the repository's Actions settings, and the pull requests it opens do not trigger CI.
