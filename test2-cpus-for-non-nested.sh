#!/bin/bash

cat "$0" >>nested-kvm-tests.log

thetest()
{
    echo =============================================================================

    for guestcpus in 1 2 4 8 ; do

	echo "====================== hosts: $hostcpus =========== guests: $guestcpus ================================="

	./nested-kvm-ctrl.sh 2 -kill
	./nested-kvm-ctrl.sh 2 -boot vmcpus=$guestcpus

    done

    echo Finished              test                   1

    echo =============================================================================
}

thelogparser()
{
    IFS=""
    while read -r ln; do
	case "$ln" in
	    *) : ;;
	esac
    done
}

case "$1" in
    -cleanlog) thelogparser "$@"
	       ;;
    -dotest) thetest "$@"
	     ;;
    *) echo "bad cmd to $0: $1" 1>&2
       ;;
esac

# first results:
# /ssh:triggers@192.168.2.24: #$ grep -o 'smp....\|real.*' nested-kvm-tests.log
# smp 1 -
# real	0m27.618s
# smp 2 -
# real	0m26.457s
# smp 4 -
# real	0m26.478s
# smp 8 -
# real	0m27.626s
