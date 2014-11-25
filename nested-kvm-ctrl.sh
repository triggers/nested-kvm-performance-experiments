#!/bin/bash

# originally copied from script for ncomputing demo:
# /ssh:triggers@192.168.2.24:/home/triggers/dev/ncomputing-in-nested-kvm-wakame/start-nested-kvm-wakame.sh

reportfailed()
{
    echo "$@" 1>&2
    exit 255
}
	   

MACADDR="52-54-00-11-a0-5b"

#  (3) Once connected, everything seems to be done through one TCP
#  connection on port 27605.  (Although the manual says many TCP ports
#  need to be open: 27605, 27615, 3581, 3597, 3645, 3646, 3725) (...and
#  these UDP ports: 1027, 1283, 3581, 3725)

BOOTIMG=./vmapp-vdc-1box/1box-kvm.netfilter.x86_64.raw
SSH=18822
MISC=18833
MONITOR=18877
WAKAME=18890

ncomp=27605

portforward=""
portforward="$portforward,hostfwd=tcp:0.0.0.0:$SSH-:22"  # ssh (for testing)
portforward="$portforward,hostfwd=tcp:0.0.0.0:$ncomp-:$ncomp"  # NComputing
portforward="$portforward,hostfwd=tcp:0.0.0.0:$WAKAME-:9000"  # test (for testing)
portforward="$portforward,hostfwd=tcp:0.0.0.0:$MISC-:7890"  # test (for testing)

dossh()
{
    ssh centos@localhost -p "$SSH" -i vmapp-vdc-1box/centos.pem -q "$@"
}

innerboot()
{
    SSH=18822
    MISC=18833
    MONITOR=18877
    WAKAME=18890

    ncomp=27605

    portforward=""
    portforward="$portforward,hostfwd=tcp:0.0.0.0:$SSH-:22"  # ssh (for testing)
    portforward="$portforward,hostfwd=tcp:0.0.0.0:$ncomp-:$ncomp"  # NComputing
    portforward="$portforward,hostfwd=tcp:0.0.0.0:$WAKAME-:9000"  # test (for testing)
    portforward="$portforward,hostfwd=tcp:0.0.0.0:$MISC-:7890"  # test (for testing)

    setsid /usr/libexec/qemu-kvm -smp 2 -cpu qemu64,+vmx -m 1500 -hda 1box-openvz.netfilter.x86_64.raw \
	   -vnc :66 -k ja \
	   -monitor telnet::$MONITOR,server,nowait \
	   -net nic,vlan=0,model=virtio,macaddr=$MACADDR \
	   -net user,net=10.0.2.0/24,vlan=0${portforward} >kvm.stdout 2>kvm.stderr &
}


cmd="$1"
shift

[ -d vmapp-vdc-1box ] || reportfailed "current directory not as expected"

case "$cmd" in
    -boot)
	setsid qemu-kvm -smp 4 -cpu qemu64,+vmx -m 6000 -hda "$BOOTIMG" \
	       -vnc :69 -k ja \
	       -monitor telnet::$MONITOR,server,nowait \
	       -net nic,vlan=0,model=virtio,macaddr=$MACADDR \
	       -net user,net=10.0.2.0/24,vlan=0${portforward} >kvm.stdout 2>kvm.stderr &
	echo "$MONITOR" >kvm.monitor
	echo $! | tee kvm.pid
	return 0
	;;
esac

kill -0 "$(cat kvm.pid)" || reportfailed "kvm not running"

case "$cmd" in
    -ssh)
	dossh "$@"
	;;
    -init*setup) # not sparse
	dossh '[ -f 1box-openvz.netfilter.x86_64.raw ]' ; echo $?
	tar cv -C vmapp-vdc-1box 1box-openvz.netfilter.x86_64.raw | dossh 'tar xv'
	;;
    -innerboot)
	(
	    declare -f innerboot
	    echo innerboot
	) | dossh bash
	sleep 1
	dossh 'netstat -nltp | grep 18822' || reportfailed "Inner kvm did not start"
	ccc=0
	while [ "$(dossh nc -w 1 localhost 18822)" == "" ]; do
	    ccc="$(( ccc + 1 ))"
	done
	echo "Took $ccc seconds"
	;;
    -killinner)
	dossh killall qemu-kvm
	;;
    *)
	echo "Unknown command"
	exit 255
esac

