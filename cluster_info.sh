#!/bin/bash

. ./textfileops.sh

list_clusters() {
	printf "\n\nClusters\n========\n\n"
	
	local files=$(ls -1 /home/clustermgr/storm-linode/)
	while read f
	do
		if [ ! -d "/home/clustermgr/storm-linode/$f" ]; then
			continue
		fi
		
		if [ ! -f "/home/clustermgr/storm-linode/$f/$f.conf" ]; then
			continue
		fi
		
		local stfile
		stfile=$(ls /home/clustermgr/storm-linode/$f/*.info 2>/dev/null)
		if [ $? -ne 0 ]; then
			continue
		fi
		
		grep -q 'nimbus' "$stfile"
		if [ $? -eq 0 ]; then
			printf "$f\t\t[Storm cluster]\n"
		
		else
			grep -q 'myids' "$stfile"
			if [ $? -eq 0 ]; then
				printf "$f\t\t[Zookeeper cluster]\n"
			fi
		fi
		
		
	done <<< "$files"
	
	printf "\n\n"
	
	return 0
}


# $1 : The directory basename of a storm cluster directory.
print_cluster_info() {
	if [ ! -d "/home/clustermgr/storm-linode/$1" ]; then
		echo "Error: $1 is not a Storm cluster directory"
		return 1
	fi
	
	if [ ! -f "/home/clustermgr/storm-linode/$1/$1.conf" ]; then
		echo "Error: $1 is not a Storm cluster directory"
		return 1
	fi
	
	local stfile
	stfile=$(ls /home/clustermgr/storm-linode/$1/*.info)
	if [ $? -ne 0 ]; then
		echo "$1 is not yet created"
		return 1
	fi

	grep -q 'nimbus' "$stfile"
	if [ $? -eq 0 ]; then
		print_storm_cluster_info "$stfile"
	else
		grep -q 'myids' "$stfile"
		if [ $? -eq 0 ]; then
			print_zk_cluster_info "$stfile"
		fi
	fi
	
	return 0
}

# $1 : A storm cluster .info file.
print_storm_cluster_info() {
	
	local stfile="$1"
	
	printf "\nStatus: $(get_section $stfile "status" | cut -d ':' -f2)\n\n"
	
	local nodes=$(get_section $stfile "nodes")
	local hostnames=$(get_section $stfile "hostnames")
	local ipaddrs=$(get_section $stfile "ipaddresses")

	local nimbus_linode_id=$(echo "$nodes"|grep 'nimbus'|cut -d ':' -f1)
	local nimbus_ipline=$(echo "$ipaddrs"|grep "$nimbus_linode_id")
	local nimbus_iparr=($nimbus_ipline)
	local nimbus_private_ip=${nimbus_iparr[1]}
	local nimbus_public_ip=${nimbus_iparr[2]}
	local nimbus_hostsline=$(echo "$hostnames"|grep "$nimbus_linode_id")
	local nimbus_hostsarr=($nimbus_hostsline)
	local nimbus_private_host=${nimbus_hostsarr[1]}
	local nimbus_public_host=${nimbus_hostsarr[2]}
		
	cat <<-ENDSTANZA
		Nimbus:
		  Linode ID:		$nimbus_linode_id
		  Private IP:		$nimbus_private_ip
		  Private hostname:	$nimbus_private_host
		  Public IP:		$nimbus_public_ip
		  Public hostname:	$nimbus_public_host
		  
	ENDSTANZA
	
	local client_linode_id=$(echo "$nodes"|grep 'client'|cut -d ':' -f1)
	local client_ipline=$(echo "$ipaddrs"|grep "$client_linode_id")
	local client_iparr=($client_ipline)
	local client_private_ip=${client_iparr[1]}
	local client_public_ip=${client_iparr[2]}
	local client_hostsline=$(echo "$hostnames"|grep "$client_linode_id")
	local client_hostsarr=($client_hostsline)
	local client_private_host=${client_hostsarr[1]}
	local client_public_host=${client_hostsarr[2]}
		
	cat <<-ENDSTANZA
		Client:
		  Linode ID:		$client_linode_id
		  Private IP:		$client_private_ip
		  Private hostname:	$client_private_host
		  Public IP:		$client_public_ip
		  Public hostname:	$client_public_host
		  
	ENDSTANZA

	echo 'Supervisors:'
	
	while read node;
	do
		local sup_linode_id=$(echo "$node"|cut -d ':' -f1)
		local sup_ipline=$(echo "$ipaddrs"|grep "$sup_linode_id")
		local sup_iparr=($sup_ipline)
		local sup_private_ip=${sup_iparr[1]}
		local sup_public_ip=${sup_iparr[2]}
		local sup_hostsline=$(echo "$hostnames"|grep "$sup_linode_id")
		local sup_hostsarr=($sup_hostsline)
		local sup_private_host=${sup_hostsarr[1]}
		local sup_public_host=${sup_hostsarr[2]}

		cat <<-ENDSTANZA
			  Linode ID:		$sup_linode_id
			  Private IP:		$sup_private_ip
			  Private hostname:	$sup_private_host
			  Public IP:		$sup_public_ip
			  Public hostname:	$sup_public_host
			  
		ENDSTANZA
	
	done <<< "$(echo "$nodes" | grep 'supervisor')"
	
	return 0
}

# $1 : A zookeeper cluster .info file.
print_zk_cluster_info() {
	
	local stfile="$1"
	
	printf "\nStatus: $(get_section $stfile "status" | cut -d ':' -f2)\n\n"
	
	local nodes=$(get_section $stfile "nodes")
	local hostnames=$(get_section $stfile "hostnames")
	local ipaddrs=$(get_section $stfile "ipaddresses")
	local zkids=$(get_section $stfile "myids")

	while read node;
	do
		local zk_linode_id=$(echo "$node")
		local zk_ipline=$(echo "$ipaddrs"|grep "$zk_linode_id")
		local zk_iparr=($zk_ipline)
		local zk_private_ip=${zk_iparr[1]}
		local zk_public_ip=${zk_iparr[2]}
		local zk_hostsline=$(echo "$hostnames"|grep "$zk_linode_id")
		local zk_hostsarr=($zk_hostsline)
		local zk_private_host=${zk_hostsarr[1]}
		local zk_public_host=${zk_hostsarr[2]}
		local zk_idline=$(echo "$zkids"|grep "$zk_linode_id")
		local zk_idarr=($zk_idline)
		local zk_id=${zk_idarr[1]}

		cat <<-ENDSTANZA
			  Linode ID:		$zk_linode_id
			  Private IP:		$zk_private_ip
			  Private hostname:	$zk_private_host
			  Public IP:		$zk_public_ip
			  Public hostname:	$zk_public_host
			  ZK ID:			$zk_id

		ENDSTANZA
	
	done <<< "$(echo "$nodes")"
	
	return 0
}

case $1 in
	list)
	list_clusters
	;;

	info)
	print_cluster_info $2
	;;
esac
