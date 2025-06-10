#!/bin/bash

##-- Script to build ec2 AMI for the deployment of versitygw S3 gateway for a LucidLink Filespace
. script/config_vars.txt
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
echo -n "${LLPASSWD1}" | base64 > ../files/lucidlink-password1.txt
echo "ROOT_ACCESS_KEY=${ROOT_ACCESS_KEY}" > ../files/.env
echo "ROOT_SECRET_KEY=${ROOT_SECRET_KEY}" >> ../files/.env

# # Create Minio config file
# cat >../files/.env <<EOF
# ROOT_ACCESS_KEY=$ROOT_ACCESS_KEY
# ROOT_SECRET_KEY=$ROOT_SECRET_KEY
# EOF

# Create build script
cat >../files/build_script.sh <<EOF 
#!/bin/bash

set -x

# Install necessary OS dependencies
sudo echo "deb http://cz.archive.ubuntu.com/ubuntu lunar main universe" >> /etc/apt/sources.list
sudo apt-get update -y
sudo DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" dist-upgrade
sudo apt-get update -y
sudo apt-get -y -qq install curl wget git vim apt-transport-https ca-certificates xfsprogs

# Install AWS CLI and SSM Agent
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
rm -rf aws awscliv2.zip

# Install SSM Agent
sudo snap install amazon-ssm-agent --classic
sudo systemctl enable snap.amazon-ssm-agent.amazon-ssm-agent.service
sudo systemctl start snap.amazon-ssm-agent.amazon-ssm-agent.service

# Setup sudo to allow no-password sudo for "lucidlink" group and adding "lucidlink" user
sudo groupadd -r lucidlink
sudo useradd -M -r -g lucidlink lucidlink
sudo useradd -m -s /bin/bash lucidlink
sudo usermod -a -G lucidlink lucidlink
sudo cp /etc/sudoers /etc/sudoers.orig
echo "lucidlink  ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/lucidlink

# Install LucidLink client and configure systemd services
sudo mkdir /s3-gw
sudo mkdir /s3-gw/lucid
sudo wget -q https://www.lucidlink.com/download/latest/lin64/stable/ -O /s3-gw/lucidinstaller.deb && apt-get install /s3-gw/lucidinstaller.deb -y
sudo wget -q https://amazoncloudwatch-agent.s3.amazonaws.com/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb -O /s3-gw/amazon-cloudwatch-agent.deb
sudo dpkg -i -E /s3-gw/amazon-cloudwatch-agent.deb
sudo mv /tmp/compose.yaml /s3-gw/compose.yaml
sudo mv /tmp/.env /s3-gw/.env
sudo mv /tmp/lucidlink-service-vars1.txt /s3-gw/lucid/lucidlink-service-vars1.txt
sudo mv /tmp/lucidlink-1.service /etc/systemd/system/lucidlink-1.service
sudo mv /tmp/s3-gw.service /etc/systemd/system/s3-gw.service

# Encrypt LucidLink passwords and shred the original base64 plaintext files
LLPASSWORD1=\$(cat /tmp/lucidlink-password1.txt | base64 --decode)
echo -n "\${LLPASSWORD1}" | systemd-creds encrypt --name=ll-password-1 - /s3-gw/lucid/ll-password-1.cred &
wait
shred -uz /tmp/lucidlink-password1.txt

# Set permissions and update fuse.conf
# sudo mkdir /media/lucidlink/\${FILESPACE1}/
sudo chown -R lucidlink:lucidlink /s3-gw/compose.yaml /s3-gw/lucid /s3-gw/.env
sudo chmod 700 -R /s3-gw/lucid
sudo chmod 400 /s3-gw/lucid/ll-password-1.cred
sudo sed -i -e 's/#user_allow_other/user_allow_other/g' /etc/fuse.conf

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

# Add the current user to the docker group
sudo usermod -aG docker lucidlink

# Install Docker Compose and pull Docker images
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-\$(uname -s)-\$(uname -m)" \
    -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
sudo docker pull versity/versitygw
sudo docker pull minio/sidekick
# Remove LL and AWS installers
sudo rm /s3-gw/lucidinstaller.deb && rm /s3-gw/amazon-cloudwatch-agent.deb
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
User=lucidlink
Group=lucidlink
WorkingDirectory=/s3-gw/lucid
EnvironmentFile=/s3-gw/lucid/lucidlink-service-vars1.txt
LoadCredentialEncrypted=ll-password-1:/s3-gw/lucid/ll-password-1.cred
ExecStart=/bin/bash -c "/usr/bin/systemd-creds cat ll-password-1 | /usr/bin/lucid2 --instance 501 daemon --fs \${FILESPACE1} --user \${FSUSER1} --mount-point /media/lucidlink --root-point \${ROOTPOINT1} --root-path /data --config-path /data --fuse-allow-other"
ExecStop=/usr/bin/lucid2 exit
[Install]
WantedBy=multi-user.target
EOF

cat >../files/s3-gw.service <<EOF
[Unit]
Description=s3-gw.service
Requires=docker.service
After=docker.service
After=lucidlink-1.service
[Service]
TimeoutStartSec=180
Restart=always
User=lucidlink
Group=lucidlink
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
    command: [ "--insecure", "--health-path", "/health", "--address", ":8000", "http://versitygw-{1...3}:9000" ]
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
      VGW_PORT: ":9000"
      VGW_HEALTH: "/health"
      VGW_REGION: "${VGW_REGION}"
      # Performance optimizations
      GOMEMLIMIT: "4GiB"
      GOGC: "100"
    volumes:
      - /media/lucidlink:/data
    command: [ "posix", "/data" ]
    ulimits:
      nofile:
        soft: 65536
        hard: 65536
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
      VGW_PORT: ":9000"
      VGW_HEALTH: "/health"
      VGW_REGION: "${VGW_REGION}"
      # Performance optimizations
      GOMEMLIMIT: "4GiB"
      GOGC: "100"
    volumes:
      - /media/lucidlink:/data
    command: [ "posix", "/data" ]
    ulimits:
      nofile:
        soft: 65536
        hard: 65536
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
      VGW_PORT: ":9000"
      VGW_HEALTH: "/health"
      VGW_REGION: "${VGW_REGION}"
      # Performance optimizations
      GOMEMLIMIT: "4GiB"
      GOGC: "100"
    volumes:
      - /media/lucidlink:/data
    command: [ "posix", "/data" ]
    ulimits:
      nofile:
        soft: 65536
        hard: 65536
EOF

echo "EC2 instance build script created: $USRDATAF"

exit 0
