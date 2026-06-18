#!/usr/bin/env bash
# Update pkgs/dirge-bin to a given (or the latest) upstream release.
#
# dirge-bin pins one prebuilt-tarball hash per platform in a custom `sel`
# attrset, which `nix-update` can't traverse (and it could only rehash the
# platform it runs on). This script rewrites the version and *both* platform
# hashes in one go, sourcing them from upstream's published `.sha256` assets.
#
# Usage:
#   pkgs/dirge-bin/update.sh            # bump to the latest GitHub release
#   pkgs/dirge-bin/update.sh 0.7.7      # bump to a specific version
set -euo pipefail

repo="dirge-code/dirge"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
nix_file="$script_dir/default.nix"

# Triples must match the `sel` attrset keys/values in default.nix.
declare -A triples=(
  [x86_64-linux]=x86_64-unknown-linux-gnu
  [aarch64-darwin]=aarch64-apple-darwin
)

# Resolve target version: explicit arg, else the latest release tag.
if [[ $# -ge 1 ]]; then
  version="${1#v}"
else
  version="$(curl -fsSL "https://api.github.com/repos/$repo/releases/latest" \
    | sed -n 's/.*"tag_name": *"v\{0,1\}\([^"]*\)".*/\1/p' | head -n1)"
  [[ -n "$version" ]] || { echo "error: could not determine latest release" >&2; exit 1; }
fi
echo "Updating dirge-bin -> $version"

to_sri() {
  # hex sha256 -> SRI, tolerating older/newer nix CLIs.
  nix hash convert --hash-algo sha256 --to sri --from base16 "$1" 2>/dev/null \
    || nix hash to-sri --type sha256 "$1"
}

# Rewrite version line (value passed via env to dodge regex-special chars).
version="$version" perl -pi -e 's/^(\s*version = ")[^"]*(";)/$1$ENV{version}$2/' "$nix_file"

# Rewrite each platform hash (the `hash =` line immediately following its
# triple). Values go through the environment and the replacement is evaluated
# (/e) so `/`, `+`, `=` in SRI hashes can't break the substitution.
for triple in "${triples[@]}"; do
  url="https://github.com/$repo/releases/download/v$version/dirge-$triple.tar.gz.sha256"
  hex="$(curl -fsSL "$url" | awk '{print $1}')"
  [[ -n "$hex" ]] || { echo "error: missing .sha256 asset: $url" >&2; exit 1; }
  sri="$(to_sri "$hex")"
  echo "  $triple -> $sri"
  triple="$triple" sri="$sri" perl -0pi -e '
    my $t = quotemeta $ENV{triple};
    s/(triple = "$t";\s*\n\s*hash = )"[^"]*"/$1 . q{"} . $ENV{sri} . q{"}/e;
  ' "$nix_file"
done

echo "Done. Verify with: nix build .#dirge-bin --impure && ./result/bin/dirge --version"
