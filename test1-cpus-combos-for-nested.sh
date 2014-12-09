#!/bin/bash

cat "$0" >>nested-kvm-tests.log

thetest()
{
    echo =============================================================================

    ./nested-kvm-ctrl.sh 4 -kill
    ./nested-kvm-ctrl.sh 3 -kill

    for hostcpus in 1 2 4 8; do

	./nested-kvm-ctrl.sh 3 -kill
	./nested-kvm-ctrl.sh 3 -boot k3cpus=$hostcpus

	for guestcpus in 1 2 4; do

	    echo "====================== hosts: $hostcpus =========== guests: $guestcpus ================================="

	    ./nested-kvm-ctrl.sh 4 -kill
	    ./nested-kvm-ctrl.sh 4 -boot vmcpus=$guestcpus

	done

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
# host   nested
# cpus  cpus      time
# 1	1	115.676
# 2	1	74.914  (surprise)
# 4	1	59.94
# 8	1	59.026
# 1	2	60.005
# 2	2	51.909
# 4	2	54.032
# 8	2	54.078
# 1	4	72.634
# 2	4	56.471  (worse than 2 2, because guest > host??)
# 4	4	54.106
# 8	4	54.086
# 
# Conclusions: 
#  - one cpu on host or nested is bad.
#  - after 2 2, not much difference
