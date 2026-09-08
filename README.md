# HeyLingo IME data

This repository produces **data-only** Rime packages for HeyLingo's English and
Traditional Chinese keyboards.  It intentionally does not distribute executable
code: the iOS app embeds the reviewed `librime` binary, while this repository
downloads upstream source data, compiles it with `rime_deployer`, and publishes
the resulting tables as GitHub Release assets.

## Release assets

Each release contains these additive packages:

- `heylingo-rime-common.zip` — Rime presets and OpenCC conversion data.
- `heylingo-rime-en.zip` — English completion schema and dictionary.
- `heylingo-rime-zh-Hant.zip` — Bopomofo / Taiwan Traditional Chinese schema,
  dictionary, and compiled tables.
- `manifest.json` — release version, source commits, asset URLs, sizes, and
  SHA-256 hashes.  The iOS host app downloads this file first and verifies every
  archive before installing it into its App Group container.

The archives are merged into one Rime shared-data directory.  Install `common`
before either language archive.  Never let the keyboard extension download,
unzip, or mutate these assets; installation belongs to the containing app.

## Upstream inputs

The workflow deliberately resolves the current `master` commit for every input
at build time and records the exact commits in `manifest.json`:

- `rime/librime` — provides `rime_deployer` for offline compilation.
- `rime/rime-prelude` — common Rime presets.
- `rime/rime-bopomofo` — Traditional Chinese Zhuyin schemas.
- `rime/rime-terra-pinyin` and `rime/rime-essay` — Traditional Chinese
  dictionary data required by Bopomofo.
- `sdadonkey/rime-english` — English dictionary source only.  HeyLingo uses its
  own small standard-Rime schema in `config/` so the first release has no Lua
  runtime dependency.

## Publishing

Run **Actions → Build and publish IME data → Run workflow**.  A scheduled run
also checks upstream every Monday.  The workflow only creates a release after a
successful build and writes immutable checksums to the manifest.

For an iOS product that downloads assets without GitHub authentication, this
repository must be public: GitHub Release downloads from a private repository
require credentials, which cannot be safely embedded in an app.
