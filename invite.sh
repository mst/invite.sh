#!/bin/bash

function unused_port() {
    netstat -aln | awk '
      $6 == "LISTEN" {
        if ($4 ~ "[.:][0-9]+$") {
          split($4, a, /[:.]/);
          port = a[length(a)];
          p[port] = 1
        }
      }
      END {
        for (i = 3000; i < 65000 && p[i]; i++){};
        if (i == 65000) {exit 1};
        print i
      }
    '
}


GITHUB_USER=$1
PORT=`unused_port`
SESSION_NAME=${2:-`tmux display-message -p '#S'`}

SSHD_CONF=`mktemp -t invite-sh-sshd_conf`
AUTHORIZED_KEYS=`mktemp -t invite-sh-authorized_keys`
PUB_KEY=`curl -s https://github.com/${GITHUB_USER}.keys`
HOST_KEY=`mktemp -t invite-sh-hostkey`

trap "{ rm -f $SSHD_CONF $AUTHORIZED_KEYS $HOST_KEY ${HOST_KEY}.pub; }" EXIT 

rm $HOST_KEY

ssh-keygen -f $HOST_KEY -N "$HOST_KEY_PASSPHRASE_MUST_BE_EMPTY" > /dev/null
chmod 700 $AUTHORIZED_KEYS 
cat > $SSHD_CONF <<EOF
AuthorizedKeysFile $AUTHORIZED_KEYS
PasswordAuthentication no
PubkeyAuthentication yes
PidFile none
EOF

echo "command=\"while ! /usr/local/bin/tmux has -t ${SESSION_NAME} 2> /dev/null; do sleep 1; echo waiting...; done; /usr/local/bin/tmux at -t ${SESSION_NAME} \",no-port-forwarding,no-X11-forwarding $PUB_KEY" > $AUTHORIZED_KEYS 

IP=`ifconfig | sed -En 's/127.0.0.1//;s/.*inet (addr:)?(([0-9]*\.){3}[0-9]*).*/\2/p' | grep 10.`
echo '---------------------------------------------------'
echo 
echo " Share this command with your peer:" 
echo 
echo "ssh ${USER}@$IP -p $PORT"
echo 
echo " while you may start the session via"
echo 
echo "tmux new -A -s $SESSION_NAME"
echo 
echo '---------------------------------------------------'
/usr/sbin/sshd -e -p $PORT -h $HOST_KEY -D -f $SSHD_CONF 2> /dev/null
