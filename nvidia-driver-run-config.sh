#!/usr/bin/env bash
set -euo pipefail

script_dir=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
pacscript="${script_dir}/nvidia-driver-run.pacscript"
generated_pacscript=''
download_tmp_file=''

if [[ -t 1 && -z ${NO_COLOR:-} ]]; then
  bold=$'\033[1m'
  dim=$'\033[2m'
  red=$'\033[31m'
  green=$'\033[32m'
  yellow=$'\033[33m'
  blue=$'\033[34m'
  cyan=$'\033[36m'
  reset=$'\033[0m'
else
  bold='' dim='' red='' green='' yellow='' blue='' cyan='' reset=''
fi

title() {
  printf '\n%s%s%s\n' "$bold$cyan" "$1" "$reset"
}

separator() {
  printf '%s%s%s\n' "$dim" "------------------------------------------------------------" "$reset"
}

spacer() {
  echo
}

info() {
  printf '%s%s%s\n' "$blue" "$1" "$reset"
}

warn() {
  printf '%s%s%s\n' "$yellow" "$1" "$reset"
}

error() {
  printf '%sERROR:%s %s\n' "$red$bold" "$reset" "$1" >&2
}

UI_BACK='__BACK__'
UI_QUIT='__QUIT__'

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

cleanup() {
  [[ -n ${download_tmp_file:-} ]] && rm -f -- "$download_tmp_file"
  [[ -n ${generated_pacscript:-} ]] && rm -f -- "$generated_pacscript"
}

handle_interrupt() {
  cleanup
  printf '\n%sInterruption utilisateur (Ctrl+C). Arret.%s\n' "$yellow" "$reset" >&2
  exit 130
}

trap cleanup EXIT
trap handle_interrupt INT TERM

ver_ge() {
  local lhs rhs
  lhs=$(printf '%s\n' "$1" | awk -F. '{ printf "%d%03d%03d\n", $1, $2, $3 }')
  rhs=$(printf '%s\n' "$2" | awk -F. '{ printf "%d%03d%03d\n", $1, $2, $3 }')
  [[ $lhs -ge $rhs ]]
}

yes_no() {
  local prompt=$1 default=${2:-yes} reply
  local suffix='[O/n]'
  [[ $default == no ]] && suffix='[o/N]'

  while true; do
    printf '%s %s%s%s: ' "$prompt" "$dim" "$suffix" "$reset"
    read -r reply
    case ${reply,,} in
      "") [[ $default == yes ]] && return 0 || return 1 ;;
      o|oui|y|yes) return 0 ;;
      n|non|no) return 1 ;;
      *) warn "Repondre par oui ou non." ;;
    esac
  done
}

install_missing_dependencies() {
  local -a missing=("$@")
  local cmd=''

  if ! command_exists apt; then
    error "Ce script gere uniquement Debian/apt."
    return 1
  fi
  cmd="sudo apt update && sudo apt install -y ${missing[*]}"
  info "Gestionnaire detecte: apt"
  info "Commande proposee: ${cmd}"
  if yes_no "Installer automatiquement ces dependances ?" yes; then
    if ! command_exists sudo; then
      warn "sudo est introuvable. Relance le script en root ou installe manuellement."
      return 1
    fi
    # shellcheck disable=SC2086
    eval "$cmd"
  else
    warn "Installation annulee. Le script peut echouer sans ces dependances."
    return 1
  fi
}

download_file() {
  local url=$1 out=$2
  if command_exists curl; then
    if [[ $out == "-" ]]; then
      curl -fsSL "$url"
    else
      curl -fL --progress-bar -o "$out" "$url"
    fi
  elif command_exists wget; then
    if [[ $out == "-" ]]; then
      wget -qO- "$url"
    else
      wget -O "$out" "$url"
    fi
  else
    error "curl ou wget est requis pour telecharger ${url}"
    return 1
  fi
}

install_deb_file() {
  local deb_path=$1
  if ! command_exists sudo; then
    error "sudo est requis pour installer ${deb_path}"
    return 1
  fi
  sudo apt update
  sudo apt install -y "$deb_path"
}

ensure_spdx_licenses() {
  local pkg='spdx-licenses'
  local deb_url="https://ftp.debian.org/debian/pool/main/s/${pkg}/${pkg}_3.27.0+ds-1_all.deb"
  local tmp_deb

  if dpkg-query -W -f='${Status}\n' "$pkg" 2>/dev/null | grep -q "install ok installed"; then
    return 0
  fi

  title "Dependance Pacstall: ${pkg}"
  warn "${pkg} n'est pas installe."
  if ! yes_no "Installer ${pkg} maintenant ?" yes; then
    return 1
  fi

  if sudo apt update && sudo apt install -y "$pkg"; then
    return 0
  fi

  warn "Installation via depots echouee, tentative via .deb Debian."
  tmp_deb=$(mktemp "/tmp/${pkg}.XXXXXX.deb")
  if download_file "$deb_url" "$tmp_deb"; then
    install_deb_file "$tmp_deb"
  else
    rm -f "$tmp_deb"
    return 1
  fi
  rm -f "$tmp_deb"
}

ensure_pacstall_installed() {
  local releases_api='https://api.github.com/repos/pacstall/pacstall/releases/latest'
  local latest_html='https://github.com/pacstall/pacstall/releases/latest'
  local deb_url=''
  local tmp_deb

  if command_exists pacstall; then
    return 0
  fi

  title "Installation de pacstall"
  warn "pacstall est introuvable dans le PATH."
  if ! yes_no "Telecharger et installer le dernier pacstall (.deb) ?" yes; then
    return 1
  fi

  if command_exists curl; then
    deb_url=$(curl -fsSL "$releases_api" \
      | sed -nE 's/.*"browser_download_url":[[:space:]]*"([^"]+\.deb)".*/\1/p' \
      | head -n 1)
  fi
  if [[ -z $deb_url ]]; then
    deb_url=$(download_file "$latest_html" - \
      | sed -nE 's/.*href="([^"]+\.deb)".*/https:\/\/github.com\1/p' \
      | head -n 1)
  fi
  if [[ -z $deb_url ]]; then
    error "Impossible de trouver un .deb pacstall dans la release latest."
    return 1
  fi

  tmp_deb=$(mktemp "/tmp/pacstall.XXXXXX.deb")
  info "Telechargement: ${deb_url}"
  if download_file "$deb_url" "$tmp_deb"; then
    install_deb_file "$tmp_deb"
  else
    rm -f "$tmp_deb"
    return 1
  fi
  rm -f "$tmp_deb"
}

check_dependencies() {
  local -a required=(awk curl df find grep sed sort tac)
  local -a missing=()
  local dep

  for dep in "${required[@]}"; do
    if ! command_exists "$dep"; then
      missing+=("$dep")
    fi
  done

  if ((${#missing[@]} == 0)); then
    return 0
  fi

  title "Dependances manquantes"
  warn "Commandes absentes: ${missing[*]}"
  install_missing_dependencies "${missing[@]}" || return 1

  missing=()
  for dep in "${required[@]}"; do
    if ! command_exists "$dep"; then
      missing+=("$dep")
    fi
  done
  if ((${#missing[@]} > 0)); then
    error "Toujours manquant apres tentative d'installation: ${missing[*]}"
    return 1
  fi

  if ! ensure_spdx_licenses; then
    error "spdx-licenses est requis pour pacstall."
    return 1
  fi
  if ! ensure_pacstall_installed; then
    error "pacstall est requis."
    return 1
  fi
  return 0
}

ui_header() {
  clear
  printf '%s%sNVIDIA Driver Run%s\n' "$bold" "$cyan" "$reset"
  printf '%sAssistant de construction Pacstall%s\n' "$dim" "$reset"
  separator
}

ui_menu() {
  local title=$1 prompt=$2 allow_back=$3 allow_quit=$4 default_tag=$5
  shift 5
  local -a pairs=("$@")
  local out rc reply i default_index=1
  local -a tags=() labels=()
  ui_header >/dev/tty
  title "$title" >/dev/tty
  printf '%s%s%s\n' "$blue" "$prompt" "$reset" >/dev/tty
  spacer >/dev/tty
  for ((i=0; i<${#pairs[@]}; i+=2)); do
    tags+=("${pairs[$i]}")
    labels+=("${pairs[$((i+1))]}")
  done
  for i in "${!tags[@]}"; do
    printf '  %s%2d)%s %-14s %s%s%s\n' "$green" "$((i + 1))" "$reset" "${tags[$i]}" "$dim" "${labels[$i]}" "$reset" >/dev/tty
    [[ ${tags[$i]} == "$default_tag" ]] && default_index=$((i + 1))
  done
  spacer >/dev/tty
  printf '%s%s%s\n' "$cyan" "Aide saisie :" "$reset" >/dev/tty
  printf '%s\n' "  - Tape un NUMERO puis Entrer pour choisir une option." >/dev/tty
  printf '%s\n' "  - Appuie simplement sur Entrer pour choisir l'option par defaut." >/dev/tty
  [[ $allow_back == yes ]] && printf '%s\n' "  - Tape b puis Entrer pour RETOURNER a l'etape precedente." >/dev/tty
  [[ $allow_quit == yes ]] && printf '%s\n' "  - Tape q puis Entrer pour QUITTER l'assistant." >/dev/tty
  spacer >/dev/tty
  while true; do
    printf '%sVotre choix%s %s[%d]%s: ' "$bold" "$reset" "$dim" "$default_index" "$reset" >/dev/tty
    read -r reply </dev/tty
    [[ -z $reply ]] && reply=$default_index
    if [[ ${reply,,} == b && $allow_back == yes ]]; then
      printf '%s' "$UI_BACK"
      return 0
    fi
    if [[ ${reply,,} == q && $allow_quit == yes ]]; then
      printf '%s' "$UI_QUIT"
      return 0
    fi
    if [[ $reply =~ ^[0-9]+$ ]] && ((reply >= 1 && reply <= ${#tags[@]})); then
      printf '%s' "${tags[$((reply - 1))]}"
      return 0
    fi
    warn "Choix invalide. Exemple: 1, 2, 3 (ou b, q selon les options)." >/dev/tty
    spacer >/dev/tty
  done
}

self_test() {
  local ok=true
  echo "== self-test =="
  for cmd in bash awk sed grep sort tac curl find df apt; do
    if command_exists "$cmd"; then
      echo "[OK] $cmd"
    else
      echo "[KO] $cmd manquant"
      ok=false
    fi
  done
  if command_exists curl; then
    if curl -fsSL https://download.nvidia.com/XFree86/Linux-x86_64/latest.txt >/dev/null 2>&1; then
      echo "[OK] acces reseau NVIDIA"
    else
      echo "[KO] acces reseau NVIDIA"
      ok=false
    fi
    if curl -fsSL https://www.nvidia.com/en-us/drivers/unix.md >/dev/null 2>&1; then
      echo "[OK] acces metadata branches"
    else
      echo "[KO] acces metadata branches"
      ok=false
    fi
  fi
  if $ok; then
    echo "SELF-TEST: PASS"
    return 0
  fi
  echo "SELF-TEST: FAIL"
  return 1
}

if [[ ${1:-} == "--self-test" ]]; then
  self_test
  exit $?
fi

choose_menu() {
  local prompt=$1 default=$2 allow_back=$3 allow_quit=$4 reply
  shift 4
  local options=("$@")
  local i

  for i in "${!options[@]}"; do
    printf '  %s%2d)%s %s\n' "$green" "$((i + 1))" "$reset" "${options[$i]}"
  done

  while true; do
    printf '%s' "$prompt"
    printf ' %s[%s]%s' "$dim" "$default" "$reset"
    [[ $allow_back == yes ]] && printf ' %s[b=retour]%s' "$dim" "$reset"
    [[ $allow_quit == yes ]] && printf ' %s[q=quitter]%s' "$dim" "$reset"
    printf ': '
    read -r reply
    [[ -z $reply ]] && reply=$default
    [[ ${reply,,} == b && $allow_back == yes ]] && { printf '__BACK__'; return 0; }
    [[ ${reply,,} == q && $allow_quit == yes ]] && { printf '__QUIT__'; return 0; }
    if [[ $reply =~ ^[0-9]+$ ]] && ((reply >= 1 && reply <= ${#options[@]})); then
      printf '%s' "${options[$((reply - 1))]}"
      return 0
    fi
    warn "Choix invalide."
  done
}

nvidia_list_versions() {
  local base_url=$1
  curl -fsSL "$base_url/" 2>/dev/null \
    | sed -nE 's/.*href=["'\'']?([0-9][^"'\''/]+)\/["'\'']?.*/\1/p' \
    | sort -uV
}

fetch_latest_version_from_latest_txt() {
  local base_url=$1
  curl -fsSL "${base_url}/latest.txt" 2>/dev/null | awk 'NR==1 {print $1}'
}

fetch_branch_markers_unix_md() {
  local url='https://www.nvidia.com/en-us/drivers/unix.md'
  local content stable feature beta legacy

  content=$(curl -fsSL "$url" 2>/dev/null || true)
  [[ -z $content ]] && return 1

  stable=$(printf '%s\n' "$content" | sed -nE 's/.*Latest Production Branch Version: \[([0-9.]+)\].*/\1/p' | head -n 1)
  feature=$(printf '%s\n' "$content" | sed -nE 's/.*Latest New Feature Branch Version: \[([0-9.]+)\].*/\1/p' | head -n 1)
  beta=$(printf '%s\n' "$content" | sed -nE 's/.*Latest Beta Version: \[([0-9.]+)\].*/\1/p' | head -n 1)
  legacy=$(printf '%s\n' "$content" | sed -nE 's/.*Latest Legacy GPU version \(([0-9]+)\.xx series\): \[([0-9.]+)\].*/\2/p' | head -n 1)

  [[ -n $stable ]] && BRANCH_STABLE_VERSION=$stable || BRANCH_STABLE_VERSION=''
  [[ -n $feature ]] && BRANCH_FEATURE_VERSION=$feature || BRANCH_FEATURE_VERSION=''
  [[ -n $beta ]] && BRANCH_BETA_VERSION=$beta || BRANCH_BETA_VERSION=''
  [[ -n $legacy ]] && BRANCH_LEGACY_VERSION=$legacy || BRANCH_LEGACY_VERSION=''
  return 0
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

major_of_version() {
  printf '%s\n' "${1%%.*}"
}

runfile_is_valid() {
  local file=$1
  [[ -f $file ]] || return 1
  [[ ${file##*/} == NVIDIA-Linux-x86_64-*.run || ${file##*/} == NVIDIA-Linux-x86_64-*.run.part ]] || return 1
  # Verifie l'integrite makeself; les runfiles NVIDIA supportent --check.
  sh "$file" --check >/dev/null 2>&1
}

collect_valid_runfiles() {
  local file
  local -a candidates
  VALID_RUNFILES=()
  INVALID_RUNFILES=()
  mapfile -t candidates < <(find "$script_dir" -maxdepth 1 -type f -name 'NVIDIA-Linux-x86_64-*.run' | sort)
  for file in "${candidates[@]}"; do
    if runfile_is_valid "$file"; then
      VALID_RUNFILES+=("$file")
    else
      INVALID_RUNFILES+=("$file")
    fi
  done
}

get_locale_mirror_urls() {
  local raw locale_code lang_code country_code
  raw="${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}"
  raw="${raw%%.*}"
  raw="${raw%%@*}"
  locale_code="${raw,,}"

  lang_code=''
  country_code=''
  if [[ $locale_code == *_* ]]; then
    lang_code="${locale_code%%_*}"
    country_code="${locale_code##*_}"
  elif [[ $locale_code =~ ^[a-z]{2}$ ]]; then
    lang_code="$locale_code"
  fi

  local -a mirrors=()
  if [[ -n $country_code ]]; then
    mirrors+=("https://${country_code}.download.nvidia.com/XFree86/Linux-x86_64")
  fi
  if [[ -n $lang_code ]]; then
    mirrors+=("https://${lang_code}.download.nvidia.com/XFree86/Linux-x86_64")
  fi
  mirrors+=(
    "https://download.nvidia.com/XFree86/Linux-x86_64"
    "https://us.download.nvidia.com/XFree86/Linux-x86_64"
  )

  printf '%s\n' "${mirrors[@]}" | awk '!seen[$0]++'
}

pick_online_runfile() {
  local base_url versions selected_ver run_url run_name candidate choice local_versions
  local stable_major='' feature_major='' legacy_major=''
  local detected_gpu=''
  local latest_version=''
  local branch_choice='stable' gpu_choice='auto' version_choice='' filter_input latest_available recommended_available default_choice
  local has_gpu_detected='no' recommended_label='' menu_prompt=''
  local -a listed_versions mirror_urls all_versions branch_versions gpu_versions filtered_versions
  local -a branch_menu gpu_menu version_menu
  PICKED_RUNFILE=''

  if ! command -v curl >/dev/null 2>&1; then
    error "curl est requis pour la recherche en ligne."
    return 1
  fi

  title "Recherche NVIDIA en ligne"
  info "Recuperation des versions disponibles..."

  mapfile -t mirror_urls < <(get_locale_mirror_urls)
  mirror_urls+=(
    "https://download.nvidia.com/XFree86/Linux-x86_64"
    "https://us.download.nvidia.com/XFree86/Linux-x86_64"
  )
  mapfile -t mirror_urls < <(printf '%s\n' "${mirror_urls[@]}" | awk '!seen[$0]++')
  base_url=''
  versions=''
  for candidate in "${mirror_urls[@]}"; do
    info "Test miroir: ${candidate}"
    if local_versions=$(nvidia_list_versions "$candidate"); then
      if [[ -n $local_versions ]]; then
        versions=$local_versions
        base_url=$candidate
        break
      fi
    fi
  done

  if [[ -z $base_url ]]; then
    # Dernier recours: latest.txt (une seule version)
    for candidate in "${mirror_urls[@]}"; do
      info "Test fallback latest.txt: ${candidate}"
      if latest_version=$(fetch_latest_version_from_latest_txt "$candidate"); then
        if [[ -n $latest_version ]]; then
          versions=$latest_version
          base_url=$candidate
          info "Fallback latest.txt utilise: ${latest_version}"
          break
        fi
      fi
    done
  fi

  if [[ -z $base_url ]]; then
    error "Impossible de recuperer la liste des versions depuis NVIDIA."
    return 1
  fi

  # Si le miroir locale ne donne qu'un latest.txt, on tente de recuperer une vraie liste
  # depuis les index connus afin d'offrir un choix numerote a l'utilisateur.
  if [[ $versions != *$'\n'* ]]; then
    for candidate in "https://download.nvidia.com/XFree86/Linux-x86_64" "https://us.download.nvidia.com/XFree86/Linux-x86_64"; do
      if local_versions=$(nvidia_list_versions "$candidate"); then
        if [[ -n $local_versions ]]; then
          versions=$local_versions
          info "Liste complete recuperee depuis: ${candidate}"
          break
        fi
      fi
    done
  fi
  info "Miroir utilise: ${base_url}"

  fetch_branch_markers_unix_md || true
  if [[ -n ${BRANCH_STABLE_VERSION:-} ]]; then
    stable_major=$(major_of_version "$BRANCH_STABLE_VERSION")
  fi
  if [[ -n ${BRANCH_FEATURE_VERSION:-} ]]; then
    feature_major=$(major_of_version "$BRANCH_FEATURE_VERSION")
  fi
  if [[ -n ${BRANCH_LEGACY_VERSION:-} ]]; then
    legacy_major=$(major_of_version "$BRANCH_LEGACY_VERSION")
  fi

  mapfile -t all_versions < <(printf '%s\n' "$versions" | sort -uV | tac)
  if ((${#all_versions[@]} == 0)); then
    error "Aucune version exploitable trouvee sur ${base_url}."
    return 1
  fi
  latest_available="${all_versions[0]}"
  recommended_available="${BRANCH_STABLE_VERSION:-}"
  [[ -z $recommended_available ]] && recommended_available="${BRANCH_FEATURE_VERSION:-}"
  [[ -z $recommended_available ]] && recommended_available="${BRANCH_BETA_VERSION:-}"
  [[ -z $recommended_available ]] && recommended_available="$latest_available"
  if command_exists lspci && detect_nvidia_gpu_model; then
    detected_gpu=$DETECTED_GPU_MODEL
    has_gpu_detected='yes'
    if ! version_supports_gpu "$recommended_available" "$detected_gpu" "$base_url"; then
      for selected_ver in "${all_versions[@]}"; do
        if version_supports_gpu "$selected_ver" "$detected_gpu" "$base_url"; then
          recommended_available=$selected_ver
          break
        fi
      done
    fi
  fi

  while true; do
    ui_header
    if [[ $has_gpu_detected == yes ]]; then
      recommended_label="Pilote recommande pour GPU detecte (${recommended_available})"
      default_choice="recommended"
      menu_prompt=$(printf 'Miroir: %s\nNombre de versions disponibles trouvees: %d\nDerniere version dispo: %s\nGPU detecte: %s\nVersion recommandee: %s' \
        "$base_url" "${#all_versions[@]}" "$latest_available" "$detected_gpu" "$recommended_available")
    else
      recommended_label="Pilote recommande (pas de GPU NVIDIA detecte)"
      default_choice="latest"
      menu_prompt=$(printf 'Miroir: %s\nNombre de versions disponibles trouvees: %d\nDerniere version dispo: %s\nVersion recommandee: %s\nAttention: pas de GPU NVIDIA detecte (mode packaging).' \
        "$base_url" "${#all_versions[@]}" "$latest_available" "$recommended_available")
    fi
    branch_menu=(
      "latest" "Derniere version disponible (${latest_available})"
      "recommended" "${recommended_label}"
      "stable"  "Branche production"
      "feature" "Branche nouvelles fonctions"
      "beta"    "Derniere beta"
      "legacy"  "Branches anciennes/legacy"
      "all"     "Toutes les versions"
    )
    choice=$(ui_menu "Etape 1/3 - Branche" "$menu_prompt" no yes "$default_choice" "${branch_menu[@]}")
    if [[ $choice == "$UI_QUIT" || -z $choice ]]; then
      return 1
    fi
    branch_choice=$choice

    if [[ $branch_choice == recommended && $has_gpu_detected != yes ]]; then
      warn "Option 'recommande' indisponible sans GPU NVIDIA detecte. Choisis plutot 'latest' ou une branche."
      continue
    fi

    if [[ $branch_choice == latest ]]; then
      version_choice=$latest_available
      break
    fi

    if [[ $branch_choice == recommended ]]; then
      version_choice=$recommended_available
      break
    fi

    branch_versions=()
    case "$branch_choice" in
      stable)
        if [[ -n $stable_major ]]; then
          mapfile -t branch_versions < <(printf '%s\n' "${all_versions[@]}" | grep -E "^${stable_major}\.")
        fi
        ;;
      feature)
        if [[ -n $feature_major ]]; then
          mapfile -t branch_versions < <(printf '%s\n' "${all_versions[@]}" | grep -E "^${feature_major}\.")
        fi
        ;;
      beta)
        if [[ -n ${BRANCH_BETA_VERSION:-} ]]; then
          mapfile -t branch_versions < <(printf '%s\n' "${all_versions[@]}" | grep -Fx "${BRANCH_BETA_VERSION}")
        fi
        ;;
      legacy)
        if [[ -n $legacy_major ]]; then
          mapfile -t branch_versions < <(printf '%s\n' "${all_versions[@]}" | awk -F. -v lm="$legacy_major" '$1+0 <= lm+0')
        else
          mapfile -t branch_versions < <(printf '%s\n' "${all_versions[@]}" | grep -E '^(470|390|340|304|173|96|71|1\.0-)')
        fi
        ;;
      all)
        branch_versions=("${all_versions[@]}")
        ;;
    esac
    if ((${#branch_versions[@]} == 0)); then
      warn "Aucune version pour cette branche, retour a la liste complete."
      branch_versions=("${all_versions[@]}")
    fi
    mapfile -t listed_versions < <(printf '%s\n' "${branch_versions[@]}" | head -n 140)

    ui_header
    filtered_versions=("${listed_versions[@]}")
    if [[ -n $detected_gpu ]]; then
      gpu_menu=(
        "auto" "Filtrer avec GPU detecte: ${detected_gpu}"
        "none" "Ne pas filtrer"
      )
      choice=$(ui_menu "Etape 2/3 - Compatibilite GPU" "GPU detecte: ${detected_gpu}" yes yes "auto" "${gpu_menu[@]}")
      if [[ $choice == "$UI_QUIT" ]]; then
        return 1
      fi
      if [[ $choice == "$UI_BACK" ]]; then
        continue
      fi
      gpu_choice=$choice
      if [[ $gpu_choice == "auto" ]]; then
        gpu_versions=()
        for selected_ver in "${listed_versions[@]}"; do
          if version_supports_gpu "$selected_ver" "$detected_gpu" "$base_url"; then
            gpu_versions+=("$selected_ver")
          fi
        done
        if ((${#gpu_versions[@]} > 0)); then
          filtered_versions=("${gpu_versions[@]}")
        else
          warn "Aucun match GPU. La liste non filtree sera utilisee."
        fi
      fi
    fi

    while true; do
      ui_header
      version_menu=()
      for i in "${!filtered_versions[@]}"; do
        version_menu+=("${filtered_versions[$i]}" "Driver ${filtered_versions[$i]}")
      done
      choice=$(ui_menu "Etape 3/3 - Version" "Choisir une version (${#filtered_versions[@]} disponibles)" yes yes "${filtered_versions[0]}" "${version_menu[@]}")
      if [[ $choice == "$UI_QUIT" ]]; then
        return 1
      fi
      if [[ $choice == "$UI_BACK" ]]; then
        break
      fi
      if [[ -n $choice ]]; then
        version_choice=$choice
        break 2
      fi
    done
  done

  selected_ver=$version_choice
  run_name="NVIDIA-Linux-x86_64-${selected_ver}.run"
  run_url="${base_url}/${selected_ver}/${run_name}"
  info "Verification de ${run_name}..."
  if ! curl -fsI "$run_url" >/dev/null; then
    error "Runfile introuvable a cette URL: ${run_url}"
    return 1
  fi

  title "Telechargement"
  info "$run_url"
  download_tmp_file="${script_dir}/${run_name}.part"
  rm -f -- "$download_tmp_file"
  curl -fL --progress-bar -o "$download_tmp_file" "$run_url"
  if ! runfile_is_valid "$download_tmp_file"; then
    rm -f -- "$download_tmp_file"
    error "Le fichier telecharge est incomplet ou invalide: ${run_name}"
    return 1
  fi
  mv -f -- "$download_tmp_file" "${script_dir}/${run_name}"
  download_tmp_file=''
  PICKED_RUNFILE="${script_dir}/${run_name}"
  ui_header >/dev/tty
  title "Telechargement termine" >/dev/tty
  info "Fichier pret: ${run_name}" >/dev/tty
  info "Chemin: ${script_dir}/${run_name}" >/dev/tty
  spacer >/dev/tty
  read -r -p "Appuie sur Entrer pour continuer... " _ </dev/tty
  return 0
}

if [[ ! -f $pacscript ]]; then
  error "pacscript introuvable: ${pacscript}"
  exit 1
fi

if ! check_dependencies; then
  error "Dependances incompletes."
  exit 1
fi

collect_valid_runfiles
runfiles=("${VALID_RUNFILES[@]}")

downloaded_runfile=''
downloaded_by_script=false

printf '%s%sNVIDIA Driver Run%s\n' "$bold" "$cyan" "$reset"
printf '%sAssistant de construction Pacstall%s\n' "$dim" "$reset"

if ((${#runfiles[@]} > 0)); then
  separator
  title "Selection Source"
  source_mode=$(ui_menu "Selection Source" "Choisir la source des pilotes NVIDIA" no yes "local" \
    "local" "Utiliser un .run deja present localement" \
    "online" "Rechercher et telecharger depuis NVIDIA")
  [[ $source_mode == "$UI_QUIT" || -z $source_mode ]] && exit 0
else
  warn "Aucun installateur local detecte, bascule automatique vers la recherche NVIDIA."
  source_mode="online"
fi

if ((${#INVALID_RUNFILES[@]} > 0)); then
  warn "Fichiers .run invalides detectes (ignores):"
  for f in "${INVALID_RUNFILES[@]}"; do
    warn "  - ${f##*/}"
  done
fi

if [[ $source_mode == local ]]; then
  while true; do
    local_menu=()
    for i in "${!runfiles[@]}"; do
      base=${runfiles[$i]##*/}
      local_menu+=("$base" "Installateur local")
    done
    choice=$(ui_menu "Selection Locale" "Choisir un installateur .run local (${#runfiles[@]} detectes)" yes yes "${runfiles[$(( ${#runfiles[@]} - 1 ))]##*/}" "${local_menu[@]}")
    if [[ $choice == "$UI_QUIT" || -z $choice ]]; then
      exit 0
    fi
    if [[ $choice == "$UI_BACK" ]]; then
      source_mode=$(ui_menu "Selection Source" "Choisir la source des pilotes NVIDIA" no yes "local" \
        "local" "Utiliser un .run deja present localement" \
        "online" "Rechercher et telecharger depuis NVIDIA")
      [[ $source_mode == "$UI_QUIT" || -z $source_mode ]] && exit 0
      [[ $source_mode == "online" ]] && break
      continue
    fi
    runfile=$choice
    break
  done
  if [[ $source_mode == "online" ]]; then
    pick_online_runfile
    downloaded_runfile=$PICKED_RUNFILE
    if [[ -z $downloaded_runfile ]]; then
      error "Echec du telechargement online."
      exit 1
    fi
    downloaded_by_script=true
    runfile=${downloaded_runfile##*/}
  fi
else
  pick_online_runfile
  downloaded_runfile=$PICKED_RUNFILE
  if [[ -z $downloaded_runfile ]]; then
    error "Echec du telechargement online."
    exit 1
  fi
  downloaded_by_script=true
  runfile=${downloaded_runfile##*/}
fi

pkgver=${runfile#NVIDIA-Linux-x86_64-}
pkgver=${pkgver%.run}
generated_pacscript="${script_dir}/nvidia-driver-run-${pkgver}.pacscript"

if ver_ge "$pkgver" "515"; then
  title "Module noyau"
  info "kernel-open existe depuis la serie 515."
  echo "  - Recommande pour les GPU Turing/RTX 20 et plus recents."
  echo "  - Pour les GPU plus anciens, choisir le module proprietaire."
  if yes_no "Utiliser le module kernel-open si disponible ?" yes; then
    nvidia_open=true
  else
    nvidia_open=false
  fi
else
  title "Module noyau"
  warn "La serie ${pkgver%%.*} est anterieure a 515: kernel-open indisponible."
  info "Le module proprietaire sera utilise."
  nvidia_open=false
fi

if (($# > 0)); then
  pacstall_args=("$@")
  action_label="options fournies: ${pacstall_args[*]}"
else
  action_choice=$(ui_menu "Action Pacstall" \
"Choisir ce que Pacstall doit faire ensuite" \
no yes "2" \
"1" "Installer le paquet apres construction (-I)" \
"2" "Construire le paquet seulement (-IB)" \
"3" "Construire et garder les fichiers de debogage (-IBK)")
  [[ $action_choice == "$UI_QUIT" || -z $action_choice ]] && exit 0
  case "$action_choice" in
    1) pacstall_args=(-I); action_label="installer apres construction" ;;
    2) pacstall_args=(-IB); action_label="construire seulement" ;;
    3) pacstall_args=(-IBK); action_label="construire et garder les fichiers de debogage" ;;
  esac
fi

available_kib=$(df -Pk "$script_dir" | awk 'NR==2 {print $4}')
available_gib=$((available_kib / 1024 / 1024))
if ((available_gib < 3)); then
  echo
  warn "Espace libre faible dans ${script_dir}: environ ${available_gib} Gio."
  echo "La construction NVIDIA peut demander plusieurs Gio selon la version."
fi

title "Resume"
printf '  %-15s %s\n' "Version NVIDIA:" "${bold}${pkgver}${reset}"
printf '  %-15s %s\n' "Installateur:" "$runfile"
printf '  %-15s %s\n' "Module noyau:" "$([[ $nvidia_open == true ]] && echo kernel-open || echo proprietaire)"
printf '  %-15s %s\n' "Action:" "$action_label"
printf '  %-15s %s\n' "Pacscript:" "${generated_pacscript}"
printf '  %-15s %s\n' "Commande:" "pacstall ${pacstall_args[*]} ${generated_pacscript}"
echo
if ! yes_no "Continuer ?" yes; then
  warn "Annule."
  exit 0
fi

echo
sed \
  -e "s|^pkgver=.*|pkgver='${pkgver}'|" \
  -e "s|^nvidia_open=.*|nvidia_open='${nvidia_open}'|" \
  "$pacscript" > "$generated_pacscript"

title "Lancement de Pacstall"
pacstall "${pacstall_args[@]}" "$generated_pacscript"

if [[ $downloaded_by_script == true ]]; then
  echo
  title "Nettoyage du runfile telecharge"
  if yes_no "Conserver ${runfile} dans ${script_dir} ?" no; then
    info "Runfile conserve: ${runfile}"
  else
    rm -f -- "$downloaded_runfile"
    info "Runfile supprime: ${runfile}"
  fi
fi
