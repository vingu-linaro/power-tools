#!/bin/bash - 
#Copyright (C) 2018  Vincent Guittot <vincent.guittot@linaro.org>
#
#This program is free software; you can redistribute it and/or
#modify it under the terms of the GNU General Public License
#as published by the Free Software Foundation; version 2
#of the License.
#
#This program is distributed in the hope that it will be useful,
#but WITHOUT ANY WARRANTY; without even the implied warranty of
#MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#GNU General Public License for more details.
#
#You should have received a copy of the GNU General Public License
#along with this program; if not, write to the Free Software
#Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
#
#Tis script monitors the residency time of the differents C-state of the CPU of
#the system. Configuration are available is .cfg file

. ./residency_monitor.cfg
if [ -r ~/.residency_monitor.cfg ]; then
  . ~/.residency_monitor.cfg
fi

ssh -p $PORT $TARGET 'rm -rf '"$TESTDIR"'' > /dev/null
ssh -p $PORT $TARGET 'mkdir -p '"$TESTDIR"'' > /dev/null

#upload json file that will force all cpu to update with latest c-state changes
scp -P $PORT static-run.json $TARGET:$TESTDIR  > /dev/null


for CLUSTER in $CLUSTER_LIST ; do

# Read config
var="LIST_$CLUSTER"
LIST=${!var}
var="FREQS_$CLUSTER"
FREQS=${!var}
var="MAX_$CLUSTER"
MAX=${!var}
var="JSON_$CLUSTER"
JSONFILE=${!var}

# Create rt-app test file
cp $JSONFILE residency-run.json

# Set to min (or max) freq all cpus
ssh -p $PORT $TARGET 'for i in '"$CPUS"'; do echo performance | sudo tee /sys/devices/system/cpu/cpu$i/cpufreq/scaling_governor; sleep 0.1; done;' > /dev/null
ssh -p $PORT $TARGET 'for i in '"$CPUS"'; do cat /sys/devices/system/cpu/cpu$i/cpufreq/scaling_min_freq | sudo tee /sys/devices/system/cpu/cpu$i/cpufreq/scaling_max_freq; sleep 0.1; done;' > /dev/null
#ssh -p $PORT $TARGET 'for i in '"$CPUS"'; do echo '"$MAX"' | sudo tee /sys/devices/system/cpu/cpu$i/cpufreq/scaling_max_freq; sleep 0.1; done;' > /dev/null
# Display freq all cpus
#ssh -p $PORT $TARGET 'for i in '"$CPUS"'; do echo "CPU"$i" freq"; cat  /sys/devices/system/cpu/cpu$i/cpufreq/scaling_cur_freq; done;'

# Disable all c-states on all cpus
ssh -p $PORT $TARGET 'for i in '"$CPUS"'; do for j in '"$STATES"' ; do  echo 1 | sudo tee /sys/devices/system/cpu/cpu$i/cpuidle/state$j/disable; sleep 0.1; done; done;' > /dev/null
# Enable only wfi on all cpus
ssh -p $PORT $TARGET 'for i in '"$CPUS"'; do for j in 0 ; do  echo 0 | sudo tee /sys/devices/system/cpu/cpu$i/cpuidle/state$j/disable; sleep 0.1; done; done;' > /dev/null
# Show c-states config of all cpus
#ssh -p $PORT $TARGET 'for i in '"$CPUS"'; do echo "CPU"$i ; for j in '"$STATES"' ; do echo "   state"$j; cat /sys/devices/system/cpu/cpu$i/cpuidle/state$j/disable; done; done;'


for FREQ in $FREQS; do

# Set target freq for target cpus
ssh -p $PORT $TARGET 'for i in '"$LIST"'; do echo '"$FREQ"' | sudo tee /sys/devices/system/cpu/cpu$i/cpufreq/scaling_max_freq; sleep 0.1; done;' > /dev/null
# Display freq target cpus
#ssh -p $PORT $TARGET 'for i in '"$LIST"'; do echo "CPU"$i" freq"; cat  /sys/devices/system/cpu/cpu$i/cpufreq/scaling_cur_freq; done;'


for STATE in $STATES; do

sleep 1

# Disable all c-states for target cpus
ssh -p $PORT $TARGET 'for i in '"$LIST"'; do for j in '"$STATES"' ; do  echo 1 | sudo tee /sys/devices/system/cpu/cpu$i/cpuidle/state$j/disable; sleep 0.1; done; done;' > /dev/null
# Enable target state for target cpus
ssh -p $PORT $TARGET 'for i in '"$LIST"'; do for j in '"$STATE"' ; do  echo 0 | sudo tee /sys/devices/system/cpu/cpu$i/cpuidle/state$j/disable; sleep 0.1; done; done;' > /dev/null
# Show state config
#ssh -p $PORT $TARGET 'for i in '"$LIST"'; do echo "CPU"$i ; for j in '"$STATES"' ; do echo "   state"$j; cat /sys/devices/system/cpu/cpu$i/cpuidle/state$j/disable; done; done;'

# Trig c-state change
ssh -p $PORT $TARGET 'sudo rt-app '"$TESTDIR"'static-run.json 2> /dev/null'

sleep 1

PERIOD=$PERIOD_INIT

while [ $PERIOD -ge $PERIOD_MIN ]; do

PREV=`cat latency-run.json | grep timer | awk '{ print $9 }' | sed s/,// | tail -n 1`
sed 's/"period" : '$PREV',/"period" : '$PERIOD',/' -i residency-run.json

scp -P $PORT residency-run.json $TARGET:$TESTDIR  > /dev/null

# Start tests loop
for j in `seq 1 $LOOP`; do
echo "cluster:"$CLUSTER" c-state:"$STATE" freq:"$FREQ" period:"$PERIOD" loop:"$j

ssh -p $PORT $TARGET 'sync'

sleep 1

#ssh -p $PORT $TARGET 'cd '"$TESTDIR"'; sudo rt-app '"$TESTDIR"'residency-run.json 2> /dev/null' &
ssh -p $PORT $TARGET 'cd '"$TESTDIR"'; sudo /home/linaro/power-tools/trace-activity.sh - residency "rt-app '"$TESTDIR"'residency-run.json 2> /dev/null" 2> /dev/null'  > /dev/null &

sleep 5

timeout -s TERM $DURATION arm-probe --config /home/vingu/Linaro/Boards/hikey/config-hikey960 -q 0 > $TMP 2> /dev/null

sleep 5

parse_aep.py -i $TMP | grep VDD_4V2 | awk '{ print $3" "$3/$9" "$9 }'

sleep 20

rm -rf ./residency-state$STATE-freq$FREQ-$PERIOD-$j
mkdir ./residency-state$STATE-freq$FREQ-$PERIOD-$j

scp -P $PORT  $TARGET:${TESTDIR}residency* ./residency-state$STATE-freq$FREQ-$PERIOD-$j/ >/dev/null
cp $TMP ./residency-state$STATE-freq$FREQ-$PERIOD-$j/

done

PERIOD=$(( $PERIOD - $STEP ))

done

done

done

done
