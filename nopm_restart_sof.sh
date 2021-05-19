#!/bin/bash

set -e

mydir=$(cd $(dirname "$0") && /bin/pwd)

main()
{
    local logger_func="$1" # optionally started at the end

    kill_loggers

    reload_drivers

    # "on" means "always on" instead of "auto"
    # disable_all_pm
    # sudo journalctl -f -p 7 -g 'DSP'

    # disable_top_pm on

    hostname

    # start logger
    test -z "$logger_func" || (
#	sleep 1
        set -x
        "$logger_func"
    )
}


get_pci_id()
{
    # Better PCI "scan" in zephyr commit ed2d104baba9

    local pci_id_line
    # grep trigger set -e if nothing found
    pci_id_line=$("$mydir"/tools/sof-dump-status.py | grep '^PCI ID:')
    # Undefined behavior with multiple sounds cards
    printf '%s' "$pci_id_line" | awk '{ print $3 }'
}
# TODO: ACPI?


get_platform()
{
    "$mydir"/tools/sof-dump-status.py -p
    # works only when driver is loaded
#    readlink /sys/bus/*/drivers/sof-audio-*/*/driver | awk -F- '{ print $NF }'

}

kill_loggers()
{
    sudo killall sof-logger || true
    sudo pkill -f kernel/debug/sof
}

reload_drivers()
{
    # modprobe -r saves no time!

    # whole script as root: 3.2s
    # double sudo: 6.5. single low level sudo rmmod same
    time sudo "$mydir"/tools/kmod/sof_remove.sh

#    sleep 1

    # whole script as root: 0.7s
    # double sudo: 2.5s. single low level sudo modprobe same
    time sudo "$mydir"/tools/kmod/sof_insert.sh
}

# Wow, I never realized yet that
# /sys/devices/pci0000\:00/0000\:00\:0e.0/power/control is ON by default
# with Zephyr. Also, there's no way back: after loading Zephyr, when
# going back to XTOS then the DSP never goes to D3 again, not even when
# power/control lies and says auto

# "on" means "always on" instead of "auto"
disable_all_pm()
{
    local pci_id;    pci_id=$(get_pci_id) # typically: /sys/devices/pci0000:00/0000:00:13.1/power/control
    # find is overkill?
    find /sys/devices/pci0000:00/"${pci_id}" -name control | while read -r; do
        echo on | sudo tee "$REPLY" > /dev/null
    done
}

disable_top_pm()
{
    # APL = /sys/devices/pci0000\:00/0000\:00\:0e.0/power/control
    local pci_id;    pci_id=$(get_pci_id)
    echo "$1" |
        sudo tee /sys/devices/pci0000:00/"${pci_id}"/power/control > /dev/null
}

sof_zephyr_logger()
{
    sudo ~mherber2/bin/sof-logger  -l /lib/firmware/intel/sof/sof-$(get_platform).ldc -t -e 1 -f 0
}

# diagnostic driver?
old_zephyr_logger()
{
    sudo ~mherber2/zeproj/zephyr/boards/xtensa/intel_adsp_cavs15/tools/logtool.py
}

# old Andy mmap
oldnew_zephyr_logger()
{
    sudo ~mherber2/zeproj/zephyr/boards/xtensa/intel_adsp_cavs15/tools/adsplog.py
}

# game over, mtrace now
cavs_zephyr_logger()
{
#    sleep 2
#    sudo ~mherber2/zeproj/zephyr/soc/xtensa/intel_adsp/tools/cavstool.py --log-only
    sudo ~mherber2/bin/cavstool.py --log-only
}

# TODO:

mtrace_zephyr_logger()
{
    # on APL: No such file or directory: '/sys/kernel/debug/sof/mtrace/core0'
 exit 1

}

# ~/zeproj/zephyr/boards/xtensa/intel_adsp_cavs15/tools/adsplog.py

main "$@"
