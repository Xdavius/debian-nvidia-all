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
  "0001-Enable-atomic-kernel-modesetting-by-default.diff"
  "0002-Add-IBT-support.diff"
  "01-ipmi-vm.diff"
  "02-ipmi-vm.diff"
  "455-crashfix.diff"
  "5.11-legacy.diff"
  "5.6-ioremap.diff"
  "5.6-legacy-includes.diff"
  "5.8-legacy.diff"
  "5.9-gpl.diff"
  "6.1-6-7-8-gpl.diff"
  "6.11-fbdev.diff"
  "Add-IBT-support.diff"
  "Enable-atomic-kernel-modesetting-by-default.diff"
  "GFP_RETRY_MAYFAIL-test.diff"
  "fix-hdmi-names.diff"
  "fix-hw-cursor-kde.diff"
  "gcc-14-470.diff"
  "gcc-14.diff"
  "gcc-15.diff"
  "kernel-4.16.patch"
  "kernel-4.19.patch"
  "kernel-5.0.patch"
  "kernel-5.1.patch"
  "kernel-5.10.patch"
  "kernel-5.11.patch"
  "kernel-5.12.patch"
  "kernel-5.14.patch"
  "kernel-5.16-std.diff"
  "kernel-5.16.patch"
  "kernel-5.17.patch"
  "kernel-5.2.patch"
  "kernel-5.3.patch"
  "kernel-5.4-prime.diff"
  "kernel-5.4-symver.diff"
  "kernel-5.4.patch"
  "kernel-5.5.patch"
  "kernel-5.6.patch"
  "kernel-5.7.patch"
  "kernel-5.8.patch"
  "kernel-5.9.patch"
  "kernel-6.0-470.patch"
  "kernel-6.0.patch"
  "kernel-6.12.patch"
  "kernel-6.17.patch"
  "kernel-6.19-470.patch"
  "kernel-6.19.patch"
  "kernel-6.2.patch"
  "kernel-6.3.patch"
  "kernel-6.4.patch"
  "kernel-6.5.patch"
  "kernel-6.8.patch"
  "kernel-7.0-470.patch"
  "kernel-7.0-580.patch"
  "kernel-7.0.patch"
  "kernel-7.1.patch"
  "legacy-kernel-6.4.diff"
  "legacy-kernel-6.5.diff"
  "legacy-kernel-6.6.diff"
  "linux-version.diff"
  "list_is_first.diff"
  "make-modeset-fbdev-default-565.diff"
  "make-modeset-fbdev-default.diff"
  "nvidia-bsb-dsc-fix.diff"
  "nvidia-open-gcc-ibt-sls.diff"
  "nvidia-settings-libxnvctrl_so.diff"
  "silence-event-assert-until-570.diff"
  "99-local-kernel-compat-390.patch"
)
sha256sums=('SKIP')
maintainer=("xdavius <xdavius@gmail.com>")

# ---------------------------------------------------------------------------
# Sélection conditionnelle des patchs NVIDIA
# ---------------------------------------------------------------------------

_ver_major() {
  echo "${pkgver%%.*}"
}

_patch_plan() {
  local p=$1 major
  major=$(_ver_major)

  # Sortie: status|base_dir|patch_level|reason
  # status: apply pour tenter le patch, skip pour le noter sans tenter.
  case $p in
    99-local-kernel-compat-390.patch)
      [[ $major == 390 ]] && echo "apply|.|1|compatibilite locale serie 390" || \
        echo "skip|||patch reserve a la serie 390"
      return ;;

    0001-Enable-atomic-kernel-modesetting-by-default.diff|fix-hw-cursor-kde.diff)
      [[ ${has_real_kernel_open:-false} == "true" && $nvidia_open == "true" ]] && \
        echo "apply|kernel-open|1|patch kernel-open" || \
        echo "skip|||patch kernel-open non applicable au mode courant"
      return ;;

    0002-Add-IBT-support.diff|Add-IBT-support.diff|nvidia-open-gcc-ibt-sls.diff|\
    silence-event-assert-until-570.diff|fix-hdmi-names.diff|kernel-7.0-580.patch)
      [[ ${has_real_kernel_open:-false} == "true" && $nvidia_open == "true" ]] && \
        echo "apply|kernel-open|1|patch sources kernel-open" || \
        echo "skip|||patch kernel-open non applicable au mode courant"
      return ;;

    Enable-atomic-kernel-modesetting-by-default.diff|make-modeset-fbdev-default.diff|\
    make-modeset-fbdev-default-565.diff|6.11-fbdev.diff|kernel-*.patch|kernel-*.diff|\
    legacy-kernel-*.diff|[0-9].*-*.diff|gcc-*.diff|linux-version.diff|\
    list_is_first.diff|GFP_RETRY_MAYFAIL-test.diff|455-crashfix.diff|\
    nvidia-bsb-dsc-fix.diff|01-ipmi-vm.diff|02-ipmi-vm.diff)
      [[ $nvidia_open == "false" || ${has_real_kernel_open:-false} != "true" ]] && \
        echo "apply|.|1|patch arbre proprietaire/legacy" || \
        echo "skip|||patch proprietaire ignore en mode kernel-open"
      return ;;

    nvidia-settings-libxnvctrl_so.diff)
      echo "apply|.|1|patch utilisateur"
      return ;;
  esac

  echo "apply|.|1|patch non classe, tentative prudente"
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

  echo "Patches trouvés dans ${srcdir} : $(find "${srcdir}" -maxdepth 1 \( -name "*.patch" -o -name "*.diff" \) -print | xargs -r -n1 basename | tr '\n' ' ')"

  applied_patches=()
  failed_patches=()
  skipped_patches=()

  local p p_name plan status base_dir patch_level reason oldpwd
  for p in "${source[@]}"; do
    p_name=$(basename "$p")
    [[ $p_name == *.diff || $p_name == *.patch ]] || continue
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
      echo "  [--] $p_name ($reason)"
      echo "SKIP: $reason" >> "${srcdir}/debug.txt"
      continue
    fi
    if [[ ! -d $base_dir ]]; then
      failed_patches+=("$p_name")
      echo "  [!!] $p_name (Dossier cible absent: $base_dir)"
      echo "MISSING TARGET DIR: $base_dir ($reason)" >> "${srcdir}/debug.txt"
      continue
    fi
    echo "Target: ${base_dir}, -p${patch_level} (${reason})" >> "${srcdir}/debug.txt"
    
    # Test à blanc (dry-run) pour éviter de corrompre les fichiers en cas d'échec partiel
    oldpwd=$PWD
    cd "$base_dir" || return 1
    if patch -p"$patch_level" -N -F 3 --dry-run < "$p" >> "${srcdir}/debug.txt" 2>&1; then
      if patch -p"$patch_level" -N -F 3 < "$p" >> "${srcdir}/debug.txt" 2>&1; then
        applied_patches+=("$p_name")
        echo "  [OK] $p_name (${base_dir})"
      else
        failed_patches+=("$p_name")
        echo "  [!!] $p_name (Erreur imprévue)"
      fi
    else
      failed_patches+=("$p_name")
      echo "  [..] $p_name (Incompatible)"
    fi
    cd "$oldpwd" || return 1
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
  if [[ ${#skipped_patches[@]} -gt 0 ]]; then
    echo " Liste des patches ignorés :"
    for p in "${skipped_patches[@]}"; do
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
  
  # Remplacement complet de la ligne MAKE[0] pour éviter les problèmes de placeholders
  # On y injecte IGNORE_CC_MISMATCH=1, le nombre de coeurs, et LLVM=1
  sed -i "s|^MAKE\[0\].*|MAKE[0]=\"env IGNORE_CC_MISMATCH=1 'make' -j$(nproc) NV_EXCLUDE_BUILD_MODULES='' KERNEL_UNAME=\${kernelver} modules LLVM=1\"|" "$dkms_conf"
  
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
