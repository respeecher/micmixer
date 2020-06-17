#!/bin/bash

# Copyright 2020 Respeecher
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#    http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# This simple script will hopefully get you stream your computer audio
# during voice chats

# define functions
function early_exit() {
    echo
    echo "Dang it! Alright then, see you soon."
    exit
}

function clean_up() {
    echo
    echo
    echo "Returning to default sinks and sources..."
    pacmd set-default-sink $(get_sink_id "${default_sink}")
    pacmd set-default-source $(get_source_id "${default_source}")
    echo "Unloading audio pipes..."
    pacmd unload-module ${lb1_mod}
    pacmd unload-module ${lb2_mod}
    pacmd unload-module ${lb3_mod}
    echo "Unloading virtual sinks..."
    pacmd unload-module ${vss_mod_id}
    pacmd unload-module ${mas_mod_id}
    
    if [ ! -z device_restore_disabled ]
    then
        echo "Re-enabling per-app default device feature..."
        enable_device_restore
    fi

    exit
}

function get_sink_mod_id() {
    echo $(pacmd list-sinks |
           grep -e "name:" -e "module:" |
           grep -A 2 -e "$1" |
           grep -e "module:" |
           awk -F": " '{print $2}')
}

function get_source_mod_id() {
    echo $(pacmd list-sources |
           grep -e "name:" -e "module:" |
           grep -A 2 -e "$1" |
           grep -e "module:" |
           awk -F": " '{print $2}')
}

function get_sink_id() {
    echo $(pactl list short sinks | grep "$1" | awk '{print $1}')
}

function get_source_id() {
    echo $(pactl list short sources | grep "$1" | awk '{print $1}')
}

function check_module() {
    if [ -z "$1" ]
    then
        echo
        echo "Error: something went wrong and we didn't get the module ID" \
            "from pulseaudio. Check the error above to see if anything can" \
            "be done about it. Aborting..."
        clean_up
    fi
}

function move_sink_users() {
    src_sink_id="$1"
    tgt_sink_id="$2"

    sink_users=$(\
        pactl list short sink-inputs |\
        awk '$2 == '"${src_sink_id}"' {print $1}')

    for u in $(echo -e "${sink_users}")
    do
        pactl move-sink-input $u $tgt_sink_id
    done
}

function move_source_users() {
    src_source_id="$1"
    tgt_source_id="$2"

    source_users=$(\
        pactl list short source-outputs |\
        awk '$2 == '"${src_source_id}"' {print $1}')

    for u in $(echo -e "${source_users}")
    do
        echo "User: $u; source: ${tgt_source_id}"
        pactl move-source-output $u $tgt_source_id
    done
}

function disable_device_restore() {
    has_restoring=$(pactl list short modules | grep module-stream-restore)
    if [ ! -z "$has_restoring" ]
    then
        pacmd unload-module module-stream-restore
        pacmd load-module module-stream-restore restore_device=false
        echo "disabled"
    fi
}

function enable_device_restore() {
    pacmd load-module module-stream-restore restore_device=true
}

# make sure we have pacmd
# credit: https://stackoverflow.com/a/677212
command -v pacmd >/dev/null 2>&1 || {
   echo >&2 "Couldn't find pacmd! Make sure you've got pulseaudio! Aborting.";
   exit 1;
}
command -v pavucontrol >/dev/null 2>&1 || {
   echo >&2 "Couldn't find pavucontrol! Please install pavucontrol because"\
            "you'll need it to use the virtual mic (unless you are a pacmd guru"\
            "of course, in which case you should just comment out this check"\
            "and run the script again. Aborting for now.";
   exit 1;
}

# obtain default sink and source
# credit: https://unix.stackexchange.com/a/251920
default_sink=$(pacmd stat | awk -F": " '/^Default sink name: /{print $2}')
default_sink_id=$(get_sink_id ${default_sink})
default_source=$(pacmd stat | awk -F": " '/^Default source name: /{print $2}')
default_source_id=$(get_source_id ${default_source})

trap early_exit INT
echo
echo "This is what I found on this machine:"
echo
echo -e "Default sink:\t\t${default_sink}"
echo -e "Default source:\t\t${default_source}"
echo 
read  -n 1 -p "If this looks good to you, hit Enter to proceed or ^C to exit:"
echo
echo "Awesome, let's go!"


# In general, we want to achieve mixing by implementing the following routing
# scheme:
#
#
# <app1> _____ [VirtualSystemSink] __loopback___> (System sink)
# <app2> ____/                     |
#  ...                             |__loopback__
#                                               \
# (System Source) ____________________loopback___> {mix} > [MicAndSystemSink]
#
#
# Playback apps should stream their outputs to VirtualSystemSink instead of the
# real one. In this case, if your target app uses the monitor of
# MicAndSystemSink instead of the real mic, it should be receiving a mix of
# system's default mic and whatever gets streamed to VirtualSystemSink.


# Create virtual sinks
echo
echo "Creating virtual sinks..."

echo "    Creating VirtualSystemSink..."
vss_mod_id=$(pactl load-module module-null-sink \
    sink_name=VirtualSystemSink \
    sink_properties=device.description=VirtualSystemSink)
check_module ${vss_mod_id}

echo "    Creating MicAndSystemSink..."
mas_mod_id=$(pactl load-module module-null-sink \
    sink_name=MicAndSystemSink \
    sink_properties=device.description=MicAndSystemSink)
check_module ${mas_mod_id}

# get ids for convenience
vss_id=$(get_sink_id VirtualSystemSink)
mas_id=$(get_sink_id MicAndSystemSink)
mas_mon_id=$(get_source_id MicAndSystemSink.monitor)

# set virtual sinks and sources as new defaults
echo
echo "Setting virtual sinks and sources as new defaults..."
pacmd set-default-sink "$vss_id"
pacmd set-default-source "$mas_mon_id"

# make sure newly started playback streams use the new default sink instead of
# what they are used to.
device_restore_disabled=$(disable_device_restore)

# Route virtual sinks and sources to the real ones
echo
echo "Creating audio pipes..."
echo "    Connecting VirtualSystemSink to the default system sink..."
lb1_mod=$(pactl load-module module-loopback \
    source=VirtualSystemSink.monitor \
    sink=${default_sink} \
    latency_msec=30 \
)
check_module ${lb1_mod}

echo "    Connecting VirtualSystemSink to MicAndSystemSink..."
lb2_mod=$(pactl load-module module-loopback \
    source=VirtualSystemSink.monitor \
    sink=MicAndSystemSink \
    latency_msec=30 \
)
check_module ${lb2_mod}

echo "    Connecting default mic to MicAndSystemSink..."
lb3_mod=$(pactl load-module module-loopback \
    source=${default_source} \
    sink=MicAndSystemSink \
    latency_msec=30 \
)
check_module ${lb3_mod}


trap clean_up INT
echo
echo "Wow, looks like it didn't crash!"
echo
echo "* * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *"
echo
echo "If you want to use this to mix in system sounds to your voice chat," \
     "do the following:"
echo "  * open the 'pavucontrol' GUI"
echo "  * go to the 'Recording' tab"
echo "  * find your browser's recording stream and select 'Monitor of" \
     "MicAndSystemSink' in the dropdown."
echo
echo "* * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *"
echo
echo

echo "Hope it works for you. Hit ^C to try to undo everything..."
sleep infinity
