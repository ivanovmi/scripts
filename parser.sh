lkey= #уровень логирования(обязательный)
pkey= #номер процесса
dt= #начало/г-м-д(обязательный)
tt= #начало/ч:м(обязательный)
dT= #конец/г-м-д
tT= #конец/ч:м
fkey= #файл(обязательный)

d="$1" ; shift
 
while [ 1 ] ; do
	if [[ "$1" == "-l" ]] ; then
		shift ; lkey="$1"
	elif [[ "$1" == "-t" ]] ; then
		shift ; dt="$1" ; shift;  tt="$1"	
	elif [[ "$1" == "-f" ]] ; then
		shift ; fkey=1 ; fn="$1" 
	elif [[ "$1" == "-T" ]] ; then
		shift ; dT="$1" ; shift ; tT="$1" 
	elif [[ "$1" == "-p" ]]	; then
		shift ; pkey="$1"
	elif [ -z "$1" ] ; then
		break
	else
		echo "Error! Unknown key." 1>&2
		exit 1
	fi
	shift
done

touch $fn 2>/dev/null
if [[ $? == 0 ]] ; then
if [[ -z "$lkey" || -z "$fkey" || -z "$tt" || -z "$dt" ]] ; then
	
	echo "Error! You don't pass required parameter." 1>&2
	exit 1
else
	if [[ $fkey -eq 1 ]] ; then
		if [ -f $fn ] ; then
			rm -f $fn
		fi
	fi
	if [[ -n "$dT" || -n "$tT" ]] ; then
		if [[ -n "$pkey" ]] ; then
			awk "/$dt $tt/,/$dT $tT/" "$d"*.log | grep "$lkey" | grep "$pkey" >> "$fn"
		else
			awk "/$dt $tt/,/$dT $tT/" "$d"*.log | grep "$lkey"  >> "$fn"	
		fi	
	else
		if [[ -n "$pkey" ]] ; then
			awk "/$dt $tt/,/$(cat "$d"*.log | tail -1 | cut -d , -f1)/" "$d"*.log | grep "$lkey" | grep "$pkey" >> "$fn"
		else
			awk "/$dt $tt/,/$(cat "$d"*.log | tail -1 | cut -d , -f1)/" "$d"*.log | grep "$lkey" >> "$fn"
		fi
	fi
fi
else
	echo "The file was not created. Restart the script with the correct path."
fi
