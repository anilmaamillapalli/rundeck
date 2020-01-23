#!/bin/bash

#test  /api/job/{id}/run

DIR=$(cd `dirname $0` && pwd)
source $DIR/include.sh

###
# setup: create a new job and acquire the ID
###

# job exec
args="echo hello there"

project=$2
if [ "" == "$2" ] ; then
    project="test"
fi

randport(){
  FLOOR=${1:-0}
  RANGE=${2:-1000}

  number=0   #initialize
  while [ "$number" -le $FLOOR ]
  do
    number=$RANDOM
    let "number %= $RANGE"  # Scales $number down within $RANGE.
    let "number += $FLOOR"  # Scales $number down within $RANGE.
  done
  echo $number
}

PORT=$(randport 4441 1000)
if [ -n "$TEST_NC_PORT" ]; then
  echo "use static nc port $TEST_NC_PORT"
  PORT=$TEST_NC_PORT
fi
nchost=127.0.0.1
#if [ -n "$TEST_NC_HOST" ]; then
#  echo "use static nc host $TEST_NC_HOST"
#  nchost=$TEST_NC_HOST
#fi

#escape the string for xml
xmlargs=$($XMLSTARLET esc "$args")
xmlproj=$($XMLSTARLET esc "$project")
xmlhost=$($XMLSTARLET esc "$nchost")
echo "host:port is $xmlhost:$PORT"

#produce job.xml content corresponding to the dispatch request
cat > $DIR/temp.out <<END
<joblist>
   <job>
      <name>webhook job</name>
      <group>api-test/job-run-webhook</group>
      <description></description>
      <loglevel>INFO</loglevel>
      <context>
          <project>$xmlproj</project>
          <options>
              <option name="opt1" value="testvalue" required="true"/>
              <option name="opt2" values="a,b,c" required="true"/>
          </options>
      </context>
      <dispatch>
        <threadcount>1</threadcount>
        <keepgoing>true</keepgoing>
      </dispatch>
      
      <notification>
        <onsuccess>
        <webhook urls="http://$xmlhost:$PORT/test?id=\${execution.id}&amp;status=\${execution.status}"/>
        </onsuccess>
      </notification>
      
      <sequence>
        <command>
        <exec>$xmlargs</exec>
        </command>
      </sequence>
   </job>
</joblist>

END

# now submit req
runurl="${APIURL}/project/$project/jobs/import"

params=""

# specify the file for upload with curl, named "xmlBatch"
ulopts="-F xmlBatch=@$DIR/temp.out"

# get listing
docurl $ulopts  ${runurl}?${params} > $DIR/curl.out
if [ 0 != $? ] ; then
    errorMsg "ERROR: failed query request"
    exit 2
fi

$SHELL $SRC_DIR/api-test-success.sh $DIR/curl.out || exit 2

#result will contain list of failed and succeeded jobs, in this
#case there should only be 1 failed or 1 succeeded since we submit only 1

succount=$($XMLSTARLET sel -T -t -v "/result/succeeded/@count" $DIR/curl.out)
jobid=$($XMLSTARLET sel -T -t -v "/result/succeeded/job/id" $DIR/curl.out)

if [ "1" != "$succount" -o "" == "$jobid" ] ; then
    errorMsg  "Upload was not successful."
    exit 
fi


###
#  start nc process to listen on port , cat any input to a file, and echo http 200 response
###
startnc(){
    port=$1
    shift
    file=$1
    shift
    echo "start nc on $port ... "
    nccmd="nc -w 30 -l -p $port"
    osname=$(uname)
    if [ "Darwin" = "$osname" ] ; then
      nccmd="nc -4 -w 30 -l $port"
    fi
    echo -n "HTTP/1.1 200 OK\r\n\r\n" | $nccmd > $file &
}

startnc $PORT $DIR/nc.out
ncpid=$!

trap "ps -p $ncpid >/dev/null && kill $ncpid" EXIT

###
# Run the chosen id, expect success message
###

echo "TEST: job/id/run should succeed"


# now submit req
runurl="${APIURL}/job/${jobid}/run"
params=""
execargs="-opt2 a"

# get listing
$CURL -H "$AUTHHEADER" --data-urlencode "argString=${execargs}" ${runurl}?${params} > $DIR/curl.out || fail "failed request: ${runurl}"

$SHELL $SRC_DIR/api-test-success.sh $DIR/curl.out || exit 2

#get execid

execcount=$($XMLSTARLET sel -T -t -v "/result/executions/@count" $DIR/curl.out)
execid=$($XMLSTARLET sel -T -t -v "/result/executions/execution/@id" $DIR/curl.out)

if [ "1" == "${execcount}" -a "" != "${execid}" ] ; then
    echo "OK"
else
    errorMsg "FAIL: expected run success message for execution id. (count: ${execcount}, id: ${execid})"
    exit 2
fi

#wait for nc to finish, should close after RunDeck server reads response
#check if pid has finished after 5 secs
# sleep 5
# ps -p $ncpid >/dev/null && kill $ncpid

####
# Verify the webhook data
####

echo "TEST: Webhook notification should submit to result"

[ -f $DIR/nc.out ] || fail "expected to see output from netcat"

cat $DIR/nc.out

grep -q "POST /test?id=${execid}&status=succeeded" $DIR/nc.out || fail "didn't see POST data"
grep -q "Content-Type: text/xml" $DIR/nc.out || fail "didn't see XML content data"
grep -q "<notification" $DIR/nc.out || fail "didn't see XML content data"

echo "OK"

rm $DIR/nc.out
rm $DIR/curl.out

