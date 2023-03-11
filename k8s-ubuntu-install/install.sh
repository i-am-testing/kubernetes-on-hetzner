#!/bin/bash

set -e

export DEBIAN_FRONTEND="noninteractive"
export CONTAINERD_VERSION="1.6.18"
export KUBERNETES_VERSION="1.26.2"
export DPKG_LOCK_TIMOUT="-1"

#############################################
# Disable UFW cause of Problems with Docker #
#############################################
echo '> Disable ufw and purge iptables ...'
systemctl stop ufw.service
systemctl disable ufw.service
# iptables -F

########################################
# Letting iptables see bridged traffic #
########################################
echo '> Letting iptables see bridged traffic ...'
test -e /etc/modules-load.d/k8s.conf || cat <<EOF | tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
test -e /etc/sysctl.d/k8s.conf || cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system

################
# Disable SWAP #
################
echo '> Disable SWAP ...'
swapoff -a
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

#################################################################
# Installs packages needed to use the Kubernetes apt repository
#################################################################
echo '> Installs packages needed to use the Kubernetes apt repository  ...'
apt-get -o DPkg::Lock::Timeout=${DPKG_LOCK_TIMOUT} update
apt-get -o DPkg::Lock::Timeout=${DPKG_LOCK_TIMOUT} install -y \
  apt-transport-https \
  ca-certificates \
  curl \
  gnupg \
  lsb-release \
  apparmor \
  apparmor-profiles \
  apparmor-utils \
  apt-transport-https \
  ca-certificates \
  curl \
  dirmngr \
  git \
  gnupg \
  gnupg-l10n \
  gpgsm \
  gpgv \
  inotify-tools \
  linux-virtual-hwe-22.04 \
  lsb-release \
  mlocate \
  ntp \
  p7zip-full \
  software-properties-common \
  wget



############################################
# Add  apt repository signing key
############################################
echo '> Add  apt repository signing key ...'
test -f /usr/share/keyrings/kubernetes-archive-keyring.gpg || curl -fsSLo /usr/share/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg
test -f /etc/apt/trusted.gpg.d/docker.gpg || curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmour -o /etc/apt/trusted.gpg.d/docker.gpg

####################################
# Add apt repositories
####################################
test -f /etc/apt/sources.list.d/kubernetes.list ||echo "deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | tee /etc/apt/sources.list.d/kubernetes.list
test -f /etc/apt/sources.list.d/docker.list ||echo "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list

####################################
# Install and Lock Packages
####################################
apt update
apt install -y \
  kubelet="${KUBERNETES_VERSION}-00"\
  kubeadm="${KUBERNETES_VERSION}-00"\
  kubectl="${KUBERNETES_VERSION}-00" \
  containerd.io="${CONTAINERD_VERSION}-1"

apt-mark -o DPkg::Lock::Timeout=${DPKG_LOCK_TIMOUT} hold kubelet kubeadm kubectl containerd

####################################
# Configures Containerd
####################################
echo '> Configure Containerd ...'
containerd config default | tee /etc/containerd/config.toml >/dev/null 2>&1
sed -i 's/SystemdCgroup \= false/SystemdCgroup \= true/g' /etc/containerd/config.toml
systemctl enable containerd
systemctl daemon-reload
systemctl restart containerd

#####################
# Configure Kubelet #
#####################
test -d /etc/systemd/system/kubelet.service.d || mkdir /etc/systemd/system/kubelet.service.d
test -e /etc/systemd/system/kubelet.service.d/20-hcloud.conf || cat > /etc/systemd/system/kubelet.service.d/20-hcloud.conf <<EOF
[Service]
Environment="KUBELET_EXTRA_ARGS=--cloud-provider=external"
EOF
systemctl enable --now kubelet
