#!/bin/bash
set -euo pipefail

usage() {
  echo "Usage: $0 --version V --aarch64-sha SHA [--x86_64-sha SHA]"
  exit 1
}

VERSION=""
AARCH64_SHA=""
X86_64_SHA="0000000000000000000000000000000000000000000000000000000000000000"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) VERSION="$2"; shift 2 ;;
    --aarch64-sha) AARCH64_SHA="$2"; shift 2 ;;
    --x86_64-sha) X86_64_SHA="$2"; shift 2 ;;
    *) usage ;;
  esac
done

if [ -z "$VERSION" ] || [ -z "$AARCH64_SHA" ]; then
  usage
fi

TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

git clone --depth 1 https://github.com/begitcn/homebrew-tap.git "$TEMP_DIR"
cd "$TEMP_DIR"
git remote set-url origin "https://x-access-token:${GH_PAT}@github.com/begitcn/homebrew-tap.git"

CASK_DIR="$TEMP_DIR/Casks"
mkdir -p "$CASK_DIR"
CASK_FILE="$CASK_DIR/shelldeck.rb"

cat > "$CASK_FILE" << CASK_EOF
cask "shelldeck" do
  version "${VERSION}"
  arch arm: "aarch64", intel: "x86_64"

  on_arm do
    sha256 "${AARCH64_SHA}"
    url "https://github.com/begitcn/ShellDeck/releases/download/v#{version}/ShellDeck-#{arch}-v#{version}.dmg"
  end
  on_intel do
    sha256 "${X86_64_SHA}"
    url "https://github.com/begitcn/ShellDeck/releases/download/v#{version}/ShellDeck-#{arch}-v#{version}.dmg"
  end

  name "ShellDeck"
  desc "Native macOS SSH management tool — terminal, file manager, system monitor"
  homepage "https://github.com/begitcn/ShellDeck"

  app "ShellDeck.app"

  zap trash: [
    "~/Library/Application Support/com.chaogeek.ShellDeck",
    "~/Library/Caches/com.chaogeek.ShellDeck",
    "~/Library/Preferences/com.chaogeek.ShellDeck.plist",
  ]
end
CASK_EOF

git add -A
git config user.name "ShellDeck Bot"
git config user.email "bot@shelldeck.app"
git commit -m "shelldeck: update to v${VERSION}"
git push
