#!/bin/bash 

###########################################
# Prep: Set Versions 
###########################################

VERSION_K9S="v0.50.15"
# please without v before the version
VERSION_STERN="1.33.0"
# please without v before the version
VERSION_HELMFILE="1.1.7"

###########################################
# Basic Setup: 
###########################################

groupadd sshadmin
USERS="11trainingdo $(echo tln{1..20})"
echo $USERS
for USER in $USERS
do
  echo "Adding user $USER"
  useradd -s /bin/bash --create-home $USER
  usermod -aG sshadmin $USER
  echo "$USER:$SSH_PASS" | chpasswd
done

# We can sudo with 11trainingdo
usermod -aG sudo 11trainingdo 

# 20.04 and 22.04 this will be in the subfolder
if [ -f /etc/ssh/sshd_config.d/50-cloud-init.conf ]
then
  sed -i "s/PasswordAuthentication no/PasswordAuthentication yes/g" /etc/ssh/sshd_config.d/50-cloud-init.conf
fi

# seen this in ubuntu 24.04 important here
if [ -f /etc/ssh/sshd_config.d/60-cloudimg-settings.conf ]
then
  sed -i "s/PasswordAuthentication no/PasswordAuthentication yes/g" /etc/ssh/sshd_config.d/60-cloudimg-settings.conf
  # 2025-10-09 Let us try to set KeepAlive on ServerSide 
  echo "clientaliveinterval 60" >> /etc/ssh/sshd_config.d/60-cloudimg-settings.conf
  echo "clientalivecountmax 3"  >> /etc/ssh/sshd_config.d/60-cloudimg-settings.conf

fi

## both is needed 
sed -i "s/PasswordAuthentication no/PasswordAuthentication yes/g" /etc/ssh/sshd_config
usermod -aG sshadmin root

# TBD - Delete AllowUsers Entries with sed 
# otherwice we cannot login by group 
echo "AllowGroups sshadmin" >> /etc/ssh/sshd_config 

###########################################
# Phase 1: Install bash completion 
###########################################

apt-get update 
apt-get install -y bash-completion
source /usr/share/bash-completion/bash_completion
# is it installed properly
type _init_completion

###########################################
# Phase 2: Install kubectl and oc
# - install   kubectl - binary from OpenShift
# - install   oc - binary from OpenShift
# - configure kubectl - completion
# - configure oc - completion
###########################################

echo "Installing kubectl and oc from OpenShift"
cd /usr/src
# Download latest OpenShift client tools
curl -LO "https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable/openshift-client-linux.tar.gz"
tar -xzf openshift-client-linux.tar.gz
install kubectl /usr/local/bin/
install oc /usr/local/bin/
rm -f openshift-client-linux.tar.gz kubectl oc README.md

# Configure bash completion
kubectl completion bash | sudo tee /etc/bash_completion.d/kubectl > /dev/null
oc completion bash | sudo tee /etc/bash_completion.d/oc > /dev/null

###########################################
# Phase 3: Install helm & helm completion
# - install   helm - binary from OpenShift
# - configure helm - completion
###########################################

echo "Installing helm from OpenShift"
cd /usr/src
# Download latest Helm from OpenShift mirror
curl -LO "https://mirror.openshift.com/pub/openshift-v4/clients/helm/latest/helm-linux-amd64"
install helm-linux-amd64 /usr/local/bin/helm
rm -f helm-linux-amd64

# Configure bash completion
helm completion bash | sudo tee /etc/bash_completion.d/helm > /dev/null

# Install nfs-common for mounting, just in case we need it for persistant storage exercise
apt-get install -y nfs-common

# Looks like it takes a while till ssh is running
date > /var/log/training_reload_ssh
systemctl restart ssh

####################################
# Phase 4: Install k9s             
####################################

cd /usr/src 
wget https://github.com/derailed/k9s/releases/download/$VERSION_K9S/k9s_linux_amd64.deb
dpkg -i k9s_linux_amd64.deb

###################################
# Phase 5: Install stern           
###################################

cd /usr/src
wget https://github.com/stern/stern/releases/download/v$VERSION_STERN/stern_${VERSION_STERN}_linux_amd64.tar.gz
tar xvf stern_${VERSION_STERN}_linux_amd64.tar.gz
install stern /usr/local/bin

###################################
# Phase 6: Configure vi  
###################################

cd /usr/local/bin 
curl -L https://github.com/helmfile/helmfile/releases/download/v${VERSION_HELMFILE}/helmfile_${VERSION_HELMFILE}_linux_amd64.tar.gz -o helmfile.tar.gz
tar xvfz helmfile.tar.gz 
rm -f README* 
rm -f LICENSE 
rm -f helmfile.tar.gz

###################################
# Phase 7: Configure vi  
###################################

# Activate syntax - stuff for vim
# Tested on Ubuntu 
echo "hi CursorColumn cterm=NONE ctermbg=lightred ctermfg=white" >> /etc/vim/vimrc.local 
echo "autocmd FileType y?ml setlocal ts=2 sts=2 sw=2 ai number expandtab cursorline cursorcolumn" >> /etc/vim/vimrc.local 
echo "set paste" >> /etc/vim/vimrc.local

###################################
# Phase 8: Configure - nano 
###################################

echo "include /usr/share/nano/yaml.nanorc" >> /etc/nanorc 
echo "set autoindent" >> /etc/nanorc
echo "set tabsize 2" >> /etc/nanorc
echo "set tabstospaces" >> /etc/nanorc 

