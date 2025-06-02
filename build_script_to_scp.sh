#!/bin/bash
# build_script_to_scp.sh - Helper script to SCP the main build script to the VM and verify.

# Exit on any error
set -e

# Configuration
VM_NAME="kernel-builder-2"
VM_ZONE="us-central1-a"
REMOTE_USER="joshuathweny" # Assuming your username on the VM is joshuathweny
REMOTE_SCRIPT_PATH="/home/$REMOTE_USER/build_kernelsu_note10plus.sh"
LOCAL_SCRIPT_PATH="build_kernelsu_note10plus.sh"

echo "[INFO] Removing old script from VM to ensure clean transfer..."
gcloud compute ssh --zone "$VM_ZONE" "$VM_NAME" --command="rm -f $REMOTE_SCRIPT_PATH" || echo "[WARN] Failed to remove old script, or it didn't exist. Continuing..."

echo "[INFO] SCPing '$LOCAL_SCRIPT_PATH' to '$VM_NAME:$REMOTE_SCRIPT_PATH'..."
gcloud compute scp "$LOCAL_SCRIPT_PATH" "$VM_NAME:$REMOTE_SCRIPT_PATH" --zone "$VM_ZONE"

echo "[INFO] Verifying by cat-ing the remote script. Please check the output below:"
gcloud compute ssh --zone "$VM_ZONE" "$VM_NAME" --command="cat $REMOTE_SCRIPT_PATH"

echo "[INFO] SCP and verification script finished."