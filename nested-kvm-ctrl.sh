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

Extra parameters handled by this script are handled by simple
environment variables.  For command line flexibility, any parameter
with an "=" in it is evaled so that environment variables can be set
at the end of the command line.

All the configuration and output information should be formatted
(somehow) to make extraction not-too-hard.  (update) The must-do rules
for making the extraction not-too-hard are, so far): (1) Each separate
boot or test run must write a line with the following prefix to the
log: "* [[[out Begin ".  The rest of the line can be anything.  (2)
Any section with data to parse must begin begin with "** ((( Begin ".
The rest of the line will give hints on where to send the text for
parsing.  In particular, "** ((( Begin post output )))" will always be
automatically inserted, to mark where the output from the overall
"time" command will appear (along with any post test garbage that
makes its way to stdout).  That's it.  Only two levels.  Some somewhat
arbitrary patterns to use carefully, but only three of them.

EOF

}

[ -d vmapp-vdc-1box ] || reportfailed "current directory not as expected"

# Glob patterns

export SESSION_START='\* *[[[out Begin*'
export section_START='\*\* *((( Begin*'
export postout_START='\*\* *((( Begin post output )))*'
export postout_START='*post*' # this line will be deleted soon

default-environment-params()
{
    : ${ORGPRE:="* "}  # prefix for making log hierarchy browseable through emacs' org-mode
    export ORGPRE
    : ${logname:="./nested-kvm-tests.log"}
    
    : ${vmcpus:=2} ${vmmem:=1500}
    : ${k3cpus:=4} ${k3mem:=6000}

    : ${diskopts:=1}  # 1 = "-hda $diskpath", see below for other options
}

parse-params()
{
    klist=()
    thecmd=""
    theparams=()
    for i in "$@"; do
	case "$i" in
	    *=*) echo "evaluating: $i"
		 eval "$i"  ## experimental hack for easier UI
		 ;;
	    [1234])
		[ -z "$thecmd" ] && klist=("${klist[@]}" "$i")
		[ -n "$thecmd" ] && theparams=("${theparams[@]}" "$i")
		;;
	    -boot|-status|-doscript|-kill|-dotest|-cleanlog)
		thecmd="$i"
		;;
	    *)
		[ -n "$thecmd" ] || reportfailed "parameter appeared before command: $i"
		theparams=("${theparams[@]}" "$i")
		;;
	esac
    done
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
    echo
    echo "$ORGPRE ((( Begin info for K$k:"
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
$(echo 'find /sys -name scheduler 2>/dev/null | grep noop $(cat)' | do-doscript $k bash)
KERNELCMDLINE="$(do-doscript $k cat /proc/cmdline)"
FLAGS="$(do-doscript $k cat /proc/cpuinfo | grep flags -m 1)"
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

    MACADDR="52-54-00-11-a0-5b"
}

pick-kvm()
{
    kvmbin=/usr/libexec/qemu-kvm
    [ -f "$kvmbin" ] || kvmbin=/usr/bin/qemu-kvm
}

pick-disk-parameters()
{
    k="$1"
    case "$k" in
	2)  diskpath="./1box-openvz.netfilter.x86_64.raw"
	    ;;
	3)  diskpath="./vmapp-vdc-1box/1box-kvm.netfilter.x86_64.raw"
	    ;;
	4)  diskpath="./1box-openvz.netfilter.x86_64.raw"
	    ;;
	*) reportfailed "bug"
	   ;;
    esac
    case "$diskopts" in
	1)  diskparams=( -hda $diskpath )
	    ;;
	2)  diskparams=( -drive file="$diskpath",id=centos-drive,cache=none,aio=native,if=none
			 -device virtio-blk-pci,drive=centos-drive,bootindex=0,bus=pci.0,addr=0x4
			 )
	    ;;
	3)  diskparams=( -drive file="$diskpath",id=centos-drive,cache=none,aio=native,if=none
			 -device virtio-blk,drive=centos-drive,scsi=off,config-wce=off,x-data-plane=on
			 )
	    ;;
	3v1)  diskparams=( -drive file="$diskpath",id=centos-drive,cache=none,aio=native,if=none
			 -device virtio-blk,drive=centos-drive,scsi=off,x-data-plane=on
			 )
	      #  0.12.1 complains about config-wce
	    ;;
	*) reportfailed "invalid diskopt: $diskopts"
	   ;;
    esac
}

do-boot-k2()
{
    do-status 1
    kill -0 "$(cat ./k2/kvm.pid)" && reportfailed "kvm 2 already running"
    rm ./k2 -fr
    mkdir ./k2
    pick-ports 2
    pick-kvm
    pick-disk-parameters 2
    
    setsid  "$kvmbin" -smp "$vmcpus" -cpu qemu64,+vmx -m "$vmmem" "${diskparams[@]}" \
	    -vnc :$VNC -k ja \
	    -monitor telnet::$MONITOR,server,nowait \
	    -net nic,vlan=0,model=virtio,macaddr=$MACADDR \
	    -net user,net=10.0.2.0/24,vlan=0${portforward} >k2/kvm.stdout 2>k2/kvm.stderr &
    echo $! | tee k2/kvm.pid
    echo "$kvmbin" >k2/kvm.binpath
    echo -n "booting..."
    while ! do-doscript 2 echo booted; do
	echo -n "."
	sleep 1
    done
    do-status 2
}

do-boot-k3()
{
    do-status 1
    kill -0 "$(cat ./k3/kvm.pid)" && reportfailed "kvm 3 already running"
    rm ./k3 -fr
    mkdir ./k3
    pick-ports 3
    pick-kvm
    pick-disk-parameters 3
    
    setsid  "$kvmbin" -smp "$k3cpus" -cpu qemu64,+vmx -m "$k3mem" "${diskparams[@]}" \
	    -vnc :$VNC -k ja \
	    -monitor telnet::$MONITOR,server,nowait \
	    -net nic,vlan=0,model=virtio,macaddr=$MACADDR \
	    -net user,net=10.0.2.0/24,vlan=0${portforward} >k3/kvm.stdout 2>k3/kvm.stderr &
    echo $! | tee k3/kvm.pid
    echo "$kvmbin" >k3/kvm.binpath
    # The time here may not be used for benchmarks, but putting this here makes
    # the code synchronous and easier to script
    echo -n "booting..."
    while ! do-doscript 3 echo booted; do
	echo -n "."
	sleep 1
    done
    echo
    do-status 3
}

startkvm-for-k4()
{
    kill -0 "$(cat ./k4/kvm.pid 2>/dev/null )" 2>/dev/null && { echo "kvm 4 already running" 1>&2 ; exit 255 ; }
    rm ./k4 -fr
    mkdir ./k4
    pick-ports 4
    pick-kvm
    pick-disk-parameters 4
    setsid  "$kvmbin" -smp "$vmcpus" -cpu qemu64,+vmx -m "$vmmem" "${diskparams[@]}" \
	    -vnc :$VNC -k ja \
	    -monitor telnet::$MONITOR,server,nowait \
	    -net nic,vlan=0,model=virtio,macaddr=$MACADDR \
	    -net user,net=10.0.2.0/24,vlan=0${portforward} >k4/kvm.stdout 2>k4/kvm.stderr &
    echo $! | tee k4/kvm.pid
    echo "$kvmbin" >k4/kvm.binpath
}


do-boot-k4()
{
    do-doscript 3 true || reportfailed "VM/kernel 3 not booted yet"
    do-status 1
    do-status 3
    rm ./k4 -fr
    mkdir ./k4
    
    (
	#echo 'exec 2>/tmp/start-k4.trace'
	#echo set -x
	echo vmcpus=$vmcpus
	echo vmmem=$vmmem
	echo diskopts=$diskopts
	declare -f reportfailed
	declare -f pick-ports
	declare -f pick-kvm
	declare -f pick-disk-parameters
	declare -f startkvm-for-k4
	echo startkvm-for-k4
    ) | do-doscript 3 bash

    do-doscript 3 cat k4/kvm.pid >k4/kvm.pid || reportfailed "Boot failed"
    do-doscript 3 cat k4/kvm.binpath >k4/kvm.binpath
    echo -n "booting..."
    while ! do-doscript 4 echo booted; do
	echo -n "."
	sleep 1
    done
    echo
    do-status 4
}

do-boot()
{
    echo "$ORGPRE [[[out Begin boot: $*"
    ORGPRE="*$ORGPRE"
    sleep 0.5 # Make sure stdout gets written out through its filter before stderr
    echo "[[[err Begin boot: $*" 1>&2
    time ( do-boot-k${1} ; echo "$ORGPRE post boot" )
    echo "    End boot: $*  out]]]"
    echo "    End boot: $*  err]]]" 1>&2
}

do-doscript()
{
    k="$1"
    shift
    ct="-o ConnectTimeout=1"
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
	     2) ssh centos@localhost $ct -p 11222 -i vmapp-vdc-1box/centos.pem -q bash
		;;
	     3) ssh centos@localhost $ct -p 11322 -i vmapp-vdc-1box/centos.pem -q bash
		;;
#	     4) ssh centos@localhost -p 11322 -A -i vmapp-vdc-1box/centos.pem -q ssh centos@localhost -p 11422 -q bash
#		;;
	     4) cat vmapp-vdc-1box/centos.pem | ssh centos@localhost -p 11322 -i vmapp-vdc-1box/centos.pem -q 'cat >c.pem ; chmod 600 c.pem'
		ssh centos@localhost -p 11322 -i vmapp-vdc-1box/centos.pem -q ssh centos@localhost $ct -p 11422 -q -i c.pem bash
		;;
	 esac
}

do-dotest() # wrap a piped in test script with status
{
    k="$1"
    shift
    echo "$ORGPRE [[[out Begin test: $*"
    ORGPRE="*$ORGPRE"
    sleep 0.5 # Make sure stdout gets written out through its filter before stderr
    echo "[[[err Begin test: $*" 1>&2
    case "$k" in
	1)
	    do-status 1
	    ;;
	2)
	    do-status 1
	    do-status 2
	    ;;
	3)
	    do-status 1
	    do-status 3
	    ;;
	4)
	    do-status 1
	    do-status 3
	    do-status 4
	    ;;
    esac
    echo "$ORGPRE test script from: $*"  # the test script should send its name to -dotest
    ORGPRE="*$ORGPRE"
    time ( do-doscript "$k" bash ; echo "$ORGPRE post test" )
    echo "    End test: $*  out]]]"
    echo "    End test: $*  err]]]" 1>&2
}

do-kill()
{
    k="$1"
    shift
    case "$k" in
	1) reportfailed "Cannot kill physical machine"
	   ;;
	2|3) kill $(cat k$k/kvm.pid)
	     ;;
	4) do-doscript 3 'kill $(cat k4/kvm.pid)'
    esac
}

log-newsection()
{
    startln="$1"
    case "$startln" in
	$SESSION_START) echo "$ORGPRE Begin ${startln#*Begin}"
		       ;;
	*)  echo "Don't know how to parse: $startln"
	    ;;
    esac
    sectiontestscript=""
    if [[ "${startln#*test: }" == test* ]]; then
	sectiontestscript="${startln#*test: }"
    fi
}

log-infosection()
{
    startln="$1"
    IFS=""
    kvmversion="metal"
    cpus=""
    while read -r ln; do
	case "$ln" in
	    End\ info*) break
			;;
	    KVMVERSION*version*)
		kvmversion="${ln#*version }"
		kvmversion="${kvmversion%%,*}"
		kvmversion="${kvmversion%% *}"
		;;
	    KVMPS*-smp*)
		cpus="${ln#*-smp }"
		cpus="${cpus%% *}"
		;;
	esac
    done
    echo KVMVERSION="$kvmversion"
    [ -n "$cpus" ] && echo CPUS="$cpus"
}

do-cleanlog()
{
    thelog="$logname"
    [ "$1" != "" ] && thelog="$1"
    echo "$ORGPRE Log summary for $thelog"
    ORGPRE="*$ORGPRE"

    inpostsection=false
    usingtestscript=false
    exec 7<"$thelog"  # keep primary copy of fd safe at 7
    IFS=""
    while read -r ln; do
	case "$ln" in
	    $SESSION_START) log-newsection "$ln"
					 inpostsection=false
					 usingtestscript=false
					 exec 0<&7 # reset stdin to normal
					 ;;
	    *Begin\ info*) log-infosection "$ln"
			   ;;
	    $postout_START) inpostsection=true
				       ;;
	    *real*) elapsetime="${ln#*real}"
		    $inpostsection && echo "ELAPSE=$elapsetime"
		    ;;
	    \**)
		if $usingtestscript; then
		    echo "$ln" # pass through unchanged
		else
		    # process the rest of the section with the test script, if any
		    if [ "$sectiontestscript" != "" ]; then
			read sname rest <<<"$sectiontestscript"
			exec 0< <($(readlink -f "$sname") -cleanlog "$rest" <&7)
			usingtestscript=true
		    fi
		    # else ignore the line of log text
		fi
		    ;;
	    *)
		: # ignore
		    ;;
	esac
    done 0<&7
    echo "* end"
}

default-environment-params

parse-params "$@"
[ -n "$thecmd" ] || reportfailed "no command given"
if [ "$thecmd" = "-cleanlog" ]; then
    do-cleanlog "${theparams[@]}"
else
    exec 2> >(while read -r ln ; do echo "stderr: $ln" ; done | tee -a "$logname")
    exec 1> >(tee -a "$logname")

    [ -n "${klist[*]}" ] || reportfailed "no kernels specified"
    for k in "${klist[@]}"; do
	do$thecmd "$k" "${theparams[@]}"
    done
fi

exit

### rest to be deleted during refactoring:


case "$cmd" in

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
esac
