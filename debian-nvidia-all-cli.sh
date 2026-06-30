#!/usr/bin/env bash
set -euo pipefail

script_dir=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
pacscript_dir="${script_dir}/pacscript"
pacscript="${pacscript_dir}/nvidia-driver-run.pacscript"
generated_pacscript=''
download_tmp_file=''
mkdir -p "$pacscript_dir"

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

# title : voir nom de la fonction pour le role.
title() { printf '\n%s%s%s\n' "$bold$cyan" "$1" "$reset"; }
# separator : voir nom de la fonction pour le role.
separator() { printf '%s%s%s\n' "$dim" "------------------------------------------------------------" "$reset"; }
# spacer : voir nom de la fonction pour le role.
spacer() { echo; }
# info : voir nom de la fonction pour le role.
info() { printf '%s%s%s\n' "$blue" "$1" "$reset"; }
# warn : voir nom de la fonction pour le role.
warn() { printf '%s%s%s\n' "$yellow" "$1" "$reset"; }
# error : voir nom de la fonction pour le role.
error() { printf '%sERROR:%s %s\n' "$red$bold" "$reset" "$1" >&2; }

# command_exists : voir nom de la fonction pour le role.
command_exists() { command -v "$1" >/dev/null 2>&1; }

# run_as_root : voir nom de la fonction pour le role.
run_as_root() {
  local -a cmd=("$@")
  local cmd_str prompt_used=false pass=""
  local gui_backend=false

  if ((${#cmd[@]} == 0)); then
    error "Commande privilegiee vide."
    return 1
  fi

  cmd_str=$(printf '%q ' "${cmd[@]}")
  cmd_str=${cmd_str% }

  if [[ ${NVIDIA_GUI_BACKEND:-} =~ ^(1|true|yes|on)$ ]]; then
    gui_backend=true
  fi

  if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
    "${cmd[@]}"
    return $?
  fi

  if command_exists sudo; then
    if [[ $gui_backend == true ]]; then
      if sudo -n true 2>/dev/null && sudo -n "${cmd[@]}"; then
        return 0
      fi
    else
      if sudo "${cmd[@]}"; then
        return 0
      fi
    fi
  fi

  if command_exists pkexec; then
    if pkexec "${cmd[@]}"; then
      return 0
    fi
  fi

  if ! command_exists sudo; then
    error "Impossible d'elever les privileges: sudo introuvable."
    return 1
  fi

  if command_exists zenity; then
    prompt_used=true
    pass=$(zenity --password --title="Privilèges administrateur" --text="Mot de passe requis pour executer :\n${cmd_str}" 2>/dev/null || true)
  elif command_exists kdialog; then
    prompt_used=true
    pass=$(kdialog --password "Mot de passe requis pour executer : ${cmd_str}" 2>/dev/null || true)
  fi

  if [[ -n $pass ]]; then
    if echo "$pass" | sudo -S "${cmd[@]}"; then
      pass=""
      return 0
    fi
    pass=""
    error "Mot de passe incorrect."
    return 1
  fi

  if [[ $prompt_used == true ]]; then
    error "Authentification annulee."
    return 130
  fi

  return 1
}

# cleanup : voir nom de la fonction pour le role.
cleanup() {
  [[ -n ${download_tmp_file:-} ]] && rm -f -- "$download_tmp_file"
  [[ -n ${generated_pacscript:-} ]] && rm -f -- "$generated_pacscript"
  if [[ ${downloaded_by_script:-false} == true && ${OPT_KEEP_RUNFILE:-false} == false && -n ${downloaded_runfile:-} ]]; then
    rm -f -- "$downloaded_runfile"
  fi
}

# handle_interrupt : voir nom de la fonction pour le role.
handle_interrupt() {
  cleanup
  printf '\n%sInterruption utilisateur (Ctrl+C). Arret.%s\n' "$yellow" "$reset" >&2
  exit 130
}

trap cleanup EXIT
trap handle_interrupt INT TERM

# ver_ge : voir nom de la fonction pour le role.
ver_ge() {
  local lhs rhs
  lhs=$(printf '%s\n' "$1" | awk -F. '{ printf "%d%03d%03d\n", $1, $2, $3 }')
  rhs=$(printf '%s\n' "$2" | awk -F. '{ printf "%d%03d%03d\n", $1, $2, $3 }')
  [[ $lhs -ge $rhs ]]
}

# show_help : voir nom de la fonction pour le role.
show_help() {
  cat << EOF
Usage: $(basename "$0") [OPTIONS] [PACSTALL_ARGS...]

Configuration CLI pour le script d'installation NVIDIA.
Ce script automatise la recherche, le téléchargement et l'installation du pilote NVIDIA de manière non-interactive.
Sans argument, l'aide est affichee.

Options:
  -h, --help                 Affiche cette aide et quitte
  --check-dependencies       Verifie/installe les dependances puis quitte
  --inspect-dependencies     Inspecte les dependances sans installer puis quitte
  --print-local-runfiles     Affiche les runfiles locaux valides puis quitte
  --source <local|online>    Source du pilote (defaut: online)
  --runfile <fichier>        Fichier .run local (si --source local et absent: auto-detection dans pacscript/)
  --branch <branche>         Branche: latest|recommended|stable|feature|beta|legacy|all (defaut: latest)
  --version <version>        Version spécifique à télécharger (ex: 550.78)
  --gpu <modele>             Filtre pour vérifier la compatibilité avec un modèle de GPU (ex: "RTX 4090")
  --nvidia-open <true|false> Activer/Désactiver kernel-open (defaut: auto = true si >= 515)
  --action <1|2|3>           Action Pacstall: 1=(-PI), 2=(-PIB), 3=(-PIBK) (defaut: 1)
  --keep-runfile             Conserver le fichier .run téléchargé
  --print-versions           Affiche les versions détectées (recommended/latest/legacy) puis quitte
  --self-test                Exécute le test de diagnostic intégré puis quitte

Pacstall Args:
  Tout argument non reconnu est transmis à pacstall.
  Si des Pacstall Args sont fournis, ils remplacent --action.

Exemples:
  $(basename "$0")
  $(basename "$0") --check-dependencies
  $(basename "$0") --inspect-dependencies
  $(basename "$0") --branch recommended
  $(basename "$0") --source local --runfile ./NVIDIA-Linux-x86_64-580.95.05.run --action 2
  $(basename "$0") --print-versions
EOF
}

# self_test : voir nom de la fonction pour le role.
self_test() {
  local ok=true
  echo "== self-test =="
  for cmd in bash awk sed grep sort tac curl find df apt sudo lspci; do
    if command_exists "$cmd"; then echo "[OK] $cmd"; else echo "[KO] $cmd manquant"; ok=false; fi
  done
  if command_exists curl; then
    if curl -fsSL https://download.nvidia.com/XFree86/Linux-x86_64/latest.txt >/dev/null 2>&1; then echo "[OK] acces reseau NVIDIA"; else echo "[KO] acces reseau NVIDIA"; ok=false; fi
    if curl -fsSL https://www.nvidia.com/en-us/drivers/unix.md >/dev/null 2>&1; then echo "[OK] acces metadata branches"; else echo "[KO] acces metadata branches"; ok=false; fi
  fi
  if $ok; then echo "SELF-TEST: PASS"; return 0; fi
  echo "SELF-TEST: FAIL"; return 1
}



# install_missing_dependencies : voir nom de la fonction pour le role.
install_missing_dependencies() {
  local -a missing=("$@")
  if ! command_exists apt; then error "Ce script gere uniquement Debian/apt."; return 1; fi
  info "Installation automatique des dependances: ${missing[*]}"
  run_as_root apt update
  run_as_root apt install -y "${missing[@]}"
}

# download_file : voir nom de la fonction pour le role.
download_file() {
  local url=$1 out=$2
  if command_exists curl; then
    if [[ $out == "-" ]]; then curl -fsSL "$url"; else curl -fL --progress-bar -o "$out" "$url"; fi
  elif command_exists wget; then
    if [[ $out == "-" ]]; then wget -qO- "$url"; else wget -O "$out" "$url"; fi
  else
    error "curl ou wget est requis"
    return 1
  fi
}

# install_deb_file : voir nom de la fonction pour le role.
install_deb_file() {
  local deb_path=$1
  run_as_root apt update
  run_as_root apt install -y "$deb_path"
}

# ensure_spdx_licenses : voir nom de la fonction pour le role.
ensure_spdx_licenses() {
  local pkg='spdx-licenses'
  local deb_url="https://ftp.debian.org/debian/pool/main/s/${pkg}/${pkg}_3.27.0+ds-1_all.deb"
  if dpkg-query -W -f='${Status}\n' "$pkg" 2>/dev/null | grep -q "install ok installed"; then return 0; fi
  info "Installation de ${pkg}..."
  if run_as_root apt update && run_as_root apt install -y "$pkg"; then return 0; fi
  local tmp_deb
  tmp_deb=$(mktemp "/tmp/${pkg}.XXXXXX.deb")
  if download_file "$deb_url" "$tmp_deb"; then install_deb_file "$tmp_deb"; else rm -f "$tmp_deb"; return 1; fi
  rm -f "$tmp_deb"
}

# ensure_pacstall_installed : voir nom de la fonction pour le role.
ensure_pacstall_installed() {
  local releases_api='https://api.github.com/repos/pacstall/pacstall/releases/latest'
  local latest_html='https://github.com/pacstall/pacstall/releases/latest'
  local deb_url='' tmp_deb
  if [[ -f /tmp/pacstall ]]; then
    warn "/tmp/pacstall est un fichier, suppression pour restaurer le dossier attendu."
    if ! rm -f -- /tmp/pacstall 2>/dev/null; then
      run_as_root rm -f -- /tmp/pacstall
    fi
  fi
  if ! mkdir -p /tmp/pacstall 2>/dev/null; then
    run_as_root mkdir -p /tmp/pacstall
  fi
  if command_exists pacstall; then return 0; fi
  info "Installation de pacstall..."
  if command_exists curl; then
    deb_url=$(curl -fsSL "$releases_api" | sed -nE 's/.*"browser_download_url":[[:space:]]*"([^"]+\.deb)".*/\1/p' | head -n 1)
  fi
  if [[ -z $deb_url ]]; then
    deb_url=$(download_file "$latest_html" - | sed -nE 's/.*href="([^"]+\.deb)".*/https:\/\/github.com\1/p' | head -n 1)
  fi
  if [[ -z $deb_url ]]; then error "Impossible de trouver pacstall .deb"; return 1; fi
  info "Pacstall .deb: ${deb_url}"
  tmp_deb=$(mktemp "/tmp/pacstall.XXXXXX.deb")
  if download_file "$deb_url" "$tmp_deb"; then install_deb_file "$tmp_deb"; else rm -f "$tmp_deb"; return 1; fi
  rm -f "$tmp_deb"
  if ! command_exists pacstall; then
    error "pacstall reste introuvable apres installation du paquet."
    return 1
  fi
}

# check_dependencies : voir nom de la fonction pour le role.
check_dependencies() {
  local -a required=(awk curl df find grep sed sort tac lspci)
  local -a missing=()
  local -a missing_pkgs=()
  info "Etape 1/3: verification des outils systeme..."
  for dep in "${required[@]}"; do
    if ! command_exists "$dep"; then
      missing+=("$dep")
      if [[ $dep == lspci ]]; then missing_pkgs+=("pciutils"); else missing_pkgs+=("$dep"); fi
    fi
  done
  if ((${#missing[@]} > 0)); then
    warn "Outils manquants: ${missing[*]}"
    install_missing_dependencies "${missing_pkgs[@]}" || return 1
  else
    info "Outils systeme: OK"
  fi
  info "Etape 2/3: verification spdx-licenses..."
  if ! ensure_spdx_licenses; then error "spdx-licenses requis"; return 1; fi
  info "spdx-licenses: OK"
  info "Etape 3/3: verification pacstall..."
  if ! ensure_pacstall_installed; then error "pacstall requis"; return 1; fi
  info "pacstall: OK"
  return 0
}

## Inspecte les dependances sans installation et emet un format machine-readable.
inspect_dependencies_cli() {
  local -a required=(awk curl df find grep sed sort tac lspci)
  local -a missing_tools=()
  local -a missing_pkgs=()
  local dep
  local missing_spdx=false
  local missing_pacstall=false

  for dep in "${required[@]}"; do
    if ! command_exists "$dep"; then
      missing_tools+=("$dep")
      if [[ $dep == lspci ]]; then missing_pkgs+=("pciutils"); else missing_pkgs+=("$dep"); fi
    fi
  done

  if ! dpkg-query -W -f='${Status}\n' "spdx-licenses" 2>/dev/null | grep -q "install ok installed"; then
    missing_spdx=true
  fi
  if ! command_exists pacstall; then
    missing_pacstall=true
  fi

  printf 'MISSING_TOOLS=%s\n' "${missing_tools[*]}"
  printf 'MISSING_PACKAGES=%s\n' "${missing_pkgs[*]}"
  printf 'MISSING_SPDX=%s\n' "$missing_spdx"
  printf 'MISSING_PACSTALL=%s\n' "$missing_pacstall"

  if ((${#missing_tools[@]} > 0)) || [[ $missing_spdx == true || $missing_pacstall == true ]]; then
    printf 'HAS_MISSING=true\n'
  else
    printf 'HAS_MISSING=false\n'
  fi
}

# nvidia_list_versions : voir nom de la fonction pour le role.
nvidia_list_versions() {
  local base_url=$1
  curl -fsSL "$base_url/" 2>/dev/null | sed -nE 's/.*href=["'\'']?([0-9][^"'\''/]+)\/["'\'']?.*/\1/p' | sort -uV
}

# fetch_latest_version_from_latest_txt : voir nom de la fonction pour le role.
fetch_latest_version_from_latest_txt() {
  local base_url=$1
  curl -fsSL "${base_url}/latest.txt" 2>/dev/null | awk 'NR==1 {print $1}'
}

# fetch_branch_markers_unix_md : voir nom de la fonction pour le role.
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

# detect_nvidia_gpu_model : voir nom de la fonction pour le role.
detect_nvidia_gpu_model() {
  local line model
  line=$(lspci -nn 2>/dev/null | grep -Ei 'VGA|3D' | grep -i nvidia | head -n 1 || true)
  [[ -z $line ]] && return 1
  model=$(printf '%s\n' "$line" | sed -nE 's/.*\[(.*)\].*/\1/p')
  [[ -z $model ]] && model="$line"
  DETECTED_GPU_MODEL=$model
  return 0
}

# version_supports_gpu : voir nom de la fonction pour le role.
version_supports_gpu() {
  local version=$1 gpu_model=$2 base_url=$3
  local chips_url="${base_url}/${version}/README/supportedchips.html"
  curl -fsSL "$chips_url" 2>/dev/null | grep -Fqi "$gpu_model"
}

# major_of_version : voir nom de la fonction pour le role.
major_of_version() {
  printf '%s\n' "${1%%.*}"
}

# gpu_support_label_for_version : voir nom de la fonction pour le role.
gpu_support_label_for_version() {
  local version=$1 base_url=$2 major
  major=$(major_of_version "$version")

  case "$major" in
    390) printf '%s' "Legacy Fermi (GeForce 4xx/5xx)" ;;
    470) printf '%s' "Legacy Kepler (GeForce 6xx/7xx)" ;;
    495|510|515|520|525|530|535|545|550|555|560|565|570|575|580)
      printf '%s' "Maxwell/Pascal/Turing/Ampere/Ada - GTX 9xx/10xx/16xx, RTX 20xx/30xx/40xx"
      ;;
    590|595|6[0-9][0-9]|[7-9][0-9][0-9])
      printf '%s' "Turing/Ampere/Ada/Blackwell - RTX 20xx/30xx/40xx/50xx"
      ;;
    460|465)
      printf '%s' "Maxwell/Pascal/Turing - GTX 9xx/10xx/16xx, RTX 20xx"
      ;;
    *) printf '%s' "Serie ${major}.x" ;;
  esac
}

# runfile_is_valid : voir nom de la fonction pour le role.
runfile_is_valid() {
  local file=$1
  [[ -f $file ]] || return 1
  [[ ${file##*/} == NVIDIA-Linux-x86_64-*.run || ${file##*/} == NVIDIA-Linux-x86_64-*.run.part ]] || return 1
  sh "$file" --check >/dev/null 2>&1
}

# collect_valid_runfiles : voir nom de la fonction pour le role.
collect_valid_runfiles() {
  local file
  local -a candidates
  VALID_RUNFILES=()
  mapfile -t candidates < <(find "$pacscript_dir" -maxdepth 1 -type f -name 'NVIDIA-Linux-x86_64-*.run' 2>/dev/null | sort -u)
  for file in "${candidates[@]}"; do
    if runfile_is_valid "$file"; then
      VALID_RUNFILES+=("$file")
    fi
  done
}

# get_locale_mirror_urls : voir nom de la fonction pour le role.
get_locale_mirror_urls() {
  local raw locale_code lang_code country_code
  raw="${LANG:-${LC_ALL:-${LC_MESSAGES:-${LANGUAGE:-}}}}"
  if [[ -z $raw || ${raw,,} == c || ${raw,,} == c.utf-8 || ${raw,,} == posix ]]; then
    if [[ -r /etc/default/locale ]]; then
      raw=$(awk -F= '/^LANG=/{gsub(/"/,"",$2); if (!lang) lang=$2} /^LANGUAGE=/{gsub(/"/,"",$2); if (!language) language=$2} END{if (lang && lang !~ /^(C|C\.UTF-8|POSIX)$/) print lang; else if (language) print language;}' /etc/default/locale)
    fi
  fi
  raw="${raw%%:*}"; raw="${raw%%.*}"; raw="${raw%%@*}"
  locale_code="${raw,,}"; locale_code="${locale_code//-/_}"
  lang_code=''; country_code=''
  if [[ $locale_code == *_* ]]; then lang_code="${locale_code%%_*}"; country_code="${locale_code##*_}"
  elif [[ $locale_code =~ ^[a-z]{2}$ ]]; then lang_code="$locale_code"; fi

  local -a mirrors=()
  if [[ -n $country_code ]]; then mirrors+=("https://${country_code}.download.nvidia.com/XFree86/Linux-x86_64"); fi
  if [[ -n $lang_code ]]; then mirrors+=("https://${lang_code}.download.nvidia.com/XFree86/Linux-x86_64"); fi
  mirrors+=("https://download.nvidia.com/XFree86/Linux-x86_64" "https://us.download.nvidia.com/XFree86/Linux-x86_64")
  printf '%s\n' "${mirrors[@]}" | awk '!seen[$0]++'
}

# pick_online_runfile_cli : voir nom de la fonction pour le role.
pick_online_runfile_cli() {
  local base_url versions selected_ver run_url run_name candidate local_versions
  local stable_major='' feature_major='' legacy_major=''
  local detected_gpu=''
  local latest_available recommended_available
  local -a mirror_urls all_versions branch_versions
  PICKED_RUNFILE=''

  info "Recherche NVIDIA en ligne..."

  mapfile -t mirror_urls < <(get_locale_mirror_urls)
  mirror_urls+=("https://download.nvidia.com/XFree86/Linux-x86_64" "https://us.download.nvidia.com/XFree86/Linux-x86_64")
  mapfile -t mirror_urls < <(printf '%s\n' "${mirror_urls[@]}" | awk '!seen[$0]++')
  base_url=''
  versions=''
  for candidate in "${mirror_urls[@]}"; do
    if local_versions=$(nvidia_list_versions "$candidate"); then
      if [[ -n $local_versions ]]; then versions=$local_versions; base_url=$candidate; break; fi
    fi
  done
  if [[ -z $base_url ]]; then
    for candidate in "${mirror_urls[@]}"; do
      if latest_version=$(fetch_latest_version_from_latest_txt "$candidate"); then
        if [[ -n $latest_version ]]; then versions=$latest_version; base_url=$candidate; break; fi
      fi
    done
  fi
  if [[ -z $base_url ]]; then error "Impossible de recuperer la liste des versions depuis NVIDIA."; return 1; fi
  if [[ $versions != *$'\n'* ]]; then
    for candidate in "https://download.nvidia.com/XFree86/Linux-x86_64" "https://us.download.nvidia.com/XFree86/Linux-x86_64"; do
      if local_versions=$(nvidia_list_versions "$candidate"); then
        if [[ -n $local_versions ]]; then versions=$local_versions; break; fi
      fi
    done
  fi

  fetch_branch_markers_unix_md || true
  if [[ -n ${BRANCH_STABLE_VERSION:-} ]]; then stable_major=$(major_of_version "$BRANCH_STABLE_VERSION"); fi
  if [[ -n ${BRANCH_FEATURE_VERSION:-} ]]; then feature_major=$(major_of_version "$BRANCH_FEATURE_VERSION"); fi
  if [[ -n ${BRANCH_LEGACY_VERSION:-} ]]; then legacy_major=$(major_of_version "$BRANCH_LEGACY_VERSION"); fi

  mapfile -t all_versions < <(printf '%s\n' "$versions" | sort -uV | tac)
  if ((${#all_versions[@]} == 0)); then error "Aucune version exploitable trouvee."; return 1; fi
  latest_available="${all_versions[0]}"

  if [[ -n $OPT_VERSION ]]; then
    local found=false
    for v in "${all_versions[@]}"; do
      if [[ $v == "$OPT_VERSION" ]]; then found=true; break; fi
    done
    if [[ $found == false ]]; then error "La version $OPT_VERSION n'a pas ete trouvee."; return 1; fi
    selected_ver="$OPT_VERSION"
  else
    recommended_available="${BRANCH_STABLE_VERSION:-}"
    [[ -z $recommended_available ]] && recommended_available="${BRANCH_FEATURE_VERSION:-}"
    [[ -z $recommended_available ]] && recommended_available="${BRANCH_BETA_VERSION:-}"
    [[ -z $recommended_available ]] && recommended_available="$latest_available"

    detected_gpu="$OPT_GPU"
    if [[ -z $detected_gpu ]]; then
      if command_exists lspci && detect_nvidia_gpu_model; then detected_gpu=$DETECTED_GPU_MODEL; fi
    fi
    if [[ -n $detected_gpu ]]; then
      if ! version_supports_gpu "$recommended_available" "$detected_gpu" "$base_url"; then
        for selected_ver in "${all_versions[@]}"; do
          if version_supports_gpu "$selected_ver" "$detected_gpu" "$base_url"; then recommended_available=$selected_ver; break; fi
        done
      fi
    fi

    if [[ $OPT_BRANCH == "recommended" ]]; then
      selected_ver=$recommended_available
    elif [[ $OPT_BRANCH == "latest" ]]; then
      selected_ver=$latest_available
    else
      branch_versions=()
      case "$OPT_BRANCH" in
        stable) if [[ -n $stable_major ]]; then mapfile -t branch_versions < <(printf '%s\n' "${all_versions[@]}" | grep -E "^${stable_major}\."); fi ;;
        feature) if [[ -n $feature_major ]]; then mapfile -t branch_versions < <(printf '%s\n' "${all_versions[@]}" | grep -E "^${feature_major}\."); fi ;;
        beta) if [[ -n ${BRANCH_BETA_VERSION:-} ]]; then mapfile -t branch_versions < <(printf '%s\n' "${all_versions[@]}" | grep -Fx "${BRANCH_BETA_VERSION}"); fi ;;
        legacy) mapfile -t branch_versions < <(printf '%s\n' "${all_versions[@]}" | grep -E '^(580|470|390)\.') ;;
        all) branch_versions=("${all_versions[@]}") ;;
        *) error "Branche non reconnue: $OPT_BRANCH"; return 1 ;;
      esac
      if ((${#branch_versions[@]} == 0)); then error "Aucune version pour cette branche: $OPT_BRANCH"; return 1; fi
      
      if [[ -n $detected_gpu ]]; then
        for v in "${branch_versions[@]}"; do
          if version_supports_gpu "$v" "$detected_gpu" "$base_url"; then selected_ver="$v"; break; fi
        done
        if [[ -z ${selected_ver:-} ]]; then
          warn "Aucune version de $OPT_BRANCH ne supporte $detected_gpu. Fallback sur la plus recente."
          selected_ver="${branch_versions[0]}"
        fi
      else
        selected_ver="${branch_versions[0]}"
      fi
    fi
  fi

  run_name="NVIDIA-Linux-x86_64-${selected_ver}.run"
  run_url="${base_url}/${selected_ver}/${run_name}"
  if ! curl -fsI "$run_url" >/dev/null; then error "Runfile introuvable: ${run_url}"; return 1; fi

  info "Telechargement: $run_url"
  download_tmp_file="${pacscript_dir}/${run_name}.part"
  rm -f -- "$download_tmp_file"
  curl -fL --progress-bar -o "$download_tmp_file" "$run_url"
  if ! runfile_is_valid "$download_tmp_file"; then rm -f -- "$download_tmp_file"; error "Telechargement invalide."; return 1; fi

  mv -f -- "$download_tmp_file" "${pacscript_dir}/${run_name}"
  download_tmp_file=''
  PICKED_RUNFILE="${pacscript_dir}/${run_name}"
  info "Telechargement termine."
  return 0
}

# print_versions_cli : voir nom de la fonction pour le role.
print_versions_cli() {
  local base_url versions latest_version local_versions
  local -a mirror_urls all_versions
  
  mapfile -t mirror_urls < <(get_locale_mirror_urls)
  mirror_urls+=("https://download.nvidia.com/XFree86/Linux-x86_64" "https://us.download.nvidia.com/XFree86/Linux-x86_64")
  mapfile -t mirror_urls < <(printf '%s\n' "${mirror_urls[@]}" | awk '!seen[$0]++')
  base_url=''
  versions=''
  for candidate in "${mirror_urls[@]}"; do
    if local_versions=$(nvidia_list_versions "$candidate"); then
      if [[ -n $local_versions ]]; then versions=$local_versions; base_url=$candidate; break; fi
    fi
  done
  if [[ -z $base_url ]]; then
    for candidate in "${mirror_urls[@]}"; do
      if latest_version=$(fetch_latest_version_from_latest_txt "$candidate"); then
        if [[ -n $latest_version ]]; then versions=$latest_version; base_url=$candidate; break; fi
      fi
    done
  fi
  if [[ -z $base_url ]]; then echo "ERROR=Network"; return 1; fi
  if [[ $versions != *$'\n'* ]]; then
    for candidate in "https://download.nvidia.com/XFree86/Linux-x86_64" "https://us.download.nvidia.com/XFree86/Linux-x86_64"; do
      if local_versions=$(nvidia_list_versions "$candidate"); then
        if [[ -n $local_versions ]]; then versions=$local_versions; break; fi
      fi
    done
  fi

  fetch_branch_markers_unix_md >/dev/null 2>&1 || true

  mapfile -t all_versions < <(printf '%s\n' "$versions" | sort -uV | tac)
  if ((${#all_versions[@]} == 0)); then echo "ERROR=NoVersions"; return 1; fi
  latest_available="${all_versions[0]}"

  recommended_available="${BRANCH_STABLE_VERSION:-}"
  [[ -z $recommended_available ]] && recommended_available="${BRANCH_FEATURE_VERSION:-}"
  [[ -z $recommended_available ]] && recommended_available="${BRANCH_BETA_VERSION:-}"
  [[ -z $recommended_available ]] && recommended_available="$latest_available"

  local detected_gpu=''
  if command_exists lspci && detect_nvidia_gpu_model; then detected_gpu=$DETECTED_GPU_MODEL; fi
  if [[ -n $detected_gpu ]]; then
    if ! version_supports_gpu "$recommended_available" "$detected_gpu" "$base_url"; then
      for selected_ver in "${all_versions[@]}"; do
        if version_supports_gpu "$selected_ver" "$detected_gpu" "$base_url"; then recommended_available=$selected_ver; break; fi
      done
    fi
  fi

  local legacy580='' legacy470='' legacy390=''
  for v in "${all_versions[@]}"; do
    if [[ -z $legacy580 && $v == 580.* ]]; then legacy580=$v; fi
    if [[ -z $legacy470 && $v == 470.* ]]; then legacy470=$v; fi
    if [[ -z $legacy390 && $v == 390.* ]]; then legacy390=$v; fi
  done

  echo "RECOMMENDED=$recommended_available"
  echo "LATEST=$latest_available"
  echo "LEGACY580=$legacy580"
  echo "LEGACY470=$legacy470"
  echo "LEGACY390=$legacy390"
  echo "LATEST_SUPPORT=$(gpu_support_label_for_version "$latest_available" "$base_url")"
  echo "DETECTED_GPU=$detected_gpu"
}

# Affiche les runfiles locaux valides (nom de fichier) puis quitte.
print_local_runfiles_cli() {
  local rf
  collect_valid_runfiles
  for rf in "${VALID_RUNFILES[@]}"; do
    printf '%s\n' "${rf##*/}"
  done
}

# Lance pacstall avec élévation de privilèges unifiée.
run_pacstall_gui() {
  run_as_root pacstall "${PACSTALL_ARGS[@]}" "$generated_pacscript"
}

# Initialise toutes les options CLI avec leurs valeurs par défaut.
init_options() {
  OPT_SOURCE="online"
  OPT_RUNFILE=""
  OPT_BRANCH="latest"
  OPT_VERSION=""
  OPT_GPU=""
  OPT_NVIDIA_OPEN=""
  OPT_KEEP_RUNFILE=false
  OPT_PACSTALL_ACTION=1
  PACSTALL_ARGS=()
  downloaded_runfile=''
  downloaded_by_script=false
}

# Parse les arguments CLI et gère les sorties immédiates (help/self-test/print-versions).
parse_args() {
  if [[ $# -eq 0 ]]; then
    show_help
    exit 0
  fi

  while [[ $# -gt 0 ]]; do
    case $1 in
      -h|--help) show_help; exit 0 ;;
      --check-dependencies) check_dependencies; exit $? ;;
      --inspect-dependencies) inspect_dependencies_cli; exit 0 ;;
      --print-local-runfiles) print_local_runfiles_cli; exit 0 ;;
      --source) OPT_SOURCE="$2"; shift 2 ;;
      --runfile) OPT_RUNFILE="$2"; shift 2 ;;
      --branch) OPT_BRANCH="$2"; shift 2 ;;
      --version) OPT_VERSION="$2"; shift 2 ;;
      --gpu) OPT_GPU="$2"; shift 2 ;;
      --nvidia-open) OPT_NVIDIA_OPEN="$2"; shift 2 ;;
      --action) OPT_PACSTALL_ACTION="$2"; shift 2 ;;
      --keep-runfile) OPT_KEEP_RUNFILE=true; shift ;;
      --self-test) self_test; exit $? ;;
      --print-versions) print_versions_cli; exit 0 ;;
      -*) PACSTALL_ARGS+=("$1"); shift ;;
      *) PACSTALL_ARGS+=("$1"); shift ;;
    esac
  done
}

# Sélectionne le runfile local ou distant selon les options.
resolve_runfile() {
  if [[ $OPT_SOURCE == "local" ]]; then
    if [[ -z $OPT_RUNFILE ]]; then
      collect_valid_runfiles
      if ((${#VALID_RUNFILES[@]} > 0)); then
        runfile="${VALID_RUNFILES[-1]}"
        info "Utilisation du runfile local: ${runfile##*/}"
      else
        error "Aucun runfile local."
        return 1
      fi
    else
      candidate_runfile="$OPT_RUNFILE"
      if [[ ! -f $candidate_runfile && -f "$pacscript_dir/$OPT_RUNFILE" ]]; then
        candidate_runfile="$pacscript_dir/$OPT_RUNFILE"
      fi
      if ! runfile_is_valid "$candidate_runfile"; then error "Runfile local invalide: $OPT_RUNFILE"; return 1; fi
      runfile="${candidate_runfile##*/}"
      if [[ $(dirname "$(realpath "$candidate_runfile")") != "$(realpath "$pacscript_dir")" ]]; then
        cp "$candidate_runfile" "$pacscript_dir/$runfile"
      fi
      runfile="$pacscript_dir/$runfile"
    fi
  else
    pick_online_runfile_cli || return 1
    downloaded_runfile=$PICKED_RUNFILE
    [[ -n $downloaded_runfile ]] || return 1
    downloaded_by_script=true
    runfile=${downloaded_runfile##*/}
  fi
}

# Déduit pkgver/nvidia_open, prépare les args pacstall et génère le pacscript final.
prepare_pacscript() {
  pkgver=${runfile##*/}
  pkgver=${pkgver#NVIDIA-Linux-x86_64-}
  pkgver=${pkgver%.run}
  generated_pacscript="${pacscript_dir}/nvidia-driver-run-${pkgver}.pacscript"

  if ver_ge "$pkgver" "515"; then
    if [[ -z $OPT_NVIDIA_OPEN ]]; then nvidia_open=true; else nvidia_open=$OPT_NVIDIA_OPEN; fi
  else
    nvidia_open=false
  fi

  if ((${#PACSTALL_ARGS[@]} == 0)); then
    case "$OPT_PACSTALL_ACTION" in
      1) PACSTALL_ARGS=(-PI) ;;
      2) PACSTALL_ARGS=(-PIB) ;;
      3) PACSTALL_ARGS=(-PIBK) ;;
      *) PACSTALL_ARGS=(-PI) ;;
    esac
  fi

  sed -e "s|^pkgver=.*|pkgver='${pkgver}'|" -e "s|^nvidia_open=.*|nvidia_open='${nvidia_open}'|" "$pacscript" > "$generated_pacscript"
}

# Nettoie le runfile téléchargé si demandé.
cleanup_downloaded_runfile() {
  if [[ $downloaded_by_script == true && $OPT_KEEP_RUNFILE == false ]]; then
    rm -f -- "$downloaded_runfile"
    info "Runfile nettoye."
  fi
}

# Orchestration principale de la CLI.
main() {
  init_options
  parse_args "$@"

  if [[ ! -f $pacscript ]]; then error "pacscript introuvable: ${pacscript}"; exit 1; fi
  if ! check_dependencies; then error "Dependances incompletes."; exit 1; fi
  if ! resolve_runfile; then exit 1; fi

  prepare_pacscript
  info "Lancement de Pacstall avec $runfile..."
  run_pacstall_gui
  cleanup_downloaded_runfile
}

main "$@"
