# Slint GUI (helper non-intrusif)

Cette GUI n'edite pas `nvidia-driver-run-config.sh`.

Elle lance `../nvidia-driver-run-config-slint-helper.sh` avec:

- Profil: `latest`, `recommended`, `legacy580`, `legacy470`, `legacy390`
- Action pacstall: `I`, `IB`, `IBK`, `PI`, `PIB`, `PIBK`
- Mode module: `auto`, `open`, `proprietary`

Regles appliquees par le helper:

- `latest` => `kernel-open` force
- toute version `580.x` => `kernel-open` force
- sinon mode selon selection UI

## Build

```bash
cd slint-gui
cargo run
```
