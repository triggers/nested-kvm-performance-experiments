#!/bin/bash

thetest()
{
    ./nested-kvm-ctrl.sh 2 -dotest "${0##*/} $*" <<EOF
sleep 2
echo hey
pstree -pa \$\$
EOF
}

thelogparser()  # just some simple parsing for testing the script itself
{
    IFS=""
    ccc=0
    while read -r ln; do
	case "$ln" in
	    bash*) echo BASHPID="${ln#*,}" ;;
	    *) : ;;
	esac
	(( ccc++ ))
    done
    echo "LINES=$ccc"
}

case "$1" in
    -cleanlog) thelogparser "$@"
	       ;;
    -dotest) thetest "$@"
	     ;;
    *) echo "bad cmd to $0: $1" 1>&2
       ;;
esac
