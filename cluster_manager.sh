#!/bin/bash

# Set the root user password for cluster manager linode.
# It should contain at least two of these four character classes: 
# lower case letters - upper case letters - numbers - punctuation.
#
# Some special characters may require escape prefixing and the password to be enclosed in
# single or double quotes.
# Some examples:
# - for password with spaces, enclose in double quotes 
#		ROOT_PASSWORD="a PassworD with spaces"
#
# - for password with double quotes, enclose in double quotes and prefix every double quote in the password with a backslash \ : 
#		ROOT_PASSWORD="pswd_WITH_\"dbl\"_quotes"
#
# - for password with $, enclose in double quotes and prefix every $ in the password with a backslash \ : 
#		ROOT_PASSWORD="pswd_with_\$a_"
ROOT_PASSWORD=""

PLAN_ID=1
DATACENTER="newark"
DISTRIBUTION=124
KERNEL=138

# Set the default available ssh authentication mechanisms to log in to the cluster manager node.
# Password authentication is considered less secure, and hence disabled by default.
# 	'yes' disables password authentication and enables only public key authentication.
# 	'no' enables both public key and password authentication.
DISABLE_SSH_PASSWORD_AUTHENTICATION=yes

# The default Storm and Zookeeper download URLs.
STORM_URL='http://www.us.apache.org/dist/storm/apache-storm-0.9.5/apache-storm-0.9.5.tar.gz'
ZOOKEEPER_URL='http://www.us.apache.org/dist/zookeeper/zookeeper-3.4.7/zookeeper-3.4.7.tar.gz'

create_cluster_manager_linode() {
	. $1
	
	if [ "x$ROOT_PASSWORD" == "x" ]; then
		printf "Error: ROOT_PASSWORD for the cluster manager node is not set. \n \
		Open this file in an editor, set ROOT_PASSWORD='<a strong password>' and re-run this script.\n\n"
		return 1
	fi
	
	# Check if the Zookeeper and Storm packages are available, because sometimes releases are taken off the download
	# servers.
	local zk_url_check=$(curl -s -o /dev/null -I -w "%{http_code}" "$ZOOKEEPER_URL")
	if [ "$zk_url_check" == "404" ]; then
		echo "Error: The Zookeeper package $ZOOKEEPER_URL is no longer available. Open this file in an editor and change ZOOKEEPER_URL to an available package URL."
		return 1
	fi
	local storm_url_check=$(curl -s -o /dev/null -I -w "%{http_code}" "$STORM_URL")
	if [ "$storm_url_check" == "404" ]; then
		echo "Error: The Storm package $STORM_URL is no longer available. Open this file in an editor and change STORM_URL to an available package URL."
		return 1
	fi
	
	echo "Creating keypair for cluster manager root ssh authentication"
	ssh-keygen -t rsa -b 4096 -q -f $HOME/.ssh/clustermgrroot -N ''
	
	echo "Creating keypair for cluster manager clustermgr user ssh authentication"
	ssh-keygen -t rsa -b 4096 -q -f $HOME/.ssh/clustermgr -N ''
	
	echo "Creating keypair for cluster manager clustermgrguest user ssh authentication"
	ssh-keygen -t rsa -b 4096 -q -f $HOME/.ssh/clustermgrguest -N ''
	
	local linout linerr linret
	
	echo "Creating linode"
	linode_api linout linerr linret "create-node" $PLAN_ID "$DATACENTER"
	if [ $linret -eq 1 ]; then
		echo "Failed to create temporary linode. Error:$linerr"
		return 1
	fi
	local linode_id=$linout
	echo "Created cluster manager linode $linode_id"

	# Create a disk from distribution.
	echo "Creating disk"
	linode_api linout linerr linret "create-disk-from-distribution" $linode_id "$DISTRIBUTION" \
		8000 "$ROOT_PASSWORD" "$HOME/.ssh/clustermgrroot.pub"
		
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
	
	echo "Copying cluster_manager.sh to cluster manager node"
	scp -i "$HOME/.ssh/clustermgrroot" -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no 'cluster_manager.sh' \
		"root@$public_ip:cluster_manager.sh"
		
	echo "Running cluster_manager.sh setup on cluster manager node"
	ssh_command "$public_ip" "root" "$HOME/.ssh/clustermgrroot" "chmod ugo+x *.sh; ./cluster_manager.sh setup"

	echo "Copying clustermgr public key to cluster manager node"
	scp -i "$HOME/.ssh/clustermgrroot" -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no "$HOME/.ssh/clustermgr.pub" \
		"root@$public_ip:/home/clustermgr/.ssh/authorized_keys"
		
	ssh_command "$public_ip" "root" "$HOME/.ssh/clustermgrroot" "chmod go-w /home/clustermgr/.ssh/authorized_keys; chown clustermgr:clustermgr /home/clustermgr/.ssh/authorized_keys"
	
	echo "Copying clustermgrguest public key to cluster manager node"
	scp -i "$HOME/.ssh/clustermgrroot" -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no "$HOME/.ssh/clustermgrguest.pub" \
		"root@$public_ip:/home/clustermgrguest/.ssh/authorized_keys"
		
	ssh_command "$public_ip" "root" "$HOME/.ssh/clustermgrroot" "chmod go-w /home/clustermgrguest/.ssh/authorized_keys; chown clustermgrguest:clustermgrguests /home/clustermgrguest/.ssh/authorized_keys"
	
	# Cleanup:
	# We don't want to keep the cluster_manager.sh around, since it contains the root user password for the node.
	rm ./cluster_manager.sh
}

setup_cluster_manager() {
	apt-get -y update
	#apt-get -y upgrade
	
	apt-get -y install git python2.7 ssh wget sed
	
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
	
	wget "$STORM_URL"
	local storm_package_name=$(basename "$STORM_URL")
	sed -i -r "s|^INSTALL_STORM_DISTRIBUTION=.*\$|INSTALL_STORM_DISTRIBUTION=./$storm_package_name|" storm-image-example.conf
	
	wget "$ZOOKEEPER_URL"
	local zk_package_name=$(basename "$ZOOKEEPER_URL")
	sed -i -r "s|^INSTALL_ZOOKEEPER_DISTRIBUTION=.*\$|INSTALL_ZOOKEEPER_DISTRIBUTION=./$zk_package_name|" zk-image-example.conf
	
	mkdir -p /home/clustermgr/.ssh
	ssh-keygen -t rsa -b 4096 -q -f /home/clustermgr/.ssh/clusterroot -N ''
	ssh-keygen -t rsa -b 4096 -q -f /home/clustermgr/.ssh/clusteradmin -N ''
	
	chmod go-rwx /home/clustermgr/storm-linode/*
	chown -R clustermgr:clustermgr /home/clustermgr
	
	# Disable ssh password authentication.
	if [ "$DISABLE_SSH_PASSWORD_AUTHENTICATION" == "yes" ];  then
		echo "Disabling SSH password authentication"
		
		grep -q 'PasswordAuthentication yes$\|PasswordAuthentication no$' /etc/ssh/sshd_config
		if [ $? -eq 1 ]; then 
			echo 'PasswordAuthentication no' >> /etc/ssh/sshd_config
		else 
			sed -r -i '/PasswordAuthentication yes$|PasswordAuthentication no$/ c PasswordAuthentication no' /etc/ssh/sshd_config
		fi
		
		
		
	elif [ "$DISABLE_SSH_PASSWORD_AUTHENTICATION" == "no" ];  then
		echo "Enabling SSH password authentication"
		
		grep -q 'PasswordAuthentication yes$\|PasswordAuthentication no$' /etc/ssh/sshd_config
		if [ $? -eq 1 ]; then
			echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config
		else 
			sed -r -i '/PasswordAuthentication yes$|PasswordAuthentication no$/ c PasswordAuthentication yes' /etc/ssh/sshd_config
		fi
	fi
	
	service ssh restart

	# Create 'clustermgrguest' non-privileged user for devs  to get non-sensitive information about clusters,
	# such as client node IP addresses.
	addgroup clustermgrguests
	adduser --ingroup clustermgrguests clustermgrguest
	
	mkdir -p /home/clustermgrguest/storm-linode
	cp cluster_info.sh /home/clustermgrguest/storm-linode/
	cp textfileops.sh /home/clustermgrguest/storm-linode/
	chown -R clustermgrguest:clustermgrguests /home/clustermgrguest/
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

#	$1 -> IP address or hostname of node
#	$2 -> SSH login username for node
#	$3 -> SSH private key for node
#	$4... -> Command and paramters to send to remote server. 
#			 Either Redirection character (>) should be escaped with a backslash(\) (without
#			 the backslash, the redirection is attempted on the host machine instead of guest)
#			 Or instead of escaping, the command should be enclosed in a pair of '(...)'. That seems to work even with unescaped redirection.
ssh_command() {

	# IMPORTANT: The -n option is very important to avoid abruptly terminating callers who are in a "while read" loop. 
	# This is because ssh without -n option reads complete stdin by default,
	# as explained in http://stackoverflow.com/questions/346445/bash-while-read-loop-breaking-early
	# -n : avoid reading stdin by redirecting stdin from /dev/null
	# -x : disable X11 negotiation
	# -q : quiet
	ssh -q -n -x -i "$3" -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no $2@$1 "${@:4}"
}

case $1 in
	create-linode)
	create_cluster_manager_linode $2
	;;

	setup)
	setup_cluster_manager
	;;
esac
