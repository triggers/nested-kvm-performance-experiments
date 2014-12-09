#!/bin/bash

thetest()
{
    ./nested-kvm-ctrl.sh 2 -dotest "${0##*/}" <<EOF
sleep 2
echo hey
pstree -pa \$\$
EOF
}

thelogparser()
{
    IFS=""
    while read -r ln; do
	case "$ln" in
	    $SESSION_START|$section_START)
		echo "$ln"
		break;
		;;
	    $postout_START|*real*) 
		echo "$ln"
		;;
	    *) :
	       ;;
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
