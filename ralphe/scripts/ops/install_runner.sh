#!/bin/bash
set -e
echo '=> Creating github-runner user...'
if ! id "github-runner" &>/dev/null; then
    useradd -m github-runner
    usermod -aG docker github-runner
else
    echo '=> github-runner user already exists.'
fi

echo '=> Downloading and extracting Actions runner...'
su - github-runner -c "
mkdir -p actions-runner && cd actions-runner
if [ ! -f config.sh ]; then
    curl -o actions-runner-linux-x64-2.322.0.tar.gz -L https://github.com/actions/runner/releases/download/v2.322.0/actions-runner-linux-x64-2.322.0.tar.gz
    tar xzf ./actions-runner-linux-x64-2.322.0.tar.gz
fi
"

echo '=> Installing dependencies...'
cd /home/github-runner/actions-runner
./bin/installdependencies.sh

echo '=> Configuring runner...'
su - github-runner -c "
cd actions-runner
if [ ! -f .runner ]; then
    ./config.sh --url https://github.com/zerAda/RestaurantAgentAutomation --token ALXWRQHRRPBHE2EBK32WFTTJUL3EM --name vps-primary --labels self-hosted,vps-primary --work _work --unattended --replace
fi
"

echo '=> Installing and starting systemd service...'
cd /home/github-runner/actions-runner
if [ ! -f .service ]; then
    ./svc.sh install github-runner
    ./svc.sh start
else
    ./svc.sh stop
    ./svc.sh start
fi

echo '=> Runner installed and running!'
