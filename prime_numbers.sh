#! /bin/bash
start='date +"%H:%M:%S"'
fkey=0 #ключ на сохранение файла
hkey=0 #справка
vkey=0 #verbose mode
dkey=0 #debug mode
nkey=0 #Конечное число
mkey=0 #ключ для почты
fn=0 #Файл для записи
m=0 #E-mail

function usage {
	echo "-f - save to file(required filename)
-h - print help
-v - verbose mode
-m - send e-mail(required e-mail)
-d - debug mode
-n or -N - required parameter, limit of the prime numbers"
}

function main {
flag=0
i=2
while [ $i -le $nkey ]; do
	j=2
	flag=0
	while [ $j -lt $i ]; do
		if [ `expr $i % $j` -eq 0 ] ; then
			flag=1
			if [ $vkey -eq 1 ] ; then
				echo "$i is not prime. Divides by $j"
			fi
		fi
	let j=$j+1
	done
	if [ $flag -eq 0 ]
	then
		if [[ $fkey -eq 1 ]] ; then
			echo $i >> $fn
		else
			echo $i
			flag=0
		fi
	fi
	let i=$i+1
done
if [ $mkey -eq 1 ] ; then 
	echo "Script started at $start, 
	entered number: $nkey, result" | mail -s "Result of prime
	number script" $m
fi
}

while [ 1 ] ; do
	if [[ "$1" == "-n" || "$1" == "-N" ]] ; then
		shift ; nkey="$1"
	elif [[ "$1" == "-h" ]] ; then
		hkey=1	
	elif [[ "$1" == "-f" ]] ; then
		shift ; fkey=1 ; fn="$1" 
	elif [[ "$1" == "-d" ]] ; then
		dkey=1	
	elif [[ "$1" == "-v" ]] ; then
		vkey=1
	elif [[ "$1" == "-m" ]] ; then
		shift ; mail="$1" ; mkey=1 
	elif [ -z "$1" ] ; then
		break
	else
		echo "Error! Unknown key." 1>&2
		exit 1
	fi
	shift
done

if [[ $hkey -eq 1 || -z "nkey" ]] ; then
	usage
elif [ -z "$nkey" ] ; then
	echo "Error! You don't pass required parameter." 1>&2
	exit 1
else
	if [[ $dkey -eq 1 ]] ; then
		set -x
		main
	else 
		main
	fi
fi
