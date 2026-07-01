#!/usr/bin/env bash
set -euo pipefail

script_dir=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
cli_script="${script_dir}/debian-nvidia-all-cli.sh"
pacscript_dir="${script_dir}/pacscript"

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

UI_BACK='__BACK__'
UI_QUIT='__QUIT__'

## Affiche un titre colore.
title() { printf '\n%s%s%s\n' "$bold$cyan" "$1" "$reset"; }
## Affiche un separateur visuel.
separator() { printf '%s%s%s\n' "$dim" "------------------------------------------------------------" "$reset"; }
## Ajoute une ligne vide.
spacer() { echo; }
## Affiche un message d'information.
info() { printf '%s%s%s\n' "$blue" "$1" "$reset"; }
## Affiche un message d'avertissement.
warn() { printf '%s%s%s\n' "$yellow" "$1" "$reset"; }
## Affiche un message d'erreur.
error() { printf '%sERROR:%s %s\n' "$red$bold" "$reset" "$1" >&2; }

## Affiche l'en-tete du frontend TUI.
ui_header() {
  clear
  printf '%s%sNVIDIA Driver All%s\n' "$bold" "$cyan" "$reset"
  printf '%sFrontend TUI%s\n' "$dim" "$reset"
  separator
}

## Pose une question oui/non avec valeur par defaut.
yes_no() {
  local prompt=$1 default=${2:-yes} reply
  local suffix='[O/n]'
  [[ $default == no ]] && suffix='[o/N]'
  while true; do
    printf '%s%s%s %s%s%s: ' "$blue" "$prompt" "$reset" "$dim" "$suffix" "$reset"
    read -r reply
    case ${reply,,} in
      "") [[ $default == yes ]] && return 0 || return 1 ;;
      o|oui|y|yes) return 0 ;;
      n|non|no) return 1 ;;
      *) warn "Repondre par oui ou non." ;;
    esac
  done
}

## Affiche un menu texte et retourne le tag selectionne.
ui_menu() {
  local menu_title=$1 prompt=$2 allow_back=$3 allow_quit=$4 default_tag=$5
  shift 5
  local -a pairs=("$@")
  local reply i default_index=1
  local -a tags=() labels=()

  ui_header >/dev/tty
  title "$menu_title" >/dev/tty
  printf '%s%s%s\n' "$blue" "$prompt" "$reset" >/dev/tty
  spacer >/dev/tty

  for ((i=0; i<${#pairs[@]}; i+=2)); do
    tags+=("${pairs[$i]}")
    labels+=("${pairs[$((i+1))]}")
  done
  for i in "${!tags[@]}"; do
    printf '  %s%2d)%s %s%s%s\n' "$green" "$((i + 1))" "$reset" "$dim" "${labels[$i]}" "$reset" >/dev/tty
    [[ ${tags[$i]} == "$default_tag" ]] && default_index=$((i + 1))
  done

  spacer >/dev/tty
  printf '%s%s%s\n' "$cyan" "Aide saisie :" "$reset" >/dev/tty
  printf '  - Tape un %sNUMERO%s puis %sEntree%s pour choisir une option.\n' "$blue" "$reset" "$green" "$reset" >/dev/tty
  printf '  - Appuie simplement sur %sEntree%s pour choisir l''option par defaut.\n' "$green" "$reset" >/dev/tty
  [[ $allow_back == yes ]] && printf '  - Tape %sb%s puis %sEntree%s pour RETOURNER a l''etape precedente.\n' "$blue" "$reset" "$green" "$reset" >/dev/tty
  [[ $allow_quit == yes ]] && printf '  - Tape %sq%s puis %sEntree%s pour %sANNULER%s l''assistant.\n' "$blue" "$reset" "$green" "$reset" "$red" "$reset" >/dev/tty
  spacer >/dev/tty

  while true; do
    printf '%sVotre choix%s %s[%d]%s: ' "$bold" "$reset" "$dim" "$default_index" "$reset" >/dev/tty
    read -r reply </dev/tty
    [[ -z $reply ]] && reply=$default_index
    if [[ ${reply,,} == b && $allow_back == yes ]]; then printf '%s' "$UI_BACK"; return 0; fi
    if [[ ${reply,,} == q && $allow_quit == yes ]]; then printf '%s' "$UI_QUIT"; return 0; fi
    if [[ $reply =~ ^[0-9]+$ ]] && ((reply >= 1 && reply <= ${#tags[@]})); then
      printf '%s' "${tags[$((reply - 1))]}"
      return 0
    fi
    warn "Choix invalide." >/dev/tty
  done
}

## Verifie la presence du backend CLI et lance son check dependances.
check_backend_ready() {
  local inspect_out missing_tools missing_pkgs missing_spdx missing_pacstall missing_kernel_headers kernel_release kernel_header_pkgs has_missing
  [[ -f $cli_script ]] || { error "CLI introuvable: ${cli_script}"; return 1; }
  ui_header
  title "Verification initiale"
  info "Etape 1/2: inspection des dependances via le backend CLI..."
  inspect_out=$(bash "$cli_script" --inspect-dependencies) || return 1

  missing_tools=$(printf '%s\n' "$inspect_out" | sed -n 's/^MISSING_TOOLS=//p')
  missing_pkgs=$(printf '%s\n' "$inspect_out" | sed -n 's/^MISSING_PACKAGES=//p')
  missing_spdx=$(printf '%s\n' "$inspect_out" | sed -n 's/^MISSING_SPDX=//p')
  missing_pacstall=$(printf '%s\n' "$inspect_out" | sed -n 's/^MISSING_PACSTALL=//p')
  missing_kernel_headers=$(printf '%s\n' "$inspect_out" | sed -n 's/^MISSING_KERNEL_HEADERS=//p')
  kernel_release=$(printf '%s\n' "$inspect_out" | sed -n 's/^KERNEL_RELEASE=//p')
  kernel_header_pkgs=$(printf '%s\n' "$inspect_out" | sed -n 's/^KERNEL_HEADER_PACKAGES=//p')
  has_missing=$(printf '%s\n' "$inspect_out" | sed -n 's/^HAS_MISSING=//p')

  if [[ $has_missing == "true" ]]; then
    info "Etape 2/2: dependances manquantes detectees."
    title "Dependances requises"
    [[ -n $missing_tools ]] && warn "Outils manquants: $missing_tools"
    [[ -n $missing_pkgs ]] && warn "Paquets a installer: $missing_pkgs"
    [[ $missing_kernel_headers == "true" ]] && warn "Headers noyau manquants (${kernel_release}): ${kernel_header_pkgs}"
    [[ $missing_spdx == "true" ]] && warn "Paquet requis manquant: spdx-licenses"
    [[ $missing_pacstall == "true" ]] && warn "Outil requis manquant: pacstall"
    if ! yes_no "Continuer et installer automatiquement ces dependances ?" yes; then
      warn "Interrompu."
      return 1
    fi
    spacer
    printf '%sAppuie sur Entree pour lancer l''installation des dependances...%s' "$dim" "$reset"
    read -r
    info "Installation des dependances via le backend CLI..."
    bash "$cli_script" --check-dependencies
    info "Verification initiale terminee."
    spacer
    printf '%sAppuie sur Entree pour continuer...%s' "$dim" "$reset"
    read -r
  else
    info "Etape 2/2: aucune dependance manquante."
    info "Dependances: OK"
    sleep 2
  fi
}

## Retourne 0 si au moins un runfile local valide est disponible via la CLI.
has_local_runfiles() {
  local first_line=''
  first_line=$(bash "$cli_script" --print-local-runfiles | head -n 1 || true)
  [[ -n $first_line ]]
}

## UI locale: selectionne un runfile local depuis la liste fournie par la CLI.
select_local_runfile_ui() {
  local -a candidates=()
  local -a menu=()
  local choice

  mapfile -t candidates < <(bash "$cli_script" --print-local-runfiles)
  if ((${#candidates[@]} == 0)); then
    error "Aucun runfile local detecte dans ${pacscript_dir}."
    return 1
  fi

  for rf in "${candidates[@]}"; do
    menu+=("${rf##*/}" "${rf##*/}")
  done

  choice=$(ui_menu "Selection Locale" "Choisir un installateur .run local" yes yes "${candidates[-1]##*/}" "${menu[@]}")
  [[ $choice == "$UI_QUIT" ]] && return 2
  [[ $choice == "$UI_BACK" ]] && return 3
  SELECTED_RUNFILE="$choice"
  return 0
}

## Orchestration principale du frontend TUI.
main() {
  local source_mode branch_choice nvidia_open_mode action_choice action_label
  local -a cli_args=()

  if [[ ${1:-} == "--self-test" ]]; then
    bash "$cli_script" --self-test
    exit $?
  fi

  check_backend_ready || exit 1

  if has_local_runfiles; then
    source_mode=$(ui_menu "Selection Source" "Choisir la source des pilotes NVIDIA" no yes "online" \
      "online" "Recherche et telechargement en ligne" \
      "local" "Utiliser un Runfile local")
  else
    warn "Aucun Runfile local valide detecte. Le mode local est masque."
    source_mode=$(ui_menu "Selection Source" "Choisir la source des pilotes NVIDIA" no yes "online" \
      "online" "Recherche et telechargement en ligne")
  fi
  [[ $source_mode == "$UI_QUIT" || -z $source_mode ]] && exit 0

  cli_args=(--keep-runfile --source "$source_mode")

  if [[ $source_mode == "local" ]]; then
    if ! select_local_runfile_ui; then
      rc=$?
      [[ $rc -eq 2 ]] && exit 0
      if [[ $rc -eq 3 ]]; then
        exec "$0"
      fi
      exit 1
    fi
    cli_args+=(--runfile "$SELECTED_RUNFILE")
  else
    branch_choice=$(ui_menu "Branche NVIDIA" "Choisir la branche (la CLI fera la resolution exacte)" yes yes "recommended" \
      "recommended" "Branche recommandee" \
      "latest" "Derniere version" \
      "stable" "Production" \
      "feature" "Nouvelles fonctions" \
      "beta" "Beta" \
      "legacy" "Legacy" \
      "all" "Toutes")
    [[ $branch_choice == "$UI_QUIT" || -z $branch_choice ]] && exit 0
    [[ $branch_choice == "$UI_BACK" ]] && exec "$0"
    cli_args+=(--branch "$branch_choice")
  fi

  nvidia_open_mode=$(ui_menu "Module noyau" "Comportement kernel-open" yes yes "auto" \
    "auto" "Laisser la CLI decider selon version" \
    "proprietaire" "Forcer module proprietaire" \
    "open-kernel-module" "Forcer open-kernel-module")
  [[ $nvidia_open_mode == "$UI_QUIT" || -z $nvidia_open_mode ]] && exit 0
  [[ $nvidia_open_mode == "$UI_BACK" ]] && exec "$0"
  case "$nvidia_open_mode" in
    auto) ;;
    proprietaire) cli_args+=(--nvidia-open "false") ;;
    open-kernel-module) cli_args+=(--nvidia-open "true") ;;
  esac

  action_choice=$(ui_menu "Action Pacstall" "Choisir l'action" yes yes "1" \
    "1" "Installer apres construction (-PI)" \
    "2" "Construire seulement (-PIB)" \
    "3" "Construire + debug (-PIBK)")
  [[ $action_choice == "$UI_QUIT" || -z $action_choice ]] && exit 0
  [[ $action_choice == "$UI_BACK" ]] && exec "$0"
  case "$action_choice" in
    1) action_label="Installer apres construction (-PI)" ;;
    2) action_label="Construire seulement (-PIB)" ;;
    3) action_label="Construire + debug (-PIBK)" ;;
    *) action_label="Inconnue" ;;
  esac
  cli_args+=(--action "$action_choice")

  title "Resume"
  printf '  %-15s %s\n' "Source:" "$source_mode"
  [[ $source_mode == local ]] && printf '  %-15s %s\n' "Runfile:" "$SELECTED_RUNFILE"
  [[ $source_mode == online ]] && printf '  %-15s %s\n' "Branche:" "$branch_choice"
  printf '  %-15s %s\n' "Module noyau:" "$nvidia_open_mode"
  printf '  %-15s %s\n' "Action:" "$action_label"
  printf '  %-15s %s\n' "Backend:" "${cli_script}"

  spacer
  if ! yes_no "Continuer et lancer la CLI ?" yes; then
    warn "Annule."
    exit 0
  fi

  title "Lancement du backend CLI"
  info "Commande: bash ${cli_script} ${cli_args[*]}"
  bash "$cli_script" "${cli_args[@]}"
}

main "$@"
