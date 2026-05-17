#!/usr/bin/env bash
set -euo pipefail

script_dir=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
pacscript_dir="${script_dir}/pacscript"
pacscript="${pacscript_dir}/nvidia-driver-run.pacscript"

profile="${1:-}"
open_mode="${2:-auto}" # auto|open|proprietary

if [[ -z "$profile" ]]; then
  echo "Usage: $0 <latest|recommended|legacy580|legacy470|legacy390> [auto|open|proprietary]" >&2
  exit 2
fi

pacstall_args=(-PI)

action_note="Action Pacstall imposee: -PI (mode non interactif)"

# Garde-fous anti-blocage reseau
CURL_CONNECT_TIMEOUT=${CURL_CONNECT_TIMEOUT:-15}
CURL_MAX_TIME=${CURL_MAX_TIME:-120}
CURL_RETRIES=${CURL_RETRIES:-2}

curl_get() {
  curl -fsSL \
    --connect-timeout "$CURL_CONNECT_TIMEOUT" \
    --max-time "$CURL_MAX_TIME" \
    --retry "$CURL_RETRIES" \
    --retry-delay 2 \
    "$@"
}

for cmd in awk curl sed grep sort tac find df; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "Commande requise absente: $cmd" >&2; exit 1; }
done

[[ -f "$pacscript" ]] || { echo "pacscript introuvable: $pacscript" >&2; exit 1; }

if ! command -v pacstall >/dev/null 2>&1; then
  echo "pacstall introuvable dans PATH." >&2
  exit 1
fi

if ! dpkg-query -W -f='${Status}\n' spdx-licenses 2>/dev/null | grep -q "install ok installed"; then
  echo "Dependance manquante: spdx-licenses (requis par pacstall)." >&2
  echo "Installe-la puis relance: sudo apt update && sudo apt install -y spdx-licenses" >&2
  exit 1
fi

# pacstall attend /tmp/pacstall comme dossier de travail.
# Si un fichier parasite existe a cette place, pacstall casse avec des erreurs "not a directory".
if [[ -e /tmp/pacstall && ! -d /tmp/pacstall ]]; then
  ts=$(date +%Y%m%d-%H%M%S)
  bad_path="/tmp/pacstall.bad-${ts}"
  echo "Anomalie detectee: /tmp/pacstall est un fichier. Backup: ${bad_path}" >&2
  mv -f -- /tmp/pacstall "$bad_path"
fi
mkdir -p /tmp/pacstall

nvidia_list_versions() {
  local base_url=$1
  curl_get "$base_url/" 2>/dev/null \
    | sed -nE "s/.*href=[\"']?([0-9][^\"'/]+)\/[\"']?.*/\1/p" \
    | sort -uV
}

fetch_latest_version_from_latest_txt() {
  local base_url=$1
  curl_get "${base_url}/latest.txt" 2>/dev/null | awk 'NR==1 {print $1}'
}

fetch_branch_markers_unix_md() {
  local url='https://www.nvidia.com/en-us/drivers/unix.md'
  local content stable feature beta legacy
  content=$(curl_get "$url" 2>/dev/null || true)
  [[ -z $content ]] && return 1

  stable=$(printf '%s\n' "$content" | sed -nE 's/.*Latest Production Branch Version: \[([0-9.]+)\].*/\1/p' | head -n 1)
  feature=$(printf '%s\n' "$content" | sed -nE 's/.*Latest New Feature Branch Version: \[([0-9.]+)\].*/\1/p' | head -n 1)
  beta=$(printf '%s\n' "$content" | sed -nE 's/.*Latest Beta Version: \[([0-9.]+)\].*/\1/p' | head -n 1)
  legacy=$(printf '%s\n' "$content" | sed -nE 's/.*Latest Legacy GPU version \(([0-9]+)\.xx series\): \[([0-9.]+)\].*/\2/p' | head -n 1)

  BRANCH_STABLE_VERSION=${stable:-}
  BRANCH_FEATURE_VERSION=${feature:-}
  BRANCH_BETA_VERSION=${beta:-}
  BRANCH_LEGACY_VERSION=${legacy:-}
}

detect_nvidia_gpu_model() {
  local line model
  line=$(lspci -nn 2>/dev/null | grep -Ei 'VGA|3D' | grep -i nvidia | head -n 1 || true)
  [[ -z $line ]] && return 1
  model=$(printf '%s\n' "$line" | sed -nE 's/.*\[(.*)\].*/\1/p')
  [[ -z $model ]] && model="$line"
  DETECTED_GPU_MODEL=$model
  return 0
}

version_supports_gpu() {
  local version=$1 gpu_model=$2 base_url=$3
  local chips_url="${base_url}/${version}/README/supportedchips.html"
  curl -fsSL "$chips_url" 2>/dev/null | grep -Fqi "$gpu_model"
}

major_of_version() { printf '%s\n' "${1%%.*}"; }

pick_version() {
  local candidate base_url='' versions='' local_versions latest_version
  local -a mirror_urls all_versions

  mirror_urls=(
    "https://download.nvidia.com/XFree86/Linux-x86_64"
    "https://us.download.nvidia.com/XFree86/Linux-x86_64"
  )

  for candidate in "${mirror_urls[@]}"; do
    if local_versions=$(nvidia_list_versions "$candidate"); then
      if [[ -n $local_versions ]]; then
        versions=$local_versions
        base_url=$candidate
        break
      fi
    fi
  done

  if [[ -z $base_url ]]; then
    for candidate in "${mirror_urls[@]}"; do
      if latest_version=$(fetch_latest_version_from_latest_txt "$candidate"); then
        if [[ -n $latest_version ]]; then
          versions=$latest_version
          base_url=$candidate
          break
        fi
      fi
    done
  fi

  [[ -z $base_url ]] && { echo "Impossible de recuperer les versions NVIDIA." >&2; exit 1; }

  if [[ $versions != *$'\n'* ]]; then
    for candidate in "${mirror_urls[@]}"; do
      if local_versions=$(nvidia_list_versions "$candidate"); then
        if [[ -n $local_versions ]]; then
          versions=$local_versions
          break
        fi
      fi
    done
  fi

  mapfile -t all_versions < <(printf '%s\n' "$versions" | sort -uV | tac)
  ((${#all_versions[@]} > 0)) || { echo "Aucune version exploitable." >&2; exit 1; }

  fetch_branch_markers_unix_md || true

  local latest recommended detected_gpu=''
  latest="${all_versions[0]}"
  recommended="${BRANCH_STABLE_VERSION:-${BRANCH_FEATURE_VERSION:-${BRANCH_BETA_VERSION:-$latest}}}"

  if command -v lspci >/dev/null 2>&1 && detect_nvidia_gpu_model; then
    detected_gpu=$DETECTED_GPU_MODEL
    if ! version_supports_gpu "$recommended" "$detected_gpu" "$base_url"; then
      local v
      for v in "${all_versions[@]}"; do
        if version_supports_gpu "$v" "$detected_gpu" "$base_url"; then
          recommended=$v
          break
        fi
      done
    fi
  fi

  case "$profile" in
    latest)
      PICKED_VERSION="$latest"
      ;;
    recommended)
      PICKED_VERSION="$recommended"
      ;;
    legacy580|legacy470|legacy390)
      local target_major="${profile#legacy}"
      local v
      PICKED_VERSION=''
      for v in "${all_versions[@]}"; do
        if [[ $(major_of_version "$v") == "$target_major" ]]; then
          PICKED_VERSION="$v"
          break
        fi
      done
      [[ -n $PICKED_VERSION ]] || { echo "Aucune version legacy trouvee pour ${target_major}.x" >&2; exit 1; }
      ;;
    *)
      echo "Profil invalide: $profile" >&2
      exit 2
      ;;
  esac

  BASE_URL="$base_url"
}

runfile_is_valid() {
  local file=$1
  [[ -f $file ]] || return 1
  [[ ${file##*/} == NVIDIA-Linux-x86_64-*.run || ${file##*/} == NVIDIA-Linux-x86_64-*.run.part ]] || return 1
  sh "$file" --check >/dev/null 2>&1
}

pick_version

run_name="NVIDIA-Linux-x86_64-${PICKED_VERSION}.run"
run_url="${BASE_URL}/${PICKED_VERSION}/${run_name}"
out_part="${pacscript_dir}/${run_name}.part"
out_file="${pacscript_dir}/${run_name}"

echo "$action_note"
echo "Version cible: $PICKED_VERSION"

if runfile_is_valid "$out_file"; then
  echo "Runfile local valide detecte, reutilisation: $out_file"
else
  echo "Telechargement: $run_url"
  rm -f -- "$out_part"
  curl -fL --progress-bar \
    --connect-timeout "$CURL_CONNECT_TIMEOUT" \
    --max-time "$CURL_MAX_TIME" \
    --retry "$CURL_RETRIES" \
    --retry-delay 2 \
    -o "$out_part" "$run_url"
  if ! runfile_is_valid "$out_part"; then
    rm -f -- "$out_part"
    echo "Runfile invalide/incomplet: $run_name" >&2
    exit 1
  fi
  mv -f -- "$out_part" "$out_file"
  echo "Runfile telecharge et valide: $out_file"
fi

pkgver="$PICKED_VERSION"
generated_pacscript="${pacscript_dir}/nvidia-driver-run-${pkgver}.pacscript"

major="${pkgver%%.*}"
if [[ "$profile" == "latest" || "$major" == "580" ]]; then
  nvidia_open=true
  echo "kernel-open force (latest/580)."
else
  case "$open_mode" in
    open) nvidia_open=true ;;
    proprietary) nvidia_open=false ;;
    auto)
      if [[ "$major" -ge 515 ]]; then
        nvidia_open=true
      else
        nvidia_open=false
      fi
      ;;
    *)
      echo "Mode module invalide: $open_mode" >&2
      exit 2
      ;;
  esac
fi

sed \
  -e "s|^pkgver=.*|pkgver='${pkgver}'|" \
  -e "s|^nvidia_open=.*|nvidia_open='${nvidia_open}'|" \
  "$pacscript" > "$generated_pacscript"

echo "Pacscript genere: $generated_pacscript"
echo "Commande: (cd $pacscript_dir && pacstall ${pacstall_args[*]} ./$(basename "$generated_pacscript"))"

cd "$pacscript_dir"
echo "Repertoire de travail pacstall: $(pwd)"
echo "Debut etape pacstall..."

run_pacstall_direct() {
  set +e
  pacstall "${pacstall_args[@]}" "./$(basename "$generated_pacscript")"
  rc=$?
  set -e
  echo "pacstall exit code: $rc"
  return "$rc"
}

run_pacstall_sudo_n() {
  set +e
  sudo -n pacstall "${pacstall_args[@]}" "./$(basename "$generated_pacscript")"
  rc=$?
  set -e
  echo "pacstall (sudo -n) exit code: $rc"
  return "$rc"
}

run_pacstall_sudo_askpass() {
  local askpass_script
  askpass_script=$(mktemp /tmp/pacstall-askpass.XXXXXX.sh)
  cat >"$askpass_script" <<'EOF'
#!/usr/bin/env bash
prompt="${SUDO_ASKPASS_PROMPT:-Mot de passe sudo requis pour pacstall}"
if command -v zenity >/dev/null 2>&1; then
  exec zenity --password --title="Authentification sudo" --text="$prompt"
elif command -v kdialog >/dev/null 2>&1; then
  exec kdialog --password "$prompt"
else
  exit 1
fi
EOF
  chmod 700 "$askpass_script"
  set +e
  SUDO_ASKPASS="$askpass_script" \
  SUDO_ASKPASS_PROMPT="Saisis ton mot de passe sudo pour continuer l'installation pacstall" \
  sudo -A pacstall "${pacstall_args[@]}" "./$(basename "$generated_pacscript")"
  rc=$?
  set -e
  rm -f -- "$askpass_script"
  echo "pacstall (sudo -A) exit code: $rc"
  return "$rc"
}

if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
  run_pacstall_direct
  exit $?
fi

# 1) pkexec (souvent meilleur hors distrobox)
if command -v pkexec >/dev/null 2>&1; then
  echo "Execution pacstall via pkexec (popup d'authentification)." >&2
  pkexec_err_log=$(mktemp /tmp/pkexec-pacstall.XXXXXX.log)
  set +e
  pkexec env PATH="$PATH" bash -lc "cd '$pacscript_dir' && pacstall ${pacstall_args[*]} './$(basename "$generated_pacscript")'" 2>"$pkexec_err_log"
  rc=$?
  set -e
  echo "pacstall (pkexec) exit code: $rc"
  if [[ $rc -eq 0 ]]; then
    rm -f -- "$pkexec_err_log"
    exit 0
  fi
  cat "$pkexec_err_log" >&2 || true
  rm -f -- "$pkexec_err_log"
fi

# 2) sudo non interactif si ticket deja actif
if command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then
  run_pacstall_sudo_n
  exit $?
fi

# 3) sudo askpass GUI (zenity/kdialog), utile en distrobox sans polkit
if command -v sudo >/dev/null 2>&1; then
  if command -v zenity >/dev/null 2>&1 || command -v kdialog >/dev/null 2>&1; then
    echo "Fallback vers sudo -A (askpass GUI)." >&2
    run_pacstall_sudo_askpass
    exit $?
  fi
fi

echo "Impossible d'obtenir des privileges automatiquement (pkexec/sudo)." >&2
echo "Solution: lance la GUI depuis un terminal avec un ticket sudo actif (sudo -v), ou installe zenity/kdialog." >&2
exit 1
