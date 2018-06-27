# power-tools

Power-tools is a bunch of scripts that are used to hel computing the parameters of c-state table of a platform.

The tool is made of 3 scripts that compute:
- exit latency of idle state: latency_exit_monitor.sh
- entry latency of idle state: latency_entry_monitor.sh
- residency time of idle state: residency_monitor.sh

The script use rt-app to generate scheduling pattern on the platform: https://github.com/scheduler-tools/rt-app

In orer to compute the residency time, you also need a power measurement probe. The residency_monitor.sh currently uses the arm-probe tool to get power consumption figures of the board: https://git.linaro.org/tools/arm-probe.git/

The configuration of the scripts for the target platform is done thanks to the .cfg file

More details about how to process of the results of the scripts are available in these video and slideset : http://connect.linaro.org/resource/hkg18/hkg18-111/
