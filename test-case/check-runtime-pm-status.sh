#!/bin/bash

##
## Case Name: check-runtime-pm-status
## Preconditions:
##    N/A
## Description:
##    check the audio runtime pm status
## Case step:
##    1. start aplay/arecord
##    2. stop aplay/arecord
##    3. sleep for runtime pm transition time
##    4. check the runtime pm status
## Expect result:
##    command line check with $? without error
##    runtime pm status must be suspended
##    no error in dmesg
##

source $(dirname ${BASH_SOURCE[0]})/../case-lib/lib.sh

OPT_NAME['t']='tplg'     OPT_DESC['t']='tplg file, default value is env TPLG: $TPLG'
OPT_HAS_ARG['t']=1         OPT_VAL['t']="$TPLG"

OPT_NAME['l']='loop'     OPT_DESC['l']='loop count'
OPT_HAS_ARG['l']=1         OPT_VAL['l']=3

OPT_NAME['d']='delay'    OPT_DESC['d']='max delay time for state convert'
OPT_HAS_ARG['d']=1         OPT_VAL['d']=15

OPT_NAME['s']='sof-logger'   OPT_DESC['s']="Open sof-logger trace the data will store at $LOG_ROOT"
OPT_HAS_ARG['s']=0             OPT_VAL['s']=1

# param: $1 -> max delay time for dsp pm status switch
func_check_dsp_status()
{
    dlogi "wait dsp power status to become suspended"
    for i in $(seq 1 $1)
    do
        # Here we pass a hardcoded 0 to python script, and need to ensure
        # DSP is the first audio pci device in 'lspci', this is true unless
        # we have a third-party pci sound card installed.
        [[ $(sof-dump-status.py --dsp_status 0) == "suspended" ]] && break
        sleep 1
        if [ $i -eq $1 ]; then
            die "dsp is not suspended after $1s, end test"
        fi
    done
    dlogi "dsp suspended in ${i}s"
}

func_opt_parse_option "$@"
setup_kernel_check_point

tplg=${OPT_VAL['t']}
loop_count=${OPT_VAL['l']}

start_test

[[ -z $tplg ]] && die "Miss tplg file to run"

[[ $(sof-dump-status.py --dsp_status 0) == "unsupported" ]] &&
    skip_test "platform doesn't support runtime pm, skip test case"

declare -A APP_LST DEV_LST
APP_LST['playback']='aplay'
DEV_LST['playback']='/dev/zero'
APP_LST['capture']='arecord'
DEV_LST['capture']='/dev/null'

logger_disabled || func_lib_start_log_collect
func_pipeline_export "$tplg" "type:any"

for idx in $(seq 0 $(expr $PIPELINE_COUNT - 1))
do
    channel=$(func_pipeline_parse_value $idx channel)
    rate=$(func_pipeline_parse_value $idx rate)
    fmt=$(func_pipeline_parse_value $idx fmt)
    dev=$(func_pipeline_parse_value $idx dev)
    pcm=$(func_pipeline_parse_value $idx pcm)
    type=$(func_pipeline_parse_value $idx type)
    snd=$(func_pipeline_parse_value $idx snd)

    cmd="${APP_LST[$type]}"
    dummy_file="${DEV_LST[$type]}"
    [[ -z $cmd ]] && die "$type is not supported, $cmd, $dummy_file"

    for i in $(seq 1 $loop_count)
    do
        # set up checkpoint for each iteration
        setup_kernel_check_point
        dlogi "===== Iteration $i of $loop_count for $pcm ====="
        # playback or capture device - check status
        dlogc "$cmd -D $dev -r $rate -c $channel -f $fmt $dummy_file -q"
        $cmd -D $dev -r $rate -c $channel -f $fmt $dummy_file -q &
        pid=$!

        # TODO: delay 2.5s is workaround for the SSH aplay delay issue.
        sleep 2.5

        kill -0 $pid
        if [ $? -ne 0 ]; then
            func_lib_lsof_error_dump $snd
            die "$cmd process for pcm $pcm is not alive"
        fi

        [[ -d /proc/$pid ]] && result=`sof-dump-status.py --dsp_status 0`

        dlogi "runtime status: $result"
        if [[ $result == active ]]; then
            # stop playback or capture device - check status again
            dlogc "kill process: kill -9 $pid"
            kill -9 $pid && wait $pid 2>/dev/null
            dlogi "$cmd killed"
            func_check_dsp_status ${OPT_VAL['d']}
            result=`sof-dump-status.py --dsp_status 0`

            dlogi "runtime status: $result"
            if [[ $result != suspended ]]; then
                func_lib_lsof_error_dump $snd
                die "$cmd process for pcm $pcm runtime status is not suspended as expected"
            fi
        else
            dloge "$cmd process for pcm $pcm runtime status is not active as expected"
            # stop playback or capture device otherwise no one will stop this $cmd.
            dlogc "kill process: kill -9 $pid"
            kill -9 $pid && wait $pid 2>/dev/null
            func_lib_lsof_error_dump $snd
            exit 1
        fi
        # check kernel log for each iteration to catch issues
        sof-kernel-log-check.sh "$KERNEL_CHECKPOINT" || die "Caught error in kernel log"
    done
done
