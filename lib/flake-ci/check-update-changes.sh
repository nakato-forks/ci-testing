#!/usr/bin/env bash

set -euo pipefail

set -x

CI_FORCE_REFRESH="${CI_FORCE_REFRESH:-false}"

SCRIPT_PATH="$(readlink -f $0)"
SCRIPT_DIR="$(dirname ${SCRIPT_PATH})"

export GIT_AUTHOR_EMAIL="${CI_GIT_EMAIL}"
export GIT_AUTHOR_NAME="SBC-CI"

git config --global user.email "${GIT_AUTHOR_EMAIL}"
git config --global user.name "${GIT_AUTHOR_NAME}"

if [[ ${CI_FORCE_REFRESH} != true ]]; then
  PREV_ATTRSET="$(nix eval '.#_lib.builders.buildTargets.aarch64-linux' --apply 'drv: builtins.mapAttrs (k: v: {prev = v.drvPath;}) drv')"

  nix flake update --commit-lock-file

  NEXT_ATTRSET="$(nix eval '.#_lib.builders.buildTargets.aarch64-linux' --apply 'drv: builtins.mapAttrs (k: v: {next = v.drvPath;}) drv')"

  NEEDS_REFRESH="$(nix eval --impure --expr "import ${SCRIPT_DIR}/compareDrvs.nix ${PREV_ATTRSET} ${NEXT_ATTRSET}" --apply "as: as.needsRefresh")"
else
  # Skip updating lockfile on force-refresh.
  echo "Refresh has been forced"
  NEEDS_REFRESH="true"
fi

if [[ ${NEEDS_REFRESH} = false ]]; then
  echo "No derivations need refreshed, not updating lockfile and not rebuilding"
  exit 0
fi

echo "Derivations need to be built and pushed to cache"

TARGETS=($(nix eval --raw .#_lib.builders.buildTargets.aarch64-linux --apply 'f: builtins.concatStringsSep " " (builtins.attrNames f)'))

for TARGET in ${TARGETS[@]}; do
  echo "Building target: $TARGET"
  nix build ".#_lib.builders.buildTargets.aarch64-linux.${TARGET}"
done

for TARGET in ${TARGETS[@]}; do
  echo "Pushing artifacts for: $TARGET"
  nix eval --json ".#_lib.builders.buildTargets.aarch64-linux.${TARGET}" --apply 'drv: builtins.map (n: drv.${n}) drv.outputs' | jq -r '.[]' | nix run 'nixpkgs#cachix' -- push "$CACHIX_REPO"
done

git push
