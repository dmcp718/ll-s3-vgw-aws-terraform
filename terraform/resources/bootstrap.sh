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

# Setup NVMe instance storage for high-throughput caching
# Find actual NVMe instance storage devices (exclude root and EBS volumes)
ROOT_DEVICE=$(lsblk -n -o NAME,MOUNTPOINT | grep "/$" | awk '{print $1}' | sed 's/[0-9]*$//' | sed 's/p$//')
NVME_DEVICES=$(lsblk -d -n -o NAME,TYPE | grep disk | grep nvme | grep -v "^${ROOT_DEVICE}" | awk '{print "/dev/"$1}')

# Filter out EBS volumes (they typically have vendor "Amazon" or appear as attached volumes)
INSTANCE_STORAGE_DEVICES=""
for device in $NVME_DEVICES; do
    # Check if it's instance storage (not EBS) by checking if it's listed in /proc/partitions
    # Instance storage typically shows up as larger devices and doesn't have the EBS characteristics
    VENDOR=$(cat /sys/block/$(basename $device)/device/vendor 2>/dev/null | tr -d ' ')
    if [[ "$VENDOR" != "Amazon" ]] && [[ "$VENDOR" != "AmazonEC2" ]]; then
        INSTANCE_STORAGE_DEVICES="$INSTANCE_STORAGE_DEVICES $device"
    fi
done

if [ -n "$INSTANCE_STORAGE_DEVICES" ]; then
    echo "Found NVMe instance storage devices: $INSTANCE_STORAGE_DEVICES"
    
    # Create RAID 0 array with NVMe devices for maximum throughput
    NVME_COUNT=$(echo $INSTANCE_STORAGE_DEVICES | wc -w)
    if [ $NVME_COUNT -gt 1 ]; then
        echo "Creating RAID 0 array with $NVME_COUNT NVMe devices"
        sudo mdadm --create --verbose /dev/md0 --level=0 --raid-devices=$NVME_COUNT $INSTANCE_STORAGE_DEVICES
        sudo mkfs.xfs -f /dev/md0
        sudo mkdir -p /mnt/nvme-cache
        sudo mount /dev/md0 /mnt/nvme-cache
        echo '/dev/md0 /mnt/nvme-cache xfs defaults,noatime 0 0' | sudo tee -a /etc/fstab
    else
        echo "Setting up single NVMe device"
        SINGLE_NVME=$(echo $INSTANCE_STORAGE_DEVICES | awk '{print $1}')
        sudo mkfs.xfs -f $SINGLE_NVME
        sudo mkdir -p /mnt/nvme-cache
        sudo mount $SINGLE_NVME /mnt/nvme-cache
        echo "$SINGLE_NVME /mnt/nvme-cache xfs defaults,noatime 0 0" | sudo tee -a /etc/fstab
    fi
    
    # Set proper permissions for cache directory
    sudo chown -R lucidlink:lucidlink /mnt/nvme-cache
    sudo chmod 755 /mnt/nvme-cache
else
    echo "No NVMe instance storage found"
fi

# Setup high-performance EBS data volume
# Find the EBS data volume (excluding root volume)
ROOT_DEVICE_FULL=$(df / | tail -1 | awk '{print $1}')
EBS_DATA_DEVICE=""

# Check common device paths for the additional EBS volume
for device in /dev/nvme1n1 /dev/nvme2n1 /dev/nvme3n1 /dev/xvdb /dev/sdb; do
    if [ -e "$device" ] && [ "$device" != "$ROOT_DEVICE_FULL" ]; then
        # Check if it's not already mounted and is a block device
        if ! mount | grep -q "$device" && [ -b "$device" ]; then
            EBS_DATA_DEVICE="$device"
            break
        fi
    fi
done

if [ -n "$EBS_DATA_DEVICE" ]; then
    echo "Setting up high-performance EBS data volume: $EBS_DATA_DEVICE"
    sudo mkfs.xfs -f $EBS_DATA_DEVICE
    sudo mkdir -p /data
    sudo mount $EBS_DATA_DEVICE /data
    echo "$EBS_DATA_DEVICE /data xfs defaults,noatime 0 0" | sudo tee -a /etc/fstab
    sudo chown -R lucidlink:lucidlink /data
else
    echo "EBS data volume not found, creating /data directory on root volume"
    sudo mkdir -p /data
    sudo chown -R lucidlink:lucidlink /data
fi

# Enable and start lucidlink service
echo "Enabling 'systemctl enable lucidlink-1.service'"
sudo systemctl enable lucidlink-1.service
wait
echo "Starting 'systemctl start lucidlink-1.service'"
sudo systemctl start lucidlink-1.service
wait

# Wait for lucidlink to be linked
until lucid2 --instance 501 status | grep -qo "Linked"
do
    sleep 1
done
sleep 1

# Optimize LucidLink cache settings for NVMe storage
if [ -d "/mnt/nvme-cache" ]; then
    echo "Configuring LucidLink to use NVMe cache"
    /usr/bin/lucid2 --instance 501 config --set --DataCache.Size 80G
    /usr/bin/lucid2 --instance 501 config --set --DataCache.Path /mnt/nvme-cache
    # Enable high-performance cache settings
    /usr/bin/lucid2 --instance 501 config --set --DataCache.WriteMode async
    /usr/bin/lucid2 --instance 501 config --set --DataCache.ReadAhead 32M
else
    /usr/bin/lucid2 --instance 501 config --set --DataCache.Size 80G
fi

wait
sleep 1

# Enable and start s3-gw service
echo "Enabling 'systemctl enable s3-gw.service'"
sudo systemctl enable s3-gw.service
wait
echo "Starting 'systemctl start s3-gw.service'"
sudo systemctl start s3-gw.service
