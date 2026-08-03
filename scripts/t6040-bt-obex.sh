#!/bin/sh
# Bring up BlueZ OBEX object push on the T6040 and report state.
#
# Runs ON the M4 (SD root or a RAM root that has bluez + bluez-obexd + dbus).
# CJ's acceptance test for "Bluetooth working" is an OBEX file transfer between
# the M1 host and this machine in either direction (2026-08-04).
#
# The detail that breaks naive attempts: obexd is a SESSION-bus service, not a
# system-bus one. bluetoothd lives on the system bus; obexd and obexctl must
# share a session bus, or obexctl reports "org.bluez.obex not provided".
#
# Usage:
#   t6040-bt-obex.sh up                    # start dbus/bluetoothd/obexd, report
#   t6040-bt-obex.sh receive               # up + discoverable + auto-accept inbox
#   t6040-bt-obex.sh pair <MAC>            # pair/trust a remote controller
#   t6040-bt-obex.sh send <MAC> <file>     # push one file to a paired device
#   t6040-bt-obex.sh status                # report only, change nothing
#
# No PMU, charger, NVRAM, firmware, SMC, or SPMI operation. rfkill unblock of
# the Bluetooth soft-block is a normal driver operation, not a hardware policy
# write.
set -u

INBOX=${T6040_OBEX_INBOX:-/root/obex-inbox}
SESSION_ADDR_FILE=/run/t6040-obex-session-bus
# obexd's stderr is the only place an option or plugin error appears. Keeping it
# out of /dev/null is what makes a failure diagnosable from the rig transcript
# instead of looking like a silent hang.
OBEXD_LOG=${T6040_OBEX_LOG:-/tmp/t6040-obexd.log}
OBEXD=
for c in /usr/libexec/bluetooth/obexd /usr/lib/bluetooth/obexd /usr/libexec/obexd; do
    [ -x "$c" ] && OBEXD=$c && break
done

say() { echo "== $*"; }
die() { echo "STOP: $*" >&2; exit 1; }

need() {
    command -v "$1" >/dev/null 2>&1 || die "$1 is missing; apk add bluez bluez-obexd dbus"
}

start_system_bus() {
    mkdir -p /run/dbus /var/lib/bluetooth /var/lib/dbus
    # The image ships NO /etc/machine-id on purpose (a baked-in random UUID made
    # the build non-reproducible), so create a volatile one before dbus starts.
    if [ ! -s /etc/machine-id ]; then
        dbus-uuidgen --ensure=/etc/machine-id 2>/dev/null || \
            dbus-uuidgen > /etc/machine-id 2>/dev/null || \
            die "cannot create a machine-id"
    fi
    [ -s /var/lib/dbus/machine-id ] || \
        cp /etc/machine-id /var/lib/dbus/machine-id 2>/dev/null || true
    if [ ! -S /run/dbus/system_bus_socket ]; then
        dbus-daemon --system --fork 2>/dev/null || die "cannot start the system bus"
    fi
}

start_bluetoothd() {
    if ! pidof bluetoothd >/dev/null 2>&1; then
        # -C keeps the deprecated compat interfaces available for hciconfig.
        bluetoothd -C 2>/dev/null &
        n=0
        while [ "$n" -lt 20 ] && ! pidof bluetoothd >/dev/null 2>&1; do
            n=$((n + 1)); sleep 1
        done
    fi
    pidof bluetoothd >/dev/null 2>&1 || die "bluetoothd did not start"
    rfkill unblock bluetooth 2>/dev/null || true
    bluetoothctl power on >/dev/null 2>&1 || true
}

# One session bus per boot, address cached so every later invocation joins the
# same bus as the running obexd.
start_session_bus() {
    if [ -f "$SESSION_ADDR_FILE" ]; then
        DBUS_SESSION_BUS_ADDRESS=$(cat "$SESSION_ADDR_FILE")
        export DBUS_SESSION_BUS_ADDRESS
        # Prove the cached bus is still alive before reusing it.
        if dbus-send --session --dest=org.freedesktop.DBus --print-reply \
            /org/freedesktop/DBus org.freedesktop.DBus.ListNames \
            >/dev/null 2>&1; then
            return 0
        fi
        rm -f "$SESSION_ADDR_FILE"
    fi
    addr=$(dbus-daemon --session --fork --print-address 2>/dev/null) || \
        die "cannot start a session bus"
    printf '%s' "$addr" > "$SESSION_ADDR_FILE"
    DBUS_SESSION_BUS_ADDRESS=$addr
    export DBUS_SESSION_BUS_ADDRESS
}

# The session bus ships org.bluez.obex.service with `Exec=obexd -n` -- no
# --root and no --auto-accept. If that activation wins the race, an obexd is
# running and owns the bus name, but it roots transfers at $XDG_CACHE_HOME and
# registers no OBEX agent, so an inbound push is REJECTED. A bare `pidof obexd`
# guard would silently accept that instance and report success, so verify the
# live process's actual flags and replace it if they are wrong.
obexd_flags_ok() {
    pid=$(pidof obexd 2>/dev/null | awk '{print $1}')
    [ -n "$pid" ] || return 1
    cl=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null)
    case "$cl" in
        *"--root=$INBOX"*) ;;
        *) return 1 ;;
    esac
    case "$cl" in
        *--auto-accept*) return 0 ;;
        *) return 1 ;;
    esac
}

start_obexd() {
    [ -n "$OBEXD" ] || die "obexd binary not found; apk add bluez-obexd"
    mkdir -p "$INBOX"
    if obexd_flags_ok; then
        return 0
    fi
    if pidof obexd >/dev/null 2>&1; then
        echo "note: replacing an obexd started without --root/--auto-accept" \
             "(bus activation uses Exec=obexd -n)"
        kill $(pidof obexd) 2>/dev/null
        n=0
        while [ "$n" -lt 10 ] && pidof obexd >/dev/null 2>&1; do
            n=$((n + 1)); sleep 1
        done
    fi
    # --auto-accept makes an inbound push land without an agent prompt; --root
    # bounds where a remote device may write. Only the long options this build
    # actually implements are used: debug noplugin nodetach root root-setup
    # symlinks auto-accept system-bus version. There is NO --no-input; passing
    # one is fatal because obexd does not ignore unknown GOptions.
    "$OBEXD" --root="$INBOX" --auto-accept >>"$OBEXD_LOG" 2>&1 &
    n=0
    while [ "$n" -lt 15 ] && ! pidof obexd >/dev/null 2>&1; do
        n=$((n + 1)); sleep 1
    done
    pidof obexd >/dev/null 2>&1 || {
        echo "--- obexd log ---"; tail -20 "$OBEXD_LOG" 2>/dev/null
        die "obexd did not start (see $OBEXD_LOG)"
    }
    obexd_flags_ok || {
        echo "--- obexd log ---"; tail -20 "$OBEXD_LOG" 2>/dev/null
        die "obexd is running without the required --root/--auto-accept flags"
    }
}

report() {
    say "controller"
    bluetoothctl list 2>/dev/null
    bluetoothctl show 2>/dev/null | \
        grep -Ei 'Controller|Name|Powered|Discoverable|Pairable|Alive|UUID: OBEX'
    say "hci"
    hciconfig -a 2>/dev/null | head -12 || echo "(hciconfig unavailable)"
    say "daemons"
    printf 'bluetoothd: %s\n' "$(pidof bluetoothd 2>/dev/null || echo ABSENT)"
    printf 'obexd:      %s\n' "$(pidof obexd 2>/dev/null || echo ABSENT)"
    printf 'session:    %s\n' "${DBUS_SESSION_BUS_ADDRESS:-UNSET}"
    say "obex service on the session bus"
    if dbus-send --session --dest=org.freedesktop.DBus --print-reply \
        /org/freedesktop/DBus org.freedesktop.DBus.ListNames 2>/dev/null | \
        grep -q 'org.bluez.obex'; then
        echo "org.bluez.obex PRESENT"
    else
        echo "org.bluez.obex ABSENT (obexd not on this session bus)"
    fi
    # Bus-name presence is NOT sufficient: a bus-activated obexd owns the name
    # but rejects pushes. Report the live flags, which is the property that
    # actually decides whether a transfer can land.
    say "obexd flags (must show --root and --auto-accept)"
    pid=$(pidof obexd 2>/dev/null | awk '{print $1}')
    if [ -n "$pid" ]; then
        tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null; echo
        if obexd_flags_ok; then
            echo "OBEXD_FLAGS_OK"
        else
            echo "OBEXD_FLAGS_WRONG — inbound pushes would be REJECTED"
        fi
    else
        echo "(no obexd running)"
    fi
    [ -s "$OBEXD_LOG" ] && { say "obexd log tail"; tail -10 "$OBEXD_LOG"; }
    say "inbox"
    printf '%s\n' "$INBOX"
    ls -l "$INBOX" 2>/dev/null || echo "(absent)"
}

cmd=${1:-status}
case "$cmd" in
status)
    need bluetoothctl
    [ -f "$SESSION_ADDR_FILE" ] && {
        DBUS_SESSION_BUS_ADDRESS=$(cat "$SESSION_ADDR_FILE")
        export DBUS_SESSION_BUS_ADDRESS
    }
    report
    ;;
up)
    need bluetoothctl; need dbus-daemon
    start_system_bus; start_bluetoothd; start_session_bus; start_obexd
    report
    echo "T6040_OBEX_UP"
    ;;
receive)
    need bluetoothctl; need dbus-daemon
    start_system_bus; start_bluetoothd; start_session_bus; start_obexd
    bluetoothctl --timeout 5 pairable on >/dev/null 2>&1 || true
    bluetoothctl --timeout 5 discoverable-timeout 0 >/dev/null 2>&1 || true
    bluetoothctl --timeout 5 discoverable on >/dev/null 2>&1 || true
    # NoInputNoOutput takes the JustWorks path so pairing needs no local input.
    (bluetoothctl --agent=NoInputNoOutput --timeout 600 >/dev/null 2>&1 &) || true
    report
    say "ready to receive"
    echo "Send from macOS: Bluetooth File Exchange, or"
    echo "  /usr/bin/open -a 'Bluetooth File Exchange' <file>"
    echo "Files land in $INBOX"
    echo "T6040_OBEX_RECEIVE_READY"
    ;;
pair)
    mac=${2:?usage: t6040-bt-obex.sh pair <MAC>}
    need bluetoothctl
    start_system_bus; start_bluetoothd
    bluetoothctl --timeout 10 scan on >/dev/null 2>&1 &
    sleep 8
    bluetoothctl --agent=NoInputNoOutput --timeout 30 pair "$mac"
    rc=$?
    bluetoothctl --timeout 5 trust "$mac"
    bluetoothctl --timeout 5 info "$mac" | \
        grep -Ei 'Name|Paired|Trusted|Connected|UUID: OBEX|UUID: Obex'
    [ "$rc" -eq 0 ] && echo "T6040_OBEX_PAIRED mac=$mac" || \
        echo "T6040_OBEX_PAIR_FAILED mac=$mac rc=$rc"
    exit "$rc"
    ;;
send)
    mac=${2:?usage: t6040-bt-obex.sh send <MAC> <file>}
    file=${3:?usage: t6040-bt-obex.sh send <MAC> <file>}
    [ -f "$file" ] || die "$file is not a file"
    need bluetoothctl; need dbus-daemon
    # Alpine's bluez ships no obexctl, so drive the OBEX client over D-Bus.
    # gdbus (from glib) is used rather than dbus-send because it accepts
    # variant syntax for the a{sv} session dictionary.
    need gdbus
    start_system_bus; start_bluetoothd; start_session_bus; start_obexd
    say "sha256 of the source file"
    sha256sum "$file"
    say "creating an OPP session to $mac"
    sess=$(gdbus call --session --dest org.bluez.obex \
        --object-path /org/bluez/obex \
        --method org.bluez.obex.Client1.CreateSession \
        "$mac" "{'Target': <'opp'>}" 2>&1) || die "CreateSession failed: $sess"
    # gdbus prints ("/org/bluez/obex/client/session0",)
    sess=$(printf '%s' "$sess" | sed -n "s/.*'\(\/org\/bluez\/obex[^']*\)'.*/\1/p")
    [ -n "$sess" ] || die "could not parse the session path"
    echo "session: $sess"
    say "pushing $file"
    xfer=$(gdbus call --session --dest org.bluez.obex --object-path "$sess" \
        --method org.bluez.obex.ObjectPush1.SendFile \
        "$file" 2>&1) || die "SendFile failed: $xfer"
    echo "$xfer"
    xpath=$(printf '%s' "$xfer" | \
        sed -n "s/.*'\(\/org\/bluez\/obex[^']*\)'.*/\1/p")
    say "transfer status"
    n=0; status=unknown
    while [ "$n" -lt 60 ]; do
        n=$((n + 1))
        status=$(gdbus call --session --dest org.bluez.obex \
            --object-path "$xpath" \
            --method org.freedesktop.DBus.Properties.Get \
            org.bluez.obex.Transfer1 Status 2>/dev/null | \
            sed -n "s/.*'\([a-z]*\)'.*/\1/p")
        [ -n "$status" ] || status=gone
        case "$status" in
            complete|error|gone) break ;;
        esac
        sleep 1
    done
    echo "final status: $status"
    gdbus call --session --dest org.bluez.obex --object-path "$sess" \
        --method org.bluez.obex.Client1.RemoveSession "$sess" >/dev/null 2>&1 || \
    gdbus call --session --dest org.bluez.obex \
        --object-path /org/bluez/obex \
        --method org.bluez.obex.Client1.RemoveSession "$sess" >/dev/null 2>&1 || true
    if [ "$status" = complete ]; then
        echo "T6040_OBEX_SEND_COMPLETE mac=$mac file=$file"
        exit 0
    fi
    echo "T6040_OBEX_SEND_FAILED mac=$mac file=$file status=$status"
    exit 1
    ;;
*)
    die "unknown command: $cmd (status|up|receive|pair|send)"
    ;;
esac
