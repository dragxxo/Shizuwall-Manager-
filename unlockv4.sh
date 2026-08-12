#!/data/data/com.termux/files/usr/bin/bash
#
# shizuwall_manager.sh
#
# ShizuWall state:
#   - ON  -> password/PIN or Face unlock
#   - OFF -> screen turns off (+ switches profile to "Lockdown")
#   - NO  -> fingerprint unlock
#
# Uses RISH + Shizuku instead of a persistent ADB connection.

set -u

LOGFILE="$HOME/shizuwall_manager.log"
RISH="$HOME/rish"

fingerprint_unlock=0
shizuwall_state="unknown"
shizuwall_profile="unknown"


# ------------------------------------------------
# CHECK RISH
# ------------------------------------------------

if [ ! -x "$RISH" ]; then
    echo "ERROR: RISH not found or not executable:"
    echo "$RISH"
    echo
    echo "Make sure ~/rish exists and run:"
    echo "chmod +x ~/rish"
    exit 1
fi


# ------------------------------------------------
# SHIZUWALL CONTROL (on/off)
# ------------------------------------------------

set_shizuwall() {
    local state="$1"

    if "$RISH" -c \
        "am broadcast \
        -a shizuwall.CONTROL \
        -n com.arslan.shizuwall/.receivers.FirewallControlReceiver \
        --ez state $state" >/dev/null 2>&1; then

        shizuwall_state="$state"
        return 0

    else

        echo "[$(date '+%F %T')] ERROR: Failed to set ShizuWall -> $state" \
            | tee -a "$LOGFILE"

        return 1
    fi
}


# ------------------------------------------------
# SHIZUWALL PROFILE CONTROL
# ------------------------------------------------

set_shizuwall_profile() {
    local profile="$1"

    if "$RISH" -c \
        "am broadcast \
        -a shizuwall.PROFILE \
        -n com.arslan.shizuwall/.receivers.ProfileControlReceiver \
        --es profile \"$profile\"" >/dev/null 2>&1; then

        shizuwall_profile="$profile"
        return 0

    else

        echo "[$(date '+%F %T')] ERROR: Failed to set ShizuWall profile -> $profile" \
            | tee -a "$LOGFILE"

        return 1
    fi
}


# ------------------------------------------------
# TEST SHIZUKU / RISH
# ------------------------------------------------

if ! "$RISH" -c 'echo RISH_OK' >/dev/null 2>&1; then

    echo "ERROR: Cannot communicate with Shizuku through RISH." >&2
    echo "Make sure Shizuku is running." >&2
    exit 1

fi


echo "=================================================="
echo "       ShizuWall Dual-State Manager"
echo "=================================================="
echo "ON  : Password/PIN + Face"
echo "OFF : Screen off -> profile \"Lockdown\""
echo "IGN : Fingerprint"
echo "MODE: RISH + Shizuku"
echo "Logs: $LOGFILE"
echo "=================================================="
echo


# ------------------------------------------------
# LOGCAT
# ------------------------------------------------

"$RISH" -c \
'logcat -v threadtime -T 1 \
-s \
BiometricStatusRepositoryImpl:D \
KeyguardViewMediator:D \
PowerGroup:I \
PowerManagerService:I' |
while IFS= read -r line; do


    # ------------------------------------------------
    # SCREEN OFF
    # ------------------------------------------------

    if [[ "$line" == *"PowerGroup: Powering off display group"* ]] ||
       [[ "$line" == *"PowerManagerService: Going to sleep"* ]]; then

        fingerprint_unlock=0

        echo "[$(date '+%F %T')] SCREEN OFF -> ShizuWall OFF + Lockdown profile" \
            | tee -a "$LOGFILE"

        set_shizuwall false
        set_shizuwall_profile "Lockdown"
        continue
    fi


    # ------------------------------------------------
    # FINGERPRINT SUCCESS
    # ------------------------------------------------

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

