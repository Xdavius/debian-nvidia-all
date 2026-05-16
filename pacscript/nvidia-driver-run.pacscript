# shellcheck shell=bash
# nvidia-driver-run.pacscript
#
# Repaquette l'installateur officiel NVIDIA .run en un paquet compatible Debian.
# Le placement des fichiers est géré par le fichier .manifest de NVIDIA : chaque
# fichier est déjà catégorisé (OPENGL_LIB, UTILITY_BINARY, FIRMWARE, ...).
# Nous associons chaque catégorie à un dossier de destination, puis une boucle
# s'occupe de tout installer.
#
# Tous les fichiers propriétaires de NVIDIA sont installés. L'installateur .run
# contient aussi ses propres clients GLVND (libGL, libGLX, libEGL, etc.) et un
# chargeur OpenCL. Comme ils font doublon avec les paquets système de Debian
# (libglvnd0 et ocl-icd-libopencl1), nous les ignorons volontairement pour
# utiliser ceux du système. Cela évite tout conflit de fichiers sous Debian.

# Valeurs par defaut. Elles peuvent etre surchargees par le wrapper
# nvidia-driver-run-config.sh ou directement via l'environnement:
#   pkgver=390.157 nvidia_open=false pacstall -IB ./nvidia-driver-run.pacscript

pkgver="${pkgver:-580.159.03}"
patch_relaxed="${patch_relaxed:-${PATCH_RELAXED:-true}}"
libxnvctrl_patch="${libxnvctrl_patch:-${LIBXNVCTRL_PATCH:-false}}"

# Mode module noyau. true utilise kernel-open quand le .run NVIDIA le fournit;
# false utilise l'arbre kernel proprietaire classique.

nvidia_open="${nvidia_open:-true}"

pkgname="nvidia-driver-run-${pkgver}"
gives="nvidia-driver-run"
arch=('amd64')
pkgrel='1'
url='https://www.nvidia.com/Download/index.aspx'
license=('custom:NVIDIA')
[[ $nvidia_open == "true" ]] && _dkmsname="nvidia-open" || _dkmsname="nvidia"
pkgdesc="NVIDIA $([[ $nvidia_open == "true" ]] && echo 'open-source' || echo 'proprietary') driver from the .run installer, repackaged for Debian"
depends=(
  'dkms'
  'libglvnd0'           # Fournit libGL/libGLX/libEGL/libGLES/libOpenGL
  'libvulkan1'          # Fournit libvulkan icd
  'ocl-icd-libopencl1'  # Fournit libOpenCL
  'initramfs-tools'     # Pour update-initramfs
  'clang'               # Pour la compilation du module DKMS pour llvm 
  'lld'                 # Pour l'édition de liens
  'llvm'                # Fournit llvm-strip utilisé par DKMS lors de la signature
)
makedepends=('build-essential' 'kmod' 'awk')
source=(
  "NVIDIA-Linux-x86_64-${pkgver}.run"
  "nvidia-settings-libxnvctrl_so.diff"
  "nvidia-open-gcc-ibt-sls.diff"
  "Add-IBT-support.diff"
  "make-modeset-fbdev-default.diff"
  "make-modeset-fbdev-default-565.diff"
  "silence-event-assert-until-570.diff"
  "fix-hdmi-names.diff"
  "Enable-atomic-kernel-modesetting-by-default.diff"
  "0001-Enable-atomic-kernel-modesetting-by-default.diff"
  "0002-Add-IBT-support.diff"
  "fix-hw-cursor-kde.diff"
  "nvidia-bsb-dsc-fix.diff"
  "linux-version.diff"
  "455-crashfix.diff"
  "01-ipmi-vm.diff"
  "02-ipmi-vm.diff"
  "list_is_first.diff"
  "legacy-kernel-6.4.diff"
  "legacy-kernel-6.5.diff"
  "legacy-kernel-6.6.diff"
  "kernel-6.12.patch"
  "kernel-6.17.patch"
  "kernel-6.19.patch"
  "470-kernel-7.0.patch"
  "kernel-7.0.patch"
  "kernel-7.0-580.patch"
  "kernel-7.1.patch"
  "gcc-14.diff"
  "gcc-15.diff"
  "GFP_RETRY_MAYFAIL-test.diff"
  "390-kernel-7.0.patch"
)
sha256sums=('SKIP')
maintainer=("xdavius <xdavius@gmail.com>")

# ---------------------------------------------------------------------------
# Sélection conditionnelle des patchs NVIDIA
# ---------------------------------------------------------------------------

_ver_major() {
  echo "${pkgver%%.*}"
}

_kernel_release() {
  uname -r 2>/dev/null || echo "0.0.0"
}

_kernel_triplet() {
  local rel=${1:-$(_kernel_release)}
  rel=${rel%%-*}
  local a b c
  IFS='.' read -r a b c <<< "$rel"
  echo "${a:-0}.${b:-0}.${c:-0}"
}

_kernel_ge() {
  local lhs rhs
  lhs=$(_kernel_triplet "$1")
  rhs=$(_kernel_triplet "$2")
  [[ "$(printf '%s\n%s\n' "$rhs" "$lhs" | sort -V | tail -n1)" == "$lhs" ]]
}

_ver_ge() {
  [[ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | tail -n1)" == "$1" ]]
}

_ver_le() {
  [[ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n1)" == "$2" ]]
}

_driver_matches() {
  local pattern
  for pattern in "$@"; do
    [[ $pkgver == $pattern ]] && return 0
  done
  return 1
}

_gcc_major() {
  gcc -dumpversion 2>/dev/null | sed 's/\..*//' || true
}

_extract_patch_kernel_tag() {
  local p=$1
  if [[ $p =~ ^kernel-([0-9]+\.[0-9]+) ]]; then
    echo "${BASH_REMATCH[1]}"
    return 0
  fi
  if [[ $p =~ ^legacy-kernel-([0-9]+\.[0-9]+) ]]; then
    echo "${BASH_REMATCH[1]}"
    return 0
  fi
  return 1
}

_extract_patch_driver_tag() {
  local p=$1
  # Exemples: kernel-6.19-470.patch, *-565.diff, *-580.patch
  if [[ $p =~ -([0-9]{3})([.-]|$) ]]; then
    echo "${BASH_REMATCH[1]}"
    return 0
  fi
  return 1
}

_collect_patch_candidates() {
  local -a listed
  local p n
  listed=()
  for p in "${source[@]}"; do
    n=$(basename "$p")
    [[ $n == *.diff || $n == *.patch ]] || continue
    listed+=("$n")
  done
  while IFS= read -r n; do
    listed+=("$n")
  done < <(find "${srcdir}" -maxdepth 1 \( -name "*.patch" -o -name "*.diff" \) -printf "%f\n" | sort -u)

  printf '%s\n' "${listed[@]}" | awk 'NF && !seen[$0]++'
}

_patch_is_open() {
  [[ ${has_real_kernel_open:-false} == "true" && $nvidia_open == "true" ]]
}

_patch_is_closed() {
  [[ $nvidia_open == "false" ]]
}

_cond_major_390() { [[ $(_ver_major) == 390 ]]; }
_cond_libxnvctrl() { [[ $libxnvctrl_patch == "true" ]]; }
_cond_open_lt525() { _patch_is_open && [[ $(_ver_major) -lt 525 ]]; }
_cond_open_570() { _patch_is_open && [[ $(_ver_major) == 570 ]]; }
_cond_open_565() { _patch_is_open && [[ $(_ver_major) == 565 ]]; }
_cond_open_580() { _patch_is_open && [[ $(_ver_major) == 580 ]]; }
_cond_open_550_564() { _patch_is_open && [[ $(_ver_major) -ge 550 && $(_ver_major) -lt 565 ]]; }
_cond_open_580_594() { _patch_is_open && [[ $(_ver_major) -ge 580 && $(_ver_major) -lt 595 ]]; }
_cond_open_ge580() { _patch_is_open && [[ $(_ver_major) -ge 580 ]]; }
_cond_bsb_dsc() { _patch_is_open && [[ ${bsb_dsc_fix:-false} == "true" && $(_ver_major) -ge 580 ]]; }
_cond_closed_le455() { _patch_is_closed && [[ $(_ver_major) -le 455 ]]; }
_cond_closed_455_crashfix() { _patch_is_closed && _driver_matches "455.2*" "455.3*" "455.4*"; }
_cond_closed_ipmi_vm1() { _patch_is_closed && _driver_matches "396*" "410.5*" "410.6*" "410.7*" "415.1*" && _kernel_ge "$(_kernel_triplet)" "4.20.0"; }
_cond_closed_ipmi_vm2() { _patch_is_closed && _driver_matches "410.5*" "410.6*" "410.7*" "415.1*" && _kernel_ge "$(_kernel_triplet)" "4.20.0"; }
_cond_closed_list_is_first() { _patch_is_closed && _driver_matches "396*" "410*" "415*" "418.3*" "418.4*" && _kernel_ge "$(_kernel_triplet)" "5.1.0"; }
_cond_closed_470199_k64() { _patch_is_closed && _driver_matches "470.199*" && _kernel_ge "$(_kernel_triplet)" "6.4.0"; }
_cond_closed_470199_k65() { _patch_is_closed && _driver_matches "470.199*" && _kernel_ge "$(_kernel_triplet)" "6.5.0"; }
_cond_closed_470199_k66() { _patch_is_closed && _driver_matches "470.199*" && _kernel_ge "$(_kernel_triplet)" "6.6.0"; }
_cond_closed_56557_k612() { _patch_is_closed && _driver_matches "565.57*" && _kernel_ge "$(_kernel_triplet)" "6.12.0"; }
_cond_open_590_k619() { _patch_is_open && [[ $(_ver_major) == 590 ]] && _kernel_ge "$(_kernel_triplet)" "6.19.0"; }
_cond_closed_470xx() { _patch_is_closed && [[ $(_ver_major) == 470 ]]; }
_cond_closed_470xx_k610() { _cond_closed_470xx && _kernel_ge "$(_kernel_triplet)" "6.10.0"; }
_cond_closed_470xx_k612() { _cond_closed_470xx && _kernel_ge "$(_kernel_triplet)" "6.12.0"; }
_cond_closed_470xx_k613() { _cond_closed_470xx && _kernel_ge "$(_kernel_triplet)" "6.13.0"; }
_cond_closed_470xx_k614() { _cond_closed_470xx && _kernel_ge "$(_kernel_triplet)" "6.14.0"; }
_cond_closed_470xx_k615() { _cond_closed_470xx && _kernel_ge "$(_kernel_triplet)" "6.15.0"; }
_cond_closed_470xx_k617() { _cond_closed_470xx && _kernel_ge "$(_kernel_triplet)" "6.17.0"; }
_cond_closed_470xx_k619() { _cond_closed_470xx && _kernel_ge "$(_kernel_triplet)" "6.19.0"; }
_cond_closed_470xx_k70() { _cond_closed_470xx && _kernel_ge "$(_kernel_triplet)" "7.0.0"; }
_cond_open_590_595_k70() {
  _patch_is_open && [[ $(_ver_major) == 590 || $(_ver_major) == 595 ]] &&
    [[ "$pkgver" != "595.44.06" && "$pkgver" != "595.44.07" ]] &&
    _kernel_ge "$(_kernel_triplet)" "7.0.0" && _ver_le "$pkgver" "595.58.03"
}
_cond_580_k70() { [[ $(_ver_major) == 580 ]] && _kernel_ge "$(_kernel_triplet)" "7.0.0" && _ver_le "$pkgver" "580.142"; }
_cond_open_595_k71() {
  _patch_is_open && [[ $(_ver_major) == 595 ]] &&
    [[ "$pkgver" != "595.44.06" && "$pkgver" != "595.44.07" ]] &&
    _kernel_ge "$(_kernel_triplet)" "7.1.0" && _ver_le "$pkgver" "595.58.03"
}
_cond_gcc14_470() { _patch_is_closed && [[ $(_ver_major) == 470 && $(_gcc_major) == 14 ]]; }
_cond_gcc14_non470() { _patch_is_closed && [[ $(_ver_major) != 470 && $(_gcc_major) == 14 ]]; }
_cond_gcc15() { [[ $(_gcc_major) == 15 ]]; }
_cond_never() { return 1; }
_cond_modeset_default() {
  { _cond_open_550_564; } || { _patch_is_closed && [[ $(_ver_major) == 560 ]] && _kernel_ge "$(_kernel_triplet)" "6.11.0"; }
}
_cond_modeset_default_565() {
  { _cond_open_565; } || { _patch_is_closed && [[ $(_ver_major) == 565 ]] && _kernel_ge "$(_kernel_triplet)" "6.11.0"; }
}

_patch_rules_init() {
  [[ ${_patch_rules_ready:-false} == true ]] && return
  declare -gA _patch_base _patch_level _patch_cond _patch_reason

  _patch_rule_add() {
    local p=$1 base=$2 level=$3 cond=$4 reason=$5
    _patch_base["$p"]=$base
    _patch_level["$p"]=$level
    _patch_cond["$p"]=$cond
    _patch_reason["$p"]=$reason
  }

  _patch_rule_add "390-kernel-7.0.patch" "." 1 _cond_major_390 "serie 390 locale"
  _patch_rule_add "nvidia-settings-libxnvctrl_so.diff" "." 1 _cond_libxnvctrl "whitelist nvidia-settings: libxnvctrl_patch=true"

  _patch_rule_add "nvidia-open-gcc-ibt-sls.diff" auto 1 _cond_open_lt525 "whitelist open: < 525"
  _patch_rule_add "Add-IBT-support.diff" auto 1 _cond_open_570 "whitelist open: 570"
  _patch_rule_add "make-modeset-fbdev-default.diff" auto 1 _cond_modeset_default "whitelist: open 550-564 ou closed 560/kernel >= 6.11"
  _patch_rule_add "make-modeset-fbdev-default-565.diff" auto 1 _cond_modeset_default_565 "whitelist: 565 uniquement"
  _patch_rule_add "silence-event-assert-until-570.diff" auto 1 _cond_open_565 "whitelist open: 565"
  _patch_rule_add "fix-hdmi-names.diff" auto 1 _cond_open_565 "whitelist open: 565"
  _patch_rule_add "Enable-atomic-kernel-modesetting-by-default.diff" auto 1 _cond_open_570 "whitelist open: 570"
  _patch_rule_add "0001-Enable-atomic-kernel-modesetting-by-default.diff" auto 1 _cond_open_580_594 "whitelist open: 580-594"
  _patch_rule_add "0002-Add-IBT-support.diff" auto 1 _cond_open_ge580 "whitelist open: >= 580"
  _patch_rule_add "fix-hw-cursor-kde.diff" auto 1 _cond_open_580 "whitelist open: 580"
  _patch_rule_add "nvidia-bsb-dsc-fix.diff" auto 1 _cond_bsb_dsc "whitelist open: >= 580 + bsb_dsc_fix=true"

  _patch_rule_add "linux-version.diff" auto 1 _cond_closed_le455 "whitelist closed: <= 455"
  _patch_rule_add "455-crashfix.diff" auto 1 _cond_closed_455_crashfix "whitelist closed: 455.2/455.3/455.4"
  _patch_rule_add "01-ipmi-vm.diff" auto 1 _cond_closed_ipmi_vm1 "whitelist closed: old ipmi/vm + kernel >= 4.20"
  _patch_rule_add "02-ipmi-vm.diff" auto 1 _cond_closed_ipmi_vm2 "whitelist closed: 410/415 ipmi/vm addon + kernel >= 4.20"
  _patch_rule_add "list_is_first.diff" auto 1 _cond_closed_list_is_first "whitelist closed: < 418.56 + kernel >= 5.1"
  _patch_rule_add "legacy-kernel-6.4.diff" auto 1 _cond_closed_470199_k64 "whitelist closed: 470.199 + kernel >= 6.4"
  _patch_rule_add "legacy-kernel-6.5.diff" auto 1 _cond_closed_470199_k65 "whitelist closed: 470.199 + kernel >= 6.5"
  _patch_rule_add "legacy-kernel-6.6.diff" auto 1 _cond_closed_470199_k66 "whitelist closed: 470.199 + kernel >= 6.6"
  _patch_rule_add "kernel-6.12.patch" auto 1 _cond_closed_56557_k612 "whitelist closed: 565.57 + kernel >= 6.12"
  _patch_rule_add "kernel-6.17.patch" "" "" _cond_never "whitelist absente dans PKGBUILD.txt pour kernel-6.17.patch"
  _patch_rule_add "kernel-6.19.patch" auto 2 _cond_open_590_k619 "whitelist open: 590 + kernel >= 6.19"
  _patch_rule_add "470-kernel-7.0.patch" kernel-dkms 1 _cond_closed_470xx_k612 "whitelist closed: 470xx + kernel >= 6.12 (cumulative)"
  _patch_rule_add "kernel-7.0.patch" auto 2 _cond_open_590_595_k70 "whitelist open: 590/595 <= 595.58.03 + kernel >= 7.0"
  _patch_rule_add "kernel-7.0-580.patch" auto 1 _cond_580_k70 "whitelist: 580 <= 580.142 + kernel >= 7.0"
  _patch_rule_add "kernel-7.1.patch" auto 2 _cond_open_595_k71 "whitelist open: 595 <= 595.58.03 + kernel >= 7.1"
  _patch_rule_add "gcc-14.diff" auto 1 _cond_gcc14_non470 "whitelist closed: non-470 + GCC 14"
  _patch_rule_add "gcc-15.diff" auto 1 _cond_gcc15 "whitelist: GCC 15"
  _patch_rule_add "GFP_RETRY_MAYFAIL-test.diff" "" "" _cond_never "whitelist absente dans PKGBUILD.txt pour GFP_RETRY_MAYFAIL-test.diff"

  _patch_rules_ready=true
}

_patch_plan_from_rules() {
  local p=$1 cond major
  _patch_rules_init
  [[ -v _patch_cond["$p"] ]] || return 1

  major=$(_ver_major)
  # Règle cumulative: pour la branche 390, on n'utilise que le patch dédié.
  if [[ $major == 390 && $p != "390-kernel-7.0.patch" ]]; then
    echo "skip|||branche 390: patch cumulatif unique 390-kernel-7.0.patch"
    return 0
  fi

  cond=${_patch_cond["$p"]}
  if "$cond"; then
    echo "apply|${_patch_base["$p"]}|${_patch_level["$p"]}|${_patch_reason["$p"]}"
  else
    echo "skip|||${_patch_reason["$p"]}"
  fi
  return 0
}

_patch_plan() {
  local p=$1 major
  local patch_driver_tag
  local running_kernel
  major=$(_ver_major)
  running_kernel=$(_kernel_triplet)

  if _patch_plan_from_rules "$p"; then
    return
  fi

  case $p in
    390-kernel-7.0.patch)
      [[ $major == 390 ]] && echo "apply|.|1|serie 390 locale" || \
        echo "skip|||whitelist: serie 390 uniquement"
      return ;;

    nvidia-settings-libxnvctrl_so.diff)
      [[ $libxnvctrl_patch == "true" ]] && echo "apply|.|1|whitelist nvidia-settings: libxnvctrl_patch=true" || \
        echo "skip|||whitelist nvidia-settings: libxnvctrl_patch=true"
      return ;;
  esac

  # Filtrage par branche du driver quand le patch l'indique explicitement
  # (ex: *-470.*, *-565.*, *-580.*).
  if patch_driver_tag=$(_extract_patch_driver_tag "$p"); then
    if [[ "$patch_driver_tag" != "$major" ]]; then
      echo "skip|||patch reserve a la branche ${patch_driver_tag} (branche active: ${major})"
      return
    fi
  fi

  case $p in
    nvidia-open-gcc-ibt-sls.diff)
      [[ ${has_real_kernel_open:-false} == "true" && $nvidia_open == "true" && $major -lt 525 ]] && \
        echo "apply|auto|1|whitelist open: < 525" || \
        echo "skip|||whitelist open: < 525"
      return ;;

    Add-IBT-support.diff)
      [[ ${has_real_kernel_open:-false} == "true" && $nvidia_open == "true" && $major == 570 ]] && \
        echo "apply|auto|1|whitelist open: 570" || \
        echo "skip|||whitelist open: 570"
      return ;;

    make-modeset-fbdev-default.diff)
      if [[ ${has_real_kernel_open:-false} == "true" && $nvidia_open == "true" && $major -ge 550 && $major -lt 565 ]]; then
        echo "apply|auto|1|whitelist open: 550-564"
      elif [[ $nvidia_open == "false" && $major == 560 ]] && _kernel_ge "$running_kernel" "6.11.0"; then
        echo "apply|auto|1|whitelist closed: 560 + kernel >= 6.11"
      else
        echo "skip|||whitelist: open 550-564 ou closed 560/kernel >= 6.11"
      fi
      return ;;

    make-modeset-fbdev-default-565.diff)
      if [[ ${has_real_kernel_open:-false} == "true" && $nvidia_open == "true" && $major == 565 ]]; then
        echo "apply|auto|1|whitelist open: 565"
      elif [[ $nvidia_open == "false" && $major == 565 ]] && _kernel_ge "$running_kernel" "6.11.0"; then
        echo "apply|auto|1|whitelist closed: 565 + kernel >= 6.11"
      else
        echo "skip|||whitelist: 565 uniquement"
      fi
      return ;;

    silence-event-assert-until-570.diff|fix-hdmi-names.diff)
      [[ ${has_real_kernel_open:-false} == "true" && $nvidia_open == "true" && $major == 565 ]] && \
        echo "apply|auto|1|whitelist open: 565" || \
        echo "skip|||whitelist open: 565"
      return ;;

    Enable-atomic-kernel-modesetting-by-default.diff)
      [[ ${has_real_kernel_open:-false} == "true" && $nvidia_open == "true" && $major == 570 ]] && \
        echo "apply|auto|1|whitelist open: 570" || \
        echo "skip|||whitelist open: 570"
      return ;;

    0001-Enable-atomic-kernel-modesetting-by-default.diff)
      [[ ${has_real_kernel_open:-false} == "true" && $nvidia_open == "true" && $major -ge 580 && $major -lt 595 ]] && \
        echo "apply|auto|1|whitelist open: 580-594" || \
        echo "skip|||whitelist open: 580-594"
      return ;;

    0002-Add-IBT-support.diff)
      [[ ${has_real_kernel_open:-false} == "true" && $nvidia_open == "true" && $major -ge 580 ]] && \
        echo "apply|auto|1|whitelist open: >= 580" || \
        echo "skip|||whitelist open: >= 580"
      return ;;

    fix-hw-cursor-kde.diff)
      [[ ${has_real_kernel_open:-false} == "true" && $nvidia_open == "true" && $major == 580 ]] && \
        echo "apply|auto|1|whitelist open: 580" || \
        echo "skip|||whitelist open: 580"
      return ;;

    nvidia-bsb-dsc-fix.diff)
      [[ ${has_real_kernel_open:-false} == "true" && $nvidia_open == "true" && ${bsb_dsc_fix:-false} == "true" && $major -ge 580 ]] && \
        echo "apply|auto|1|whitelist open: >= 580 + bsb_dsc_fix=true" || \
        echo "skip|||whitelist open: >= 580 + bsb_dsc_fix=true"
      return ;;
  esac

  case $p in
    linux-version.diff)
      [[ $nvidia_open == "false" && $major -le 455 ]] && \
        echo "apply|auto|1|whitelist closed: <= 455" || \
        echo "skip|||whitelist closed: <= 455"
      return ;;

    455-crashfix.diff)
      [[ $nvidia_open == "false" ]] && _driver_matches "455.2*" "455.3*" "455.4*" && \
        echo "apply|auto|1|whitelist closed: 455.2/455.3/455.4" || \
        echo "skip|||whitelist closed: 455.2/455.3/455.4"
      return ;;

    01-ipmi-vm.diff)
      [[ $nvidia_open == "false" ]] && _driver_matches "396*" "410.5*" "410.6*" "410.7*" "415.1*" && _kernel_ge "$running_kernel" "4.20.0" && \
        echo "apply|auto|1|whitelist closed: old ipmi/vm + kernel >= 4.20" || \
        echo "skip|||whitelist closed: old ipmi/vm + kernel >= 4.20"
      return ;;

    02-ipmi-vm.diff)
      [[ $nvidia_open == "false" ]] && _driver_matches "410.5*" "410.6*" "410.7*" "415.1*" && _kernel_ge "$running_kernel" "4.20.0" && \
        echo "apply|auto|1|whitelist closed: 410/415 ipmi/vm addon + kernel >= 4.20" || \
        echo "skip|||whitelist closed: 410/415 ipmi/vm addon + kernel >= 4.20"
      return ;;

    list_is_first.diff)
      [[ $nvidia_open == "false" ]] && _driver_matches "396*" "410*" "415*" "418.3*" "418.4*" && _kernel_ge "$running_kernel" "5.1.0" && \
        echo "apply|auto|1|whitelist closed: < 418.56 + kernel >= 5.1" || \
        echo "skip|||whitelist closed: < 418.56 + kernel >= 5.1"
      return ;;

    legacy-kernel-6.4.diff)
      [[ $nvidia_open == "false" ]] && _driver_matches "470.199*" && _kernel_ge "$running_kernel" "6.4.0" && \
        echo "apply|auto|1|whitelist closed: 470.199 + kernel >= 6.4" || \
        echo "skip|||whitelist closed: 470.199 + kernel >= 6.4"
      return ;;

    legacy-kernel-6.5.diff)
      [[ $nvidia_open == "false" ]] && _driver_matches "470.199*" && _kernel_ge "$running_kernel" "6.5.0" && \
        echo "apply|auto|1|whitelist closed: 470.199 + kernel >= 6.5" || \
        echo "skip|||whitelist closed: 470.199 + kernel >= 6.5"
      return ;;

    legacy-kernel-6.6.diff)
      [[ $nvidia_open == "false" ]] && _driver_matches "470.199*" && _kernel_ge "$running_kernel" "6.6.0" && \
        echo "apply|auto|1|whitelist closed: 470.199 + kernel >= 6.6" || \
        echo "skip|||whitelist closed: 470.199 + kernel >= 6.6"
      return ;;

    kernel-6.12.patch)
      [[ $nvidia_open == "false" ]] && _driver_matches "565.57*" && _kernel_ge "$running_kernel" "6.12.0" && \
        echo "apply|auto|1|whitelist closed: 565.57 + kernel >= 6.12" || \
        echo "skip|||whitelist closed: 565.57 + kernel >= 6.12"
      return ;;

    kernel-6.17.patch)
      echo "skip|||whitelist absente dans PKGBUILD.txt pour kernel-6.17.patch"
      return ;;

    kernel-6.19.patch)
      [[ ${has_real_kernel_open:-false} == "true" && $nvidia_open == "true" && $major == 590 ]] && _kernel_ge "$running_kernel" "6.19.0" && \
        echo "apply|auto|2|whitelist open: 590 + kernel >= 6.19" || \
        echo "skip|||whitelist open: 590 + kernel >= 6.19"
      return ;;

    kernel-7.0.patch)
      if [[ ${has_real_kernel_open:-false} == "true" && $nvidia_open == "true" && ( $major == 590 || $major == 595 ) && "$pkgver" != "595.44.06" && "$pkgver" != "595.44.07" ]] && _kernel_ge "$running_kernel" "7.0.0" && _ver_le "$pkgver" "595.58.03"; then
        echo "apply|auto|2|whitelist open: 590/595 <= 595.58.03 + kernel >= 7.0"
      else
        echo "skip|||whitelist open: 590/595 <= 595.58.03 + kernel >= 7.0"
      fi
      return ;;

    kernel-7.0-580.patch)
      if [[ $major == 580 ]] && _kernel_ge "$running_kernel" "7.0.0" && _ver_le "$pkgver" "580.142"; then
        [[ ${has_real_kernel_open:-false} == "true" && $nvidia_open == "true" ]] && \
          echo "apply|auto|1|whitelist open: 580 <= 580.142 + kernel >= 7.0" || \
          echo "apply|auto|1|whitelist closed: 580 <= 580.142 + kernel >= 7.0"
      else
        echo "skip|||whitelist: 580 <= 580.142 + kernel >= 7.0"
      fi
      return ;;

    kernel-7.1.patch)
      if [[ ${has_real_kernel_open:-false} == "true" && $nvidia_open == "true" && $major == 595 && "$pkgver" != "595.44.06" && "$pkgver" != "595.44.07" ]] && _kernel_ge "$running_kernel" "7.1.0" && _ver_le "$pkgver" "595.58.03"; then
        echo "apply|auto|2|whitelist open: 595 <= 595.58.03 + kernel >= 7.1"
      else
        echo "skip|||whitelist open: 595 <= 595.58.03 + kernel >= 7.1"
      fi
      return ;;

    gcc-14.diff)
      [[ $nvidia_open == "false" && $major != 470 && $(_gcc_major) == 14 ]] && \
        echo "apply|auto|1|whitelist closed: non-470 + GCC 14" || \
        echo "skip|||whitelist closed: non-470 + GCC 14"
      return ;;

    gcc-15.diff)
      [[ $(_gcc_major) == 15 ]] && echo "apply|auto|1|whitelist: GCC 15" || \
        echo "skip|||whitelist: GCC 15"
      return ;;

    GFP_RETRY_MAYFAIL-test.diff)
      echo "skip|||whitelist absente dans PKGBUILD.txt pour GFP_RETRY_MAYFAIL-test.diff"
      return ;;
  esac

  # Mode strict optionnel: ne tente pas les patchs ciblant un noyau plus récent.
  if [[ $patch_relaxed != "true" ]]; then
    local patch_kernel
    if patch_kernel=$(_extract_patch_kernel_tag "$p"); then
      if ! _kernel_ge "$running_kernel" "${patch_kernel}.0"; then
        echo "skip|||patch cible kernel ${patch_kernel}+ (kernel courant: ${running_kernel}, mode strict)"
        return
      fi
    fi
  fi

  echo "skip|||patch non whitelisté"
}

_patch_base_dir_auto() {
  local patch_file=$1
  local first_path
  first_path=$(sed -nE 's#^(\\+\\+\\+|---) [ab]/([^[:space:]]+).*#\\2#p' "$patch_file" \
    | grep -v '^/dev/null$' | head -n1)
  [[ -z $first_path ]] && { echo "."; return; }
  case "$first_path" in
    kernel-dkms/*|kernel-open/*|kernel/*) echo "." ;;
    common/*|nvidia/*|nvidia-drm/*|nvidia-modeset/*|nvidia-uvm/*|conftest.sh|Kbuild|Makefile)
      echo "kernel-dkms" ;;
    *) echo "." ;;
  esac
}

# ---------------------------------------------------------------------------
# Association des fichiers du Manifest vers leur dossier de destination
# ---------------------------------------------------------------------------

# Détermine le dossier de destination pour un fichier donné.
# Arguments attendus : catégorie, architecture (NATIVE|COMPAT32), sous-dossier
# Retourne une erreur (1) si la catégorie est inconnue.
_dest_dir() {
  # $cat : catégorie du fichier (ex: OPENGL_LIB, FIRMWARE)
  # $abi : architecture ciblée (NATIVE=64bits, COMPAT32=32bits)
  # $sub : sous-dossier éventuel (on retire le slash final s'il y en a un)
  # $lib : chemin de base par défaut (64 bits)
  local cat=$1 abi=$2 sub=${3%/} lib=${_LIB64}

  # Si on cible l'architecture 32 bits, on change le chemin de base pour les bibliothèques
  [[ $abi == COMPAT32 ]] && lib=${_LIB32}

  # On détermine le bon chemin de destination selon la catégorie
  case $cat in
    # Utilitaires exécutables
    UTILITY_BINARY|NVIDIA_MODPROBE|UTILITY_BIN_SYMLINK)
      echo /usr/bin ;;

    # Bibliothèques partagées spécifiques à NVIDIA (libcuda, libnvidia-*, etc.)
    # et leurs liens symboliques. Les wrappers (GLVND/GLX/EGL/OPENCL) ne sont
    # volontairement PAS dans cette liste : ils sont ignorés plus bas dans le
    # code pour ne pas écraser les paquets Debian existants.
    # Note : "${lib}${sub:+/$sub}" ajoute le sous-dossier uniquement s'il n'est pas vide
    OPENGL_LIB|OPENGL_SYMLINK|TLS_LIB|\
    CUDA_LIB|CUDA_SYMLINK|\
    OPENCL_LIB|OPENCL_LIB_SYMLINK|\
    UTILITY_LIB|UTILITY_LIB_SYMLINK|\
    NVCUVID_LIB|NVCUVID_LIB_SYMLINK|\
    ENCODEAPI_LIB|ENCODEAPI_LIB_SYMLINK|\
    VDPAU_LIB|VDPAU_SYMLINK|\
    GBM_BACKEND_LIB_SYMLINK|\
    NVIFR_LIB|NVIFR_LIB_SYMLINK)
      echo "${lib}${sub:+/$sub}" ;;

    # Modules pour le serveur graphique Xorg
    XMODULE_SHARED_LIB|GLX_MODULE_SHARED_LIB|GLX_MODULE_SYMLINK|XMODULE_SYMLINK|XMODULE_NEWSYM)
      echo "/usr/lib/xorg/modules${sub:+/$sub}" ;;

    # Utilitaires internes NVIDIA
    # Séparation selon l'architecture pour que la version 32-bit n'écrase pas la 64-bit.
    INTERNAL_UTILITY_BINARY|INTERNAL_UTILITY_LIB|INTERNAL_UTILITY_DATA)
      echo "${lib}/libglvnd_install_checker" ;;

    # Fichiers sources pour le module noyau (DKMS)
    KERNEL_MODULE_SRC|KERNEL_OPEN_MODULE_SRC|DKMS_CONF) echo "/usr/src/${_dkmsname}-${pkgver}" ;;

    # Micrologiciels (firmwares) nécessaires au fonctionnement du GPU
    FIRMWARE)                          echo "/lib/firmware/nvidia/${pkgver}" ;;
    
    # Les DLLs Wine NGX sont indépendantes de l'architecture (Wine les trouve par leur nom).
    WINE_LIB)                          echo /usr/lib/nvidia/wine ;;
    
    # Fichiers de description (JSON/texte) pour aider le système à trouver les bibliothèques
    VULKAN_ICD_JSON|VULKANSC_ICD_JSON) echo "/usr/share/vulkan/${sub:-icd.d}" ;;
    GLVND_EGL_ICD_JSON)                echo /usr/share/glvnd/egl_vendor.d ;;
    EGL_EXTERNAL_PLATFORM_JSON)        echo /usr/share/egl/egl_external_platform.d ;;
    CUDA_ICD)                          echo /etc/OpenCL/vendors ;;
    
    # Profils et données générales pour les applications NVIDIA
    APPLICATION_PROFILE|SANDBOXUTILS_FILELIST_JSON|OPENGL_DATA)
                                       echo /usr/share/nvidia ;;
    
    # Raccourci bureau (fichier .desktop) et icônes
    DOT_DESKTOP)                       echo /usr/share/applications ;;
    ICON)                              echo "/usr/share/icons/hicolor/${sub}" ;;
    
    # Manuels (manpages) et documentation texte
    DOCUMENTATION)                     echo "/usr/share/doc/${pkgname}/${sub#NVIDIA_GLX-1.0/}" ;;
    MANPAGE|NVIDIA_MODPROBE_MANPAGE)   echo /usr/share/man/man1 ;;
    
    # Configuration additionnelle pour le serveur X11
    XORG_OUTPUTCLASS_CONFIG)           echo /usr/share/X11/xorg.conf.d ;;
    
    # Fichiers d'intégration pour Systemd (services de démarrage, scripts de mise en veille)
    SYSTEMD_UNIT)                      echo /usr/lib/systemd/system ;;
    SYSTEMD_UNIT_SYMLINK)              echo "/usr/lib/systemd/system/${sub}" ;;
    SYSTEMD_SLEEP_SCRIPT)              echo /usr/lib/systemd/system-sleep ;;
    
    # Si la catégorie n'est pas gérée, on déclenche une erreur
    *) return 1 ;;
  esac
}

# ---------------------------------------------------------------------------
# Cycle de vie Pacstall (Fonctions d'installation principales)
# ---------------------------------------------------------------------------

prepare() {
  local major
  major=$(_ver_major)
  echo "Mode patch: $([[ $patch_relaxed == "true" ]] && echo "relax" || echo "strict") (kernel courant: $(_kernel_triplet))"
  local runfile
  runfile=$(find "${srcdir}" -maxdepth 1 -type f -name 'NVIDIA-Linux-*.run' | head -n1)
  [[ -n $runfile ]] || { echo "ERROR: no NVIDIA-Linux-*.run in ${srcdir}"; return 1; }

  chmod +x "$runfile"
  rm -rf "${srcdir}/extracted-nvidia"
  "$runfile" --extract-only --target "${srcdir}/extracted-nvidia" >/dev/null || return 1
  [[ -r "${srcdir}/extracted-nvidia/.manifest" ]] || {
    echo "ERROR: manifest missing after extraction"; return 1; }

  # --- Étape : Application des patchs ---
  echo "Application des patchs (Log: ${srcdir}/debug.txt)..."
  > "${srcdir}/debug.txt"
  
  pushd "${srcdir}/extracted-nvidia" >/dev/null || return 1
  
  # Les patchs legacy/closed ciblent souvent kernel-dkms, tandis que les patchs
  # open récents ciblent kernel-open. On expose uniquement l'arbre du mode actif
  # pour éviter qu'un patch destiné à l'autre variante s'applique par accident.
  local compat_link='' created_compat_link=false
  has_real_kernel_open=false
  [[ -d kernel-open ]] && has_real_kernel_open=true
  if [[ $nvidia_open == "true" ]]; then
    compat_link=kernel-open
  else
    compat_link=kernel-dkms
  fi
  if [[ ! -e $compat_link ]]; then
    ln -sf kernel "$compat_link"
    created_compat_link=true
  fi

  local -a patch_candidates
  mapfile -t patch_candidates < <(_collect_patch_candidates)

  applied_patches=()
  failed_patches=()
  skipped_patches=()
  already_patches=()

  echo "Patches detectes: ${#patch_candidates[@]}"

  _apply_one_patch() {
    local patch_file=$1 patch_name=$2 target_dir=$3 p_level=$4
    local oldpwd_apply=$PWD
    cd "$target_dir" || return 1
    # Le patch cumulatif 390 contient plusieurs passages sur certains fichiers.
    # Avec --dry-run, patch peut produire un faux negatif; on teste d'abord le
    # cas "deja applique", puis on applique directement.
    if [[ $patch_name == "390-kernel-7.0.patch" ]]; then
      if patch --batch -p"$p_level" -R -F 3 --dry-run < "$patch_file" >> "${srcdir}/debug.txt" 2>&1; then
        already_patches+=("$patch_name")
        printf "  [DONE ] %-45s deja applique (%s)\n" "$patch_name" "$target_dir"
      elif patch --batch -p"$p_level" -N -F 3 < "$patch_file" >> "${srcdir}/debug.txt" 2>&1; then
        applied_patches+=("$patch_name")
        printf "  [APPLY] %-45s %s\n" "$patch_name" "$target_dir"
      else
        failed_patches+=("$patch_name")
        printf "  [MISS ] %-45s incompatible\n" "$patch_name"
      fi
      cd "$oldpwd_apply" || return 1
      return 0
    fi

    if patch --batch -p"$p_level" -N -F 3 --dry-run < "$patch_file" >> "${srcdir}/debug.txt" 2>&1; then
      if patch --batch -p"$p_level" -N -F 3 < "$patch_file" >> "${srcdir}/debug.txt" 2>&1; then
        applied_patches+=("$patch_name")
        printf "  [APPLY] %-45s %s\n" "$patch_name" "$target_dir"
      else
        failed_patches+=("$patch_name")
        printf "  [ERR ] %-45s Erreur imprévue\n" "$patch_name"
      fi
    else
      # Si le patch est déjà présent (arbre réutilisé), on le considère comme OK.
      if patch --batch -p"$p_level" -R -F 3 --dry-run < "$patch_file" >> "${srcdir}/debug.txt" 2>&1; then
        already_patches+=("$patch_name")
        printf "  [DONE ] %-45s deja applique (%s)\n" "$patch_name" "$target_dir"
      else
        failed_patches+=("$patch_name")
        printf "  [MISS ] %-45s incompatible\n" "$patch_name"
      fi
    fi
    cd "$oldpwd_apply" || return 1
  }

  local p p_name plan status base_dir patch_level reason oldpwd
  for p_name in "${patch_candidates[@]}"; do
    p="${srcdir}/${p_name}"
    [[ -e "$p" ]] || {
      failed_patches+=("$p_name")
      echo "  [!!] $p_name (Fichier manquant)"
      continue
    }
    
    echo "--- Patch: $p_name ---" >> "${srcdir}/debug.txt"
    plan=$(_patch_plan "$p_name")
    IFS='|' read -r status base_dir patch_level reason <<< "$plan"
    if [[ $status == skip ]]; then
      skipped_patches+=("$p_name ($reason)")
      printf "  [SKIP] %-45s %s\n" "$p_name" "$reason"
      echo "SKIP: $reason" >> "${srcdir}/debug.txt"
      continue
    fi
    if [[ $base_dir == auto ]]; then
      base_dir=$(_patch_base_dir_auto "$p")
    fi
    if [[ ! -d $base_dir ]]; then
      failed_patches+=("$p_name")
      printf "  [ERR ] %-45s Dossier cible absent: %s\n" "$p_name" "$base_dir"
      echo "MISSING TARGET DIR: $base_dir ($reason)" >> "${srcdir}/debug.txt"
      continue
    fi
    echo "Target: ${base_dir}, -p${patch_level} (${reason})" >> "${srcdir}/debug.txt"
    _apply_one_patch "$p" "$p_name" "$base_dir" "$patch_level" || return 1
  done

  # On retire les liens de compatibilité
  [[ $created_compat_link == true && -L $compat_link ]] && rm -f "$compat_link"
  
  popd >/dev/null || return 1
}

build() {
  local ext=${srcdir}/extracted-nvidia
  local manifest=${ext}/.manifest
  _LIB64=/usr/lib/$(dpkg-architecture -qDEB_HOST_MULTIARCH 2>/dev/null \
                    || echo x86_64-linux-gnu)
  _LIB32=/usr/lib/i386-linux-gnu

  local -a files_to_install=()
  local -a symlinks_to_create=()
  local -a skipped_files=()
  local installed=0 skipped=0
  local has_kernel_open=false
  grep -q '^kernel-open/' "$manifest" && has_kernel_open=true

  # On n'écrase pas le debug.txt pour conserver les logs de prepare()
  echo -e "\n--- Début du Build ---" >> "${srcdir}/debug.txt"
  if [[ $nvidia_open == "true" && $has_kernel_open != true ]]; then
    echo "AVERTISSEMENT: kernel-open absent du manifest; utilisation de kernel/ comme arbre module." \
      >> "${srcdir}/debug.txt"
  fi

      # --- Étape 1 : Analyse du manifeste (Parsing) ---
      while read -r -a F; do
        [[ ${#F[@]} -ge 4 ]] || continue
        local path=${F[0]} mode=${F[1]} cat=${F[2]}

        # On ignore les fichiers inutiles ou conflictuels :
        # - INSTALLER_BINARY : l'installateur NVIDIA officiel (conflit potentiel avec dpkg).
        # - GLVND_LIB/SYMLINK : les clients GLVND (libGL, libGLES, etc.) sont fournis par le paquet 'libglvnd0'.
        # - GLX_CLIENT/EGL_CLIENT : les wrappers GLX/EGL sont également délégués au système (libglvnd0).
        # - OPENCL_WRAPPER : le chargeur OpenCL est fourni par 'ocl-icd-libopencl1' dans les dépendances.
        # - libGLX_indirect.so.0 : ce lien symbolique crée un conflit direct avec le paquet 'libglx-mesa0'.
        # - UTILITY_BIN_SYMLINK (nvidia-installer) : lien vers l'installateur à ignorer.
        if [[ $cat == INSTALLER_BINARY ]] || \
           [[ $cat == GLVND_LIB ]] || [[ $cat == GLVND_SYMLINK ]] || \
           [[ $cat == GLX_CLIENT_LIB ]] || [[ $cat == GLX_CLIENT_SYMLINK ]] || \
           [[ $cat == EGL_CLIENT_LIB ]] || [[ $cat == EGL_CLIENT_SYMLINK ]] || \
           [[ $cat == OPENCL_WRAPPER_LIB ]] || [[ $cat == OPENCL_WRAPPER_SYMLINK ]] || \
           [[ $path == *libGLX_indirect.so.0 ]] || \
           [[ $cat == LIBGL_LA ]] || [[ $cat == OPENGL_HEADER ]] || \
           [[ $cat == UTILITY_BIN_SYMLINK && ${F[3]:-} == nvidia-installer ]]; then
          skipped_files+=("$path"); ((skipped++)); continue
        fi

    # Filtrage entre modules noyau Open-Source et Propriétaires (Closed)
    if [[ $nvidia_open == "true" ]]; then
      # Si le .run fournit un vrai arbre open, on ignore l'arbre propriétaire.
      # Les vieux .run comme 390 n'ont que kernel/; dans ce cas on garde kernel/
      # pour que les patchs kernel-open appliqués via le lien de compat soient
      # bien empaquetés.
      [[ $has_kernel_open == true && $path == kernel/* ]] && {
        skipped_files+=("$path"); ((skipped++)); continue; }
    else
      # Si on veut le propriétaire, on ignore les fichiers du dossier 'kernel-open/' (ouvert)
      [[ $path == kernel-open/* ]] && { skipped_files+=("$path"); ((skipped++)); continue; }
    fi

    # SYSTEMD_UNIT_SYMLINK est un cas particulier : la cible du lien est implicite
    # (le fichier de l'unité se trouve dans le dossier parent).
    if [[ $cat == SYSTEMD_UNIT_SYMLINK ]]; then
      local d=/usr/lib/systemd/system/${F[3]}
      symlinks_to_create+=("../${path}|${d}/${path}")
      echo "SYMLINK: $path -> ${d}/${path} (target: ../${path})" >> "${srcdir}/debug.txt"
      ((installed++)); continue
    fi

    # Analyse générique de la ligne : [NATIVE|COMPAT32] [subdir|INHERIT_PATH_DEPTH:N] [target] MODULE:xxx
    local rest=("${F[@]:3}") abi=NATIVE sub='' target='' depth=0
    unset 'rest[-1]'                                          # Ignore la partie MODULE:xxx
    if [[ ${rest[0]:-} == NATIVE || ${rest[0]:-} == COMPAT32 ]]; then
      abi=${rest[0]}; rest=("${rest[@]:1}")
    fi
    if [[ $mode == 0000 ]]; then                              # C'est un lien symbolique
      [[ ${#rest[@]} -gt 0 ]] && { target=${rest[-1]}; unset 'rest[-1]'; }
    fi
    sub=${rest[0]:-}; [[ $sub == / ]] && sub=''

    # INHERIT_PATH_DEPTH:N permet de conserver les chemins de dossiers imbriqués
    # (comme firmware/, kernel/...). Enlève N dossiers du début du chemin.
    local rel=${path##*/}
    if [[ $sub == INHERIT_PATH_DEPTH:* ]]; then
      depth=${sub#INHERIT_PATH_DEPTH:}
      rel=$path
      while ((depth-- > 0)); do rel=${rel#*/}; done
      sub=''
    fi

    local destdir
    destdir=$(_dest_dir "$cat" "$abi" "$sub") || {
      echo "  ?? unhandled category $cat ($path)"; skipped_files+=("$path"); ((skipped++)); continue; }

    # Ajout aux listes correspondantes
    if [[ $mode == 0000 ]]; then
      symlinks_to_create+=("$target|${destdir}/${rel}")
      echo "SYMLINK: $path -> ${destdir}/${rel} (target: $target)" >> "${srcdir}/debug.txt"
    else
      files_to_install+=("$mode|${ext}/${path}|${destdir}/${rel}")
      echo "FILE: $path -> ${destdir}/${rel} (mode: $mode)" >> "${srcdir}/debug.txt"
    fi
    ((installed++))
  done < <(tail -n +9 "$manifest")

  # --- Étape 2 : Installation des fichiers ---
  for item in "${files_to_install[@]}"; do
    IFS='|' read -r mode src dest <<< "$item"
    install -D -m"$mode" "$src" "${pkgdir}${dest}"
  done

  # --- Étape 3 : Création des liens symboliques ---
  for item in "${symlinks_to_create[@]}"; do
    IFS='|' read -r target dest <<< "$item"
    install -d -m755 "$(dirname "${pkgdir}${dest}")"
    ln -sfT "$target" "${pkgdir}${dest}"
  done

  # --- Étape 4 : Vérification et Résumé ---
  echo "Vérification des fichiers installés..."
  local errors=0
  for item in "${files_to_install[@]}"; do
    IFS='|' read -r mode src dest <<< "$item"
    if [[ ! -f "${pkgdir}${dest}" ]]; then
      echo "  ERREUR: Fichier manquant -> ${pkgdir}${dest}"
      ((errors++))
    fi
  done
  for item in "${symlinks_to_create[@]}"; do
    IFS='|' read -r target dest <<< "$item"
    if [[ ! -L "${pkgdir}${dest}" ]]; then
      echo "  ERREUR: Lien symbolique manquant -> ${pkgdir}${dest}"
      ((errors++))
    fi
  done

  if (( errors > 0 )); then
    echo "ÉCHEC de la vérification : $errors erreur(s) trouvée(s)."
    return 1
  else
    echo "SUCCÈS : Tous les fichiers et liens listés ont été copiés."
  fi

  local total_files=$((installed + skipped))
  echo ""
  echo "=========================================================="
  echo " RÉSUMÉ DE L'INSTALLATION "
  echo "=========================================================="
  echo " -- Manifest --"
  echo " Total fichiers manifest : $total_files"
  echo " Fichiers installés      : $installed"
  echo " Fichiers ignorés        : $skipped"
  if [[ ${#skipped_files[@]} -gt 0 ]]; then
    echo " Liste des fichiers ignorés :"
    for f in "${skipped_files[@]}"; do
      echo "   - $f"
    done
  fi
  echo ""
  echo " -- Patches --"
  echo " Patches appliqués      : ${#applied_patches[@]}"
  if [[ ${#applied_patches[@]} -gt 0 ]]; then
    echo " Liste des patches appliqués :"
    for p in "${applied_patches[@]}"; do
      echo "   - $p"
    done
  fi
  echo " Patches échoués (ign.) : ${#failed_patches[@]}"
  if [[ ${#failed_patches[@]} -gt 0 ]]; then
    echo " Liste des patches échoués :"
    for p in "${failed_patches[@]}"; do
      echo "   - $p"
    done
  fi
  echo " Patches ignorés (règles): ${#skipped_patches[@]}"
  echo " Patches deja appliqués : ${#already_patches[@]}"
  if [[ ${#already_patches[@]} -gt 0 ]]; then
    echo " Liste des patches deja appliqués :"
    for p in "${already_patches[@]}"; do
      echo "   - $p"
    done
  fi
  echo "=========================================================="
  echo " Un log complet a été généré : ${srcdir}/debug.txt"
  echo "=========================================================="

  # ---- Copie de sécurité de l'arbre noyau actif ----
  local ksrc="${pkgdir}/usr/src/${_dkmsname}-${pkgver}"
  # On s'assure que tous les fichiers du noyau sont bien présents AVANT de les modifier.
  if [[ $nvidia_open == "true" && $has_kernel_open == true ]]; then
    cp -r "${ext}/kernel-open"/* "$ksrc/"
  else
    cp -r "${ext}/kernel"/* "$ksrc/"
  fi

  # Le fichier dkms.conf fourni est un modèle, généralement rempli par nvidia-installer.
  # La liste des modules se trouve à la ligne 4 du manifest, séparée par des espaces.
  local modules; modules=$(awk 'NR==4{$1=$1;print}' "$manifest")
  local dkms_modules='' i=0
  for m in $modules; do
    dkms_modules+=$'\n'"BUILT_MODULE_NAME[$i]=\"$m\""
    dkms_modules+=$'\n'"DEST_MODULE_LOCATION[$i]=\"/kernel/drivers/video\""
    ((i++))
  done
  local dkms_conf="${ksrc}/dkms.conf"
  sed -i "s/__VERSION_STRING/${pkgver}/g" "$dkms_conf"
  sed -i "s/PACKAGE_NAME=\"nvidia\"/PACKAGE_NAME=\"${_dkmsname}\"/g" "$dkms_conf"
  
  # Remplacement complet de la ligne MAKE[0] pour éviter les problèmes de placeholders.
  # Kernel compilé avec clang => build module en clang/lld, sinon build classique.
  sed -i "s|^MAKE\[0\].*|MAKE[0]=\"env IGNORE_CC_MISMATCH=1 bash -c 'if grep -qi clang \\\"/lib/modules/\\\${kernelver}/build/include/generated/compile.h\\\" 2>/dev/null; then exec make -j$(nproc) LLVM=1 CC=clang LD=ld.lld NV_EXCLUDE_BUILD_MODULES=\\\"\\\" KERNEL_UNAME=\\\${kernelver} modules; else exec make -j$(nproc) NV_EXCLUDE_BUILD_MODULES=\\\"\\\" KERNEL_UNAME=\\\${kernelver} modules; fi'\"|" "$dkms_conf"
  
  # Insertion des modules (remplace la ligne __DKMS_MODULES)
  echo "$dkms_modules" > "${srcdir}/dkms_modules.txt"
  sed -i "/__DKMS_MODULES/r ${srcdir}/dkms_modules.txt" "$dkms_conf"
  sed -i "/__DKMS_MODULES/d" "$dkms_conf"
}

package() {
  # Fichiers de configuration additionnels, standards pour les paquets NVIDIA sous Debian.
  install -d -m755 "${pkgdir}/etc/modprobe.d" "${pkgdir}/etc/modules-load.d"

  cat > "${pkgdir}/etc/modprobe.d/blacklist-nouveau.conf" <<'EOF'
blacklist nouveau
options nouveau modeset=0
EOF

  cat > "${pkgdir}/etc/modprobe.d/nvidia.conf" <<'EOF'
options nvidia NVreg_PreserveVideoMemoryAllocations=1
options nvidia NVreg_TemporaryFilePath=/tmp
options nvidia-drm modeset=1 fbdev=1
EOF

  cat > "${pkgdir}/etc/modules-load.d/nvidia.conf" <<'EOF'
nvidia
nvidia-drm
nvidia-uvm
EOF

  # Ajustement du fichier .desktop pour correspondre aux conventions Debian
sed \
  -e 's:__UTILS_PATH__:/usr/bin:' \
  -e 's:__PIXMAP_PATH__:/usr/share/pixmaps:' \
  -e 's/__NVIDIA_SETTINGS_DESKTOP_CATEGORIES__/Settings;HardwareSettings;/' \
  -e 's/Icon=.*/Icon=nvidia-settings/' \
  -i "${pkgdir}/usr/share/applications/nvidia-settings.desktop" || true
}

# ---------------------------------------------------------------------------
# Scripts de cycle de vie (Hooks)
# ---------------------------------------------------------------------------

pre_upgrade() {
  # Suppression de l'ancienne version des modules DKMS
  if command -v dkms >/dev/null; then dkms remove "${_dkmsname}/${pkgver}" --all 2>/dev/null || true; fi
}

post_upgrade() {
  post_install
}

pre_remove() {
  # Suppression des modules du noyau via DKMS avant la désinstallation
  if command -v dkms >/dev/null; then dkms remove "${_dkmsname}/${pkgver}" --all 2>/dev/null || true; fi
}

post_install() {
  # Installation des modules du noyau avec DKMS (gère automatiquement add et build)
  if command -v dkms >/dev/null; then
    dkms install "${_dkmsname}/${pkgver}" || echo "AVERTISSEMENT: L'installation DKMS a échoué (en-têtes du noyau manquants ?)"
  fi
  # Mise à jour du cache des bibliothèques partagées et de l'initramfs
  if command -v ldconfig >/dev/null; then ldconfig || true; fi
  if command -v update-initramfs >/dev/null; then update-initramfs -u || true; fi
  xdg-desktop-menu forceupdate
}

post_remove() {
  # Mise à jour post-désinstallation
  if command -v ldconfig >/dev/null; then ldconfig || true; fi
  if command -v update-initramfs >/dev/null; then update-initramfs -u || true; fi
  xdg-desktop-menu forceupdate
}
