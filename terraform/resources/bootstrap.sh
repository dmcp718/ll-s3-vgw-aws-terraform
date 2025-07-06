#!/bin/bash

set -x

# Install AWS CLI and SSM Agent
if command -v dnf &> /dev/null; then
    # Amazon Linux 2023
    sudo dnf install -y aws-cli amazon-ssm-agent mdadm
    sudo systemctl enable amazon-ssm-agent
    sudo systemctl start amazon-ssm-agent
elif command -v yum &> /dev/null; then
    # Amazon Linux 2
    sudo yum install -y aws-cli amazon-ssm-agent mdadm
    sudo systemctl enable amazon-ssm-agent
    sudo systemctl start amazon-ssm-agent
else
    # Ubuntu
    sudo apt-get update
    sudo apt-get install -y awscli mdadm
fi

# Setup NVMe instance storage for high-performance data and caching
# c6id.2xlarge has one instance storage device (nvme1n1)
# Use lsblk raw output to avoid tree characters
ROOT_PARTITION=$(lsblk -r -n -o NAME,MOUNTPOINT | grep "/$" | awk '{print $1}')
ROOT_DEVICE=$(echo "$ROOT_PARTITION" | sed 's/[0-9]*$//' | sed 's/p$//')
echo "Root partition: $ROOT_PARTITION"
echo "Root device: $ROOT_DEVICE"

# For c6id.2xlarge, instance storage is typically nvme1n1
INSTANCE_STORAGE_DEVICE="/dev/nvme1n1"
echo "Checking for instance storage device: $INSTANCE_STORAGE_DEVICE"

if [ -b "$INSTANCE_STORAGE_DEVICE" ]; then
    device_name=$(basename $INSTANCE_STORAGE_DEVICE)
    echo "Found device: $INSTANCE_STORAGE_DEVICE"
    
    # Check if this is not the root device
    if [[ "$device_name" != "$ROOT_DEVICE" ]] && ! lsblk "$INSTANCE_STORAGE_DEVICE" | grep -q "/"; then
        echo "  -> Verified as instance storage (not root device)"
        INSTANCE_STORAGE_DEVICES="$INSTANCE_STORAGE_DEVICE"
    else
        echo "  -> Device is root device or already mounted, skipping"
        INSTANCE_STORAGE_DEVICES=""
    fi
else
    echo "Instance storage device $INSTANCE_STORAGE_DEVICE not found"
    INSTANCE_STORAGE_DEVICES=""
fi

# Check if /data is already mounted from EBS and unmount it
if mountpoint -q /data; then
    echo "Unmounting existing /data mount to use instance storage instead"
    sudo umount /data || true
    # Remove any existing /data entries from fstab
    sudo sed -i '/\/data/d' /etc/fstab
fi

echo "Instance storage devices found: '$INSTANCE_STORAGE_DEVICES'"

if [ -n "$INSTANCE_STORAGE_DEVICES" ]; then
    echo "Found instance storage device: $INSTANCE_STORAGE_DEVICES"
    
    # Format and mount single NVMe instance storage device
    echo "Setting up single NVMe device for high-performance data storage"
    sudo mkfs.xfs -f $INSTANCE_STORAGE_DEVICES -d su=256k,sw=1
    
    # Mount as /data for LucidLink
    sudo mkdir -p /data
    sudo mount $INSTANCE_STORAGE_DEVICES /data -o defaults,noatime,largeio,swalloc
    echo "$INSTANCE_STORAGE_DEVICES /data xfs defaults,noatime,largeio,swalloc 0 0" | sudo tee -a /etc/fstab
    
    # Set proper permissions
    sudo chown -R ubuntu:ubuntu /data
    sudo chmod 755 /data
    
    echo "Instance storage mounted at /data with optimized XFS settings"
else
    echo "No instance storage found, using root volume for /data as fallback"
    sudo mkdir -p /data
    sudo chown -R ubuntu:ubuntu /data
fi

# Create /media/lucidlink mount point with correct permissions
sudo mkdir -p /media/lucidlink
sudo chown -R ubuntu:ubuntu /media/lucidlink

# Enable and start lucidlink service
echo "Enabling 'systemctl enable lucidlink-1.service'"
sudo systemctl enable lucidlink-1.service
sudo systemctl daemon-reload
wait
echo "Starting 'systemctl start lucidlink-1.service'"
sudo systemctl start lucidlink-1.service
wait

# Get FSVERSION from environment or systemd service
FSVERSION=$(systemctl show -p Environment lucidlink-1.service | grep -o 'FSVERSION=[0-9]*' | cut -d= -f2)
FSVERSION=${FSVERSION:-2}  # Default to version 2 if not found

# Determine LucidLink binary path and instance ID based on version
if [ "$FSVERSION" = "3" ]; then
    LUCID_BIN="/usr/local/bin/lucid3"
    INSTANCE_ID="2001"
else
    LUCID_BIN="/usr/bin/lucid2"
    INSTANCE_ID="501"
fi

# Wait for lucidlink to be linked
until $LUCID_BIN --instance $INSTANCE_ID status | grep -qo "Linked"
do
    sleep 1
done
sleep 1

# Wait a bit longer for daemon to be fully ready for config changes
sleep 5

# Optimize LucidLink cache settings
echo "Configuring LucidLink cache settings..."

# Calculate cache size based on available space in /data
if mountpoint -q /data; then
    # Get available space in /data and use 80% for cache
    AVAILABLE_KB=$(df /data | tail -1 | awk '{print $4}')
    CACHE_SIZE_KB=$((AVAILABLE_KB * 80 / 100))
    CACHE_SIZE_GB=$((CACHE_SIZE_KB / 1024 / 1024))
    
    # Ensure minimum 10GB and maximum 400GB
    if [ $CACHE_SIZE_GB -lt 10 ]; then
        CACHE_SIZE_GB=10
    elif [ $CACHE_SIZE_GB -gt 400 ]; then
        CACHE_SIZE_GB=400
    fi
    
    echo "Setting DataCache.Size to ${CACHE_SIZE_GB}GiB (80% of available /data space)..."
    if ! $LUCID_BIN --instance $INSTANCE_ID config --set --DataCache.Size ${CACHE_SIZE_GB}GiB; then
        echo "Warning: Failed to set DataCache.Size to ${CACHE_SIZE_GB}GiB"
    fi
else
    # Fallback to fixed size if /data not mounted
    echo "Setting DataCache.Size to 25GiB (fallback)..."
    if ! $LUCID_BIN --instance $INSTANCE_ID config --set --DataCache.Size 25GiB; then
        echo "Warning: Failed to set DataCache.Size"
    fi
fi

# Verify configuration was applied
echo "Verifying LucidLink cache configuration..."
$LUCID_BIN --instance $INSTANCE_ID config --list --local | grep -E "DataCache" || echo "Could not retrieve cache config"

wait
sleep 1

# Enable and start s3-gw service
echo "Enabling 'systemctl enable s3-gw.service'"
sudo systemctl enable s3-gw.service
sudo systemctl daemon-reload
wait
echo "Starting 'systemctl start s3-gw.service'"
sudo systemctl start s3-gw.service
# Verify service is running
sleep 5
if ! systemctl is-active --quiet s3-gw.service; then
    echo "ERROR: s3-gw service failed to start"
    systemctl status s3-gw.service
    journalctl -u s3-gw.service -n 50
fi
