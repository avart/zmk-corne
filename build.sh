#!/usr/bin/env bash
# Build the ZMK firmware locally in Docker, the same way the GitHub workflow does.
#
#   ./build.sh                 build every target in build.yaml
#   ./build.sh left            build only targets whose name contains "left"
#   ./build.sh --update        run "west update" first (e.g. to pull zmk-locales main)
#   ./build.sh --pristine      clean build directories first
#   ./build.sh --reset         delete the cached west workspace and start over
#
# Output: firmware/<artifact-name>.uf2
#
# The west workspace (ZMK, Zephyr, modules, build dirs) lives in a Docker volume so
# it survives between runs and avoids slow bind mounts on macOS. The first run
# downloads a few GB and takes a while; later runs are incremental.
set -euo pipefail

IMAGE="${ZMK_IMAGE:-zmkfirmware/zmk-build-arm:stable}"
VOLUME="${ZMK_VOLUME:-zmk-corne-workspace}"

# ---------------------------------------------------------------- host side --
if [ -z "${ZMK_IN_CONTAINER:-}" ]; then
    repo="$(cd "$(dirname "$0")" && pwd)"
    if [[ " $* " == *" --reset "* ]]; then
        echo ">> Removing volume ${VOLUME}"
        docker volume rm -f "${VOLUME}" >/dev/null
    fi
    tty_flag=-i
    [ -t 0 ] && [ -t 1 ] && tty_flag=-it
    exec docker run --rm "${tty_flag}" \
        -e ZMK_IN_CONTAINER=1 \
        -v "${VOLUME}:/zmk" \
        -v "${repo}:/repo" \
        -w /zmk \
        "${IMAGE}" \
        /repo/build.sh "$@"
fi

# ----------------------------------------------------------- container side --
update=0
pristine=auto
filters=()
for arg in "$@"; do
    case "$arg" in
        --update) update=1 ;;
        --pristine) pristine=always ;;
        --reset) ;;
        -h|--help) sed -n '2,13p' /repo/build.sh; exit 0 ;;
        -*) echo "Unknown option: $arg" >&2; exit 2 ;;
        *) filters+=("$arg") ;;
    esac
done

# The workspace only gets a copy of the manifest; the config, boards and
# shields are read straight from the repo so edits are picked up directly.
mkdir -p /zmk/config
if ! cmp -s /repo/config/west.yml /zmk/config/west.yml; then
    cp /repo/config/west.yml /zmk/config/west.yml
    update=1
fi
if [ ! -d /zmk/.west ]; then
    echo ">> west init"
    west init -l /zmk/config
    update=1
fi
if [ "$update" = 1 ] || [ ! -d /zmk/zmk ]; then
    echo ">> west update"
    west update --fetch-opt=--filter=tree:0
fi
west zephyr-export >/dev/null

extra_modules=""
[ -e /repo/zephyr/module.yml ] && extra_modules="-DZMK_EXTRA_MODULES=/repo"

# One line per build.yaml entry: board|shield|snippet|cmake-args|artifact-name
targets="$(python3 - <<'EOF'
import yaml
with open("/repo/build.yaml") as f:
    m = yaml.safe_load(f) or {}
entries = list(m.get("include") or [])
for b in m.get("board") or []:
    for s in m.get("shield") or [None]:
        entries.append({"board": b, "shield": s})
for e in entries:
    board, shield = e["board"], e.get("shield") or ""
    name = e.get("artifact-name") or (f"{shield}-" if shield else "") + f"{board}-zmk"
    print("|".join([board, shield, e.get("snippet") or "", e.get("cmake-args") or "", name]))
EOF
)"

mkdir -p /repo/firmware
built=()
failed=()
while IFS='|' read -r board shield snippet cmake_args name; do
    [ -z "$board" ] && continue
    if [ ${#filters[@]} -gt 0 ]; then
        match=0
        for f in "${filters[@]}"; do [[ "$name" == *"$f"* ]] && match=1; done
        [ "$match" = 1 ] || continue
    fi

    echo
    echo ">> Building ${name}"
    args=(-s zmk/app -d "/zmk/build/${name}" -b "$board" -p "$pristine")
    [ -n "$snippet" ] && args+=(-S "$snippet")
    cmake=(-DZMK_CONFIG=/repo/config)
    [ -n "$shield" ] && cmake+=("-DSHIELD=${shield}")
    [ -n "$extra_modules" ] && cmake+=("$extra_modules")
    # shellcheck disable=SC2206
    [ -n "$cmake_args" ] && cmake+=($cmake_args)

    if west build "${args[@]}" -- "${cmake[@]}"; then
        out="/zmk/build/${name}/zephyr"
        if [ -f "$out/zmk.uf2" ]; then
            cp "$out/zmk.uf2" "/repo/firmware/${name}.uf2"
            built+=("firmware/${name}.uf2")
        else
            cp "$out/zmk.bin" "/repo/firmware/${name}.bin"
            built+=("firmware/${name}.bin")
        fi
    else
        failed+=("$name")
    fi
done <<< "$targets"

echo
if [ ${#built[@]} -eq 0 ] && [ ${#failed[@]} -eq 0 ]; then
    echo "No targets matched: ${filters[*]}" >&2
    exit 1
fi
for f in "${built[@]}"; do echo "OK      $f"; done
for f in "${failed[@]}"; do echo "FAILED  $f"; done
[ ${#failed[@]} -eq 0 ]
