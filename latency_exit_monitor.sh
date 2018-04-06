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
#Tis script monitors the exit latency of the differents C-state of the CPU of
#the system. Configuration are available is .cfg file

. ./latency_exit_monitor.cfg
if [ -r ~/.latency_exit_monitor.cfg ]; then
  . ~/.latency_exit_monitor.cfg
fi

# Create a Temp dir to save test and log files
ssh -p $PORT $TARGET 'rm -rf '"$TESTDIR"'' > /dev/null
ssh -p $PORT $TARGET 'mkdir -p '"$TESTDIR"'' > /dev/null

# Upload json file that will force all cpu to update with latest c-state changes
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
cp $JSONFILE latency-run.json

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


for PERIOD in $PERIODS; do

PREV=`cat latency-run.json | grep timer | awk '{ print $9 }' | sed s/,// | tail -n 1`
sed 's/"period" : '$PREV',/"period" : '$PERIOD',/' -i latency-run.json

scp -P $PORT latency-run.json $TARGET:$TESTDIR  > /dev/null

# Start tests loop
for j in `seq 1 $LOOP`; do
echo "cluster:"$CLUSTER" c-state:"$STATE" freq:"$FREQ" period:"$PERIOD" loop:"$j

ssh -p $PORT $TARGET 'sync'

sleep 1

ssh -p $PORT $TARGET 'cd '"$TESTDIR"'; sudo rt-app '"$TESTDIR"'latency-run.json 2> /dev/null'
#ssh -p $PORT $TARGET 'cd '"$TESTDIR"'; sudo  /home/linaro/power-tools/trace-activity.sh - latency "rt-app '"$TESTDIR"'latency-run.json 2> /dev/null" 2> /dev/null'  > /dev/null 

sleep 1

rm -rf ./latency-state$STATE-freq$FREQ-$PERIOD-$j
mkdir ./latency-state$STATE-freq$FREQ-$PERIOD-$j
scp -P $PORT  $TARGET:${TESTDIR}latency* ./latency-state$STATE-freq$FREQ-$PERIOD-$j/ >/dev/null

for i in `ls ./latency-state$STATE-freq$FREQ-$PERIOD-$j/latency-run-thread*`; do cat $i | head -n -1| sed '/wu_lat/d' | awk -v max=0 -v min=5000 '{ total += $11; total2 += $11*$11;  if($11>max){max=$11}; if($11<min){min=$11} } END { print min " " total/NR " " max " " NR " " sqrt(total2*NR - total*total)/NR}'; done

done

done

done

done

done
