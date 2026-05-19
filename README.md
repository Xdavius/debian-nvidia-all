# Debian NVIDIA Driver Run (Pacstall)

Ce projet permet de construire et installer des paquets Debian NVIDIA à partir
des installateurs officiels `.run`, avec une logique de patch automatique.

![Capture de la GUI](ui/screenshot.png)

## Pourquoi ce projet

Objectif: fournir un flux fiable pour builder/installer les drivers NVIDIA sur Debian,
avec une UX simple (CLI/TUI/GUI) et une logique backend centralisée.

## Branches supportées 

Il supporte officiellement pour le kernel 6.12 les branches :
- Latest (Dernière version en date pour les cartes récentes)
- 580xx  (Dernière version pour les cartes GTX9xx et GTX10xx)
- 470xx  (Dernière version pour les GTX 600 et GTX 700, ainsi que certaines GTX 800M)
- 390xx  (Dernière version pour les GTX 400 et GTX 500)

Pour les kernels plus récents, il est possible que les patchs ne soient pas à jour.
- Les builds ont été testé sur le 7.0 TKG LLVM.
- Les drivers les plus problématiques sont les legacy 390 et 470. Il est recommandée de rester sur un kernel 6.12 pour ces vieux GPU

En cas de problèmes de build, merci d'ouvrir une issue en précisant :
- le kernel utilisé
- la version du driver NVIDIA
- les logs de build

## Modes d'utilisation

- **Easy mode (recommandé)** : GUI Rust/Slint
  - interface visuelle, guidage simple, logs intégrés
  - lancement : `cargo run`

- **Mode avancé** : TUI
  - assistant terminal avec plus de contrôle explicite
  - lancement : `bash ./debian-nvidia-all-tui.sh`

- **Mode expert / scripting** : CLI directe
  - automatisation, intégration scripts, debug fin
  - lancement : `bash ./debian-nvidia-all-cli.sh --help`

Dans tous les cas, le backend métier reste la CLI.

## Releases prébuild

Des builds précompilés sont publiés dans les **GitHub Releases** du projet.
Si tu ne veux pas compiler la GUI localement, récupère la release correspondant
à ton système et utilise les binaires/scripts fournis :
- Pour la GUI : `debian-nvidia-all-gui`
- Pour la TUI : `debian-nvidia-all-tui.sh`
- Pour la CLI : `debian-nvidia-all-cli.sh`

## Entrées recommandées

- CLI : `debian-nvidia-all-cli.sh`
- TUI : `debian-nvidia-all-tui.sh`
- GUI (Rust/Slint) : `cargo run`

## Architecture actuelle

- **Backend unique** : `debian-nvidia-all-cli.sh` (logique métier et système)
- **Frontend terminal** : `debian-nvidia-all-tui.sh` (menus, navigation)
- **Frontend graphique** : `ui/app.slint` + `src/main.rs` (orchestration + logs)

Le TUI et la GUI délèguent le métier au backend CLI.

## Le pacscript et Pacstall

Le coeur du build est le pacscript :

- `pacscript/nvidia-driver-run.pacscript`

Le pacscript contient :

- les dépendances,
- la logique d’extraction du `.run`,
- l’application des patchs,
- la préparation DKMS,
- la création du paquet.

Ce projet dépend de **Pacstall** pour exécuter ce pacscript et produire le
paquet Debian final.
Projet officiel : https://pacstall.dev/

Le script CLI `debian-nvidia-all-cli.sh` gère :
- la vérification/installation des dépendances (`spdx-licenses`, `pacstall`, outils requis),
- l’élévation de privilèges (sudo/pkexec + fallback prompts),
- la sélection runfile local/en ligne,
- l’exécution finale via Pacstall.

Options CLI utiles :
- `--check-dependencies`
- `--inspect-dependencies`
- `--print-versions`
- `--print-local-runfiles`

## Interface graphique (GUI Rust/Slint)

La GUI utilise Slint + Rust et pilote le backend shell (`debian-nvidia-all-cli.sh`).

### 1) Installer Rust/Cargo

Copier/coller :

```bash
sudo apt update
sudo apt install -y cargo
```

### 2) Optionnel: support XWayland

La GUI tente automatiquement un mode XWayland si possible, avec fallback Wayland natif.
Ce paquet peut être nécessaire selon l’environnement :

```bash
sudo apt install -y libxkbcommon-x11-0
```

### 3) Lancer la GUI

Depuis la racine du projet :

```bash
cargo run
```

Mode test popup dépendances (simulation) :

```bash
NVIDIA_GUI_TEST_MISSING_DEPS=1 cargo run
```

## État actuel (ce qui fonctionne)

- Drivers `580 -> latest` : **OK** sur kernels `6.12 -> 7.0` (GCC/Clang)
- Driver legacy `470` : **OK** sur kernels `6.12 -> 7.0` (GCC/Clang)
- Driver legacy `390.157` : **OK** sur kernels `6.12 -> 7.0` (GCC/Clang)

## Notes

- Les patchs actifs sont dans `pacscript/`.
- Règle actuelle : un patch cumulatif principal par branche NVIDIA.
- Branche `390` :
  - patch principal : `pacscript/390-kernel-7.0.patch`
  - le pacscript force uniquement ce patch pour la branche 390
- Branche `470` :
  - patch principal : `pacscript/470-kernel-7.0.patch`

## Remerciements

- **TKG** et son projet **nvidia-all** pour l'idée initiale et la collection de patchs :
  https://github.com/Frogging-Family/nvidia-all
