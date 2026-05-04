#!/bin/bash
#===============================================================================
# USAGE: ./install_dst.sh [OPTION]...
# 
# OPTIONS:
#   --dst-root-dir=DIRECTORY    Full path to directory to install DST
#   --dst-local-dir=DIRECTORY   Full path to directory to store DST's local data
#   --python-venv-dir=DIRECTORY Full path to directory to store python virtual environment
#   --python-version=VERSION    Python3 version to use, minimum version: 3.11 
#   --port=NUMBER               Set port the app will use, default: 8383
#   --nginx-group=GROUP         Nginx user/group name
#   --nginx-confd=DIRECTORY     Full path to directory for Nginx server block configuration
#   --use-url-prefix            Use an URL prefix
#   --url-prefix=STRING         Name of the URL prefix, default: dst
#   --uwsgi-logger              uWSGI: configures a logger for all types of messages
#
#
# EXAMPLES:
# ./install_dst.sh
#
# ./install_dst.sh --dst-root-dir=/home/rijaf \
#                  --dst-local-dir=/home/rijaf/Desktop/emi_dev_data \
#.                 --python-venv-dir=/Users/rijaf/Desktop/DATA/VirtualEnv \
#                  --python-version=3.14 \
#                  --port=8383
#
# ./install_dst.sh --dst-root-dir=/home/rijaf \
#                  --python-version=3.14 \
#                  --port=8383 \
#                  --use-url-prefix \
#                  --url-prefix=dst
#
# ./install_dst.sh --uwsgi-logger
#
# # centos
# ./install_dst.sh --nginx-group=nginx --nginx-confd=/etc/nginx/conf.d
# # ubuntu
# ./install_dst.sh --nginx-group=www-data --nginx-confd=/etc/nginx/sites-enabled
# # macos, with homebrew
# ./install_dst.sh --nginx-group=staff --nginx-confd=/usr/local/etc/nginx/sites-enabled
# #or
# ./install_dst.sh --nginx-group=staff --nginx-confd=/usr/local/etc/nginx/servers
#
#===============================================================================

if ! echo "Linux Darwin" | grep -wq "$(uname)"; then
    echo "Unknown operating system."
    exit 1
fi

#===============================================================================
## Directory to install DST commands
DST_CMD_BIN=/usr/local/bin
## Python minimum version requirement
req_python_v=3.11

#===============================================================================
## GitHub repositories
github_user=sei-africa
github_dst=DST
github_dst_api=dst_api
github_dst_conf=configuration_DST

#===============================================================================
## Default values
dst_root_dir=""
dst_local_dir=""
python_venv_dir=""
python_v=""
app_port=""
nginx_group=""
nginx_confd=""
use_url_prefix=false
url_prefix=""
uwsgi_logger=false

for arg in "$@"; do
    case $arg in
        --dst-root-dir=*)
            dst_root_dir="${arg#*=}"
            shift
            ;;
        --dst-local-dir=*)
            dst_local_dir="${arg#*=}"
            shift
            ;;
        --python-venv-dir=*)
            python_venv_dir="${arg#*=}"
            shift
            ;;
        --python-version=*)
            python_v="${arg#*=}"
            shift
            ;;
        --port=*)
            app_port="${arg#*=}"
            shift
            ;;
        --nginx-group=*)
            nginx_group="${arg#*=}"
            shift
            ;;
        --nginx-confd=*)
            nginx_confd="${arg#*=}"
            shift
            ;;
        --use-url-prefix)
            use_url_prefix=true
            shift
            ;;
        --url-prefix=*)
            url_prefix="${arg#*=}"
            shift
            ;;
        --uwsgi-logger)
            uwsgi_logger=true
            shift
            ;;
        *)
            echo "Unknown argument: $arg"
            exit 1
            ;;
    esac
done

UWSGI_LOGGER=$uwsgi_logger
USE_URL_PREFIX=$use_url_prefix
URL_PREFIX=dst

if $USE_URL_PREFIX; then
    if [[ -n "$url_prefix" ]]; then
        URL_PREFIX=$url_prefix
    else
        echo "No url prefix provided. The prefix 'dst' will be used"
    fi
fi

if [[ "$(uname)" == "Linux" ]]; then
    sed_cmd="sed -i"
    SYSTEMD_DIR=/etc/systemd/system

    if systemctl is-active --quiet "$URL_PREFIX"; then
        sudo systemctl stop $URL_PREFIX
        sudo systemctl disable $URL_PREFIX
    fi
fi

if [[ "$(uname)" == "Darwin" ]]; then
    if which gsed &>/dev/null; then
        sed_cmd="gsed -i"
    elif which sed &>/dev/null; then
        sed_cmd="sed -i ''"
    else
        echo "No 'sed' command found."
        exit 1
    fi
    export LC_ALL=C
    PLIST_DIR=/Library/LaunchDaemons
    MAC_PLIST=com.enacts.${URL_PREFIX}

    dst_exist=$(sudo launchctl list | grep  "$MAC_PLIST")
    if [[ -n "$dst_exist" ]]; then
        sudo launchctl unload -w ${PLIST_DIR}/${MAC_PLIST}.plist
        sudo launchctl remove $MAC_PLIST
    fi
fi

echo "==============================================================================="
echo -e "\nChecking Python version .....................\n"

req_py3_minor=$(echo $req_python_v | awk -F'.' '{print $2}')
if [[ -n $python_v ]]; then
    py3_major=$(echo $python_v | awk -F'.' '{print $1}')
    if (( $py3_major != 3 )); then
        echo "Requires Python 3"
        exit 1
    fi

    py3_minor=$(echo $python_v | awk -F'.' '{print $2}')
    if (( $py3_minor < $req_py3_minor )); then
        echo "Requires Python 3.11 or higher"
        exit 1
    fi

    PYTHON=python${python_v}
    if ! which $PYTHON &>/dev/null; then
        echo "${PYTHON} is not installed."
        exit 1
    fi
else
    if command -v python3 &>/dev/null; then
        py3_ver=$(python3 --version | awk '{print $NF}')
        py3_major=$(echo $py3_ver | awk -F'.' '{print $1}')
        if (( $py3_major != 3 )); then
            echo "Requires Python 3"
            exit 1
        fi

        py3_minor=$(echo $py3_ver | awk -F'.' '{print $2}')
        if (( $py3_minor < $req_py3_minor )); then
            no_py311=true
            for v in {15..11}; do
                if command -v python3.${v} &>/dev/null; then
                    py3_minor=$v
                    no_py311=false
                    break
                fi
            done

            if $no_py311; then
                echo "Requires Python 3.11 or higher"
                exit 1
            fi
        fi
    else
        echo "Python 3 is not installed."
        exit 1
    fi

    PYTHON=python${py3_major}.${py3_minor}
fi

echo "----- Python: ${PYTHON} ----- OK"
echo "==============================================================================="
echo -e "\nChecking Port .....................\n"

PORT=8383
if [[ "$(uname)" == "Linux" ]]; then
    port_open=false
    if [[ -n $app_port ]]; then
        if nc -zv localhost ${app_port} &>/dev/null; then
            port_open=true
        fi
        PORT=$app_port
    fi

    if ! $port_open; then
        echo "Opening port ${PORT}"
        if grep -q "ubuntu" /etc/os-release; then
            sudo ufw allow from any to any port ${PORT} proto tcp
        elif grep -q "centos" /etc/os-release; then
            sudo firewall-cmd --permanent --zone=public --add-port=${PORT}/tcp
            sudo firewall-cmd --reload
        elif command -v iptables &>/dev/null; then
            sudo iptables -A INPUT -p tcp --destination-port ${PORT} -j ACCEPT
        else
            echo "Port ${PORT} is closed or filtered. Please open it first."
            exit 1
        fi
    fi
fi

if [[ "$(uname)" == "Darwin" ]]; then
    if [[ -n $app_port ]]; then
        PORT=$app_port
    fi
fi

echo "----- Port: ${PORT} ----- OK"
echo "==============================================================================="
echo -e "\nChecking Nginx installation .....................\n"

if ! command -v nginx &>/dev/null; then
    echo "Nginx is not installed."
    exit 1
fi

NGINX_SITE_MSG="Directory for Nginx server block configuration not found."
if [[ -n "$nginx_confd" ]]; then
    if [ -d "$nginx_confd" ]; then
        NGINX_SITE=$nginx_confd
    else
        echo $NGINX_SITE_MSG
        exit 1
    fi
else
    if [[ "$(uname)" == "Linux" ]]; then
        if grep -q "ubuntu" /etc/os-release; then
            NGINX_SITE=/etc/nginx/sites-enabled
        elif grep -q "centos" /etc/os-release; then
            NGINX_SITE=/etc/nginx/conf.d
        else
            echo $NGINX_SITE_MSG
            exit 1
        fi
    elif [[ "$(uname)" == "Darwin" ]]; then
        nsite1=/usr/local/etc/nginx/sites-enabled
        nsite2=/usr/local/etc/nginx/servers
        nsite3=/opt/homebrew/etc/nginx/sites-enabled
        if [ -d "$nsite1" ]; then
            NGINX_SITE="$nsite1"
        elif [ -d "$nsite2" ]; then
            NGINX_SITE="$nsite2"
        elif [ -d "$nsite3" ]; then
            NGINX_SITE="$nsite3"
        else
            echo $NGINX_SITE_MSG
        fi
    else
        echo $NGINX_SITE_MSG
        exit 1
    fi

    if ! [ -d "$NGINX_SITE" ]; then
        echo $NGINX_SITE_MSG
        exit 1
    fi
fi

if [[ -n "$nginx_group" ]]; then
    NGINX_GRP=$nginx_group
else
    if [[ "$(uname)" == "Linux" ]]; then
        if grep -q "ubuntu" /etc/os-release; then
            nginx=$(ps -eo comm,supgrp,euser | grep nginx | tail -n1)
            NGINX_GRP=$(echo $nginx | awk '{print $NF}')
        elif grep -q "centos" /etc/os-release; then
            nginx=$(ps -eo comm,euser,supgrp | grep nginx | tail -n1)
            NGINX_GRP=$(echo $nginx | awk '{print $NF}' | awk -F',' '{print $1}')
        else
            echo "Unknown Nginx group."
            exit 1
        fi
    elif [[ "$(uname)" == "Darwin" ]]; then
        NGINX_GRP=$(groups $(whoami) | awk '{print $1}')
    else
        echo "Unknown Nginx group."
        exit 1
    fi
fi

NGINX_CONFILE=${NGINX_SITE}/${URL_PREFIX}.conf
if [ -L "$NGINX_CONFILE" ]; then
    sudo rm -f $NGINX_CONFILE
fi

echo "----- Nginx configuration dir: ${NGINX_SITE} ----- OK"
echo "----- Nginx group: ${NGINX_GRP} ----- OK"
echo "==============================================================================="
echo -e "\nChecking GitHub personal access token .....................\n"

github_pat_file=${HOME}/.GITHUB_PAT
if [ -f "${github_pat_file}" ]; then
    export GITHUB_PAT=$(awk -v t="$github_user" '$1==t {print $2}' "$github_pat_file")
    if [[ -z "$GITHUB_PAT" ]]; then
        echo "GitHub personal access token not found for user $github_user"
        exit 1
    fi
else
    echo "GitHub personal access token not found. (${github_pat_file})"
    exit 1
fi

echo "----- GitHub personal access token: ${github_pat_file} ----- OK"
echo "==============================================================================="
echo -e "\nCreating DST root directory .....................\n"

if [[ -n "$dst_root_dir" ]]; then
    ROOT_DIR=${dst_root_dir}/ENACTS_DST
else
    ROOT_DIR=${HOME}/ENACTS_DST
fi

if [ -d "$ROOT_DIR" ]; then
    echo -e "${ROOT_DIR} already exists"
    DELETE_DIR="y"
    read -p "Do you want to overwrite it? (Y/n) " USER_INPUT
    : ${USER_INPUT:=$DELETE_DIR}
    USER_INPUTl=$(echo "$USER_INPUT" | tr '[:upper:]' '[:lower:]')
    case "$USER_INPUTl" in
        y|yes)
            rm -fr $ROOT_DIR
            ;;
        *)
            echo -e "Provide a new root directory with the option --dst-root-dir"
            exit 1
            ;;
    esac
fi
mkdir -p $ROOT_DIR

APP_DIR=${ROOT_DIR}/${github_dst}

if [[ -n "$dst_local_dir" ]]; then
    DST_LOCAL_DIR=${dst_local_dir}
else
    DST_LOCAL_DIR=${ROOT_DIR}/${github_dst}_DATA
fi
mkdir -p $DST_LOCAL_DIR

echo "----- ENACTS DST API will be installed in: ${ROOT_DIR} ----- OK"
echo "----- DST will be installed in: ${APP_DIR} ----- OK"
echo "----- DST local data will be stored in: ${DST_LOCAL_DIR} ----- OK"
echo "==============================================================================="
echo -e "\nCloning DST .....................\n"

cd $ROOT_DIR
git clone https://github.com/${github_user}/${github_dst}.git
cd $APP_DIR
dst_api_git="url = git@github.com:${github_user}/${github_dst_api}.git"
dst_api_https="url = https://github.com/${github_user}/${github_dst_api}.git"
$sed_cmd 's,'"$dst_api_git"','"$dst_api_https"',g' .gitmodules
git submodule init
git submodule update

cd $ROOT_DIR
git clone https://${GITHUB_PAT}@github.com/${github_user}/${github_dst_conf}.git
cp ${github_dst_conf}/dev-* ${github_dst}/

echo "----- Cloning DST done ----- OK"
echo "==============================================================================="
echo -e "\nInstalling Python venv and requirements .....................\n"

if [[ -n "$python_venv_dir" ]]; then
    PYTHON_VENV=${python_venv_dir}
else
    PYTHON_VENV=${ROOT_DIR}
fi
mkdir -p $PYTHON_VENV

cd $PYTHON_VENV
$PYTHON -m venv venv
python_cmd=${PYTHON_VENV}/venv/bin/python
${python_cmd} -m pip install cache purge
${python_cmd} -m pip install --upgrade pip wheel setuptools
cd $APP_DIR
${python_cmd} -m pip install -r requirements.txt

flask_jsglue=${PYTHON_VENV}/venv/lib/${PYTHON}/site-packages/flask_jsglue.py
markup_old="from jinja2 import Markup"
markup_new="from markupsafe import Markup"
$sed_cmd 's#'"$markup_old"'#'"$markup_new"'#g' $flask_jsglue

echo "----- DST Python Virtual Environment is installed in: ${PYTHON_VENV}/venv ----- OK"
echo "==============================================================================="
echo -e "\nParsing DST configuration files .....................\n"

SECRET_1=$(tr -dc 'A-Za-z0-9!@?%$' < /dev/urandom | head -c 32)
SECRET_2=$(tr -dc 'A-Za-z0-9!@?%$' < /dev/urandom | head -c 32)
CONFIG_PARS=(USER NGINX_GRP PYTHON_VENV APP_DIR DST_LOCAL_DIR PORT URL_PREFIX SECRET_1 SECRET_2 MAC_PLIST)

cd $APP_DIR
for f in dev-*; do
    op_file="${f//dev-/}"
    cp $f $op_file

    for e in "${CONFIG_PARS[@]}"; do
        tag="<<<<${e}>>>>"
        value=$(eval "echo \$${e}")
        $sed_cmd 's#'"$tag"'#'"$value"'#g' $op_file
    done
done

cd ${APP_DIR}/app/yaml
for f in dev-*; do
    cp $f "${f//dev-/}"
done

cd ${APP_DIR}/app/dst_webapi/yaml
for f in dev-*; do
    cp $f "${f//dev-/}"
done

cd ${APP_DIR}/app/auth/yaml
for f in dev-*; do
    cp $f "${f//dev-/}"
done

ini=${APP_DIR}/dst.ini
if $UWSGI_LOGGER; then
    $sed_cmd "/logger/s/^[[:space:]]*#//g" $ini
fi

if [[ "$(uname)" == "Darwin" ]]; then
    $sed_cmd "/uid/s/^[[:space:]]*#//g" $ini
    $sed_cmd "/gid/s/^[[:space:]]*#//g" $ini
fi

config=${APP_DIR}/config.py
N=($(grep -n "URL_PREFIX" $config | awk -F':' '{print $1}'))
if $USE_URL_PREFIX; then
    $sed_cmd "${N[0]}s/^/#/g" $config
    $sed_cmd "${N[1]}s/^[[:space:]]*#//g" $config
    $sed_cmd "/SCRIPT_NAME/s/^[[:space:]]*#//g" ${APP_DIR}/dst.conf
fi

mkdir -p ${DST_LOCAL_DIR}/logs
touch ${DST_LOCAL_DIR}/logs/dst_access.log
touch ${DST_LOCAL_DIR}/logs/nginx_errors.log
touch ${DST_LOCAL_DIR}/logs/dst_debug.log
touch ${DST_LOCAL_DIR}/logs/dst_uwsgi.log

echo "----- Parsing DST configuration files ----- OK"
echo "==============================================================================="
echo -e "\nStarting DST service: ${URL_PREFIX} .....................\n"

if [[ "$(uname)" == "Linux" ]]; then
    sudo cp ${APP_DIR}/dst.service ${SYSTEMD_DIR}/${URL_PREFIX}.service
    sudo systemctl daemon-reload
    sudo systemctl start $URL_PREFIX
    sudo systemctl enable $URL_PREFIX
fi

if [[ "$(uname)" == "Darwin" ]]; then
    sudo cp ${APP_DIR}/dst.plist ${PLIST_DIR}/${MAC_PLIST}.plist
    sudo launchctl load -w ${PLIST_DIR}/${MAC_PLIST}.plist
    sudo launchctl start $MAC_PLIST
fi

echo "----- Starting DST service ----- OK"
echo "==============================================================================="
echo -e "\nRestarting Nginx .....................\n"

sudo ln -s ${APP_DIR}/dst.conf $NGINX_CONFILE
if [[ "$(uname)" == "Linux" ]]; then
    sudo systemctl restart nginx
fi
if [[ "$(uname)" == "Darwin" ]]; then
    brew services restart nginx
fi

echo "----- Restarting Nginx ----- OK"
echo "==============================================================================="
echo -e "\nCopying DST commands .....................\n"

if [[ "$(uname)" == "Linux" ]]; then
    restart_dst="sudo systemctl restart ${URL_PREFIX}"
fi
if [[ "$(uname)" == "Darwin" ]]; then
    restart_dst="sudo launchctl stop ${MAC_PLIST} && sudo launchctl start ${MAC_PLIST}"
fi

UPDATE_FILE=${DST_CMD_BIN}/update_${URL_PREFIX}
cat << EOF | sudo tee $UPDATE_FILE > /dev/null
#!/bin/bash
echo -e "Updating ${URL_PREFIX} .....................\n"
cd ${APP_DIR}
git pull origin main
cd app/dst_api
git pull origin main
cd ${APP_DIR}
echo -e "\nChecking new python requirements .....................\n"
${python_cmd} -m pip install -r requirements.txt
echo -e "\nRestarting ${URL_PREFIX} .....................\n"
${restart_dst}
EOF
sudo chmod 755 $UPDATE_FILE

ZARR_CONV=${DST_CMD_BIN}/convert2zarr_${URL_PREFIX}
cat << EOF | sudo tee $ZARR_CONV > /dev/null
#!/bin/bash
${python_cmd} ${APP_DIR}/convert2zarr.py
EOF
sudo chmod 755 $ZARR_CONV

ZARR_CLIM=${DST_CMD_BIN}/climato2zarr_${URL_PREFIX}
cat << EOF | sudo tee $ZARR_CLIM > /dev/null
#!/bin/bash
${python_cmd} ${APP_DIR}/climato2zarr.py
EOF
sudo chmod 755 $ZARR_CLIM

# clean mac sed in-place backup file 
if [[ "$(uname)" == "Darwin" ]]; then
    cd $APP_DIR
    for f in dev-*; do
        op_file="${f//dev-/}"
        rm -f ${op_file}\'\'
    done
fi

echo "----- Copying DST commands ----- OK"
echo "==============================================================================="
echo "----- Installation done -----"
