#!/usr/bin/env bash
#
# Builds, installs and tests the iOS app on the owner's Mac and iPad over SSH, from the Windows
# PC (Git Bash) or any shell with ssh. One agent runs the whole loop with it; nobody has to carry
# prompts to the Mac. The steps are the ones in docs/ios/mac-runbook.md.
#
#   ios/scripts/mac.sh setup                clone the agent's own checkout on the Mac, once
#   ios/scripts/mac.sh sync [--wip]         push this branch, then fetch, check out and pull it on
#                                           the Mac, with the iOS submodules. --wip also applies the
#                                           uncommitted changes under ios/ (new files must be staged);
#                                           the next sync takes them out again
#   ios/scripts/mac.sh build                xcodegen, then a Release build of the app and of the
#                                           device-run tests for the iPad
#   ios/scripts/mac.sh install              install the app over the old copy (never uninstalls)
#   ios/scripts/mac.sh test <name> [VAR=value ...]  (name: a StreamDeviceRunTests method, or Class/method)
#                                           run one StarwireDeviceRun test, for example
#                                           `test stream PRESENTER=display SECONDS=120`. VAR becomes
#                                           TEST_RUNNER_STARWIRE_VAR. The [device-run] lines and the
#                                           summary come back to build/mac/<label>.txt
#   ios/scripts/mac.sh unit                 the app's unit tests on a simulator
#   ios/scripts/mac.sh ci                   every check GitHub's iOS workflow runs, on the Mac
#   ios/scripts/mac.sh snapshots [record]   the screens' snapshot tests on an iPhone and an iPad
#                                           simulator; "record" writes new pictures
#   ios/scripts/mac.sh log [seconds] [args] start the app with its console log for N seconds (20),
#                                           with launch arguments like -StarwireVerboseLogging YES
#   ios/scripts/mac.sh run '<command>'      any command in the Mac's repo, with the same setup
#
# Test names: stream (testStreamAndSample), resume (testBackgroundAndResume), streams
# (testStreamsInARow), or a full test method name.
#
# The Mac keeps the team ID and the iPad's UDID out of git, in ~/.config/starwire/env:
#   STARWIRE_TEAM=XXXXXXXXXX   the free personal team (runbook section 3)
#   IPAD=<UDID>                optional, used only when one iPad is connected
# The iPad for install, test and log: STARWIRE_DEVICE=<UDID> in the PC's environment, or the
# first line of ~/.config/starwire/device on the PC. With more than one iPad on the Mac and no
# device named, those commands stop instead of picking one.
# Connection settings can be overridden with STARWIRE_MAC, STARWIRE_MAC_KEY and STARWIRE_MAC_REPO.
#
# The build signs the app, which needs the login keychain. macOS keeps it locked to SSH sessions,
# so the build runs as a one-off launchd job in the logged-in user's session (in_gui in
# mac-remote.sh), and the Mac's password is never needed. Such jobs can't read ~/Documents, so the
# agent has its own checkout in ~/Developer/Starwire and leaves the owner's copy alone.
#
# Rules this script keeps: it never uninstalls io.github.shev0k.starwire (pairing would be lost),
# never discards changes in the Mac's checkout (sync stops instead), and runs builds and tests
# under caffeinate so the Mac stays awake.

set -euo pipefail

# user@host of the Mac: STARWIRE_MAC, or the first line of ~/.config/starwire/mac-host on this PC
# (kept out of git, like the team ID on the Mac)
MAC=${STARWIRE_MAC:-$(head -n 1 "$HOME/.config/starwire/mac-host" 2>/dev/null || true)}
if [ -z "$MAC" ]; then
    echo "Set STARWIRE_MAC=user@host or put it in ~/.config/starwire/mac-host" >&2
    exit 2
fi
KEY=${STARWIRE_MAC_KEY:-$HOME/.ssh/id_ed25519_starwire_mac}
REPO=${STARWIRE_MAC_REPO:-/Users/shevok/Developer/Starwire}
HERE=$(cd "$(dirname "$0")/../.." && pwd)
DEVICE=${STARWIRE_DEVICE:-$(head -n 1 "$HOME/.config/starwire/device" 2>/dev/null || true)}
OUT="$HERE/build/mac"

ssh_mac() {
    ssh -i "$KEY" -o BatchMode=yes -o ConnectTimeout=15 -o ServerAliveInterval=30 "$MAC" "$@"
}

# Runs a bash script on the Mac with the shared setup: PATH for xcodegen, the env file, the repo,
# and helper functions. Arguments after the script become $1, $2 ... there.
remote() {
    local script=$1
    shift
    local quoted=""
    for a in "$@"; do
        quoted+=" $(printf '%q' "$a")"
    done
    {
        printf 'REPO=%q\n' "$REPO"
        printf 'STARWIRE_DEVICE=%q\n' "$DEVICE"
        cat "$HERE/ios/scripts/mac-remote.sh"
        printf '%s\n' "$script"
    } | ssh_mac "bash -s --$quoted"
}

cmd=${1:-}
shift || true

case "$cmd" in
setup)
    remote '
if [ ! -d "$REPO/.git" ]; then
    git clone -q https://github.com/shev0k/Starwire.git "$REPO"
fi
echo "checkout at $REPO"
'
    ;;

sync)
    branch=$(git -C "$HERE" rev-parse --abbrev-ref HEAD)
    git -C "$HERE" push -q -u origin "$branch"
    wip=""
    if [ "${1:-}" = "--wip" ]; then
        # Sent on its own over stdin: a large patch as an argument resets the SSH connection
        git -C "$HERE" diff HEAD -- ios | ssh_mac "mkdir -p '$REPO/build' && cat > '$REPO/build/wip.next.patch'"
        wip=1
    fi
    remote '
branch=$1
# Undo the last --wip patch first: it is the only change this script makes in the checkout
if [ -f build/wip.patch ]; then
    git apply -R build/wip.patch
    rm build/wip.patch
fi
if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
    echo "The Mac checkout has uncommitted changes; not touching them:" >&2
    git status --short >&2
    exit 4
fi
git fetch -q origin
if git rev-parse -q --verify "refs/heads/$branch" >/dev/null; then
    git checkout -q "$branch"
else
    git checkout -q -b "$branch" --track "origin/$branch"
fi
git pull -q --ff-only
git submodule sync -q --recursive
git submodule update -q --init --recursive ios/moonlight-common/moonlight-common-c ios/X1Kit ios/third_party/imgui ios/third_party/implot
echo "Mac at $(git rev-parse --short HEAD) on $branch"
if [ -n "${2:-}" ]; then
    mv build/wip.next.patch build/wip.patch
    git apply build/wip.patch
    echo "plus the uncommitted changes under ios/ ($(grep -c "^diff" build/wip.patch) files)"
fi
' "$branch" "$wip"
    ;;

build)
    remote '
need_team
(cd ios && xcodegen generate --quiet)
# Signing for the named iPad registers it with the team and puts it in every profile, the test
# runner too; a generic build only covers iPads that were registered before
destination=generic/platform=iOS
if [ -n "${STARWIRE_DEVICE:-}" ]; then
    destination=id=$STARWIRE_DEVICE
fi
status=0
in_gui "cd ios && caffeinate -i xcodebuild -project Starwire.xcodeproj -scheme StarwireDeviceRun     -configuration Release -destination $destination -derivedDataPath ../build/DerivedData     -allowProvisioningUpdates -allowProvisioningDeviceRegistration     DEVELOPMENT_TEAM=$STARWIRE_TEAM CODE_SIGN_STYLE=Automatic build-for-testing" > build/device-build.log 2>&1 || status=$?
grep -E ": (fatal )?error:|^error:|errSec|\[-Wformat|\*\* (BUILD|TEST BUILD) (SUCCEEDED|FAILED)" build/device-build.log | cut -c1-300 | sort -u | tail -40
echo "warnings: $(grep -c ": warning:" build/device-build.log || true)"
exit $status
'
    ;;

install)
    remote '
need_ipad
app=build/DerivedData/Build/Products/Release-iphoneos/Starwire.app
[ -d "$app" ] || { echo "No build at $app: run build first" >&2; exit 5; }
xcrun devicectl device install app --device "$IPAD" "$app" 2>&1 | tail -5
'
    ;;

test)
    name=${1:?test name: stream, resume, streams or a method name}
    shift
    case "$name" in
        stream) method=testStreamAndSample ;;
        resume) method=testBackgroundAndResume ;;
        streams) method=testStreamsInARow ;;
        */*) method=$name ;;
        *) method=StreamDeviceRunTests/$name ;;
    esac
    case "$method" in
        test*) method=StreamDeviceRunTests/$method ;;
    esac
    label="${name////-}"
    vars=()
    for kv in "$@"; do
        vars+=("TEST_RUNNER_STARWIRE_$kv")
        label+="-${kv//[^A-Za-z0-9]/}"
    done
    label+="-$(date -u +%H%M%S)"
    mkdir -p "$OUT"
    # The test runs detached on the Mac, so a dropped SSH connection (a Wi-Fi blip, the Mac
    # dozing) doesn't stop it or start a second one; the PC polls until it's done.
    remote '
need_team
need_ipad
method=$1
label=$2
shift 2
if pgrep -f "xcodebuild test-without-building" >/dev/null; then
    echo "another device test is already running on the Mac; not starting a second one" >&2
    exit 7
fi
vars=""
for kv in "$@"; do vars+=" $(printf "%q" "$kv")"; done
nohup bash -c "cd ios; status=0; env$vars caffeinate -i xcodebuild test-without-building -project Starwire.xcodeproj \
    -scheme StarwireDeviceRun -configuration Release -destination id=$IPAD -derivedDataPath ../build/DerivedData \
    -resultBundlePath ../build/runs/$label.xcresult -only-testing:StarwireDeviceRun/$method \
    > ../build/runs/$label.log 2>&1 || status=\$?; echo \$status > ../build/runs/$label.done" >/dev/null 2>&1 &
echo "started $method ($*) as $label"
' "$method" "$label" "${vars[@]}" || exit $?
    # Poll, riding out SSH failures, for as long as the stream could take plus setup
    seconds=300
    for kv in "$@"; do
        case "$kv" in SECONDS=*) seconds=${kv#SECONDS=} ;; STREAMS=*) seconds=$(( ${kv#STREAMS=} * 25 )) ;; esac
    done
    deadline=$(( $(date +%s) + seconds + 600 ))
    while :; do
        sleep 15
        done_status=$(ssh_mac "cat '$REPO/build/runs/$label.done' 2>/dev/null" 2>/dev/null) || continue
        [ -n "$done_status" ] && break
        if [ "$(date +%s)" -gt "$deadline" ]; then
            echo "the test hasn't finished in time; it may still be running on the Mac ($label)" >&2
            exit 8
        fi
    done
    remote '
label=$1
echo "test $label, exit $(cat build/runs/$label.done)"
grep -E "\[device-run\]|^ *(Video stream|Network:|Pacing|Shown for|Frames dropped|Average network|Decode time|Frame queue)|error:|Test Case .*(passed|failed|skipped)|\*\* TEST" "build/runs/$label.log" || true
' "$label" | tee "$OUT/$label.txt"
    exit "$done_status"
    ;;

ci)
    # The same checks as .github/workflows/ios.yml, on the Mac, so GitHub's runners are only
    # needed at the end of a batch. Each step's log is in build/ci/ on the Mac; a summary line per
    # step comes back. It doesn't stop at the first failure, so one run shows everything.
    remote '
mkdir -p build/ci
log=$PWD/build/ci
results=""
step() {
    local name=$1
    shift
    if (set -o pipefail; "$@" > "$log/$name.log" 2>&1); then
        results+="$name: passed"$'"'"'\n'"'"'
    else
        results+="$name: FAILED (build/ci/$name.log)"$'"'"'\n'"'"'
        grep -E "error:|failed \(|\*\* .* FAILED" "$log/$name.log" | sort -u | head -15
    fi
}
cd ios
step generate xcodegen generate --spec project.yml
step build-debug caffeinate -i xcodebuild -project Starwire.xcodeproj -scheme Starwire -configuration Debug \
    -destination "generic/platform=iOS Simulator" -derivedDataPath ../build/ci/DerivedData CODE_SIGNING_ALLOWED=NO build
step build-release caffeinate -i xcodebuild -project Starwire.xcodeproj -scheme Starwire -configuration Release \
    -destination "generic/platform=iOS Simulator" -derivedDataPath ../build/ci/DerivedData CODE_SIGNING_ALLOWED=NO build
udid=$(xcrun simctl list devices available | grep -E "iPad Pro" | head -1 | grep -Eo "[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}")
step unit-tests caffeinate -i xcodebuild -project Starwire.xcodeproj -scheme Starwire -configuration Debug \
    -destination "id=$udid" -derivedDataPath ../build/ci/DerivedDataTests -collect-test-diagnostics never CODE_SIGN_IDENTITY=- test
step build-device-run caffeinate -i xcodebuild -project Starwire.xcodeproj -scheme StarwireDeviceRun -configuration Release \
    -destination "generic/platform=iOS Simulator" -derivedDataPath ../build/ci/DerivedData CODE_SIGNING_ALLOWED=NO build-for-testing
cd ..
step script-tests python3 -m unittest discover -s ios/scripts/tests
step string-catalog python3 ios/scripts/strings-to-xcstrings.py --check
step starwirekit caffeinate -i swift test --package-path ios/StarwireKit --scratch-path build/ci/kit
grep -hE "Executed [0-9]+ tests" "$log/unit-tests.log" "$log/starwirekit.log" | tail -2
printf "%s" "$results"
! printf "%s" "$results" | grep -q FAILED
'
    ;;

unit)
    remote '
cd ios
xcodegen generate --quiet
sim=$(xcrun simctl list devices available | grep -Eo "iPhone [0-9]+ Pro \(" | head -1 | sed "s/ ($//")
[ -n "$sim" ] || sim=$(xcrun simctl list devices available | grep -Eo "iPhone[^(]*" | head -1 | sed "s/ *$//")
status=0
caffeinate -i xcodebuild -project Starwire.xcodeproj -scheme Starwire -configuration Debug \
    -destination "platform=iOS Simulator,name=$sim" -derivedDataPath ../build/DerivedData \
    -collect-test-diagnostics never CODE_SIGN_IDENTITY=- test > ../build/unit-tests.log 2>&1 || status=$?
grep -E "error:|Executed [0-9]+ tests|\*\* TEST|failed \(" ../build/unit-tests.log | sort -u | tail -40
exit $status
'
    ;;

snapshots)
    # The SwiftUI screens on an iPhone and an iPad simulator (SnapshotTests). "record" writes new
    # pictures to ios/Tests/Snapshots in the Mac's checkout instead of comparing.
    record=0
    [ "${1:-}" = record ] && record=1
    remote '
cd ios
xcodegen generate --quiet
status=0
for kind in iPhone iPad; do
    if [ $kind = iPhone ]; then
        line=$(xcrun simctl list devices available | grep -E "iPhone [0-9]+ Pro \(" | head -1)
    else
        line=$(xcrun simctl list devices available | grep -E "iPad Pro" | head -1)
    fi
    sim=$(echo "$line" | grep -Eo "[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}" | head -1)
    echo "== $kind: $(echo "$line" | sed "s/ *(.*//;s/^ *//") $sim"
    TEST_RUNNER_STARWIRE_RECORD='"$record"' caffeinate -i xcodebuild -project Starwire.xcodeproj -scheme Starwire         -configuration Debug -destination "platform=iOS Simulator,id=$sim" -derivedDataPath ../build/DerivedData         -resultBundlePath ../build/runs/snapshots-$kind-$(date +%H%M%S).xcresult         -only-testing:StarwireTests/SnapshotTests -collect-test-diagnostics never CODE_SIGN_IDENTITY=- test         > ../build/snapshots-$kind.log 2>&1 || status=$?
    grep -E "error:|Executed [0-9]+ tests|\*\* TEST|skipped|failed \(" ../build/snapshots-$kind.log | sort -u | tail -30
done
exit $status
'
    ;;

log)
    seconds=${1:-20}
    shift || true
    remote '
need_ipad
seconds=$1
shift
xcrun devicectl device process launch --console --terminate-existing \
    --environment-variables "{\"OS_ACTIVITY_DT_MODE\":\"enable\"}" --device "$IPAD" io.github.shev0k.starwire ${1:+--} "$@" > build/console.log 2>&1 &
pid=$!
sleep "$seconds"
kill "$pid" 2>/dev/null || true
wait "$pid" 2>/dev/null || true
grep -E "Starwire\[" build/console.log | tail -400
' "$seconds" "$@"
    ;;

run)
    remote "$1"
    ;;

*)
    sed -n '2,32p' "$0"
    exit 1
    ;;
esac
