#!/bin/bash

##-- Script to build ec2 AMI for the deployment of versitygw S3 gateway for a LucidLink Filespace
. ./config_vars.txt

# VGW_REGION is derived from AWS_REGION in config_vars.txt
VGW_REGION="$AWS_REGION"
##-- Generate ec2 instance user data file
mkdir -m 777 -p ../files
USRDATAF="build_script.sh"
if [ -e $USRDATAF ]; then
  echo "File $USRDATAF already exists!"
else
  echo "Creating $USRDATAF..."
  touch ../files/$USRDATAF
fi

if [ -w ../files/$USRDATAF ] ; then
     :
else
     echo -e "\e[91mError: write $USRDATAF permission denied.\e[0m"
     exit
fi

echo "FILESPACE1=${FILESPACE1}" > ../files/lucidlink-service-vars1.txt
echo "FSUSER1=${FSUSER1}" >> ../files/lucidlink-service-vars1.txt
echo "ROOTPOINT1=${ROOTPOINT1}" >> ../files/lucidlink-service-vars1.txt
echo "FSVERSION=${FSVERSION}" >> ../files/lucidlink-service-vars1.txt
echo -n "${LLPASSWD1}" | base64 > ../files/lucidlink-password1.txt
echo "ROOT_ACCESS_KEY=${ROOT_ACCESS_KEY}" > ../files/.env
echo "ROOT_SECRET_KEY=${ROOT_SECRET_KEY}" >> ../files/.env
echo "VGW_REGION=${VGW_REGION}" >> ../files/.env
echo "VGW_PORT=${VGW_PORT:-:9000}" >> ../files/.env
echo "VGW_IAM_DIR=${VGW_IAM_DIR:-/media/lucidlink/.vgw}" >> ../files/.env
echo "VGW_VIRTUAL_DOMAIN=${VGW_VIRTUAL_DOMAIN:-}" >> ../files/.env

# # Create Minio config file
# cat >../files/.env <<EOF
# ROOT_ACCESS_KEY=$ROOT_ACCESS_KEY
# ROOT_SECRET_KEY=$ROOT_SECRET_KEY
# EOF

# Create build script
cat >../files/build_script.sh <<EOF 
#!/bin/bash

set -x

# Set FSVERSION from config
FSVERSION="${FSVERSION}"

# Install necessary OS dependencies
sudo echo "deb http://cz.archive.ubuntu.com/ubuntu lunar main universe" >> /etc/apt/sources.list
sudo apt-get update -y
sudo DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" dist-upgrade
sudo apt-get update -y
sudo apt-get -y -qq install curl wget git vim apt-transport-https ca-certificates xfsprogs mdadm

# Install AWS CLI and SSM Agent
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
rm -rf aws awscliv2.zip

# Install SSM Agent
sudo snap install amazon-ssm-agent --classic
sudo systemctl enable snap.amazon-ssm-agent.amazon-ssm-agent.service
sudo systemctl start snap.amazon-ssm-agent.amazon-ssm-agent.service

# Ubuntu user already exists with sudo access

# Install LucidLink client and configure systemd services
sudo mkdir /s3-gw
sudo mkdir /s3-gw/lucid

# Install LucidLink based on FSVERSION
if [ "\${FSVERSION}" = "3" ]; then
    # LucidLink v3 installation
    echo "Installing LucidLink v3..."
    sudo wget -q https://www.lucidlink.com/download/new-ll-latest/linux-deb/stable/ -O /s3-gw/lucidinstaller.deb
    if [ -f "/s3-gw/lucidinstaller.deb" ]; then
        echo "Downloaded LucidLink v3 installer: \$(ls -lh /s3-gw/lucidinstaller.deb)"
        echo "Installing LucidLink v3 package..."
        sudo apt update
        sudo apt install /s3-gw/lucidinstaller.deb -y
        echo "Installation completed. Checking for binaries..."
        # Check all possible locations
        find /usr -name "lucid*" -type f 2>/dev/null || echo "No lucid binaries found in /usr"
        find /opt -name "lucid*" -type f 2>/dev/null || echo "No lucid binaries found in /opt"
        find /bin -name "lucid*" -type f 2>/dev/null || echo "No lucid binaries found in /bin"
        find /sbin -name "lucid*" -type f 2>/dev/null || echo "No lucid binaries found in /sbin"
        # Verify installation
        if [ -f "/usr/local/bin/lucid3" ]; then
            echo "LucidLink v3 installed successfully at /usr/local/bin/lucid3"
        else
            echo "ERROR: LucidLink v3 installation failed - binary not found at expected location"
        fi
    else
        echo "ERROR: Failed to download LucidLink v3 installer"
    fi
else
    # LucidLink v2 installation (default)
    echo "Installing LucidLink v2..."
    sudo wget -q https://www.lucidlink.com/download/latest/lin64/stable/ -O /s3-gw/lucidinstaller.deb
    sudo apt-get install /s3-gw/lucidinstaller.deb -y
fi
sudo wget -q https://amazoncloudwatch-agent.s3.amazonaws.com/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb -O /s3-gw/amazon-cloudwatch-agent.deb
sudo dpkg -i -E /s3-gw/amazon-cloudwatch-agent.deb
sudo mv /tmp/compose.yaml /s3-gw/compose.yaml
sudo mv /tmp/.env /s3-gw/.env
sudo mv /tmp/lucidlink-service-vars1.txt /s3-gw/lucid/lucidlink-service-vars1.txt
sudo mv /tmp/lucidlink-1.service /etc/systemd/system/lucidlink-1.service
sudo mv /tmp/s3-gw.service /etc/systemd/system/s3-gw.service

# Note: Service dependencies are handled by bootstrap.sh, no drop-in needed

# Encrypt LucidLink passwords and shred the original base64 plaintext files
LLPASSWORD1=\$(cat /tmp/lucidlink-password1.txt | base64 --decode)
echo -n "\${LLPASSWORD1}" | systemd-creds encrypt --name=ll-password-1 - /s3-gw/lucid/ll-password-1.cred &
wait
shred -uz /tmp/lucidlink-password1.txt

# Set permissions and update fuse.conf
# sudo mkdir /media/lucidlink/\${FILESPACE1}/
sudo chown -R ubuntu:ubuntu /s3-gw/compose.yaml /s3-gw/lucid /s3-gw/.env
sudo chmod 700 -R /s3-gw/lucid
sudo chmod 400 /s3-gw/lucid/ll-password-1.cred
sudo sed -i -e 's/#user_allow_other/user_allow_other/g' /etc/fuse.conf

# Network performance optimizations
echo 'net.core.rmem_max = 134217728' | sudo tee -a /etc/sysctl.conf
echo 'net.core.wmem_max = 134217728' | sudo tee -a /etc/sysctl.conf
echo 'net.ipv4.tcp_rmem = 4096 87380 134217728' | sudo tee -a /etc/sysctl.conf
echo 'net.ipv4.tcp_wmem = 4096 65536 134217728' | sudo tee -a /etc/sysctl.conf
echo 'net.core.netdev_max_backlog = 5000' | sudo tee -a /etc/sysctl.conf
echo 'net.ipv4.tcp_window_scaling = 1' | sudo tee -a /etc/sysctl.conf
echo 'net.ipv4.tcp_congestion_control = bbr' | sudo tee -a /etc/sysctl.conf
echo 'net.core.default_qdisc = fq' | sudo tee -a /etc/sysctl.conf

# Apply network optimizations
sudo sysctl -p

# Create IAM directory for versitygw
sudo mkdir -p ${VGW_IAM_DIR}
sudo chown -R ubuntu:ubuntu ${VGW_IAM_DIR}
sudo chmod 755 ${VGW_IAM_DIR}

# DO NOT enable systemd services during AMI build - bootstrap.sh will enable them
# This prevents services from starting before instance configuration is complete
sudo systemctl daemon-reload
# sudo systemctl enable lucidlink-1.service
# sudo systemctl enable s3-gw.service

# Install Docker
sudo apt-get -y install aptitude apt-utils apt-transport-https ca-certificates software-properties-common ca-certificates lsb-release jq nano
sudo aptitude update
sudo aptitude install -y \
    ca-certificates \
    curl \
    gnupg
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker.gpg
sudo chmod a+r /usr/share/keyrings/docker.gpg
echo \
    "deb [arch=\$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
    \$(. /etc/os-release && echo "\${UBUNTU_CODENAME:-\$VERSION_CODENAME}") stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo aptitude update
sudo aptitude install -y docker-ce docker-ce-cli containerd.io

# Add the ubuntu user to the docker group
sudo usermod -aG docker ubuntu

# Install Docker Compose and pull Docker images
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-\$(uname -s)-\$(uname -m)" \
    -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
sudo docker pull versity/versitygw
sudo docker pull minio/sidekick
# Clean up all installer files and temporary downloads
sudo rm -f /s3-gw/lucidinstaller.deb
sudo rm -f /s3-gw/amazon-cloudwatch-agent.deb  
sudo rm -f /s3-gw/versitygw.deb
sudo rm -f /s3-gw/*.deb
# Clean up any AWS CLI installation files
sudo rm -rf /tmp/aws*
sudo rm -f /tmp/*.zip
# Clean up apt cache to reduce image size
sudo apt-get clean
sudo apt-get autoremove -y
EOF

# Create systemd service files
cat >../files/lucidlink-1.service <<EOF
[Unit]
Description=LucidLink Daemon
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=0
[Service]
Restart=on-failure
RestartSec=1
TimeoutStartSec=180
Type=exec
User=ubuntu
Group=ubuntu
WorkingDirectory=/s3-gw/lucid
EnvironmentFile=/s3-gw/lucid/lucidlink-service-vars1.txt
LoadCredentialEncrypted=ll-password-1:/s3-gw/lucid/ll-password-1.cred
ExecStart=/bin/bash -c "LUCID_BIN=\$(if [ \"\${FSVERSION}\" = \"3\" ]; then echo \"/usr/local/bin/lucid3\"; else echo \"/usr/bin/lucid2\"; fi); INSTANCE_ID=\$(if [ \"\${FSVERSION}\" = \"3\" ]; then echo \"2001\"; else echo \"501\"; fi); /usr/bin/systemd-creds cat ll-password-1 | \$LUCID_BIN --instance \$INSTANCE_ID daemon --fs \${FILESPACE1} --user \${FSUSER1} --mount-point /media/lucidlink --root-point \${ROOTPOINT1} --root-path /data --config-path /data --fuse-allow-other"
ExecStop=/bin/bash -c "if [ \"\${FSVERSION}\" = \"3\" ]; then /usr/local/bin/lucid3 exit; else /usr/bin/lucid2 exit; fi"
[Install]
WantedBy=multi-user.target
EOF

cat >../files/s3-gw.service <<EOF
[Unit]
Description=s3-gw.service
Requires=docker.service lucidlink-1.service
After=docker.service lucidlink-1.service
StartLimitBurst=5
StartLimitIntervalSec=600
[Service]
TimeoutStartSec=30
Restart=always
RestartSec=30
User=ubuntu
Group=ubuntu
WorkingDirectory=/s3-gw
Type=simple
ExecStart=/bin/bash -c "docker compose -f /s3-gw/compose.yaml up"
ExecStop=/bin/bash -c "docker compose -f /s3-gw/compose.yaml down"

[Install]
WantedBy=multi-user.target
EOF

# Create Docker Compose file
cat >../files/compose.yaml <<EOF
services:
  sidekick-S3:
    image: minio/sidekick
    restart: always    
    depends_on:
      - versitygw-1
      - versitygw-2
      - versitygw-3
    ports:
      - "8000:8000"
    command: [ "--insecure", "--health-path", "/health", "--address", ":8000", "http://versitygw-1:9000", "http://versitygw-2:9000", "http://versitygw-3:9000" ]
    deploy:
      resources:
        limits:
          cpus: '3.0'
          memory: 6G
  versitygw-1:
    image: versity/versitygw:latest
    restart: always
    cap_add:
      - SYS_ADMIN
    devices:
      - "/dev/fuse"
    security_opt:
      - "apparmor:unconfined"
    environment:
      ROOT_ACCESS_KEY: ${ROOT_ACCESS_KEY:-s3-admin}
      ROOT_SECRET_KEY: ${ROOT_SECRET_KEY:-Nab2025!}
      VGW_PORT: "${VGW_PORT:-:9000}"
      VGW_HEALTH: "/health"
      VGW_REGION: "${VGW_REGION}"
      VGW_IAM_DIR: "${VGW_IAM_DIR:-/media/lucidlink/.vgw}"
      VGW_VIRTUAL_DOMAIN: "${VGW_VIRTUAL_DOMAIN:-}"
      # Performance optimizations for c6id.4xlarge
      GOMEMLIMIT: "8GiB"
      GOGC: "50"
      GOMAXPROCS: "4"
    volumes:
      - /media/lucidlink:/data
      - ${VGW_IAM_DIR:-/media/lucidlink/.vgw}:${VGW_IAM_DIR:-/media/lucidlink/.vgw}
    command: [ "posix", "/data" ]
    ulimits:
      nofile:
        soft: 65536
        hard: 65536
    deploy:
      resources:
        limits:
          cpus: '4.0'
          memory: 8G
  versitygw-2:
    image: versity/versitygw:latest
    restart: always
    cap_add:
      - SYS_ADMIN
    devices:
      - "/dev/fuse"
    security_opt:
      - "apparmor:unconfined"
    environment:
      ROOT_ACCESS_KEY: ${ROOT_ACCESS_KEY:-s3-admin}
      ROOT_SECRET_KEY: ${ROOT_SECRET_KEY:-Nab2025!}
      VGW_PORT: "${VGW_PORT:-:9000}"
      VGW_HEALTH: "/health"
      VGW_REGION: "${VGW_REGION}"
      VGW_IAM_DIR: "${VGW_IAM_DIR:-/media/lucidlink/.vgw}"
      VGW_VIRTUAL_DOMAIN: "${VGW_VIRTUAL_DOMAIN:-}"
      # Performance optimizations for c6id.4xlarge
      GOMEMLIMIT: "8GiB"
      GOGC: "50"
      GOMAXPROCS: "4"
    volumes:
      - /media/lucidlink:/data
      - ${VGW_IAM_DIR:-/media/lucidlink/.vgw}:${VGW_IAM_DIR:-/media/lucidlink/.vgw}
    command: [ "posix", "/data" ]
    ulimits:
      nofile:
        soft: 65536
        hard: 65536
    deploy:
      resources:
        limits:
          cpus: '4.0'
          memory: 8G
  versitygw-3:
    image: versity/versitygw:latest
    restart: always
    cap_add:
      - SYS_ADMIN
    devices:
      - "/dev/fuse"
    security_opt:
      - "apparmor:unconfined"
    environment:
      ROOT_ACCESS_KEY: ${ROOT_ACCESS_KEY:-s3-admin}
      ROOT_SECRET_KEY: ${ROOT_SECRET_KEY:-Nab2025!}
      VGW_PORT: "${VGW_PORT:-:9000}"
      VGW_HEALTH: "/health"
      VGW_REGION: "${VGW_REGION}"
      VGW_IAM_DIR: "${VGW_IAM_DIR:-/media/lucidlink/.vgw}"
      VGW_VIRTUAL_DOMAIN: "${VGW_VIRTUAL_DOMAIN:-}"
      # Performance optimizations for c6id.4xlarge
      GOMEMLIMIT: "8GiB"
      GOGC: "50"
      GOMAXPROCS: "4"
    volumes:
      - /media/lucidlink:/data
      - ${VGW_IAM_DIR:-/media/lucidlink/.vgw}:${VGW_IAM_DIR:-/media/lucidlink/.vgw}
    command: [ "posix", "/data" ]
    ulimits:
      nofile:
        soft: 65536
        hard: 65536
    deploy:
      resources:
        limits:
          cpus: '4.0'
          memory: 8G
EOF

echo "EC2 instance build script created: $USRDATAF"

# Generate Packer variables file from config_vars.txt
cat >../images/variables.auto.pkrvars.hcl <<EOF
region = "${AWS_REGION}"

instance_type = "${EC2_TYPE}"

filespace = "${FILESPACE1}"
EOF

echo "Generated Packer variables file: ../images/variables.auto.pkrvars.hcl"

exit 0
