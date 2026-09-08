#!/usr/bin/env bash
set -euo pipefail

# Build data on CI only.  The resulting archives contain data/tables, never the
# compiler or librime executable.  Required: bash, git, cmake, rime_deployer,
# OpenCC data files, sha256sum, zip, jq.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="${ROOT}/.work"
SOURCE="${WORK}/source"
SHARED="${WORK}/shared"
USER_DATA="${WORK}/user"
STAGING="${WORK}/staging"
DIST="${ROOT}/dist"
RIME_DEPLOYER="${WORK}/librime-build/bin/rime_deployer"

rm -rf "${WORK}" "${DIST}"
mkdir -p "${SOURCE}" "${SHARED}" "${USER_DATA}" "${STAGING}" "${DIST}"

clone_master() {
  local name="$1"
  local url="$2"
  git clone --depth 1 "${url}" "${SOURCE}/${name}"
  git -C "${SOURCE}/${name}" rev-parse HEAD > "${WORK}/${name}.commit"
}

clone_master librime https://github.com/rime/librime.git
clone_master rime-prelude https://github.com/rime/rime-prelude.git
clone_master rime-bopomofo https://github.com/rime/rime-bopomofo.git
clone_master rime-terra-pinyin https://github.com/rime/rime-terra-pinyin.git
clone_master rime-essay https://github.com/rime/rime-essay.git
clone_master rime-english https://github.com/sdadonkey/rime-english.git

cmake -S "${SOURCE}/librime" -B "${WORK}/librime-build" \
  -DBUILD_SHARED_LIBS=ON -DBUILD_TEST=OFF -DBUILD_MERGED_PLUGINS=OFF
cmake --build "${WORK}/librime-build" --target rime_deployer --parallel 2

# Shared presets and all source files needed by the compiled schemas.  Do not
# copy repository metadata into a client package.
rsync -a --exclude='.git' "${SOURCE}/rime-prelude/" "${SHARED}/"
rsync -a --exclude='.git' "${SOURCE}/rime-bopomofo/" "${SHARED}/"
rsync -a --exclude='.git' "${SOURCE}/rime-terra-pinyin/" "${SHARED}/"
rsync -a --exclude='.git' "${SOURCE}/rime-essay/" "${SHARED}/"
cp "${SOURCE}/rime-english/english.dict.yaml" "${SHARED}/english.dict.yaml"
cp "${ROOT}/config/heylingo_english.schema.yaml" "${SHARED}/heylingo_english.schema.yaml"

# OpenCC config files refer to sibling dictionary files.  Keep their directory
# layout intact so librime can resolve traditional-character conversions.
mkdir -p "${SHARED}/opencc"
cp -R /usr/share/opencc/. "${SHARED}/opencc/"

"${RIME_DEPLOYER}" --compile "${SHARED}/bopomofo_tw.schema.yaml" "${USER_DATA}" "${SHARED}" "${STAGING}"
"${RIME_DEPLOYER}" --compile "${SHARED}/heylingo_english.schema.yaml" "${USER_DATA}" "${SHARED}" "${STAGING}"

copy_data() {
  local from="$1"
  local to="$2"
  mkdir -p "${to}"
  rsync -a --exclude='.git' "${from}/" "${to}/"
}

make_archive() {
  local name="$1"
  shift
  local package_dir="${WORK}/package-${name}"
  mkdir -p "${package_dir}"
  for path in "$@"; do
    shopt -s nullglob
    local matches=("${SHARED}"/${path})
    shopt -u nullglob
    for source_path in "${matches[@]}"; do
      local relative_path="${source_path#"${SHARED}/"}"
      mkdir -p "${package_dir}/$(dirname "${relative_path}")"
      cp -R "${source_path}" "${package_dir}/${relative_path}"
    done
  done
  (cd "${package_dir}" && zip -qr "${DIST}/heylingo-rime-${name}.zip" .)
}

# Packages are additive: the app installs common first, followed by the active
# language package, into one atomically swapped shared-data directory.
# Keep the packages additive.  Common is copied from the prelude source since
# it also contains the stroke lookup data required by the Bopomofo schema.
COMMON_PACKAGE="${WORK}/package-common"
copy_data "${SOURCE}/rime-prelude" "${COMMON_PACKAGE}"
mkdir -p "${COMMON_PACKAGE}/opencc"
cp -R "${SHARED}/opencc/." "${COMMON_PACKAGE}/opencc/"
(cd "${COMMON_PACKAGE}" && zip -qr "${DIST}/heylingo-rime-common.zip" .)

make_archive en heylingo_english.schema.yaml english.dict.yaml build/heylingo_english.*
ZH_HANT_PACKAGE="${WORK}/package-zh-Hant"
copy_data "${SOURCE}/rime-bopomofo" "${ZH_HANT_PACKAGE}"
copy_data "${SOURCE}/rime-terra-pinyin" "${ZH_HANT_PACKAGE}"
copy_data "${SOURCE}/rime-essay" "${ZH_HANT_PACKAGE}"
mkdir -p "${ZH_HANT_PACKAGE}/build"
find "${SHARED}/build" -maxdepth 1 -type f \( -name 'bopomofo_tw.*' -o -name 'terra_pinyin.*' \) -exec cp {} "${ZH_HANT_PACKAGE}/build/" \;
(cd "${ZH_HANT_PACKAGE}" && zip -qr "${DIST}/heylingo-rime-zh-Hant.zip" .)

jq -n \
  --arg generated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg librime "$(<"${WORK}/librime.commit")" \
  --arg prelude "$(<"${WORK}/rime-prelude.commit")" \
  --arg bopomofo "$(<"${WORK}/rime-bopomofo.commit")" \
  --arg terra_pinyin "$(<"${WORK}/rime-terra-pinyin.commit")" \
  --arg essay "$(<"${WORK}/rime-essay.commit")" \
  --arg english "$(<"${WORK}/rime-english.commit")" \
  '{format: 1, generatedAt: $generated_at, sources: {librime: $librime, rimePrelude: $prelude, rimeBopomofo: $bopomofo, rimeTerraPinyin: $terra_pinyin, rimeEssay: $essay, rimeEnglish: $english}, assets: []}' \
  > "${DIST}/manifest.json"

for archive in "${DIST}"/*.zip; do
  name="$(basename "${archive}")"
  sha="$(sha256sum "${archive}" | awk '{print $1}')"
  size="$(stat --printf='%s' "${archive}")"
  tmp_manifest="${DIST}/manifest.next.json"
  jq --arg name "${name}" --arg sha "${sha}" --argjson size "${size}" \
    '.assets += [{name: $name, sha256: $sha, size: $size}]' \
    "${DIST}/manifest.json" > "${tmp_manifest}"
  mv "${tmp_manifest}" "${DIST}/manifest.json"
done

jq -e . "${DIST}/manifest.json" >/dev/null
