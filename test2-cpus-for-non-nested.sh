#!/bin/bash

cat "$0" >>nested-kvm-tests.log

echo =============================================================================

    for guestcpus in 1 2 4 8 ; do

	echo "====================== hosts: $hostcpus =========== guests: $guestcpus ================================="

	./nested-kvm-ctrl.sh 2 -kill
	./nested-kvm-ctrl.sh 2 -boot vmcpus=$guestcpus

    done

echo Finished              test                   1

echo =============================================================================

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
