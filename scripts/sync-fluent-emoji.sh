#!/usr/bin/env bash

set -euo pipefail

readonly UPSTREAM_REPOSITORY="https://github.com/microsoft/fluentui-emoji"
readonly UPSTREAM_COMMIT="62ecdc0d7ca5c6df32148c169556bc8d3782fca4"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cache_root="${FLUENT_EMOJI_CACHE_DIR:-${repo_root}/.vendor-cache/microsoft-fluent-emoji}"
selection_root="${repo_root}/vendor/microsoft-fluent-emoji"
selection_file="${selection_root}/selection.tsv"
selected_root="${cache_root}/selected"
public_license_root="${repo_root}/src/licenses/microsoft-fluent-emoji"

download_catalog() {
  local temporary_root
  local archive_path
  local extracted_root

  temporary_root="$(mktemp -d "${TMPDIR:-/tmp}/fluent-emoji.XXXXXX")"
  archive_path="${temporary_root}/fluent-emoji.tar.gz"
  extracted_root="${temporary_root}/fluentui-emoji-${UPSTREAM_COMMIT}"
  trap 'rm -rf "${temporary_root}"' RETURN

  curl --fail --location --silent --show-error \
    "${UPSTREAM_REPOSITORY}/archive/${UPSTREAM_COMMIT}.tar.gz" \
    --output "${archive_path}"
  tar -xzf "${archive_path}" -C "${temporary_root}"

  mkdir -p "${cache_root}"
  rsync -a --delete "${extracted_root}/assets/" "${cache_root}/assets/"
  cp "${extracted_root}/LICENSE" "${cache_root}/LICENSE"
  printf '%s\n' "${UPSTREAM_COMMIT}" > "${cache_root}/UPSTREAM_COMMIT"
}

if [[ ! -d "${cache_root}/assets" ]] || \
   [[ ! -f "${cache_root}/UPSTREAM_COMMIT" ]] || \
   [[ "$(<"${cache_root}/UPSTREAM_COMMIT")" != "${UPSTREAM_COMMIT}" ]]; then
  download_catalog
fi

mkdir -p "${selected_root}"
find "${selected_root}" -type f -name '*.svg' -delete

while IFS=$'\t' read -r role_id upstream_path; do
  [[ -z "${role_id}" || "${role_id}" == \#* ]] && continue

  source_path="${cache_root}/assets/${upstream_path}"
  destination_path="${selected_root}/${role_id}.svg"
  if [[ ! -f "${source_path}" ]]; then
    printf 'Missing upstream asset: %s\n' "${source_path}" >&2
    exit 1
  fi
  cp "${source_path}" "${destination_path}"
done < "${selection_file}"

mkdir -p "${public_license_root}"
cp "${cache_root}/LICENSE" "${public_license_root}/LICENSE"

printf 'Fluent Emoji cache: %s\n' "${cache_root}"
printf 'Selected SVGs: %s\n' "$(find "${selected_root}" -type f -name '*.svg' | wc -l | tr -d ' ')"
