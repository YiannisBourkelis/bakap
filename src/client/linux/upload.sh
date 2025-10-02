#!/usr/bin/env bash
# upload.sh - simple client uploader for bakap

set -euo pipefail

usage() {
        cat <<EOF
Usage: $0 -l <local-path> -u <username> -p <password> -s <server> [OPTIONS]

This script uploads a file or directory to the bakap server.
It prefers lftp (shows progress). If lftp is not installed it falls back to sshpass+sftp.

Required arguments:
    -l, --local-path PATH    Local file or directory to upload
    -u, --username USER      Remote username
    -p, --password PASS      Password for the user
    -s, --server HOST        SFTP server hostname or IP address

Optional arguments:
    -d, --dest-path PATH     Destination path relative to user's chroot (default: uploads/)
    -f, --fingerprint FP     Expected host fingerprint (optional)
    --debug                  Run lftp with debugging enabled
    --force                  Force upload: overwrite existing remote files
    -h, --help               Show this help message

Examples:
    $0 -l /path/to/file.sql.gz -u test2 -p 'P@ssw0rd' -s 202.61.225.34
    $0 -l /path/to/folder -u test2 -p 'P@ssw0rd' -s 192.168.1.100 -d uploads/backups/ -f SHA256:abcdef... --force

Notes:
- The password will appear in the process list while the command runs when using sshpass. Prefer SSH keys.
- The destination path is relative to the user's chroot (most installs use uploads/).
- If provided, expected-host-fingerprint will be compared to the server's SSH key fingerprint before adding it to your known_hosts.
EOF
}

# Initialize variables
LOCAL_PATH=""
USERNAME=""
PASSWORD=""
DEST_PATH="uploads/"
EXPECTED_FP=""
SERVER=""
DEBUG=0
FORCE=0

# Parse command line options
while [[ $# -gt 0 ]]; do
    case $1 in
        -l|--local-path)
            LOCAL_PATH="$2"
            shift 2
            ;;
        -u|--username)
            USERNAME="$2"
            shift 2
            ;;
        -p|--password)
            PASSWORD="$2"
            shift 2
            ;;
        -d|--dest-path)
            DEST_PATH="$2"
            shift 2
            ;;
        -f|--fingerprint)
            EXPECTED_FP="$2"
            shift 2
            ;;
        -s|--server)
            SERVER="$2"
            shift 2
            ;;
        --debug)
            DEBUG=1
            shift
            ;;
        --force)
            FORCE=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage
            exit 2
            ;;
    esac
done

# Check required parameters
if [[ -z "$LOCAL_PATH" || -z "$USERNAME" || -z "$PASSWORD" || -z "$SERVER" ]]; then
    echo "Error: Missing required arguments" >&2
    usage
    exit 2
fi

# Normalize destination path: remove leading slash so paths are always relative
# to the user's chroot (some clients/servers treat leading slash as absolute
# and that can cause permission failures). Also ensure non-empty.
DEST_PATH="${DEST_PATH#/}"
if [ -z "$DEST_PATH" ]; then
    DEST_PATH="uploads"
fi

# If debugging enabled, prepare a debug output file
if [ "$DEBUG" -eq 1 ]; then
    DEBUG_OUT="/tmp/bakap-upload-debug-$(date +%s).log"
    echo "Debug mode: raw lftp output will be saved to $DEBUG_OUT"
    : >"$DEBUG_OUT" || true
fi

# Mirror options (add --overwrite when forced)
MIRROR_OPTS="--verbose --continue --parallel=2"
if [ "$FORCE" -eq 1 ]; then
    MIRROR_OPTS="$MIRROR_OPTS --overwrite"
fi

if [ ! -e "$LOCAL_PATH" ]; then
    echo "Local path does not exist: $LOCAL_PATH" >&2
    exit 3
fi

echo "Uploading '$LOCAL_PATH' as user '$USERNAME' to $SERVER:$DEST_PATH"

# Ensure ~/.ssh exists for current user and known_hosts is present
SSH_DIR="$HOME/.ssh"
mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR" || true
KNOWN_HOSTS="$SSH_DIR/known_hosts"
touch "$KNOWN_HOSTS" || true
chmod 600 "$KNOWN_HOSTS" || true

# Helper: ensure server host key is in known_hosts. If EXPECTED_FP is provided, compare.
ensure_host_key() {
    # If host already in known_hosts, nothing to do
    if ssh-keygen -F "$SERVER" -f "$KNOWN_HOSTS" >/dev/null 2>&1; then
        return 0
    fi

    # Fetch host keys
    echo "Fetching host keys for $SERVER..."
    tmp=$(mktemp)
    ssh-keyscan -t rsa,ecdsa,ed25519 "$SERVER" > "$tmp" 2>/dev/null || true
    if [ ! -s "$tmp" ]; then
        echo "Failed to fetch host keys for $SERVER" >&2
        rm -f "$tmp"
        return 1
    fi

    if [ -n "$EXPECTED_FP" ]; then
        # compute fingerprint of fetched keys and compare
        match=0
        while read -r line; do
            # write line to a temp key file for fingerprinting
            keyfile=$(mktemp)
            echo "$line" > "$keyfile"
            fp=$(ssh-keygen -lf "$keyfile" 2>/dev/null | awk '{print $2}') || fp=""
            rm -f "$keyfile"
            if [ "$fp" = "$EXPECTED_FP" ]; then
                match=1
                break
            fi
        done < "$tmp"
        if [ $match -ne 1 ]; then
            echo "Server host fingerprint did not match expected fingerprint: $EXPECTED_FP" >&2
            rm -f "$tmp"
            return 2
        fi
    fi

    # Append fetched keys to known_hosts
    cat "$tmp" >> "$KNOWN_HOSTS"
    rm -f "$tmp"
    echo "Added $SERVER host key to $KNOWN_HOSTS"
    return 0
}

# Try to ensure host key; non-fatal for now
ensure_host_key || true

# Prefer lftp if available (gives a nice progress bar and supports sftp protocol)
if command -v lftp >/dev/null 2>&1; then
    echo "Using lftp (shows progress)."

    # run lftp and filter out harmless mkdir Access failed lines while preserving exit code
    run_lftp() {
        local url="$1"; shift
        local cmds="$*"
        # We need to stream output live so progress bars show up. Use a pipeline
        # where lftp writes to stdout/stderr combined, optionally tee raw output
        # to the debug file, and sed filters harmless mkdir messages before
        # displaying to the user.
        set +e
        if [ "${DEBUG:-0}" -eq 1 ] && [ -n "${DEBUG_OUT:-}" ]; then
            # debug: tee raw output to DEBUG_OUT, then filter for terminal
            lftp -d -u "$USERNAME","$PASSWORD" "$url" -e "$cmds" 2>&1 | tee -a "$DEBUG_OUT" | sed -E '/^mkdir: Access failed:/d'
            rc=${PIPESTATUS[0]}
        else
            # normal: no tee, no -d, stream filtered output
            lftp -u "$USERNAME","$PASSWORD" "$url" -e "$cmds" 2>&1 | sed -E '/^mkdir: Access failed:/d'
            rc=${PIPESTATUS[0]}
        fi
        set -e
        return $rc
    }

    # helper: inspect remote path type. Sets REMOTE_TYPE to one of: missing, dir, file
    remote_path_type() {
        REMOTE_TYPE="missing"
        tmp=$(mktemp)
        # Try to cd into the path - if it succeeds, it's a directory
        if run_lftp sftp://$SERVER "cd \"$1\"; bye" >"$tmp" 2>&1; then
            REMOTE_TYPE="dir"
        else
            # Check if it exists as a file using cls
            run_lftp sftp://$SERVER "cls -l \"$1\"; bye" >"$tmp" 2>/dev/null || true
            if [ -s "$tmp" ]; then
                REMOTE_TYPE="file"
            fi
        fi
        if [ "$DEBUG" -eq 1 ]; then
            echo "DEBUG: remote_path_type('$1') = $REMOTE_TYPE (cd test)" >&2
            if [ -s "$tmp" ]; then
                echo "DEBUG: Test output:" >&2
                cat "$tmp" >&2
            fi
        fi
        rm -f "$tmp"
    }

    # lftp: for directories use mirror -R, for files use put
    if [ -d "$LOCAL_PATH" ]; then
        # Get absolute path of local directory to avoid any path resolution issues
        # Use -P to avoid resolving symlinks to keep the original basename
        LOCAL_ABS=$(cd "$(dirname "$LOCAL_PATH")" && pwd -P)/$(basename "$LOCAL_PATH")
        # Remove trailing slash if present
        LOCAL_ABS="${LOCAL_ABS%/}"
        LOCAL_PARENT=$(dirname "$LOCAL_ABS")
        BASENAME=$(basename "$LOCAL_ABS")
        
        if [ "$DEBUG" -eq 1 ]; then
            echo "DEBUG: LOCAL_PATH=$LOCAL_PATH" >&2
            echo "DEBUG: LOCAL_ABS=$LOCAL_ABS" >&2
            echo "DEBUG: LOCAL_PARENT=$LOCAL_PARENT" >&2
            echo "DEBUG: BASENAME=$BASENAME" >&2
            echo "DEBUG: DEST_PATH=$DEST_PATH" >&2
        fi
        
        # inspect remote path
        remote_path_type "$DEST_PATH"
        if [ "$REMOTE_TYPE" = "file" ]; then
            # remote path is a file; create a directory with the source dir name in its parent
            PARENT_DIR=$(dirname "$DEST_PATH")
            TARGET="$PARENT_DIR/$BASENAME"
            # ensure parent exists
            lftp -u "$USERNAME","$PASSWORD" sftp://$SERVER -e "mkdir -p \"$PARENT_DIR\"; bye" >/dev/null 2>&1 || true
            # Mirror directory contents into the target
            LFTP_CMD="lcd \"$LOCAL_ABS\"; cd \"$TARGET\"; mkdir -p .; mirror -R $MIRROR_OPTS . .; bye"
            if [ "$DEBUG" -eq 1 ]; then
                echo "DEBUG: LFTP_CMD=$LFTP_CMD" >&2
            fi
            run_lftp sftp://$SERVER "$LFTP_CMD"
        else
            # missing or dir -> ensure directory exists then mirror
            if [ "$REMOTE_TYPE" = "missing" ]; then
                run_lftp sftp://$SERVER "mkdir -p \"$DEST_PATH\"; bye" >/dev/null 2>&1 || true
            fi
            # Mirror directory contents into the destination
            # Use lcd to enter the source directory, then mirror its contents
            if [ "$DEBUG" -eq 1 ]; then
                echo "DEBUG: About to mirror - DEST_PATH='$DEST_PATH' BASENAME='$BASENAME'" >&2
                echo "DEBUG: REMOTE_TYPE='$REMOTE_TYPE'" >&2
            fi
            LFTP_CMD="lcd \"$LOCAL_ABS\"; cd \"$DEST_PATH\"; mirror -R $MIRROR_OPTS . .; bye"
            if [ "$DEBUG" -eq 1 ]; then
                echo "DEBUG: LFTP_CMD=$LFTP_CMD" >&2
            fi
            run_lftp sftp://$SERVER "$LFTP_CMD"
        fi
    else
        # single file upload: ensure remote dir exists and upload file
        # Get absolute path of local file to avoid any path resolution issues
        # Use -P to avoid resolving symlinks
        LOCAL_ABS=$(cd "$(dirname "$LOCAL_PATH")" && pwd -P)/$(basename "$LOCAL_PATH")
        LOCAL_PARENT=$(dirname "$LOCAL_ABS")
        BASENAME=$(basename "$LOCAL_ABS")
        
        if [ "$DEBUG" -eq 1 ]; then
            echo "DEBUG: LOCAL_PATH=$LOCAL_PATH" >&2
            echo "DEBUG: LOCAL_ABS=$LOCAL_ABS" >&2
            echo "DEBUG: LOCAL_PARENT=$LOCAL_PARENT" >&2
            echo "DEBUG: BASENAME=$BASENAME" >&2
            echo "DEBUG: DEST_PATH=$DEST_PATH" >&2
        fi
        
        REMOTE_DIR="$DEST_PATH"
        # inspect remote path
        remote_path_type "$REMOTE_DIR"
        if [ "$REMOTE_TYPE" = "file" ]; then
            # remote path is a file name; overwrite it
            if [ "$FORCE" -eq 1 ]; then
                # attempt to remove remote file first (ignore errors)
                run_lftp sftp://$SERVER "rm \"$REMOTE_DIR\"; bye" >/dev/null 2>&1 || true
            fi
            # Use lcd/cd approach for clarity
            LFTP_CMD="lcd \"$LOCAL_PARENT\"; cd \"$(dirname "$REMOTE_DIR")\"; put \"$BASENAME\"; bye"
            if [ "$DEBUG" -eq 1 ]; then
                echo "DEBUG: LFTP_CMD=$LFTP_CMD" >&2
            fi
            run_lftp sftp://$SERVER "$LFTP_CMD"
        else
            if [ "$REMOTE_TYPE" = "missing" ]; then
                run_lftp sftp://$SERVER "mkdir -p \"$REMOTE_DIR\"; bye" >/dev/null 2>&1 || true
            fi
            # Use lcd/cd approach for clarity
            LFTP_CMD="lcd \"$LOCAL_PARENT\"; cd \"$REMOTE_DIR\"; put \"$BASENAME\"; bye"
            if [ "$DEBUG" -eq 1 ]; then
                echo "DEBUG: LFTP_CMD=$LFTP_CMD" >&2
            fi
            run_lftp sftp://$SERVER "$LFTP_CMD"
        fi
    fi
    rc=$?
    if [ $rc -ne 0 ]; then
        echo "lftp upload failed with exit $rc" >&2
        exit $rc
    fi
    echo "Upload finished."
    exit 0
fi

# Fallback: sshpass + sftp (may not show a neat progress bar but works with chrooted sftp)
if command -v sshpass >/dev/null 2>&1 && command -v sftp >/dev/null 2>&1; then
    echo "lftp not found; falling back to sshpass + sftp. Progress will be basic."
    if [ -d "$LOCAL_PATH" ]; then
        # for directories, tarring on the fly and uploading the tarball is simpler
        BASENAME=$(basename "$LOCAL_PATH")
        TMP_TAR="/tmp/${BASENAME}_$(date +%s).tar.gz"
        echo "Creating tarball $TMP_TAR (this may take a while)..."
        tar -czf "$TMP_TAR" -C "$(dirname "$LOCAL_PATH")" "$BASENAME"
        echo "Uploading tarball..."
        sshpass -p "$PASSWORD" sftp -oBatchMode=no -b - "$USERNAME@$SERVER" <<EOF
put $TMP_TAR $DEST_PATH
bye
EOF
        rc=$?
        rm -f "$TMP_TAR"
        if [ $rc -ne 0 ]; then
            echo "sftp upload failed with exit $rc" >&2
            exit $rc
        fi
        echo "Upload finished. Remote side will need to extract the tarball if desired."
        exit 0
    else
        # single file upload
        sshpass -p "$PASSWORD" sftp -oBatchMode=no -b - "$USERNAME@$SERVER" <<EOF
put $LOCAL_PATH $DEST_PATH
bye
EOF
        rc=$?
        if [ $rc -ne 0 ]; then
            echo "sftp upload failed with exit $rc" >&2
            exit $rc
        fi
        echo "Upload finished."
        exit 0
    fi
fi

echo "Neither lftp nor sshpass+sftp are available. Please install 'lftp' or 'sshpass' and try again." >&2
exit 4
