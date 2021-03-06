#!/bin/bash

usage() {
    echo "invite.sh -i <github user name> [ -p <bind-port> ] [ -s <session-name> ] [ -r|--read-only ]"
}

while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        -s|--tmux-session)
        CLI_SESSION_NAME="$2"
        shift # past argument
        shift # past value
        ;;
         -p|--port)
        PORT="$2"
        shift # past argument
        shift # past value
        ;;
         -i|--invitee)
        GITHUB_USER="$2"
        shift # past argument
        shift # past value
        ;;
        -r|--read-only)
        READ_ONLY="-r"
        shift # past argument
        ;;
        -h|--help|*)    # unknown option
        usage
        exit 1
        ;;
    esac
done

if [[ -z "$GITHUB_USER" ]]; then
    echo "github user name is required: -i <github user name>" 
    usage
    exit 1
fi

join_by() { local IFS="$1"; shift; echo "$*"; }

unused_port() {
  # https://github.com/v1shwa/random-port-generator/blob/master/generate.sh
  while : ; do
    random_port=$(( ((RANDOM<<15)|RANDOM) % 49152 + 10000 ))
    nc -z 127.0.0.1 $random_port < /dev/null &>/dev/null || ( echo $random_port; return 1 ) || exit 
  done
}

SESSION_NAME=${CLI_SESSION_NAME:-`tmux display-message -p '#S'`}
PORT=${PORT:-`unused_port`}

make_hostkey() {
    mkdir -p ~/.invite.sh
    HOST_KEY=~/.invite.sh/hostkey
    [[ ! -f $HOST_KEY ]] && ssh-keygen -f $HOST_KEY -N "$HOST_KEY_PASSPHRASE_MUST_BE_EMPTY" > /dev/null
    chmod 600 $HOST_KEY
    echo $HOST_KEY
}

make_temp_sshd_conf() {
    AUTHORIZED_KEYS="$1"
    SSHD_CONF=`mktemp -t invite-sh-sshd_conf`
    ## create temporary authorized keys and sshd_config 
    cat > $SSHD_CONF <<EOF
AuthorizedKeysFile $AUTHORIZED_KEYS
PasswordAuthentication no
PubkeyAuthentication yes
PidFile none
EOF
    echo $SSHD_CONF
}
    
make_authorized_keys_for_user() {
    AUTHORIZED_KEYS=`mktemp -t invite-sh-authorized_keys`
    GITHUB_USER=$1
    SESSION_NAME=$2
    [[ ! -z $READ_ONLY ]] && READ_ONLY='-r'
    TMUX=$(which tmux)
    PUB_KEY=`curl -s https://github.com/${GITHUB_USER}.keys`
    echo "command=\"while ! $TMUX has -t ${SESSION_NAME} 2> /dev/null; do sleep 1; echo waiting for the host to start the show...; done; $TMUX at $READ_ONLY -t ${SESSION_NAME} \",no-port-forwarding,no-X11-forwarding $PUB_KEY" > $AUTHORIZED_KEYS 

    chmod 600 $AUTHORIZED_KEYS 
    echo $AUTHORIZED_KEYS
}

AUTHORIZED_KEYS=`make_authorized_keys_for_user $GITHUB_USER $SESSION_NAME`
trap "{ rm $AUTHORIZED_KEYS; }" EXIT 

SSHD_CONF=`make_temp_sshd_conf "$AUTHORIZED_KEYS"`
trap "{ rm $SSHD_CONF ; }" EXIT 

HOST_KEY=`make_hostkey`

## get the local ips 
IP=`ifconfig | sed -En 's/127.0.0.1//;s/.*inet (addr:)?(([0-9]*\.){3}[0-9]*).*/\2/p'` 


echo '---------------------------------------------------'
echo 
echo " Share this command with your peer:" 
echo 
for ip in ${IP[@]};do 
    echo -n "ssh ${USER}@$ip -p $PORT ||"
done
echo "echo 'something went wrong, no connection established'"
echo 
if [[ ! -z $READ_ONLY ]]; then
    echo " The invitation is read-only "
else
    echo " The invitation is read-write!!"
fi
echo 
if [[ ! -z "$CLI_SESSION_NAME" ]]; then
    echo " while you may start the session via"
    echo 
    echo "tmux new -A -s $SESSION_NAME"
    echo 
else
    echo " The user will join your current tmux session: ${SESSION_NAME}"
fi

echo '---------------------------------------------------'
/usr/sbin/sshd -e -p $PORT -h $HOST_KEY -D -f $SSHD_CONF
