#!/usr/bin/env bash
# upload.sh - simple client uploader for bakap
# Placeholders / CLI args:
# 1) local path (file or directory)
# 2) username
# 3) password
# 4) destination path relative to user's chroot (e.g. uploads/ or uploads/subdir)

set -euo pipefail

DEFAULT_SERVER="202.61.225.34"

usage() {
        cat <<EOF
Usage: $0 <local-path> <username> <password> [dest-path] [expected-host-fingerprint]

This script uploads a file or directory to the bakap server ($DEFAULT_SERVER).
It prefers lftp (shows progress). If lftp is not installed it falls back to sshpass+sftp.

Examples:
    $0 /path/to/file.sql.gz test2 'P@ssw0rd' uploads/
    $0 /path/to/folder test2 'P@ssw0rd' uploads/backups/ SHA256:abcdef...

Notes:
- The password will appear in the process list while the command runs when using sshpass. Prefer SSH keys.
- The destination path is relative to the user's chroot (most installs use uploads/).
- If provided, expected-host-fingerprint will be compared to the server's SSH key fingerprint before adding it to your known_hosts.
EOF
}

if [ "$#" -lt 3 ]; then
    usage
    exit 2
fi

LOCAL_PATH=$1
USERNAME=$2
PASSWORD=$3
DEST_PATH=${4:-uploads/}
# Normalize destination path: remove leading slash so paths are always relative
# to the user's chroot (some clients/servers treat leading slash as absolute
# and that can cause permission failures). Also ensure non-empty.
DEST_PATH="${DEST_PATH#/}"
if [ -z "$DEST_PATH" ]; then
    DEST_PATH="uploads"
fi
EXPECTED_FP=${5:-}

if [ ! -e "$LOCAL_PATH" ]; then
    echo "Local path does not exist: $LOCAL_PATH" >&2
    exit 3
fi

echo "Uploading '$LOCAL_PATH' as user '$USERNAME' to $DEFAULT_SERVER:$DEST_PATH"

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
    if ssh-keygen -F "$DEFAULT_SERVER" -f "$KNOWN_HOSTS" >/dev/null 2>&1; then
        return 0
    fi

    # Fetch host keys
    echo "Fetching host keys for $DEFAULT_SERVER..."
    tmp=$(mktemp)
    ssh-keyscan -t rsa,ecdsa,ed25519 "$DEFAULT_SERVER" > "$tmp" 2>/dev/null || true
    if [ ! -s "$tmp" ]; then
        echo "Failed to fetch host keys for $DEFAULT_SERVER" >&2
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
    echo "Added $DEFAULT_SERVER host key to $KNOWN_HOSTS"
    return 0
}

# Try to ensure host key; non-fatal for now
ensure_host_key || true

# Prefer lftp if available (gives a nice progress bar and supports sftp protocol)
if command -v lftp >/dev/null 2>&1; then
    echo "Using lftp (shows progress)."
    # lftp: for directories use mirror -R, for files use put
    if [ -d "$LOCAL_PATH" ]; then
        # mirror local dir to remote dest path (create remote dir if needed)
        lftp -u "$USERNAME","$PASSWORD" sftp://$DEFAULT_SERVER -e \
            "mkdir -p $DEST_PATH; mirror -R --verbose --continue --parallel=2 \"$LOCAL_PATH\" \"$DEST_PATH\"; bye"
    else
        # Ensure remote directory exists and upload file
        REMOTE_DIR="$DEST_PATH"
        # strip trailing slash for lftp put -O
        lftp -u "$USERNAME","$PASSWORD" sftp://$DEFAULT_SERVER -e \
            "mkdir -p $REMOTE_DIR; put -O $REMOTE_DIR \"$LOCAL_PATH\"; bye"
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
        sshpass -p "$PASSWORD" sftp -oBatchMode=no -b - "$USERNAME@$DEFAULT_SERVER" <<EOF
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
        sshpass -p "$PASSWORD" sftp -oBatchMode=no -b - "$USERNAME@$DEFAULT_SERVER" <<EOF
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
