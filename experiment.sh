#!/bin/bash -l
#SBATCH -A p2012172
#SBATCH -p node -N 0 -n 0
#SBATCH -t 00:00:00 

# Author: Amir Ghaffari

# @RELEASE project (http://www.release-project.eu/)

BwlfCluster=$1;
experiment=$2; 
Total_Nodes=$3; 
Number_of_VMs=$4

Start_Node=1;

Base_directory=`pwd`;

Original_Config_File="${Base_directory}/template.config";

Base_Result_directory="${Base_directory}/../results";

if [ ! -d "$Base_Result_directory" ]; then
	mkdir -p $Base_Result_directory;
fi

Erlang_path="/home/ag275/sderlang/bin";

if [ ! -d "$Base_directory" ]; then
	echo "Base Directory does not exist: $Base_directory"
	exit;
fi

cd $Base_directory;

if $BwlfCluster ; then
	let To_Node=$Start_Node+$Total_Nodes-1;
	Killing_nodes=$Total_Nodes;
	Node_Counter=0;
	for index in `seq $Start_Node $To_Node`; do 
			let Node_Counter=$Node_Counter+1;
			if [ "$index" -lt 10 ]
			then
				Hostnames[$Node_Counter]="bwlf0${index}.macs.hw.ac.uk";
				tempip=`ssh -q ${Hostnames[$Node_Counter]} "hostname -i;"`;
				IPaddresses[$Node_Counter]=$tempip;
			else
				Hostnames[$Node_Counter]="bwlf${index}.macs.hw.ac.uk";
				tempip=`ssh -q ${Hostnames[$Node_Counter]} "hostname -i;"`;
				IPaddresses[$Node_Counter]=$tempip;
			fi
	done
else
	for index in `seq 1 $Total_Nodes`; do 
		let zero_index=$index-1;
		Killing_nodes=0;
		tempip=`srun -r $zero_index  -N 1 -n 1 bash -c "hostname -i"`; 
		while [ -z "$tempip" ]; do
			sleep 1;
			tempip=`srun -r $zero_index  -N 1 -n 1 bash -c "hostname -i"`;
		done
		temphostname=`srun -r  $zero_index -N 1 -n 1 bash -c hostname`;
		while [ -z "$temphostname" ]; do
			sleep 1;
			temphostname=`srun -r  $zero_index -N 1 -n 1 bash -c hostname`;
		done
		IPaddresses[$index]=$tempip;
		Hostnames[$index]=$temphostname;

	done
fi

Number_of_Nodes=$Total_Nodes;
let Total_number_of_Erlang_Nodes=$Number_of_Nodes*$Number_of_VMs;

Config_file="bench.config";

for index in `seq 1 $Number_of_VMs`; do 
	VMs[$index]="node${index}@"
done

Output_file_name="${Base_Result_directory}/output_nodes_${Number_of_Nodes}_VMs_${Number_of_VMs}_Exp_${experiment}";
echo "Start at time :">$Output_file_name;
date +'%T'>>$Output_file_name;

for index in `seq 1 $Number_of_Nodes`; do 
	echo "IP is ${IPaddresses[$index]} and name is ${Hostnames[$index]} for index $index">>$Output_file_name;
done
echo "========================================================">>$Output_file_name;

Qoute_mark="'";
Comma_mark=",";
String_format_addresses="";

for index in `seq 1 $Number_of_Nodes`; do
	for counter in `seq 1 $Number_of_VMs`; do
		VMname=${VMs[$counter]}
		if [ $index -eq 1 -a $counter -eq 1 ]
		then
			String_format_addresses=${String_format_addresses}${Qoute_mark}${VMname}${Hostnames[$index]}${Qoute_mark}
		else
			String_format_addresses=${String_format_addresses}${Comma_mark}${Qoute_mark}${VMname}${Hostnames[$index]}${Qoute_mark}
		fi
	done
done

sed "s/Here_put_VMs_names/$String_format_addresses/g" $Original_Config_File>$Config_file;
echo "Name of VM nodes are: $String_format_addresses">>$Output_file_name;

for index in `seq 1 $Killing_nodes`; do 
	ssh -q ${IPaddresses[$index]} "
		echo '========================= killing (index=$index) ==================';
		pwd;
		hostname -i;
		hostname;
		date +'%T';
		echo 'befor kill=====';
		top -b -n 1 | grep beam.smp;
		pkill beam.smp;
		kill $(pgrep beam.smp);
		echo 'after kill=====';
		top -b -n 1 | grep beam.smp;
		echo 'time:';
		date +'%T';
		echo '===========================================';
	";
done
echo "==========================================After killing VMs">>$Output_file_name;
date +'%T'>>$Output_file_name;

./compile

for index in `seq 1 $Number_of_Nodes`; do 
	ssh -q ${IPaddresses[$index]} "
	echo '===========================================';
	PATH=$Erlang_path:$PATH;
	export PATH;
	echo 'Running Erlang VM on hostname and path at time:';
	pwd;
	hostname -i;
	hostname;
	date +'%T';
	for counter in {1..$Number_of_VMs}
	do
		cd ${Base_directory};
		echo '===============';
		VMname=\"node\${counter}@\";
		if [ ${index} -eq ${Number_of_Nodes} -a \${counter} -eq ${Number_of_VMs} ]
		then
			erl -noshell -name \${VMname}${Hostnames[${index}]} -run init_bench main -s init stop -pa ${Base_directory} -pa ${Base_directory}/ebin >>$Output_file_name
		else
			erl -detached -name \${VMname}${Hostnames[${index}]} -pa ${Base_directory} -pa ${Base_directory}/ebin 
		fi
	done

	top -b -n 1 | grep beam.smp;

	date +'%T';

	echo '===========================================';
	"
done


