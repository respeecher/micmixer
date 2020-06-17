# micmixer
A simple script that creates a virtual microphone which adds
system sounds to your default mic output. This can be quite handy for
voice chats, if you want to share some audio samples or streams with your
buddies without muting yourself.

## Requirements
This is a Linux script so it probably won't work on other operting systems.
It also assumes that your system uses
[pulseaudio](https://www.freedesktop.org/wiki/Software/PulseAudio/) by
default. Most linux distros and applications do nowdays.

## Using the script
Run the script **as a regular user** and follow the instructions
```bash
$ chmod +x micmixer.sh  # if necessary
$ ./micmixer.sh
```
After you hit `^C` it will try to undo all the changes. Note that all the
changes made by this script are non-root and run-time (i.e. it doesn't
modify any config files). Therefore, in case anything goes wrong things
should get back to normal after a reboot or
```
$ killall pulseaudio
```
:)
