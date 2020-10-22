#!/bin/bash
# Author: Jrohy
# Github: https://github.com/Jrohy/docker-install

OFFLINE_FILE=""

STANDARD_MODE=0

ARCH=$(uname -m)

DOWNLOAD_URL="https://download.docker.com/linux/static/stable/$ARCH"

LATEST_VERSION_CHECK="https://api.github.com/repos/docker/docker-ce/releases/latest"

COMPLETION_FILE="https://raw.githubusercontent.com/docker/cli/master/contrib/completion/bash/docker"

# cancel centos alias
[[ -f /etc/redhat-release ]] && unalias -a

#######color code########
RED="31m"      
GREEN="32m"  
YELLOW="33m" 
BLUE="36m"
FUCHSIA="35m"

colorEcho(){
    COLOR=$1
    echo -e "\033[${COLOR}${@:2}\033[0m"
}

ipIsConnect(){
    ping -c2 -i0.3 -W1 $1 &>/dev/null
    if [ $? -eq 0 ];then
        return 0
    else
        return 1
    fi
}

getFullPath() {
   local PWD=`pwd`
   if [ -d $1 ]; then
      cd $1
   elif [ -f $1 ]; then
      cd `dirname $1`
   else
      cd
   fi
   echo $(cd ..; cd -)
   cd ${PWD} >/dev/null
}

checkFile(){
    local FILE=$1
    if [[ ! -e $FILE ]];then
        colorEcho $RED "$FILE file not exist!\n"
        exit 1
    elif [[ ! -f $FILE ]];then
        colorEcho $RED "$FILE not a file!\n"
        exit 1
    fi

    FILE_NAME=$(echo ${FILE##*/})
    FILE_PATH=$(getFullPath $FILE)
    if [[ !  $FILE_NAME =~ ".tgz" && !  $FILE_NAME =~ ".tar.gz" ]];then
        colorEcho $RED "$FILE not a tgz file!\n"
        echo -e "please download docker binary file: $(colorEcho $FUCHSIA $DOWNLOAD_URL)\n"
        exit 1
    fi
}

#######get params#########
while [[ $# > 0 ]];do
    KEY="$1"
    case $KEY in
        -f|--file=)
        OFFLINE_FILE="$2"
        checkFile $OFFLINE_FILE
        shift
        ;;
        -s|--standard)
        STANDARD_MODE=1
        shift
        ;;
        -h|--help)
        echo "$0 [-h] [-f file]"
        echo "   -f, --file=[file_path]      offline tgz file path"
        echo "   -h, --help                  find help"
        echo "   -s, --standard              use 'get.docker.com' shell to install"
        echo ""
        echo "Docker binary download link:  $(colorEcho $FUCHSIA $DOWNLOAD_URL)"
        exit 0
        shift # past argument
        ;; 
        *)
                # unknown option
        ;;
    esac
    shift # past argument or value
done
#############################

checkSys() {
    if [[ -z `command -v systemctl` ]];then
        colorEcho ${RED} "system must be have systemd!"
        exit 1
    fi
    if [[ -z `uname -m|grep 64` ]];then
        colorEcho ${RED} "docker only support 64-bit system!"
        exit 1
    fi
    # check os
    if [[ `command -v apt-get` ]];then
        PACKAGE_MANAGER='apt-get'
    elif [[ `command -v dnf` ]];then
        PACKAGE_MANAGER='dnf'
    elif [[ `command -v yum` ]];then
        PACKAGE_MANAGER='yum'
    else
        colorEcho $RED "Not support OS!"
        exit 1
    fi
}

writeService(){
        mkdir -p /usr/lib/systemd/system/
        cat > /usr/lib/systemd/system/docker.service << EOF
[Unit]
Description=Docker Application Container Engine
Documentation=https://docs.docker.com
After=network-online.target firewalld.service
Wants=network-online.target
 
[Service]
Type=notify
# the default is not to use systemd for cgroups because the delegate issues still
# exists and systemd currently does not support the cgroup feature set required
# for containers run by docker
ExecStart=/usr/bin/dockerd
ExecReload=/bin/kill -s HUP $MAINPID
# Having non-zero Limit*s causes performance problems due to accounting overhead
# in the kernel. We recommend using cgroups to do container-local accounting.
LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=infinity
# Uncomment TasksMax if your systemd version supports it.
# Only systemd 226 and above support this version.
#TasksMax=infinity
TimeoutStartSec=0
# set delegate yes so that systemd does not reset the cgroups of docker containers
Delegate=yes
# kill only the docker process, not all processes in the cgroup
KillMode=process
# restart the docker process if it exits prematurely
Restart=on-failure
StartLimitBurst=3
StartLimitInterval=60s
 
[Install]
WantedBy=multi-user.target
EOF
}

dependentInstall(){
    if [[ ${PACKAGE_MANAGER} == 'yum' || ${PACKAGE_MANAGER} == 'dnf' ]];then
        ${PACKAGE_MANAGER} install bash-completion wget -y
    else
        ${PACKAGE_MANAGER} update
        ${PACKAGE_MANAGER} install bash-completion wget -y
    fi
}

onlineInstall(){
    dependentInstall
    LASTEST_VERSION=$(curl -H 'Cache-Control: no-cache' -s "$LATEST_VERSION_CHECK" | grep 'tag_name' | cut -d\" -f4 | sed 's/v//g')
    wget $DOWNLOAD_URL/docker-$LASTEST_VERSION.tgz
    if [[ $? != 0 ]];then
        colorEcho ${RED} "Fail download docker-$LASTEST_VERSION.tgz!"
        exit 1
    fi
    tar xzvf docker-$LASTEST_VERSION.tgz
    cp -rf docker/* /usr/bin/
    rm -rf docker docker-$LASTEST_VERSION.tgz
    curl -L $COMPLETION_FILE -o /usr/share/bash-completion/completions/docker
    chmod +x /usr/share/bash-completion/completions/docker
    source /usr/share/bash-completion/completions/docker
}

offlineInstall(){
    local ORIGIN_PATH=$(pwd)
    cd $FILE_PATH
    tar xzvf $FILE_NAME
    cp -rf docker/* /usr/bin/
    rm -rf docker
    cd ${ORIGIN_PATH} >/dev/null
    if [[ -e docker.bash || -e $FILE_PATH/docker.bash ]];then
        [[ -e docker.bash ]] && COMPLETION_FILE_PATH=`getFullPath docker.bash` || COMPLETION_FILE_PATH=$FILE_PATH
        cp -f $COMPLETION_FILE_PATH/docker.bash /usr/share/bash-completion/completions/docker
        chmod +x /usr/share/bash-completion/completions/docker
        source /usr/share/bash-completion/completions/docker
    fi
}

standardInstall(){
    # Centos8
    if [[ $PACKAGE_MANAGER == 'dnf' && `cat /etc/redhat-release |grep CentOS` ]];then
        ## see https://teddysun.com/587.html
        dnf config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo
        # install lastest containerd
        local CONTAINERD_URL="https://download.docker.com/linux/centos/7/x86_64/stable/Packages/"
        local PACKAGE_LIST="`curl -s $CONTAINERD_URL`"
        CONTAINERD_INDEX=`echo "$PACKAGE_LIST"|grep containerd|awk -F' {2,}' '{print $2}'|awk '{printf("%s %s\n", $1, $2)}'|sort -r|head -n 1`
        dnf install -y $CONTAINERD_URL/`echo "$PACKAGE_LIST"|grep "$CONTAINERD_INDEX"|awk -F '"' '{print $2}'`
        dnf install -y --nobest docker-ce
    else
        ipIsConnect www.google.com
        if [[  $? -eq 0 ]]; then
            sh <(curl -sL https://get.docker.com)
        else
            sh <(curl -sL https://get.docker.com) --mirror Aliyun
        fi
    fi
}

main(){
    checkSys
    if [[ $STANDARD_MODE == 1 ]];then
        standardInstall
    else
        [[ $OFFLINE_FILE ]] && offlineInstall || onlineInstall
        writeService
        systemctl daemon-reload
    fi
    systemctl enable docker.service
    systemctl restart docker
    echo -e "docker $(colorEcho $BLUE $(docker info|grep 'Server Version'|awk '{print $3}')) install success!"
}

main