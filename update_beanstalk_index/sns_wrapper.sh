#!/bin/bash

# based on Cronic v2 - cron job report wrapper downloaded from http://habilis.net/cronic/cronic
# Copyright 2007 Chuck Houpt
# Public Domain CC0: http://creativecommons.org/publicdomain/zero/1.0/
# modified by BCT 2008 to use voro logging scheme, tweaked in 2013 for appstrap
# modified by MER 2016 to report via Amazon SNS Topic

if [[ -n "$DEBUG" ]]; then 
  set -x
fi

# can set the first opt argument to --ignore-stderr
# so that any output from stderr is not treated as a failure

IGNORE_STDERR=false

for i in "$@"
do
	case $i in
		--ignore-stderr)
		IGNORE_STDERR=true
		shift
		;;
		*)
		;;
	esac
done

set -o pipefail  # trace ERR through pipes
set -o errtrace  # trace ERR through 'time command' and other functions
set -o nounset   ## set -u : exit the script if you try to use an uninitialised variable
set -o errexit   ## set -e : exit the script if any statement returns a non-true return value
logname=`basename $1`
TIMESTAMP=`date +%Y%m%d_%H%M%S`
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )" # http://stackoverflow.com/questions/59895
LOGDIR=$HOME/log
mkdir -p $LOGDIR
OUT=$LOGDIR/${logname}.$TIMESTAMP.out
ERR=$LOGDIR/${logname}.$TIMESTAMP.err
TRACE=$LOGDIR/${logname}.$TIMESTAMP.trc



source "${DIR}/post_sns_message.sh"

# ionice -c3 -p$$ 
renice -n 10 $$ > /dev/null

# run command
set +e
"$@" >$OUT 2>$TRACE
RESULT=$?

wait

set -e

if [ -e /usr/xpg4/bin/grep ]; then # solaris
  GREP=/usr/xpg4/bin/grep
elif [ -e /bin/grep ]; then # Amazon Linux AMI
  GREP=/bin/grep
else 
  GREP=/usr/bin/grep
fi

PATTERN="^${PS4:0:1}\\+${PS4:1}"
if $GREP -q "$PATTERN" $TRACE
then
    ! $GREP -v "$PATTERN" $TRACE > $ERR
else
    ERR=$TRACE
fi

if [ $RESULT -ne 0 -o -s "$ERR" -a "$IGNORE_STDERR" == "false" ]
then
	subject="${DATA_BRANCH}: Failed: $@"
	msg="Problem with command run of command \"$@\"
RESULT CODE: $RESULT
ERROR OUTPUT: tail $ERR"
	msg+=`tail "$ERR"`
	msg+=$'\n'
	msg+="STANDARD OUTPUT: tail $OUT"
	msg+=$'\n'
	msg+=`tail "$OUT"`
	if [ $TRACE != $ERR ]
		then
			msg+=$'\n'
			msg+="TRACE-ERROR OUTPUT: tail $TRACE"
			msg+=`tail "$TRACE"`
		fi
	else
		msg="Completed $@"
		msg+=$'\n'
		msg+="STANDARD OUTPUT: tail $OUT"
		msg+=$'\n'
		msg+=`tail "$OUT"`
		subject="${DATA_BRANCH}: Completed $@"
fi

post_sns_message "${subject:0:64}" "${msg}"

# remove empty log files
# : is a null command
if [ -s "$ERR" ] ; then gzip "$ERR"
	elif [ -e "$ERR" ] ; then rm $ERR
fi

if [ -s "$OUT" ]  ; then gzip "$OUT"
	elif [ -e "$OUT" ] ; then rm $OUT
fi

if [ -s "$TRACE" ] ; then gzip "$TRACE"
	elif [ -e "$TRACE" ] ; then rm $TRACE
fi
