#!/bin/bash
echo "Size: $(du -sh . | awk '{print $1}')"
echo "Quantity: $(ls -al | grep -cvE "^(drw|total)") files"
echo "Duration: $(find -type f -name "*.mp3" -print0 | xargs -0 mplayer -vo dummy -ao dummy -identify 2>/dev/null | perl -nle '/ID_LENGTH=([0-9\.]+)/ && ($t +=$1) && printf "%02d:%02d:%02d\n",$t/3600,$t/60%60,$t%60' | tail -n 1)"
