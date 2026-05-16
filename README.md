# Debian NVIDIA Driver Run (Pacstall)

Ce projet permet de construire et installer des paquets Debian NVIDIA à partir
des installateurs officiels `.run`, avec une logique de patch automatique.

## Le programme principal

Le script principal est :

- `nvidia-driver-run-config.sh`

Son rôle :

- guider l’utilisateur (choix version/branche NVIDIA),
- trouver ou télécharger le fichier `.run`,
- préparer la configuration de build,
- lancer Pacstall pour construire/installler le paquet.

En pratique, c’est l’entrée utilisateur recommandée.

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

Le script `nvidia-driver-run-config.sh` vérifie et propose l’installation des
dépendances manquantes (dont Pacstall).

## État actuel (ce qui fonctionne)

- Drivers `580 -> latest` : **OK** sur kernels `6.12 -> 7.0` (GCC/Clang)
- Driver legacy `470` : **OK** sur kernels `6.12 -> 7.0` (GCC/Clang)

## Notes

- Les patchs actifs sont dans `pacscript/`.
- Pour la branche 470, le patch cumulatif principal est :
  - `pacscript/470-kernel-7.0.patch`
