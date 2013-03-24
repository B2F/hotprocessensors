#! /bin/bash
# hotprocessensors (hot processes sensors) by B2F

defaultTooHot=80
defaultSoFresh=75
defaultWatch="Core"
defaultRate=1
defaultSize=10
defaultBreakInterval=10

#getopts method by http://kirk.webfinish.com

for arg
do
  delim=""
  case "$arg" in
 --printemps) args="${args}-p ";;
      --temp) args="${args}-t ";;
     --break) args="${args}-b ";;
     --debug) args="${args}-d ";;   
      --tmax) args="${args}-m ";;
      --cool) args="${args}-c ";;
      --rate) args="${args}-r ";;
      --size) args="${args}-s ";;
       --fav) args="${args}-f ";;
           *) [[ "${arg:0:1}" == "-" ]] || delim="\""
           args="${args}${delim}${arg}${delim} ";;
  esac
done

#Reset the positional parameters to the short options
eval set -- $args

while getopts :c:m:t:r:s:f:b:dp opt; do
  case $opt in
    c) soFresh=${OPTARG[@]};;
    m) tooHot=${OPTARG[@]};; 
    t) sensor=${OPTARG[@]};;
    b) breakInterval=${OPTARG[@]};;
    r) rate=${OPTARG[@]};;
    s) size=${OPTARG[@]};;
    f) fav=${OPTARG[@]};;
    d) debug=true;;
    p) printemps=true;;
    ?)
      echo "invalid option -$OPTARG"
      exit 1;;
  esac
done

if [ -z "$tooHot" ] ; then
  tooHot=$defaultTooHot
  echo hotprocessensors --tmax: none provided, default \($defaultTooHot°C\) used. 
fi
if [ -z "$soFresh" ] ; then
  soFresh=$defaultSoFresh
  echo hotprocessensors --cool: none provided, default \($defaultSoFresh°C\) used. 
fi
#temperature watched under sensors
if [ -z "$sensor" ] ; then
  sensor=$defaultWatch
  echo hotprocessensors --temp: none provided, default \($defaultWatch\) used. 
fi
#sleep time between temperature checks
if [ -z "$rate" ] ; then
  rate=$defaultRate
  echo hotprocessensors --rate: none provided, default \($defaultRate sec\) used. 
fi
#maximum number of pid which can be stopped at the same time 
if [ -z "$size" ] ; then
  size=$defaultSize
  echo hotprocessensors --size: none provided, default \($defaultSize pids\) used. 
fi
#the maximum time processes can remained stopped
if [ -z "$breakInterval" ] ; then
  breakInterval=$defaultBreakInterval
  echo hotprocessensors --break: none provided, default \($defaultBreakInterval sec\) used. 
fi
#pid of processes which won't be stopped by the script (current script always favored)
if [ -z "$fav" ] ; then
  favored=$$
else
  favored=("${fav[@]}" $$)
fi

coolDowned=true
blamedPid=1
stoppedTime=0

function getTemp {
  cputemp=`sensors | grep "$1"`
  temp=`echo $cputemp | cut -d "+" -f2 | cut -c 1,2`
  sensorName=`echo $cputemp | cut -d ":" -f1`
}

function stopProcess {
  isFavored=false
  for priviledged in "${favored[@]}"; do
    if [ $priviledged -eq $1 ] ; then
      isFavored=true
    fi
  done
  if [[ $isFavored -eq false ]] ; then
    stoppedProcesses=("${stoppedProcesses[@]}" $1)
    kill -SIGSTOP $1
    #Debug: Stopped process pid
    if [[ $debug == true ]] ; then echo $1 STOPPED ; fi
  fi
}

function continueProcesses {
  for process in "${stoppedProcesses[@]}"; do
    kill -SIGCONT $process
    #Debug: Continued process pid
    if [[ $debug == true ]] ; then echo $process CONTINUE ; fi
  done
  stoppedProcesses=()
}

#check for valid sensor
getTemp $sensor
twoDigits="[[:digit:]]{2}"
if [[ ! $temp =~ $twoDigits ]] ; then
  echo Given sensor didn\'t return any valid temperature, check the sensor name with sensors \(default is Core\).
  exit 1
fi

#continue all stopped processes on exit
trap exiting_command INT

function exiting_command() {
  echo hotprocessensors exiting...
  continueProcesses
  exit 0
}

#processes watching 
while [ 1 ]; do

        getTemp $sensor
        #Debug: realtime temperatures comparaison
        if [[ $printemps == true ]] ; then echo "$sensorName = $temp <> max: $tooHot cool: $soFresh" ; fi

        #high temp reached
        if [[ $temp -ge $tooHot && $coolDowned == true ]] ; then
          #get the pid which use the most cpu:
          hotProcess=`ps -o pid -u "$USER" --sort pcpu | tail -1`
          stopProcess $hotProcess
          coolDowned=false

        #still high after last pid stopped
        elif [[ $temp -gt $soFresh && $coolDowned == false ]] ; then
          #stop the next pid in the list
          blamedPid=$(($blamedPid+1))
          if [[ $(($size-$blamedPid)) -gt 0 ]] ; then
            hotProcess=`ps -o pid -u "$USER" --sort pcpu | tail -$(($size)) | sed -n $(($size-$blamedPid))p` 
            stopProcess $hotProcess
          fi

        fi

        #temp cooled down and was hot OR forced CONTINUE if time elapsed greater than breakInterval
	if [[ $temp -le $soFresh && $coolDowned == false ]] || [[ $stoppedTime -ge $breakInterval ]] ; then
          continueProcesses
	  coolDowned=true
          #reset blamedPid to target pid with most pcpu
          blamedPid=1
          stoppedTime=0
	fi

        stoppedTime=$(($stoppedTime+$rate))
        sleep $rate;

done

