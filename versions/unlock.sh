#!/data/data/com.termux/files/usr/bin/bash
#
# fingerprint_unlock_monitor.sh
#
# Watches (or replays) Android logcat and prints/logs every time the
# lock screen is unlocked with fingerprint.
#
# Live monitor (default):       ./fingerprint_unlock_monitor.sh
# Replay a saved logcat dump:   ./fingerprint_unlock_monitor.sh unlockdata2.log
#
# --- How detection works ---
# On the current SystemUI biometric pipeline, a successful fingerprint
# match for the lock screen always logs one clean line from
# BiometricStatusRepositoryImpl, e.g.:
#
#   authenticationState updated: Succeeded(biometricSourceType=FINGERPRINT,
#   isStrongBiometric=true, requestReason=DeviceEntryAuthentication, userId=0)
#
# Matching on both FINGERPRINT and DeviceEntryAuthentication (not just
# "Succeeded") is what excludes face unlock and any in-app fingerprint
# prompts (banking apps, password managers, etc), so only actual
# lock-screen fingerprint unlocks are reported.

set -eu

LOGFILE="$HOME/fingerprint_unlocks.log"
PATTERN='authenticationState updated: Succeeded\(biometricSourceType=FINGERPRINT.*DeviceEntryAuthentication'

if [ "${1:-}" ]; then
    # Replay mode: parse an already-captured log file
    SOURCE_CMD=(cat "$1")
else
    # Live mode: stream straight from the device via adb
    if ! adb get-state >/dev/null 2>&1; then
        echo "No adb device connected (check 'adb devices')." >&2
        exit 1
    fi
    echo "Watching for fingerprint unlocks -- Ctrl+C to stop."
    echo "Events are appended to $LOGFILE"
    echo
    # -T 1   : start the stream at "now" instead of dumping old history
    # -s ...:D : device only sends this tag (Debug+), saving bandwidth
    SOURCE_CMD=(adb shell logcat -v threadtime -T 1 -s BiometricStatusRepositoryImpl:D)
fi

"${SOURCE_CMD[@]}" | grep --line-buffered -E "$PATTERN" | while read -r ts_date ts_time _rest; do
    echo "[$ts_date $ts_time] fingerprint unlock" | tee -a "$LOGFILE"
    # Uncomment for a push notification (needs: pkg install termux-api)
    # termux-notification --title "Unlocked" --content "$ts_date $ts_time"
done
