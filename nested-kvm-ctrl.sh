#!/bin/bash

# originally copied from script for ncomputing demo:
# /ssh:triggers@192.168.2.24:/home/triggers/dev/ncomputing-in-nested-kvm-wakame/start-nested-kvm-wakame.sh

reportfailed()
{
    echo "$@" 1>&2
    exit 255
}

usage()
{
    cat <<EOF
So far this help text is just informal design notes:

The overall purpose of this script is to do repeatable tests that
compare KVM running directly on the host with KVM running nested
inside another KVM.

There are 4 kernels to worry about.  For short reference, let's call them
K1,K2,K3,and K4:
(K1) bare metal/physical
(K2) KVM running directly on the host/physical machine
(K3) KVM to hold nested KVM
(K4) The nested KVM

The (planned) general form for calling this command is:
   @0 {list of Kernels} -command {parameters}
   e.g.  @0 3 4 -status  # give the status of the nested VM/kernel and
			 # the VM/kernel hosting it

The main focus is to compare (2) and (4), but the others affect the result.

Each can have many configuration options, in the kernel itself, in the
OS, and in the KVM hosting it.  For KVM this includes the compile
times options and other parameters when starting it.  The -status
command dumps as much of this info as practical for each VM/kernel.

Maybe there basically only need to be three commands: -status, -boot,
-doscript.  To keep things simple, stdout and stderr are automatically
appended to one log (let's call it nested-kvm-tests.log).  Relevant
status and time info should automatically be logged.  Each test script
should output whatever configuration it adds and also output result
data.

All the configuration and output information should be formatted
(somehow) to make extraction not-too-hard.

EOF

}

MACADDR="52-54-00-11-a0-5b"

BOOTIMG=./vmapp-vdc-1box/1box-kvm.netfilter.x86_64.raw
SSH=18822
MISC=18833
MONITOR=18877
WAKAME=18890

portforward=""
portforward="$portforward,hostfwd=tcp:0.0.0.0:$SSH-:22"  # ssh (for testing)
portforward="$portforward,hostfwd=tcp:0.0.0.0:$WAKAME-:9000"  # test (for testing)
portforward="$portforward,hostfwd=tcp:0.0.0.0:$MISC-:7890"  # test (for testing)

dossh()
{
    ssh centos@localhost -p "$SSH" -i vmapp-vdc-1box/centos.pem -q "$@"
}

if [ "$FAKELOCAL" != "" ]; then
    dossh()
    {
	eval "$@"
    }
fi

innerboot()
{
    SSH=16622
    MISC=16633
    MONITOR=16677
    WAKAME=16690

    portforward=""
    portforward="$portforward,hostfwd=tcp:0.0.0.0:$SSH-:22"  # ssh (for testing)
    portforward="$portforward,hostfwd=tcp:0.0.0.0:$WAKAME-:9000"  # test (for testing)
    portforward="$portforward,hostfwd=tcp:0.0.0.0:$MISC-:7890"  # test (for testing)

    kvmbin=/usr/libexec/qemu-kvm
    [ -f "$kvmbin" ] || kvmbin=/usr/bin/qemu-kvm
    set -x
    setsid  "$kvmbin" -smp 2 -cpu qemu64,+vmx -m 1500 -hda 1box-openvz.netfilter.x86_64.raw \
	   -vnc :66 -k ja \
	   -monitor telnet::$MONITOR,server,nowait \
	   -net nic,vlan=0,model=virtio,macaddr=$MACADDR \
	   -net user,net=10.0.2.0/24,vlan=0${portforward} >kvm2.stdout 2>kvm2.stderr &
    echo $! | tee kvm2.pid
}

[ -d vmapp-vdc-1box ] || reportfailed "current directory not as expected"

parse-params()
{
    klist=()
    thecmd=""
    theparams=()
    for i in "$@"; do
	case "$i" in
	    [1234])
		[ -z "$thecmd" ] && klist=("${klist[@]}" "$i")
		[ -n "$thecmd" ] && theparams=("${theparams[@]}" "$i")
		    ;;
	    -boot|-status|-doscript)
		thecmd="$i"
		;;
	    *)
		[ -n "$thecmd" ] || reportfailed "parameter appeared before command: $i"
		theparams=("${theparams[@]}" "$i")
		;;
	esac
    done

    [ -n "${klist[*]}" ] || reportfailed "no kernels specified"
    [ -n "$thecmd" ] || reportfailed "no command given"
}

do-status()
{
    # We want both information about KVM and the kernel/OS running in it:
    #    KVM binary  (for K2, K3, & K4)
    #    KVM parameters/configuration/status  (for K2, K3, & K4)
    #    OS/kernel version
    #    OS/kernel configuration
    # At boot, the info for each KVM is put in a ./k{2,3,4} directory.
    k="$1"
    shift
    p=1
    [ "$k" = "4" ] && p=3
    echo "((( Begin info for K$k:"
    # KVM info
    if [ "$k" != "1" ]; then
	cat <<EOF
KVMVERSION="$(do-doscript $p $(< k$k/kvm.binpath) -version)"
KVMPS="$(do-doscript $p ps --no-headers $(< k$k/kvm.pid))"
EOF
    else
	cat <<EOF
KVMVERSION=physical
EOF
    fi
    # OS info
    cat <<EOF
SCHEDULER==
$(echo 'find /sys -name scheduler 2>/dev/null | grep noop $(cat)' | ./nested-kvm-ctrl.sh $k -doscript bash)
KERNELCMDLINE="$(./nested-kvm-ctrl.sh $k -doscript cat /proc/cmdline)"
EOF
    echo "End info for K$k )))"
}

pick-ports()
{
    knumber="$1"
    SSH=11${knumber}22
    MISC=11${knumber}33
    MONITOR=11${knumber}77
    WAKAME=11${knumber}90
    VNC=6${knumber}

    portforward=""
    portforward="$portforward,hostfwd=tcp:0.0.0.0:$SSH-:22"  # ssh (for testing)
    portforward="$portforward,hostfwd=tcp:0.0.0.0:$WAKAME-:9000"  # test (for testing)
    portforward="$portforward,hostfwd=tcp:0.0.0.0:$MISC-:7890"  # test (for testing)
}

pick-kvm()
{
    kvmbin=/usr/libexec/qemu-kvm
    [ -f "$kvmbin" ] || kvmbin=/usr/bin/qemu-kvm
}

do-boot-k2()
{
    kill -0 "$(cat ./k2/kvm.pid)" && reportfailed "kvm already running"
    rm ./k2 -fr
    mkdir ./k2
    pick-ports 2
    pick-kvm
    
    setsid  "$kvmbin" -smp 2 -cpu qemu64,+vmx -m 1500 -hda ./1box-openvz.netfilter.x86_64.raw \
	    -vnc :$VNC -k ja \
	    -monitor telnet::$MONITOR,server,nowait \
	    -net nic,vlan=0,model=virtio,macaddr=$MACADDR \
	    -net user,net=10.0.2.0/24,vlan=0${portforward} >k2/kvm.stdout 2>k2/kvm.stderr &
    echo $! | tee k2/kvm.pid
    echo "$kvmbin" >k2/kvm.binpath
}

do-boot-k3()
{
    kill -0 "$(cat ./k3/kvm.pid)" && reportfailed "kvm already running"
    rm ./k3 -fr
    mkdir ./k3
    pick-ports 3
    pick-kvm
    
    setsid  "$kvmbin" -smp 4 -cpu qemu64,+vmx -m 6000 -hda ./vmapp-vdc-1box/1box-kvm.netfilter.x86_64.raw \
	    -vnc :$VNC -k ja \
	    -monitor telnet::$MONITOR,server,nowait \
	    -net nic,vlan=0,model=virtio,macaddr=$MACADDR \
	    -net user,net=10.0.2.0/24,vlan=0${portforward} >k3/kvm.stdout 2>k3/kvm.stderr &
    echo $! | tee k3/kvm.pid
    echo "$kvmbin" >k3/kvm.binpath
}

do-boot()
{
    do-boot-k${1}
}

do-doscript()
{
    k="$1"
    shift
    # Note: Piping output from if to the case.
    if [ "$*" = "bash" ]; then
	# expect a script to come in from stdin
	cat
    else
	# execute whatever is on the command line
	echo "$*"
    fi | case "$k" in
	     1) bash
		;;
	     2) ssh centos@localhost -p 11222 -i vmapp-vdc-1box/centos.pem -q bash
		;;
	     3) ssh centos@localhost -p 11322 -i vmapp-vdc-1box/centos.pem -q bash
		;;
	     4) ssh centos@localhost -p 11322 -A -i vmapp-vdc-1box/centos.pem -q ssh centos@localhost -p 11422 -q bash
		;;
	 esac
}

parse-params "$@"
for k in "${klist[@]}"; do
    do$thecmd "$k" "${theparams[@]}"
done

exit

### rest to be deleted during refactoring:


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
	dossh 'netstat -nltp | grep 16622' || reportfailed "Inner kvm did not start"
	ccc=0
	while [ "$(dossh nc -i 1 127.0.0.1 16622)" == "" ]; do
	    ccc="$(( ccc + 1 ))"
	    sleep 1
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
