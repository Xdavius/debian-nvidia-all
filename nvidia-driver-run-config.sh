#!/usr/bin/env bash
set -euo pipefail

script_dir=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
pacscript="${script_dir}/nvidia-driver-run.pacscript"

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

info() {
  printf '%s%s%s\n' "$blue" "$1" "$reset"
}

warn() {
  printf '%s%s%s\n' "$yellow" "$1" "$reset"
}

error() {
  printf '%sERROR:%s %s\n' "$red$bold" "$reset" "$1" >&2
}

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

if [[ ! -f $pacscript ]]; then
  error "pacscript introuvable: ${pacscript}"
  exit 1
fi

if ! command -v pacstall >/dev/null 2>&1; then
  error "pacstall est introuvable dans le PATH."
  exit 1
fi

mapfile -t runfiles < <(find "$script_dir" -maxdepth 1 -type f -name 'NVIDIA-Linux-x86_64-*.run' | sort)

if ((${#runfiles[@]} == 0)); then
  error "aucun NVIDIA-Linux-x86_64-*.run trouve dans ${script_dir}."
  exit 1
fi

printf '%s%sNVIDIA Driver Run%s\n' "$bold" "$cyan" "$reset"
printf '%sAssistant de construction Pacstall%s\n' "$dim" "$reset"

title "Installateurs disponibles"
for i in "${!runfiles[@]}"; do
  base=${runfiles[$i]##*/}
  printf '  %s%2d)%s %s\n' "$green" "$((i + 1))" "$reset" "$base"
done

default_selected=${#runfiles[@]}
while true; do
  printf 'Choisir la version a empaqueter %s[1-%d, defaut %d]%s: ' "$dim" "${#runfiles[@]}" "$default_selected" "$reset"
  read -r selected
  [[ -z $selected ]] && selected=$default_selected
  if [[ $selected =~ ^[0-9]+$ ]] && ((selected >= 1 && selected <= ${#runfiles[@]})); then
    break
  fi
  warn "Choix invalide."
done

runfile=${runfiles[$((selected - 1))]##*/}
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
  title "Action Pacstall"
  printf '  %s1)%s Installer le paquet apres construction %s(-I)%s\n' "$green" "$reset" "$dim" "$reset"
  printf '  %s2)%s Construire le paquet seulement %s(-IB)%s\n' "$green" "$reset" "$dim" "$reset"
  printf '  %s3)%s Construire et garder les fichiers pour debogage %s(-IBK)%s\n' "$green" "$reset" "$dim" "$reset"

  while true; do
    printf 'Choisir l'\''action %s[2]%s: ' "$dim" "$reset"
    read -r action
    case $action in
      1)  pacstall_args=(-I); action_label="installer apres construction"; break ;;
      ""|2) pacstall_args=(-IB); action_label="construire seulement"; break ;;
      3)  pacstall_args=(-IBK); action_label="construire et garder les fichiers de debogage"; break ;;
      *)  warn "Choix invalide." ;;
    esac
  done
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
trap 'rm -f "$generated_pacscript"' EXIT

title "Lancement de Pacstall"
pacstall "${pacstall_args[@]}" "$generated_pacscript"
