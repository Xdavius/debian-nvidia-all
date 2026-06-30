pkgname="debian-nvidia-all"
pkgver="1.2.2"
pkgdesc="Bootstrap launcher for Debian NVIDIA All (self-updating app payload)"
url="https://github.com/Xdavius/debian-nvidia-all"
arch=("amd64")
maintainer="xdavius <xdavius@github.com>"
license=("GPL-3.0")
source=("https://github.com/Xdavius/debian-nvidia-all.git")

depends=(
  "awk"
  "bash"
  "ca-certificates"
  "coreutils"
  "curl"
  "findutils"
  "grep"
  "gzip"
  "jq"
  "tar"
  "util-linux"
  "xdg-utils"
  "pkexec"
)

package() {
  cd "${pkgname}" || return 1

  install -d "$pkgdir/usr/bin"
  install -d "$pkgdir/usr/share/applications"
  install -d "$pkgdir/usr/share/icons/hicolor/256x256/apps"

  install -m 0755 "packaging/debian-nvidia-all" "$pkgdir/usr/bin/debian-nvidia-all"
  install -m 0644 "packaging/debian-nvidia-all.desktop" "$pkgdir/usr/share/applications/debian-nvidia-all.desktop"

  if [[ -f "packaging/debian-nvidia-all.png" ]]; then
    install -m 0644 "packaging/debian-nvidia-all.png" "$pkgdir/usr/share/icons/hicolor/256x256/apps/debian-nvidia-all.png"
  fi
}
