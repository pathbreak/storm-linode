#!/bin/bash

PLAN_ID=1
DATACENTER="newark"
DISTRIBUTION=124
KERNEL=138
ROOT_PASSWORD="ClUsTeRMgR1!?"


create_cluster_manager_linode() {
	. $1
	
	local linout linerr linret
	
	echo "Creating linode"
	linode_api linout linerr linret "create-node" $PLAN_ID "$DATACENTER"
	if [ $linret -eq 1 ]; then
		echo "Failed to create temporary linode. Error:$linerr"
		return 1
	fi
	local linode_id=$linout

	# Create a disk from distribution.
	echo "Creating disk"
	linode_api linout linerr linret "create-disk-from-distribution" $linode_id "$DISTRIBUTION" \
		8000 "$ROOT_PASSWORD" ""
		
	if [ $linret -eq 1 ]; then
		echo "Failed to create disk. Error:$linerr"
		return 1
	fi
	local disk_id=$(echo $linout|cut -d ',' -f1)
	local create_disk_job_id=$(echo $linout|cut -d ',' -f2)
	
	local disk_result
	wait_for_job $create_disk_job_id $linode_id 
	disk_result=$?
	if [ $disk_result -eq 0 ]; then
		echo "Create disk did not complete even after 4 minutes. Aborting"
		return 1
	fi
	
	if [ $disk_result -ge 2 ]; then
		echo "Create disk failed."
		return 1
	fi
	
	# Create a configuration profile with that disk.
	echo "Creating a configuration"
	linode_api linout linerr linret "create-config" $linode_id "$KERNEL" \
		$disk_id "clustermgr-configuration"
	if [ $linret -eq 1 ]; then
		echo "Failed to create configuration. Error:$linerr"
		return 1
	fi
	local config_id=$linout

	echo "Creating private IP for linode"
	linode_api linout linerr linret "add-private-ip" $linode_id
	if [ $linret -eq 1 ]; then
		echo "Failed to add private IP address. Error:$linerr"
		return 1
	fi
	local private_ip=$linout
	echo "Private IP address $private_ip created for linode $linode_id"

	
	# Get public IP address of node.
	echo "Getting IP address of linode"
	linode_api linout linerr linret "public-ip" $linode_id
	if [ $linret -eq 1 ]; then
		echo "Failed to get IP address. Error:$linerr"
		return 1
	fi

	local public_ip=$linout
	echo "Public IP address: $public_ip"

	# Boot the linode.
	echo "Booting the linode"
	linode_api linout linerr linret "boot" $linode_id $config_id
	if [ $linret -eq 1 ]; then
		echo "Failed to boot. Error:$linerr"
		return 1
	fi
	local boot_job_id=$linout
	

	# Wait for node to boot up.
	local boot_result
	wait_for_job $boot_job_id $linode_id 
	boot_result=$?
	if [ $boot_result -eq 0 ]; then
		echo "Boot job did not complete even after 4 minutes. Aborting"
		return 1
	fi
	
	if [ $boot_result -ge 2 ]; then
		echo "Booting failed."
		return 1
	fi
	
	echo "Cluster manager node has booted. Public IP address: $public_ip"
}

setup_cluster_manager() {
	apt-get -y update
	apt-get -y upgrade
	
	apt-get -y install git python2.7 ssh wget
	
	# Create the 'clustermgr' user for running scripts.
	# It should be part of sudo because script should modify /etc/hosts of cluster manager node
	# Have to logout and login after adding to sudo to be able to use 'sudo' in commands.
	addgroup clustermgr
	adduser --ingroup clustermgr clustermgr
	adduser clustermgr sudo
	adduser clustermgr adm
	
	# Setup for git cloning from github (I think email should be setup)
	#git config --global user.email "you@example.com"
	#git config --global user.name "Your Name"
	
	# git clone
	cd /home/clustermgr
	git clone "https://github.com/pathbreak/storm-linode"
	
	cd storm-linode
	chmod +x *.sh *.py
	
	wget http://www.us.apache.org/dist/storm/apache-storm-0.9.5/apache-storm-0.9.5.tar.gz
	wget http://www.us.apache.org/dist/zookeeper/zookeeper-3.4.6/zookeeper-3.4.6.tar.gz
	
	mkdir -p /home/clustermgr/.ssh
	ssh-keygen -t rsa -b 4096 -q -f /home/clustermgr/.ssh/clusterroot -N ''
	ssh-keygen -t rsa -b 4096 -q -f /home/clustermgr/.ssh/clusteradmin -N ''
	
	chown -R clustermgr:clustermgr /home/clustermgr
}

# $1 -> name of variable which receives output of command
# $2 -> name of variable which receives stderr of command
# $3 -> name of variable which receives return code of command (0=success, >0 are failures)
# $4... -> arguments to linode_api.py
linode_api() {
	error_file=$(mktemp)
	
	# Important: Don't combine "local out=$(command)" into one line, because local acts as another command
	# and clobbers the command's return code.
	# as explained in http://stackoverflow.com/questions/4421257/why-does-local-sweep-the-return-code-of-a-command
	# and http://mywiki.wooledge.org/BashPitfalls#local_varname.3D.24.28command.29
	local __out
	__out=$(./linode_api.py "${@:4}" 2>$error_file)
	local __ret=$?
	local __err="$(< $error_file)"

	# The evaulated assignments are enclosed in "" by escaping with \"\" because
	# they may contain spaces and single/double quotes which makes bash think they are 
	# separate commands.
	eval $1="\"$__out\""
	eval $2="\"$__err\""
	eval $3="$__ret"
	
	rm $error_file
}


# $1 : The Job ID
# $2 : The linode ID
# Return: 	0 -> job remains pending even after timeout
#			1 -> job completed
#			2 -> job failed
#			3 -> could not get job status
wait_for_job() {
	
	local attempt=1
	local max_attempts=48 # Check every 10 seconds for upto 8 minutes
	local job_status=0 # Pending
	local linout linerr linret
	while [ $attempt -lt $max_attempts ]; do
		linode_api linout linerr linret "job-status" $2 $1
		if [ $linret -eq 1 ]; then
			echo "Failed to find job status. Error:$linerr"
			return 3
		fi
		
		if [ $linout -eq 1 ]; then
			# Job completed
			job_status=1
			break
		elif [ $linout -eq 2 ]; then
			# Job failed
			job_status=2
			break
		fi
		
		attempt=$((attempt+1))
		
		sleep 10
	done
	
	if [ $job_status -eq 0 ]; then
		echo "Job $1 did not complete even after 4 minutes. Aborting"
		
	elif [ $job_status -eq 2 ]; then
		echo "Job $1 failed. Error:$linerr"
	fi
	
	return $job_status
}

case $1 in
	create-linode)
	create_cluster_manager_linode $2
	;;

	setup)
	setup_cluster_manager
	;;
esac
