# Debian NVIDIA Driver Run (Pacstall)

Ce projet permet de construire et installer des paquets Debian NVIDIA à partir
des installateurs officiels `.run`, avec une logique de patch automatique.
Il supporte officiellement pour le kernel 6.12 les branches :
- Latest (Dernière version en date pour les cartes récentes)
- 580xx  (Dernière version pour les cartes GTX9xx et GTX10xx)
- 470xx  (Dernière version pour les cartes GTX7xx et GTX8xx)
- 390xx  (Dernière version pour les cartes GTX5xx et GTX6xx)

Pour les kernels plus récents, il est possible que les patchs ne soient pas à jour.
Les builds ont été testé sur le 7.0 TKG LLVM.

En cas de problèmes de build, merci d'ouvrir une issue en précisant :
- le kernel utilisé
- la version du driver NVIDIA
- les logs de build


## Le programme principal

Le script principal est :

- `debian-nvidia-all-tui.sh`

Son rôle :

- guider l’utilisateur (choix version/branche NVIDIA),
- trouver ou télécharger le fichier `.run`,
- préparer la configuration de build,
- lancer Pacstall pour construire/installer le paquet.

En pratique, c’est l’entrée utilisateur recommandée.

## Entrées actuelles recommandées :

- CLI : `debian-nvidia-all-cli.sh`
- TUI : `debian-nvidia-all-tui.sh`
- GUI (Rust/Slint) : `cargo run`

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

Le script CLI actuel `debian-nvidia-all-cli.sh` vérifie et propose
l’installation des dépendances manquantes (dont Pacstall).

## Interface graphique (GUI Rust/Slint)

La GUI utilise Slint + Rust et pilote le backend shell (`debian-nvidia-all-cli.sh`).

### 1) Installer Rust/Cargo

Copier/coller :

```bash
sudo apt update
sudo apt install -y cargo
```

### 2) Optionnel: support XWayland pour mode GUI explicite (bug: la fenètre ne peut pas être déplacée en Wayland natif)

Ce paquet est utile si tu veux tester `NVIDIA_GUI_XWAYLAND=1`.

```bash
sudo apt install -y libxkbcommon-x11-0
```

### 3) Lancer la GUI

Depuis la racine du projet :

```bash
cargo run
```

Mode optionnel XWayland (avec fallback automatique si indisponible) :

```bash
NVIDIA_GUI_XWAYLAND=1 cargo run
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
