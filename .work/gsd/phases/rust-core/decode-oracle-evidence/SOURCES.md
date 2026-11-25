# C4 oracle sources

- URL: https://github.com/darktable-org/darktable/releases/download/release-5.6.2/darktable-5.6.2-arm64.dmg
- File bytes: 88884896
- sha256: 6ff88e58a2a59cb07b0a1502fea7205e68cd783380a33a3ce7bda68ec29def0c
- Reported version (`darktable-cli --version`): darktable 5.6.2
- Mount: `hdiutil attach -nobrowse -readonly` -> /Volumes/darktable (deprecated-warning only, still works)
- CLI: /Volumes/darktable/darktable.app/Contents/MacOS/darktable-cli (121824 bytes)
- OpenCL device (via darktable-cltest): Apple Apple M4, OpenCL 1.2, init OK, kernels build 2.42 s
- Sample: 7RM5-LosslessCompressedLarge.ARW (Sony ILCE-7RM5, 85950464 bytes), copied to /tmp workdir; CC0 dir never written
- Prefs protection: `defaults export org.darktable .../org.darktable.before.plist` exit 0 BEFORE first run; domain exists on this machine (user has ~/.config/darktable). No `killall cfprefsd`. HOME + CFFIXED_USER_HOME isolated per leg.
