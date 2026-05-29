pkgbase="nvidia-debian-all-bootstrap"
pkgname="nvidia-debian-all-bootstrap"
pkgver="0.1.4"
pkgdesc="Bootstrap launcher for Debian NVIDIA All (self-updating app payload)"
url="https://github.com/Xdavius/debian-nvidia-all"
arch=("amd64")
maintainer="Xdavius"
license=("GPL-3.0")

depends=(
  "bash"
  "curl"
  "jq"
  "tar"
  "util-linux"
)

prepare() {
  cd "$srcdir"
}

build() {
  cd "$srcdir"
}

package() {
  cd "$srcdir"

  install -d "$pkgdir/usr/bin"
  install -d "$pkgdir/usr/share/applications"
  install -d "$pkgdir/usr/share/icons/hicolor/256x256/apps"

  install -m 0755 "packaging/nvidia-debian-all" "$pkgdir/usr/bin/debian-nvidia-all"
  install -m 0644 "packaging/debian-nvidia-all.desktop" "$pkgdir/usr/share/applications/debian-nvidia-all.desktop"

  if [[ -f "packaging/debian-nvidia-all.png" ]]; then
    install -m 0644 "packaging/debian-nvidia-all.png" "$pkgdir/usr/share/icons/hicolor/256x256/apps/debian-nvidia-all.png"
  fi
}
