#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
RELEASE_DIR="${ROOT_DIR}/RELEASE"
CARGO_TOML="${ROOT_DIR}/Cargo.toml"

GUI_BIN_SRC="${ROOT_DIR}/target/release/debian-nvidia-all-gui"
CLI_SRC="${ROOT_DIR}/debian-nvidia-all-cli.sh"
TUI_SRC="${ROOT_DIR}/debian-nvidia-all-tui.sh"
BOOTSTRAP_SRC="${ROOT_DIR}/packaging/nvidia-debian-all"
PACSCRIPT_SRC="${ROOT_DIR}/pacscript"

if [[ ! -f "${CARGO_TOML}" ]]; then
  echo "ERROR: Cargo.toml not found: ${CARGO_TOML}" >&2
  exit 1
fi

VERSION=$(sed -n 's/^version = "\(.*\)"$/\1/p' "${CARGO_TOML}" | head -n 1)
if [[ -z "${VERSION}" ]]; then
  echo "ERROR: Unable to extract version from ${CARGO_TOML}" >&2
  exit 1
fi

ARCHIVE_NAME="nvidia-debian-all-${VERSION}.tar.gz"
ARCHIVE_PATH="${ROOT_DIR}/${ARCHIVE_NAME}"

printf '[1/5] Build GUI release...\n'
cargo build --release

printf '[2/5] Prepare clean RELEASE directory...\n'
rm -rf -- "${RELEASE_DIR}"
mkdir -p "${RELEASE_DIR}"

printf '[3/5] Copy artifacts...\n'
if [[ ! -f "${GUI_BIN_SRC}" ]]; then
  echo "ERROR: GUI binary not found: ${GUI_BIN_SRC}" >&2
  exit 1
fi
if [[ ! -f "${CLI_SRC}" ]]; then
  echo "ERROR: CLI script not found: ${CLI_SRC}" >&2
  exit 1
fi
if [[ ! -f "${TUI_SRC}" ]]; then
  echo "ERROR: TUI script not found: ${TUI_SRC}" >&2
  exit 1
fi
if [[ ! -f "${BOOTSTRAP_SRC}" ]]; then
  echo "ERROR: bootstrap script not found: ${BOOTSTRAP_SRC}" >&2
  exit 1
fi
if [[ ! -d "${PACSCRIPT_SRC}" ]]; then
  echo "ERROR: pacscript directory not found: ${PACSCRIPT_SRC}" >&2
  exit 1
fi

cp -f -- "${GUI_BIN_SRC}" "${RELEASE_DIR}/debian-nvidia-all-gui"
cp -f -- "${CLI_SRC}" "${RELEASE_DIR}/debian-nvidia-all-cli.sh"
cp -f -- "${TUI_SRC}" "${RELEASE_DIR}/debian-nvidia-all-tui.sh"
cp -f -- "${BOOTSTRAP_SRC}" "${RELEASE_DIR}/nvidia-debian-all"
cp -a -- "${PACSCRIPT_SRC}" "${RELEASE_DIR}/pacscript"

chmod +x "${RELEASE_DIR}/debian-nvidia-all-gui" "${RELEASE_DIR}/debian-nvidia-all-cli.sh" "${RELEASE_DIR}/debian-nvidia-all-tui.sh" "${RELEASE_DIR}/nvidia-debian-all"

printf '[4/5] Create tar.gz archive...\n'
rm -f -- "${ARCHIVE_PATH}"
tar -C "${RELEASE_DIR}" -czf "${ARCHIVE_PATH}" --exclude='*.run' .

printf '[5/5] Done. RELEASE content:\n'
find "${RELEASE_DIR}" -maxdepth 2 -mindepth 1 | sort
printf '\nArchive created: %s\n' "${ARCHIVE_PATH}"
