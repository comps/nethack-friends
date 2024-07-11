#!/bin/bash

# directory with the 'nethack' binary and other supporting files
#NETHACK_DISTRIB=/usr/games/nethack
NETHACK_DISTRIB=/usr/local/games/nethack_light_blue

# this is where all data will be stored - needs r/w access by the current user
BASE_DIR=$HOME

# keep away from valid unix UIDs, the game has some weird logic tied to getuid()
# like querying the user's password - non-existent UIDs will just make that
# ancient code silently fail without visible side-effects
FIRST_PLAYER_UID=2000

PLAYER_DIRS=$BASE_DIR/players
NETHACK_PLAYGROUND=$BASE_DIR/playground
NETHACKRC_SKEL=$BASE_DIR/nethackrc.skel

# directory with helper programs you should have compiled; ideally locate this
# away from BASE_DIR (as BIN_DIR is read-only), but BASE_DIR works ok as default
BIN_DIR=$BASE_DIR/bin

SECURE_EDITOR=(nano --syntax sh --restricted)


#
# UTILITY
#

function error {
    echo "error: $1" >&2
    local line
    for line in "${@:2}"; do
        echo "       $line"
    done
}

function fatal {
    error "$@"
    exit 1
}

function find_ld_so {
    local path
    # first path found
    read -r path < <(
        command -v /usr/bin/ld.so || \
        command -v /bin/ld.so || \
        command -v /usr/lib64/ld-linux*.so*
    ) || return 1
    echo "$path"
}


#
# PLAYER ACCOUNT / PROFILE
#

function gen_player_uid {
    local fd file=$BASE_DIR/player_uid_serial

    touch "$file"
    exec {fd}<"$BASE_DIR/player_uid_serial"
    flock $fd

    local current
    read -u $fd current
    if [[ -z $current ]]; then
        current=$(( FIRST_PLAYER_UID - 1 ))
    elif [[ ! $current =~ ^[0-9]+$ ]]; then
        fatal "player uid serial file contains non-number"
    fi

    (( current++ ))

    echo "$current" > "$file"  # truncate
    exec {fd}>&-

    echo "$current"
}

function player_exists {
    local name=$1
    [[ -e $PLAYER_DIRS/$name ]]
}

function create_player {
    local name=$1 uid=$(gen_player_uid)
    local dir=$PLAYER_DIRS/$name
    mkdir -p "$dir"
    cp -f "$NETHACKRC_SKEL" "$dir/.nethackrc"
    echo "$uid" > "$dir/uid"
}

function login_player {
    local name
    echo -n "Username: "
    read -r -e name
    if [[ -z $name ]]; then
        fatal "username cannot be empty"
    elif [[ ${#name} -gt 30 ]]; then
        fatal "username cannot be >30 characters long"
    elif [[ ! $name =~ ^[a-zA-Z0-9_]+$ ]]; then
        fatal "username can only contain a-z A-Z 0-9 and underscore"
    elif [[ $name =~ ^[[:space:]]*$ ]]; then
        fatal "username cannot consist only of spaces"
    fi

    if player_exists "$name"; then
        echo "Using existing user '$name'."
        show_menu "$name"
    else
        echo -ne "\nUser '$name' does not exist, create it? [y/n]: "
        local reply
        read -r -e reply
        if [[ $reply == y ]]; then
            echo "Creating user '$name'."
            create_player "$name"
            show_menu "$name"
        else
            echo "Okay, aborting."
        fi
    fi
}


#
# PLAYGROUND INIT
#

function init_playground {
    local ground=$NETHACK_PLAYGROUND
    [[ -e $ground ]] && return 0
    mkdir -p "$ground"

    mkdir "$ground/save"
    touch "$ground/logfile"
    touch "$ground/xlogfile"

    # used by nethack for locking when updating files in playground
    touch "$ground/perm"

    # write our own syscf file
    {
        echo WIZARDS=
        echo EXPLORERS=
        echo GENERICUSERS=
        echo MAXPLAYERS=0
        echo CHECK_SAVE_UID=0
        echo PANICTRACE_GDB=0
        echo PANICTRACE_LIBC=0
    } > "$ground/sysconf"

    # link other files from distrib
    local d=$NETHACK_DISTRIB
    ln -s "$d/nethack" "$d/recover" "$d/symbols" "$d/nhdat" "$ground/."
}

#
# MAIN MENU
#

function show_menu {
    local name=$1
    local dir=$PLAYER_DIRS/$name
    local uid=$(<"$dir/uid")

    echo
    echo "----------------------------------------"

    local options=(
        "Launch NetHack"
        "Edit .nethackrc"
        "Kill the NetHack process (if hung)"
        "Recover a save (after kill/disconnect)"
        "Wipe this account (ragequit)"
        "Quit (or Ctrl-D)"
    )
    local opt REPLY COLUMNS=80 PS3="Choose one: "
    select opt in "${options[@]}"; do
        case "$opt" in
            "Launch NetHack")
                run_nethack "$name" "$dir" "$uid"
                ;;
            "Edit .nethackrc")
                edit_nethackrc "$name" "$dir" "$uid"
                ;;
            "Kill the NetHack process (if hung)")
                kill_nethack "$name" "$dir" "$uid"
                ;;
            "Recover a save (after kill/disconnect)")
                recover_save "$name" "$dir" "$uid"
                ;;
            "Wipe this account (ragequit)")
                wipe_account "$name" "$dir" "$uid"
                ;;
            "Quit (or Ctrl-D)")
                break
                ;;
            *)
                # provide a nice shortcut
                if [[ $REPLY == q || $REPLY == quit ]]; then
                    break
                else
                    error "invalid option $REPLY"
                fi
                ;;
        esac
    done
}

function run_nethack {
    local name=$1 dir=$2 uid=$3

    if grep -z -q "^NETHACK_FRIENDS_UID=$uid$" /proc/*/environ 2>/dev/null; then
        error "game already running, try killing it?"
        return 0
    fi

    local bin_dir_abs=$(realpath "$BIN_DIR")
    local nethack_abs=$(realpath "$NETHACK_DISTRIB/nethack")

    local ld_so
    if ! ld_so=$(find_ld_so); then
        fatal "could not find ld.so (or ld-linux loader) on your OS"
    fi

    NETHACK_FRIENDS_UID=$uid \
    NETHACKDIR=$NETHACK_PLAYGROUND \
    USER=$name \
    LANG=en_US.UTF-8 \
    HOME=$dir \
    SHELL=/bin/true \
    MAIL=/dev/null \
    MAILREADER=/bin/true \
    LD_PRELOAD=$bin_dir_abs/fake_uid.so \
    "$BIN_DIR/cp437" "$ld_so" "$nethack_abs"
}

function kill_nethack {
    local name=$1 dir=$2 uid=$3

    # TODO: search only for pids with cwd->/home/nethack/playground,
    #       don't kill cp437 and ld.so processes
    local playground_abs=$(realpath "$NETHACK_PLAYGROUND")

    local env_path pid cwd found=
    while read -r env_path; do
        # extract pid
        [[ $env_path =~ ^/proc/([0-9]+)/environ$ ]] || continue
        pid=${BASH_REMATCH[1]}

        # skip cp437 and other parent processes
        cwd=$(readlink /proc/$pid/cwd)
        [[ $cwd == $playground_abs ]] || continue

        echo "Killing PID $pid"
        kill -9 "$pid"
        found=1
    done < <(grep -z -l "^NETHACK_FRIENDS_UID=$uid$" /proc/*/environ 2>/dev/null || true)

    if [[ -z $found ]]; then
        echo "No processes found for '$name'."
    fi
}

function recover_save {
    local name=$1 dir=$2 uid=$3

    "$NETHACK_PLAYGROUND/recover" -d "$NETHACK_PLAYGROUND" "$uid$name" || true
}

function edit_nethackrc {
    local name=$1 dir=$2 uid=$3
    "${SECURE_EDITOR[@]}" "$dir/.nethackrc"
}

function wipe_account {
    local name=$1 dir=$2 uid=$3

    # just to double check for any possible bugs and avoid rm -rf $PLAYER_DIRS
    if [[ -z $name ]]; then
        fatal "player name somehow empty - pls report this as a bug"
    fi

    echo -ne \
        "\nThis will permanently wipe all saves and config data" \
        "\nfor user '$name'." \
        "\n\nTo confirm, type this name: "
    local reply
    read -r -e reply

    if [[ $reply == $name ]]; then
        echo "Killing a possibly running instance."
        kill_nethack "$name" "$dir" "$uid"
        echo "Wiping '$name'."
        rm -rf "$dir"
        rm -f "$NETHACK_PLAYGROUND/save/$uid$name.gz"
        rm -f "$NETHACK_PLAYGROUND/$uid$name."[0-9]*
        echo "Good bye!"
        exit 0
    else
        echo "Aborting wipe."
    fi
}


#
# MAIN
#

set -e

init_playground
login_player

# vim: sts=4 sw=4 et :
