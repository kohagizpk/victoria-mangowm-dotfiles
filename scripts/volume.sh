#!/usr/bin/bash

function get_volume {
	pactl get-sink-volume @DEFAULT_SINK@ | awk '{printf $5}' | cut -d '%' -f 1
}

function is_mute {
	pactl get-sink-mute @DEFAULT_SINK@
}

function send_notification {

    overvolume=`get_volume`
    [[ $overvolume -gt 100 ]] && volume=100 || volume=$overvolume
    #Set correct icon
    if [[ $volume -eq 0 ]]
        then
            icon_name="${HOME}/.config/rice_assets/Icons/nov.png"
        elif [[ $volume -lt 35 ]] 
        then
            icon_name="${HOME}/.config/rice_assets/Icons/vlow.png"
        elif [[ $volume -lt 70 ]]
        then 
            icon_name="${HOME}/.config/rice_assets/Icons/vmid.png"
        elif [[ $volume -lt 100 ]]
        then 
            icon_name="${HOME}/.config/rice_assets/Icons/vhigh.png"
        else
            icon_name="${HOME}/.config/rice_assets/Icons/vthigh.png"
    fi;
    
                                                                                                         
    # Send the notification                                                      
    dunstify "Volume: $overvolume%" -h int:value:$volume -i /usr/share/icons/Adwaita/96x96/status/audio-volume-medium-symbolic.symbolic.png  -t 1000 --replace=555 -u normal
}

case $1 in
    up)
		swayosd-client --output-volume 5
	;;
    down)
		swayosd-client --output-volume -5
	;;
    mute)
    	# Toggle mute
	    pactl set-sink-mute @DEFAULT_SINK@ toggle > /dev/null
	    if [[ `is_mute` == "Mute: yes" ]] ; then
    		dunstify -i "${HOME}/.config/rice_assets/Icons/mute.png" --replace=555 -u normal "Volume: Mute" -t 1000 -u critical
	    else
	    	send_notification
	    fi
	;;
esac
