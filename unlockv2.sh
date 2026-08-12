#!/data/data/com.termux/files/usr/bin/bash
#
# shizuwall_manager.sh
#
# ShizuWall state:
#   - ON  -> password/PIN or Face unlock
#   - OFF -> screen turns off
#   - NO  -> fingerprint unlock
#
# Uses the actual SystemUI events found in unlockdata2.log.

set -u

LOGFILE="$HOME/shizuwall_manager.log"

fingerprint_unlock=0
shizuwall_state="unknown"

set_shizuwall() {
    local state="$1"

    if adb shell am broadcast \
        -a shizuwall.CONTROL \
        -n com.arslan.shizuwall/.receivers.FirewallControlReceiver \
        --ez state "$state" >/dev/null 2>&1; then

        shizuwall_state="$state"
        return 0
    else
        echo "[$(date '+%F %T')] ERROR: Failed to set ShizuWall -> $state" \
            | tee -a "$LOGFILE"
        return 1
    fi
}

if ! adb get-state >/dev/null 2>&1; then
    echo "No adb device connected (check 'adb devices')." >&2
    exit 1
fi

echo "=================================================="
echo "       ShizuWall Dual-State Manager"
echo "=================================================="
echo "ON  : Password/PIN + Face"
echo "OFF : Screen off"
echo "IGN : Fingerprint"
echo "Logs: $LOGFILE"
echo "=================================================="
echo

# Only listen to the relevant Android components.
#
# BiometricStatusRepositoryImpl -> fingerprint / face success
# KeyguardViewMediator          -> actual keyguard dismissal
# PowerGroup / PowerManagerService -> screen off

adb shell logcat -v threadtime -T 1 \
    -s \
    BiometricStatusRepositoryImpl:D \
    KeyguardViewMediator:D \
    PowerGroup:I \
    PowerManagerService:I |
while IFS= read -r line; do

    # ------------------------------------------------
    # SCREEN OFF
    # ------------------------------------------------

    if [[ "$line" == *"PowerGroup: Powering off display group"* ]] ||
       [[ "$line" == *"PowerManagerService: Going to sleep"* ]]; then

        fingerprint_unlock=0

        echo "[$(date '+%F %T')] SCREEN OFF -> ShizuWall OFF" \
            | tee -a "$LOGFILE"

        set_shizuwall false
        continue
    fi


    # ------------------------------------------------
    # FINGERPRINT SUCCESS
    # ------------------------------------------------
    #
    # Exact event from your log:
    #
    # authenticationState updated:
    # Succeeded(biometricSourceType=FINGERPRINT,
    # requestReason=DeviceEntryAuthentication...)

    if [[ "$line" == *"authenticationState updated: Succeeded(biometricSourceType=FINGERPRINT"* ]] &&
       [[ "$line" == *"requestReason=DeviceEntryAuthentication"* ]]; then

        fingerprint_unlock=1

        echo "[$(date '+%F %T')] FINGERPRINT unlock detected -> ShizuWall remains OFF" \
            | tee -a "$LOGFILE"

        continue
    fi


    # ------------------------------------------------
    # FACE SUCCESS
    # ------------------------------------------------
    #
    # Exact event from your log:
    #
    # Succeeded(biometricSourceType=FACE,
    # requestReason=DeviceEntryAuthentication...)

    if [[ "$line" == *"authenticationState updated: Succeeded(biometricSourceType=FACE"* ]] &&
       [[ "$line" == *"requestReason=DeviceEntryAuthentication"* ]]; then

        fingerprint_unlock=0

        echo "[$(date '+%F %T')] FACE unlock detected -> ShizuWall ON" \
            | tee -a "$LOGFILE"

        set_shizuwall true
        continue
    fi


    # ------------------------------------------------
    # KEYGUARD GONE
    # ------------------------------------------------
    #
    # Password/PIN reaches this event without a
    # preceding fingerprint success.
    #
    # Fingerprint also reaches this event, therefore
    # fingerprint_unlock is checked first.

    if [[ "$line" == *"KeyguardViewMediator: keyguardGone"* ]]; then

        if [ "$fingerprint_unlock" -eq 1 ]; then

            echo "[$(date '+%F %T')] keyguardGone after FINGERPRINT -> ShizuWall stays OFF" \
                | tee -a "$LOGFILE"

            fingerprint_unlock=0

        else

            echo "[$(date '+%F %T')] keyguardGone -> Password/PIN unlock -> ShizuWall ON" \
                | tee -a "$LOGFILE"

            set_shizuwall true
        fi

        continue
    fi

done
