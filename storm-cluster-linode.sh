# Prerequisites:
#	- ssh should be installed
#	- python2 should be installed (for JSON reading/writing)
#	- curl should be installed

. ./textfileops.sh

# Workaround to avoid "Agent admitted failure to sign using the key." ssh error despite
# using correct key, due to some conflict with gnone-keyring.
SSH_AUTH_SOCK=0
export SSH_AUTH_SOCK

# $1 -> Cluster name, or absolute or relative path of cluster directory, or
#		absolute or relative path of cluster conf file in cluster directory.
load_cluster_conf() {
	
	if [ -z "$1" ]; then
		echo "Error: Provide a cluster name or cluster directory path or cluster configuration file path"
		return 1
	fi
	
	local param_full_path=$(readlink -m "$1")
	
	if [ -d "$param_full_path" ]; then
		# Check that there is a $CLUSTER_NAME.conf in the directory and it is
		# a proper cluster conf.
		CLUSTER_NAME=$(basename "$param_full_path")
		CLUSTER_CONF_FILE="$param_full_path/$CLUSTER_NAME.conf"
		CLUSTER_CONF_DIR="$(dirname $CLUSTER_CONF_FILE)"
		
		if [ ! -f "$CLUSTER_CONF_FILE" ]; then
			echo "Error: '$1' does not seem to be a valid cluster name or cluster directory. Could not find cluster configuration file '$CLUSTER_CONF_FILE'"
			return 1
		fi
		
	elif [ -f "$param_full_path" ]; then
		# The given file may be any file at all, but what we want is a conf file with the correct cluster name.
		CLUSTER_NAME=$(basename $(dirname "$param_full_path"))
		CLUSTER_CONF_DIR=$(dirname "$param_full_path")
		CLUSTER_CONF_FILE="$CLUSTER_CONF_DIR/$CLUSTER_NAME.conf"
		
		local param_basename=$(basename "$param_full_path")
		if [ "$param_basename" != "$CLUSTER_NAME.conf" ]; then
			echo "Error: '$1' does not seem to be a valid cluster configuration filename. Expected cluster configuration filename '$CLUSTER_CONF_FILE'"
			return 1
		fi 
		
		if [ ! -f "$CLUSTER_CONF_FILE" ]; then
			echo "Error: Cluster configuration file '$CLUSTER_CONF_FILE' does not exist."
			return 1
		fi
		
	else
		echo "Error: '$param_full_path' does not exist."
		return 1
	fi


	# Absolute paths of this script's directory, and the image conf file's directory.
	SCRIPT_DIR="$(pwd)"
	
	echo "SCRIPT_DIR=$SCRIPT_DIR"
	echo "CLUSTER_NAME=$CLUSTER_NAME"
	echo "CLUSTER_CONF_DIR=$CLUSTER_CONF_DIR"
	echo "CLUSTER_CONF_FILE=$CLUSTER_CONF_FILE"
	
	# Include the cluster conf file
	source $CLUSTER_CONF_FILE



	# STORM_IMAGE_CONF may be a path that is relative to the cluster conf file, such
	# as "../storm-image1/storm-image1.conf" or "../storm-image1" or "/home/clustermgr/storm-linode/storm-image1"
	# We need to resolve it to its absolute path by prefixing it with  $CLUSTER_CONF_DIR
	# to get "$CLUSTER_CONF_DIR/../storm-image1/storm-image1.conf
	if [ -z "$STORM_IMAGE_CONF" ]; then
		echo "Error: STORM_IMAGE_CONF should be a Storm image directory or image configuration file"
		return 1
	fi
	
	local storm_image_conf
	if [ "${STORM_IMAGE_CONF:0:1}" == "/" ]; then
		# It's an absolute path. Retain as it is.
		storm_image_conf="$STORM_IMAGE_CONF"
	else
		# It's a relative path. Convert to absolute by prefixing with cluster conf dir.
		storm_image_conf="$(readlink -m $CLUSTER_CONF_DIR/$STORM_IMAGE_CONF)"
	fi
	
	if ! load_image_conf "$storm_image_conf"; then
		echo "Error: Change value of STORM_IMAGE_CONF to an existing Storm image directory or image configuration file path."
		return 1
	fi


	# We need Zookeeper cluster name as well as cluster directory for many operations in this script.
	# So validate the path pointed by ZOOKEEPER_CLUSTER.
	# ZOOKEEPER_CLUSTER may be a path that is relative to the cluster conf file, such
	# as "../zk-cluster1/zk-cluster1.conf" or "../zk-cluster1" or "/home/clustermgr/storm-linode/zk-cluster1"
	# We need to resolve it to its absolute path by prefixing it with  $CLUSTER_CONF_DIR
	# to get "$CLUSTER_CONF_DIR/../zk-cluster1/zk-cluster1.conf"
	if [ -z "$ZOOKEEPER_CLUSTER" ]; then
		echo "Error: ZOOKEEPER_CLUSTER should be a Zookeeper cluster directory or cluster configuration file"
		return 1
	fi
	
	local zk_cluster_conf="$ZOOKEEPER_CLUSTER"
	if [ "${ZOOKEEPER_CLUSTER:0:1}" != "/" ]; then
		# It's a relative path. Convert to absolute by prefixing with cluster conf dir.
		zk_cluster_conf="$(readlink -m $CLUSTER_CONF_DIR/$ZOOKEEPER_CLUSTER)"
	fi
	
	if ! load_zk_conf "$zk_cluster_conf"; then
		echo "Error: Change value of ZOOKEEPER_CLUSTER to an existing Zookeeper cluster directory or cluster configuration file path."
		return 1
	fi
	

	if ! validate_cluster_configuration; then
		return 1
	fi

	
	NODE_USERNAME=root
	if [ -z "$NODE_ROOT_SSH_PRIVATE_KEY" ]; then
		NODE_ROOT_SSH_PRIVATE_KEY=$IMAGE_ROOT_SSH_PRIVATE_KEY
	fi
	
	return 0
}


# $1 -> ZK cluster name, or absolute or relative path of cluster directory, or
#		absolute or relative path of cluster conf file in cluster directory.
load_zk_conf() {
	
	local param_full_path=$(readlink -m "$1")
	
	if [ -d "$param_full_path" ]; then
		# Check that there is a $CLUSTER_NAME.conf in the directory and it is
		# a proper cluster conf.
		ZK_CLUSTER_NAME=$(basename "$param_full_path")
		ZK_CLUSTER_CONF_FILE="$param_full_path/$ZK_CLUSTER_NAME.conf"
		ZK_CLUSTER_CONF_DIR="$(dirname $ZK_CLUSTER_CONF_FILE)"
		
		if [ ! -f "$ZK_CLUSTER_CONF_FILE" ]; then
			printf "Error: '$1' does not seem to be a valid Zookeeper cluster name or cluster directory\n."
			printf "Could not find cluster configuration file '$ZK_CLUSTER_CONF_FILE'\n"
			return 1
		fi
		
	elif [ -f "$param_full_path" ]; then
		# The given file may be any file at all, but what we want is a conf file with the correct cluster name.
		ZK_CLUSTER_NAME=$(basename $(dirname "$param_full_path"))
		ZK_CLUSTER_CONF_DIR=$(dirname "$param_full_path")
		ZK_CLUSTER_CONF_FILE="$ZK_CLUSTER_CONF_DIR/$ZK_CLUSTER_NAME.conf"
		
		local param_basename=$(basename "$param_full_path")
		if [ "$param_basename" != "$ZK_CLUSTER_NAME.conf" ]; then
			printf "Error: '$1' does not seem to be a valid Zookeeper cluster configuration filename.\n"
			printf "Expected cluster configuration filename '$ZK_CLUSTER_CONF_FILE'\n"
			return 1
		fi 
		
		if [ ! -f "$ZK_CLUSTER_CONF_FILE" ]; then
			echo "Error: Zookeeper Cluster configuration file '$ZK_CLUSTER_CONF_FILE' does not exist."
			return 1
		fi
		
	else
		echo "Error: Zookeeper Cluster configuration '$param_full_path' does not exist."
		return 1
	fi


	echo "ZK_CLUSTER_NAME=$ZK_CLUSTER_NAME"
	echo "ZK_CLUSTER_CONF_DIR=$ZK_CLUSTER_CONF_DIR"
	echo "ZK_CLUSTER_CONF_FILE=$ZK_CLUSTER_CONF_FILE"

	return 0
}



# $1 : Image name, or a target directory as absolute or relative path
create_new_image_conf() {
	
	if check_image_dir_exists "$1"; then
		echo "Validation error: Image '$1' already exists. Provide a unique name or directory."
		return 1
	fi
	
	echo "IMAGE_NAME=$IMAGE_NAME"
	if ! validate_image_name "$IMAGE_NAME"; then
		return 1
	fi
	
	mkdir -p "$1"
	
	cp storm-image-example.conf "$1/$IMAGE_NAME.conf"
	cp template-storm.yaml "$1/"
	cp template-storm-supervisord.conf "$1/"
	
	chmod go-rwx $1/*
	
	echo "Created image directory $1. "
	echo "Edit $1/$IMAGE_NAME.conf to enter mandatory properties, and then create the image with "
	echo "    storm-cluster-linode.sh create-image $1 <API-ENV-CONF-FILE>"
	
}



# 	$1 : Name of configuration file containing base node spec, template node spec, install flags and any other
#		 common configuration options.
#	$2 : Name of API environment configuration file containing API endpoint and key.
create_storm_image() {

	if ! load_image_conf "$1"; then
		return 1
	fi

	if ! load_api_env_configuration "$2"; then
		return 1
	fi
	
	NODE_USERNAME=root
	
	local stfile=$(image_status_file)
	if [ -f "$stfile" ]; then
		# Status file already exist, which means image is partially/fully created.
		echo "Image is already created or is being created. Nothing further to do..."
		return 1
	fi

	local linout linerr linret
	
	# There are limits on both number of images (max 3) and total size across
	# images (10240MB). If these limits are reached or close to breaching, warn user
	# and prevent disk imaging.
	echo "Image prechecks"
	linode_api linout linerr linret "imagestats"
	if [ $linret -eq 1 ]; then
		echo "Failed to get image statistics. Continuing, but there is a chance image creation may fail due to image count and disk size limits. Error:$linerr"
	else
		local num_images=$(echo $linout|cut -d ',' -f1)
		local total_image_size=$(echo $linout|cut -d ',' -f2)
		
		if [ $num_images -eq 3 ]; then
			printf "Error: Cannot create image because account limit of 3 images have already been created.\n"
			printf "Please delete an image using 'delete-image' or from 'Linode Manager' before retrying.\n"
			return 1
		fi
		
		if [ $total_image_size -ge 9000 ]; then
			printf "Warning: Total size of existing images $total_image_size MB is close to maximum limit of 10240 MB.\n"
			printf "There's a chance this image creation may fail.\n"
			printf "If it does, delete an existing image and try again.\n"
		fi
	fi

	create_image_status_file
	
	# Create temporary linode of lowest cost plan in specified datacenter.
	echo "Creating temporary linode"
	linode_api linout linerr linret "create-node" 1 "$DATACENTER_FOR_IMAGE"
	if [ $linret -eq 1 ]; then
		echo "Failed to create temporary linode. Error:$linerr"
		return 1
	fi
	local temp_linode_id=$linout
	echo "Created temporary linode $temp_linode_id"

	linode_api linout linerr linret "update-node" $temp_linode_id "stormtmp-$temp_linode_id" "temporary"
	if [ $linret -eq 1 ]; then
		echo "Failed to update node label $temp_linode_id. Error:$linerr"
		return 1
	fi

	# Create a disk from distribution.
	echo "Creating disk"
	linode_api linout linerr linret "create-disk-from-distribution" $temp_linode_id "$DISTRIBUTION_FOR_IMAGE" \
		$IMAGE_DISK_SIZE "$IMAGE_ROOT_PASSWORD" "$IMAGE_ROOT_SSH_PUBLIC_KEY"
		
	if [ $linret -eq 1 ]; then
		echo "Failed to create disk. Error:$linerr"
		return 1
	fi
	local disk_id=$(echo $linout|cut -d ',' -f1)
	local create_disk_job_id=$(echo $linout|cut -d ',' -f2)
	
	local disk_result
	wait_for_job $create_disk_job_id $temp_linode_id 
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
	linode_api linout linerr linret "create-config" $temp_linode_id "$KERNEL_FOR_IMAGE" \
		$disk_id "template-configuration"
	if [ $linret -eq 1 ]; then
		echo "Failed to create configuration. Error:$linerr"
		return 1
	fi
	local config_id=$linout

	
	# Boot the linode.
	echo "Booting the linode"
	linode_api linout linerr linret "boot" $temp_linode_id $config_id
	if [ $linret -eq 1 ]; then
		echo "Failed to boot. Error:$linerr"
		return 1
	fi
	local boot_job_id=$linout
	

	# Wait for node to boot up.
	local boot_result
	wait_for_job $boot_job_id $temp_linode_id 
	boot_result=$?
	if [ $boot_result -eq 0 ]; then
		echo "Boot job did not complete even after 4 minutes. Aborting"
		return 1
	fi
	
	if [ $boot_result -ge 2 ]; then
		echo "Booting failed."
		return 1
	fi
	
	
	# Get public IP address of node.
	echo "Getting IP address of linode"
	linode_api linout linerr linret "public-ip" $temp_linode_id
	if [ $linret -eq 1 ]; then
		echo "Failed to get IP address. Error:$linerr"
		return 1
	fi

	local ipaddr=$linout
	echo "IP address: $ipaddr"
	
	setup_users_and_authentication_for_image $ipaddr

	install_software_on_node $ipaddr $NODE_USERNAME

	install_storm_on_node $ipaddr $NODE_USERNAME

	# Shutdown the linode.
	echo "Shutting down the linode"
	linode_api linout linerr linret "shutdown" $temp_linode_id
	if [ $linret -eq 1 ]; then
		echo "Failed to shutdown. Error:$linerr"
		return 1
	fi
	local shutdown_job_id=$linout
	
	# Wait for linode to shutdown.
	local shutdown_result
	wait_for_job $shutdown_job_id $temp_linode_id 
	shutdown_result=$?
	if [ $shutdown_result -eq 0 ]; then
		echo "Shutdown job did not complete even after 4 minutes. Aborting"
		return 1
	fi
	
	if [ $shutdown_result -ge 2 ]; then
		echo "Shutdown failed."
		return 1
	fi
	
	
	# create image of the disk
	echo "Creating image of disk $disk_id"
	linode_api linout linerr linret "create-image" $temp_linode_id $disk_id "$LABEL_FOR_IMAGE"
	if [ $linret -eq 1 ]; then
		echo "Failed to create image of disk. Error:$linerr"
		return 1
	fi
	local image_id=$(echo $linout|cut -d ',' -f1)
	local image_disk_job_id=$(echo $linout|cut -d ',' -f2)
	
	local image_result
	wait_for_job $image_disk_job_id $temp_linode_id 
	image_result=$?
	if [ $image_result -eq 0 ]; then
		echo "Image job did not complete even after 4 minutes. Aborting"
		return 1
	fi
	
	if [ $image_result -ge 2 ]; then
		echo "Imaging failed."
		return 1
	fi
	echo "Template image $image_id successfully created"

	add_section $stfile "image"
	insert_bottom_of_section $stfile "image" "$image_id"
		
	# delete temporary linode. 'skipchecks' is 1 (true) because it's much 
	# easier than detaching disk from config and then deleting.
	echo "Deleting the temporary linode $temp_linode_id"
	linode_api linout linerr linret "delete-node" $temp_linode_id 1
	if [ $linret -eq 1 ]; then
		echo "Failed to delete temporary linode. Error:$linerr"
		return 1
	fi

	printf "\n\nFinished creating Storm template image $image_id\n"
	return 0
}



# 	$1 : Name of configuration file containing base node spec, template node spec, install flags and any other
#		 common configuration options.
#	$2 : Name of API environment configuration file containing API endpoint and key.
delete_storm_image() {

	if ! load_image_conf "$1"; then
		return 1
	fi

	if ! load_api_env_configuration "$2"; then
		return 1
	fi
	
	local stfile=$(image_status_file)
	if [ ! -f "$stfile" ]; then
		# Status file does not exist, which means image is probably not created.
		echo "Image does not exist. Nothing further to do..."
		return 1
	fi
	
	local image_id=$(get_section $stfile "image")
	echo "Deleting image $image_id"
	local linout linerr linret
	linode_api linout linerr linret "delete-image" $image_id
	if [ $linret -eq 1 ]; then
		echo "Failed to delete image $image_id. Error:$linerr"
		return 1
	fi
	
	rm -f "$stfile"

	printf "\n\nFinished deleting Storm image $image_id\n"
	return 0
}


# $1 : Cluster directory name
create_new_cluster_conf() {
	
	if check_cluster_dir_exists "$1"; then
		echo "Validation error: Cluster '$1' already exists. Provide a unique name or directory."
		return 1
	fi
	
	echo "CLUSTER_NAME=$CLUSTER_NAME"
	if ! validate_cluster_name "$CLUSTER_NAME"; then
		return 1
	fi
	
	mkdir -p "$1"
	
	cp storm-cluster-example.conf "$1/$CLUSTER_NAME.conf"
	chmod go-rwx "$1/$CLUSTER_NAME.conf"
	
	echo "Created cluster directory $1. "
	echo "Edit $1/$CLUSTER_NAME.conf to enter mandatory properties, and then create the cluster with "
	echo "    storm-cluster-linode.sh create $1 <API-ENV-CONF-FILE>"
	
}





# 	$1 : Name of cluster directory or Path of cluster configuration file.
#	$2 : The API environment configuration file
#	$3 : (Optional) If this is "--dontshutdown", then nodes are not stopped after creation. This option should be passed
#			only by start cluster. By default, nodes are shutdown after creation
create_cluster() {

	# Include the specified configuration file with cluster specific environment variables.
	if ! load_cluster_conf "$1"; then
		return 1
	fi
	
	if ! load_api_env_configuration "$2"; then
		return 1
	fi


	local stfile=$(status_file)
	if [ -f "$stfile" ]; then
		# Status file already exist, which means cluster is partially/fully created.
		echo "$CLUSTER_NAME is already created or is being created. Nothing further to do..."
		return 1
	fi

	echo "Creating storm cluster $CLUSTER_NAME..."

	# Some steps like hosts file distribution require hostnames and IP addresses of ZK nodes. If ZK cluster status file
	# does not exist, then create the cluster.
	# TODO handle zookeeper cluster creation errors better. Its possible outcomes are
	#	created | not created because it already exists | creation failed
	./zookeeper-cluster-linode.sh create "$ZK_CLUSTER_CONF_FILE" "$2"
	
	create_status_file

	update_cluster_status "creating"

	create_new_nodes $CLUSTER_NAME
	if [ $? -ne 0 ]; then
		echo "Node creation failed. Aborting"
		return 1
	fi

	start_nodes $CLUSTER_NAME
	if [ $? -ne 0 ]; then
		echo "Could not start all nodes. Aborting"
		return 1
	fi

	# Since nodes created from an image retain the image's host keys, they should
	# be changed to unique ones before doing anything else.
	change_hostkeys $CLUSTER_NAME

	set_hostnames $CLUSTER_NAME

	# Storm cluster nodes should know hostnames of all the ZK nodes too.
	distribute_hostsfile $CLUSTER_NAME
	
	# storm.yaml should contain nimbus hostname and list of all ZK nodes, and should be distributed to each node.
	create_storm_configuration $CLUSTER_NAME
	distribute_storm_configuration $CLUSTER_NAME

	# Install apache reverse proxy on client node. It should be under supervisor control (autostart)
	# This reverse proxy acts as a gateway to both the storm-ui web app and the logviewer URLs
	# of each supervisor node, which are served only via their private hostnames and hence not
	# accessible from developer/sysadmin machines outside the cluster.
	install_client_reverse_proxy $CLUSTER_NAME
	configure_client_reverse_proxy $CLUSTER_NAME
	
	# Configure firewall and security on all nodes.
	create_cluster_security_configurations $CLUSTER_NAME
	distribute_cluster_security_configurations $CLUSTER_NAME
	update_security_status "unchanged"
	
	# create may be called either independently or while starting cluster.
	# When called independently, after creation, we can shutdown all nodes.
	# When called by cluster startup, don't shutdown nodes since it's wasteful.
	if [ "$3" != "--dontshutdown" ]; then
		stop_nodes $CLUSTER_NAME
	fi

	update_cluster_status "created"
	
	echo "Storm cluster successfully created"
}





# 	$1 : Name of cluster directory or Path of cluster configuration file.
#	$2 : The API environment configuration file
start_cluster() {

	if ! load_cluster_conf "$1"; then
		return 1
	fi
	
	if ! load_api_env_configuration "$2"; then
		return 1
	fi

	echo "Starting Storm cluster $CLUSTER_NAME..."

	# If the cluster is not yet created, it should be first created along with all steps like 
	#	- getting IP addresses
	#	- setting hostnames
	#	- distributing hosts file
	#	- distributing zookeeper configurations
	#
	# If cluster is already created but not started, then all the above steps should be done, except setting hostnames - that's a creation only operation.
	#	
	# If cluster is already started, nothing to do.
	local stfile=$(status_file)
	if [ ! -f "$stfile" ]; then
		# Status file does not exist, which means cluster is not created.
		# So everything is done by create_cluster, and this function should just start storm service on all nodes.
		create_cluster "$1" "$2" "--dontshutdown"

	else
		local status=$(get_cluster_status)
		if [ "$status" == "running" ]; then
			echo "Cluster $CLUSTER_NAME is already running. Nothing further to do..."
			return 0

		elif [ "$status" == "creating" ]; then
			echo "Cluster $CLUSTER_NAME is currently being created. Please wait for it to be created and then run start..."
			return 1
	
		elif [ "$status" == "starting" ]; then
			echo "Cluster $CLUSTER_NAME is currently being started. Nothing further to do..."
			return 1
	

		elif [ "$status" == "stopping" ]; then
			echo "Cluster $CLUSTER_NAME is currently stopping. Please wait for it to stop and then run start..."
			return 1

		elif [ "$status" == "destroying" ]; then
			echo "Cluster $CLUSTER_NAME is currently being destroyed. Please wait for it to get destroyed and then run start or create..."
			return 1
		fi

		echo "Cluster already created. Starting it..."

		update_cluster_status "starting"
	
		./zookeeper-cluster-linode.sh start "$ZK_CLUSTER_CONF_FILE" "$2"
		
		start_nodes $CLUSTER_NAME
		
		# If nodes were added when cluster was stopped, we need all nodes
		# to know about all other nodes.
		distribute_hostsfile $CLUSTER_NAME
			
		# The cluster security configuration may have changed if nodes were added or 
		# admin updated the firewall rules while cluster was stopped.
		# If so, security configuration should  distributed.
		local security_status=$(get_security_status)
		if [ "$security_status" == "changed" ]; then
			echo "Security configuration has changed. Applying new configuration"
			
			# If any new supervisor nodes were added when cluster was stopped,
			# they have to be integrated with reverse web proxy running on client
			# node, to make their log files available via storm web UI.
			configure_client_reverse_proxy $CLUSTER_NAME
			
			distribute_cluster_security_configurations $CLUSTER_NAME
			
			update_security_status "unchanged"
		fi

		# The cluster storm configuration may have been changed by admin.
		# If so, it should  be distributed.
		local conf_status=$(get_conf_status)
		if [ "$conf_status" == "changed" ]; then
			echo "Storm configuration has changed. Applying new configuration"
			distribute_storm_configuration $CLUSTER_NAME
			
			update_conf_status "unchanged"
		fi
		
	fi
	
	# For newly created or restarted, we need to start the storm services.
	# storm.yaml need not be updated even if node IP addresses have changed, because it uses hostnames, not IP addresses.
	start_storm $CLUSTER_NAME

	update_cluster_status "running"

	echo "Storm cluster $CLUSTER_NAME is running"
	
	return 0
}



# 	$1 : Name of cluster directory or Path of cluster configuration file.
#	$2 : The API environment configuration file
stop_cluster() {

	if ! load_cluster_conf "$1"; then
		return 1
	fi
	
	if ! load_api_env_configuration "$2"; then
		return 1
	fi


	echo "Stopping cluster $CLUSTER_NAME..."

	update_cluster_status "stopping"

	# First stop storm services cleanly on all nodes, so that entire cluster can save whatever state it should.
	stop_storm $CLUSTER_NAME

	# Wait some time before stopping the nodes.
	sleep 20

	stop_nodes $CLUSTER_NAME

	update_cluster_status "stopped"
	
	echo "Storm cluster $CLUSTER_NAME is stopped"
}






# $1 : cluster name
create_new_nodes() {
	local linout linerr linret
	
	# Validate the datacenter.
	linode_api linout linerr linret "datacenter-id" "$DATACENTER_FOR_CLUSTER"
	if [ $linret -eq 1 ]; then
		echo "Failed to find datacenter. Error:$linerr"
		return 1
	fi
	local dc_id=$linout
	echo "Datacenter ID=$dc_id"
	
	# Get the image id from the image info file. If there is no image info file,
	# then try to find using API. 
	local img_stfile="$(image_status_file)"
	local image_id
	if [ -f "$img_stfile" ]; then
		image_id=$(get_section $img_stfile "image")
	fi
	
	if [ -z "$image_id" ]; then
		echo "Unable to get image ID from image info file. Searching for image using label..."
		linode_api linout linerr linret "image-id" "$LABEL_FOR_IMAGE"
		if [ $linret -eq 1 ]; then
			echo "Failed to find image. Error:$linerr"
			return 1
		fi
		image_id=$(echo $linout|cut -d ',' -f1)
	fi
	
	if [ -z "$image_id" ]; then
		echo "Failed to find image."
		return 1
	fi
	
	echo "Image ID=$image_id"
	
	# Get the kernel ID.
	linode_api linout linerr linret "kernel-id" "$KERNEL_FOR_IMAGE"
	if [ $linret -eq 1 ]; then
		echo "Failed to find kernel. Error:$linerr"
		return 1
	fi
	local kernel_id=$(echo $linout|cut -d ',' -f1)
	echo "Kernel ID=$kernel_id"
	
	local stfile="$(status_file)"
	add_section $stfile "nodes"
	add_section $stfile "ipaddresses"

	######################################################################################
	printf "\n\nCreating nimbus node in datacenter $dc_id based on image $image_id...\n"
	local nimbus_plan_id
	get_plan_id $NIMBUS_NODE
	nimbus_plan_id=$?
	if [ $nimbus_plan_id -eq -1 ]; then
		echo "Invalid plan $NIMBUS_NODE for Nimbus node. It should be one of 2GB|4GB|8GB|...|120GB.See https://www.linode.com/pricing for all plan names"
		return 1
	fi
	
	local nimbus_linode_id
	create_single_node $1 $nimbus_plan_id $dc_id $image_id $kernel_id nimbus_linode_id 'nimbus'
	if [ $? -eq 1 ]; then
		echo "Nimbus node creation failed. Aborting"
		return 1
	fi
	
	# We need to know role(nimbus/supervisor/client) of each node later on to build storm.yaml
	# start the correct services on each node.
	write_status "nodes" "$nimbus_linode_id:nimbus"
	#####################################################################################

	create_supervisor_nodes $1 $SUPERVISOR_NODES $dc_id $image_id $kernel_id
	if [ $? -eq 1 ]; then
		echo "Error during Supervisor nodes creation. Aborting"
		return 1
	fi

	#####################################################################################

	printf "\n\nCreating client node in datacenter $dc_id based on image $image_id...\n"
	local client_plan_id
	get_plan_id $CLIENT_NODE
	client_plan_id=$?
	if [ $client_plan_id -eq -1 ]; then
		echo "Invalid plan $CLIENT_NODE for client node. It should be one of 2GB|4GB|8GB|...|120GB.See https://www.linode.com/pricing for all plan names"
		return 1
	fi
	
	local client_linode_id
	create_single_node $1 $client_plan_id $dc_id $image_id $kernel_id client_linode_id 'client'
	if [ $? -eq 1 ]; then
		echo "Client node creation failed. Aborting"
		return 1
	fi
	
	write_status "nodes" "$client_linode_id:client"

	return 0
}


# $1 : Cluster name 
# $2 : Plan for supervisor nodes (ex: "2GB:1 4GB:1 8GB:1")
# $3 : Datacenter ID
# $4 : Image ID
# $5 : Kernel ID
# $6 : (Optional) Role suffix for the supervisor nodes. If not empty, it'll be appended as "supervisor:$6"
create_supervisor_nodes() {
	# Create the supervisor nodes.
	printf "\n\nCreating $2 new supervisor nodes...\n"

	local stfile="$(status_file)"

	local role="supervisor"
	if [ ! -z "$6" ]; then
		role="$role:$6"
	fi

	local total_sup_count=1
	for i in $2; do
		local plan=$(echo $i|cut -d ':' -f1)
		local count=$(echo $i|cut -d ':' -f2)
		
		local plan_id
		get_plan_id $plan
		plan_id=$?
		if [ $plan_id -eq -1 ]; then
			echo "Invalid plan $plan for supervisor nodes. It should be one of 2GB|4GB|8GB|...|120GB.See https://www.linode.com/pricing for all plan names"
			return 1
		fi

		echo "Creating $count supervisor linodes (plan $plan ID $plan_id)"

		local sup_node_count=1
		local supervisor_linode_id
		while [ $sup_node_count -le $count ]; do
			echo "Creating supervisor #$total_sup_count (plan $plan ID $plan_id)"
			create_single_node $1 $plan_id $3 $4 $5 supervisor_linode_id 'sup'
			if [ $? -eq 1 ]; then
				echo "Supervisor node creation failed. Aborting"
				return 1
			fi
			write_status "nodes" "$supervisor_linode_id:$role"
			sup_node_count=$((sup_node_count+1))
			total_sup_count=$((total_sup_count+1))
		done
	done
	
	return 0
}




# $1 : The plan name ("2GB | 4GB | 8GB ....")
get_plan_id() {
	local plan_id
	case $1 in
		"2GB")
			plan_id=1
			;;
			
		"4GB")
			plan_id=2
			;;
			
		"8GB")
			plan_id=4
			;;
			
		"12GB")
			plan_id=6
			;;
			
		"24GB")
			plan_id=7
			;;
			
		"48GB")
			plan_id=8
			;;
			
		"64GB")
			plan_id=9
			;;
			
		"80GB")
			plan_id=10
			;;				

		"120GB")
			plan_id=12
			;;
		
		*)
			plan_id=-1
			;;
	esac
	return $plan_id
}


# $1 : Cluster name 
# $2 : The Plan ID
# $3 : The datacenter ID (this has to be already validated by caller)
# $4 : The image ID
# $5 : The kernel ID
# $6 : Name of a variable that'll receive the created linode ID.
# $7 : Label prefix for linode
create_single_node() {
	local stfile="$(status_file)"
	
	local plan_id=$2
	local dc_id=$3
	local image_id=$4
	local kernel_id=$5
	
	# Create linode with specified plan and datacenter. The 0 at the end
	# avoids validating datacenter id for every iteration. 
	linode_api linout linerr linret "create-node" $plan_id $dc_id 0
	if [ $linret -eq 1 ]; then
		echo "Failed to create linode. Error:$linerr"
		return 1
	fi
	local __linode_id=$linout
	eval $6="$__linode_id"
	
	echo "Created linode $__linode_id"
	
	linode_api linout linerr linret "update-node" $__linode_id "$7-$__linode_id" "$CLUSTER_NAME"
	if [ $linret -eq 1 ]; then
		echo "Failed to update node label $__linode_id. Error:$linerr"
		return 1
	fi
	
	
	# Create a disk from distribution.
	echo "Creating disk from Storm image for linode $__linode_id"
	linode_api linout linerr linret "create-disk-from-image" $__linode_id $image_id \
		"Storm" $NODE_DISK_SIZE "$NODE_ROOT_PASSWORD" "$NODE_ROOT_SSH_PUBLIC_KEY"
		
	if [ $linret -eq 1 ]; then
		echo "Failed to create image. Error:$linerr"
		return 1
	fi
	local disk_id=$(echo $linout|cut -d ',' -f1)
	local create_disk_job_id=$(echo $linout|cut -d ',' -f2)
	
	local disk_result
	wait_for_job $create_disk_job_id $__linode_id 
	disk_result=$?
	if [ $disk_result -eq 0 ]; then
		echo "Create disk did not complete even after 4 minutes. Aborting"
		return 1
	fi
	
	if [ $disk_result -ge 2 ]; then
		echo "Create disk failed."
		return 1
	fi
	echo "Finished creating disk $disk_id from Storm image for linode $__linode_id"
	
	# Create a swap disk sized according to the linode's RAM.
	# The linode distributions are configured to expect /dev/sdb block device
	# as swap space. If a swap disk is not part of the configuration, everything
	# still succeeds but the dashboard shows a misconfiguration warning, and
	# performance may also suffer.
	echo "Creating swap disk"
	linode_api linout linerr linret "create-swap-disk" $__linode_id
		
	if [ $linret -eq 1 ]; then
		echo "Failed to create swap disk. Error:$linerr"
		return 1
	fi
	local swap_disk_id=$(echo $linout|cut -d ',' -f1)
	local create_swap_disk_job_id=$(echo $linout|cut -d ',' -f2)

	local disk_result
	wait_for_job $create_swap_disk_job_id $__linode_id
	disk_result=$?
	if [ $disk_result -eq 0 ]; then
		echo "Create swap disk did not complete even after 4 minutes. Aborting"
		return 1
	fi

	if [ $disk_result -ge 2 ]; then
		echo "Create swap disk failed."
		return 1
	fi
	
	# Create a configuration profile with that disk. The 0 at the end
	# avoids validating kernel id for every iteration. 
	echo "Creating a configuration"
	linode_api linout linerr linret "create-config" $__linode_id $kernel_id \
		"$disk_id,$swap_disk_id" "Storm-configuration" 0
	if [ $linret -eq 1 ]; then
		echo "Failed to create configuration. Error:$linerr"
		return 1
	fi
	local config_id=$linout
	echo "Finished creating configuration $config_id for linode $__linode_id"
	
	# Add a private IP for this linode.
	echo "Creating private IP for linode"
	linode_api linout linerr linret "add-private-ip" $__linode_id
	if [ $linret -eq 1 ]; then
		echo "Failed to add private IP address. Error:$linerr"
		return 1
	fi
	local private_ip=$linout
	echo "Private IP address $private_ip created for linode $__linode_id"

	# Get its public IP
	linode_api linout linerr linret "public-ip" $__linode_id
	if [ $linret -eq 1 ]; then
		echo "Failed to get public IP address. Error:$linerr"
		return 1
	fi
	local public_ip=$linout
	echo "Public IP address is $public_ip for linode $__linode_id"
	
	insert_or_replace_in_section $stfile "ipaddresses" $__linode_id "$__linode_id $private_ip $public_ip"
	return 0
}




# 	$1 : Name of cluster directory or Path of cluster configuration file.
#	$2 : The API environment configuration file
destroy_cluster() {

	if ! load_cluster_conf "$1"; then
		return 1
	fi
	
	if ! load_api_env_configuration "$2"; then
		return 1
	fi


	local stfile=$(status_file)

	update_cluster_status "destroying"

	local nodes=$(get_section $stfile "nodes")
	local failures=0
	while read nodeentry;
	do
		local arr=(${nodeentry//:/ })
		local node=${arr[0]}
		local role=${arr[1]}

		echo "Destroying $node..."

		# Shutdown the linode.
		echo "Shutting down the linode"
		linode_api linout linerr linret "shutdown" $node
		if [ $linret -eq 1 ]; then
			echo "Failed to shutdown. Error:$linerr"
			return 1
		fi
		local shutdown_job_id=$linout
		
		# Wait for linode to shutdown.
		local shutdown_result
		wait_for_job $shutdown_job_id $node 
		shutdown_result=$?
		if [ $shutdown_result -eq 0 ]; then
			echo "Shutdown job did not complete even after 4 minutes. Aborting"
			return 1
		fi
		
		if [ $shutdown_result -ge 2 ]; then
			echo "Shutdown failed."
			return 1
		fi
		
		sleep 2

		# Delete node (and skip checks)
		linode_api linout linerr linret "delete-node" $node 1
		if [ $linret -eq 1 ]; then
			echo "Failed to delete. Error:$linerr"
			failures=1
			continue
		fi

		# Remove entries for this node from all sections of status file
		delete_line $stfile "nodes" $node
		delete_line $stfile "ipaddresses" $node
		delete_line $stfile "hostnames" $node
	done <<< "$nodes"

	# Don't delete status file if there are any failures above
	if [ $failures -eq 0 ]; then	
		echo "Deleting cluster status file..."
		rm -f $stfile

		echo "Deleting cluster hosts file..."
		rm -f "$CLUSTER_CONF_DIR/$CLUSTER_NAME.hosts"

		echo "Deleting cluster storm yaml file..."
		rm -f "$CLUSTER_CONF_DIR/$CLUSTER_NAME.storm.yaml"
		
		echo "Deleting client proxy configuration file..."
		rm -f "$CLUSTER_CONF_DIR/$CLUSTER_NAME-stormproxy.conf"
		
		echo "Deleting security configuration files..."
		rm -f "$CLUSTER_CONF_DIR/$CLUSTER_NAME-rules.v6" 
		rm -f "$CLUSTER_CONF_DIR/$CLUSTER_NAME-rules.v4"
		rm -f "$CLUSTER_CONF_DIR/$CLUSTER_NAME-client-rules.v4"
		rm -f "$CLUSTER_CONF_DIR/$CLUSTER_NAME-rules.ipsets"  
		rm -f "$CLUSTER_CONF_DIR/$CLUSTER_NAME-whitelist.ipsets"
		rm -f "$CLUSTER_CONF_DIR/$CLUSTER_NAME-client-rules.ipsets"  
		rm -f "$CLUSTER_CONF_DIR/$CLUSTER_NAME-client-user-whitelist.ipsets"
		
		# Inform zookeeper cluster to remove this cluster's whitelist from its whitelists.
		# It expects the whitelist file path to be relative to scripts directory.
		local storm_cluster_whitelist_file="$(basename $CLUSTER_CONF_DIR)/$CLUSTER_NAME-whitelist.ipsets"
		./zookeeper-cluster-linode.sh "remove-whitelist" "$ZK_CLUSTER_CONF_FILE" "$storm_cluster_whitelist_file"

		# Delete the host entries from this cluster manager machine on which this script is running.
		echo $CLUSTER_MANAGER_NODE_PASSWORD|sudo -S sh hostname_manager.sh "delete-cluster" $CLUSTER_NAME
		
		echo "Storm cluster $CLUSTER_NAME is destroyed"
		
	else
		echo "Leaving cluster status file intact, because some nodes could not be destroyed"
	fi
}


#	$1: cluster name
#	$2: (Optional) filter for entries in "nodes" section. Only these nodes will be started.
start_nodes() {
	local stfile="$(status_file)"
	local nodes=$(get_section $stfile 'nodes')
	if [ ! -z "$2" ]; then
		nodes=$(echo "$nodes"|grep "$2")
	fi
	
	local boot_jobs=''
	
	while read nodeentry; do
		local node_arr=(${nodeentry//:/ })
		local node=${node_arr[0]}
		local role=${node_arr[1]}

		echo "Starting linode $node [$role]..."
		
		linode_api linout linerr linret "boot" $node
		if [ $linret -eq 1 ]; then
			echo "Failed to boot. Error:$linerr"
			return 1
		fi
		local boot_job_id=$linout
		boot_jobs="$boot_jobs $boot_job_id:$node"
	done <<< "$nodes"
	
	echo "Waiting for nodes to boot"
	
	for job in $boot_jobs
	do
		job_id=$(echo $job|cut -d':' -f1)
		linode_id=$(echo $job|cut -d':' -f2)
		
		# Wait for node to boot up.
		local boot_result
		wait_for_job $job_id $linode_id 
		boot_result=$?
		if [ $boot_result -eq 0 ]; then
			echo "Linode $linode_id did not boot up even after 4 minutes. Aborting"
			return 1
		fi
		
		if [ $boot_result -ge 2 ]; then
			echo "Linode $linode_id booting failed."
			return 1
		fi
	done
	
	echo "All nodes booted"
	
	return 0
}






#	$1 : Name of the cluster 
#	$2: (Optional) filter for entries in "nodes" section. Only these nodes will be stopped.
stop_nodes() {
	local stfile="$(status_file)"
	local nodes=$(get_section $stfile "nodes")
	if [ ! -z "$2" ]; then
		nodes=$(echo "$nodes"|grep "$2")
	fi


	local shutdown_jobs=''

	while read nodeentry;
	do
		local arr=(${nodeentry//:/ })
		local node=${arr[0]}
		
		echo "Shutting down $node"
		linode_api linout linerr linret "shutdown" $node
		if [ $linret -eq 1 ]; then
			echo "Failed to shutdown. Error:$linerr"
			return 1
		fi
		local shutdown_job_id=$linout
		shutdown_jobs="$shutdown_jobs $shutdown_job_id:$node"
	done <<< "$nodes"

	
	for job in $shutdown_jobs
	do
		job_id=$(echo $job|cut -d':' -f1)
		linode_id=$(echo $job|cut -d':' -f2)
		
		# Wait for node to boot up.
		local shutdown_result
		wait_for_job $job_id $linode_id 
		shutdown_result=$?
		if [ $shutdown_result -eq 0 ]; then
			echo "Linode $linode_id did not shutdown even after 4 minutes. Aborting"
			return 1
		fi
		
		if [ $shutdown_result -ge 2 ]; then
			echo "Linode $linode_id shutdown failed."
			return 1
		fi
	done
	
	return 0
	
}


#	$1 : Name of the cluster 
#	$2: (Optional) filter for entries in "nodes" section. Only these nodes' host keys will be regenerated.
change_hostkeys() {
	local stfile="$(status_file)"

	# Note: output of get_section is multiline, so always use it inside double quotes such as "$entries"
	local nodes=$(get_section $stfile "nodes")	
	if [ ! -z "$2" ]; then
		nodes=$(echo "$nodes"|grep "$2")
	fi
	local ipaddrs=$(get_section $stfile "ipaddresses")

	while read nodeentry; do
		# An entry in nodes section is of the form "nodename:role"
		local arr=(${nodeentry//:/ })
		local linode_id=${arr[0]}
		local role=${arr[1]}
		
		local private_ip=$(echo "$ipaddrs" | grep $linode_id | cut -d ' ' -f 2)
		local public_ip=$(echo "$ipaddrs" | grep $linode_id | cut -d ' ' -f 3)

		echo "Changing host keys of $linode_id..."

		# Default ssh target is the private IP address.
		local target_ip=$private_ip
		if [ "$CLUSTER_MANAGER_USES_PUBLIC_IP" == "true" ]; then
			target_ip=$public_ip
		fi

		ssh_command $target_ip $NODE_USERNAME $NODE_ROOT_SSH_PRIVATE_KEY "sh -c
			\"rm /etc/ssh/ssh_host_*;/usr/sbin/dpkg-reconfigure openssh-server\""
			
	done <<< "$nodes" # The "$nodes" should be in double quotes because output is multline
}



#	$1 : Name of the cluster 
#	$2: (Optional) filter for entries in "nodes" section. Only these nodes' hostnames will be changed.
set_hostnames() {
	local stfile="$(status_file)"

	add_section $stfile "hostnames"

	# Note: output of get_section is multiline, so always use it inside double quotes such as "$entries"
	local nodes=$(get_section $stfile "nodes")	
	if [ ! -z "$2" ]; then
		nodes=$(echo "$nodes"|grep "$2")
	fi
	local ipaddrs=$(get_section $stfile "ipaddresses")

	# If there are existing supervisor nodes, the hostname counter should start from last counter.
	local sup_node_counter=1
	local existing_hostnames=$(get_section $stfile "hostnames")
	local last_supervisor_hostname=$(echo "$existing_hostnames" | grep "$SUPERVISOR_NODES_PRIVATE_HOSTNAME_PREFIX" | tail -n1 | cut -d ' ' -f2)
	if [ ! -z "$last_supervisor_hostname" ]; then
		sup_node_counter=$(echo $last_supervisor_hostname|sed -r "s/$SUPERVISOR_NODES_PRIVATE_HOSTNAME_PREFIX//")
		sup_node_counter=$((sup_node_counter+1))
	fi

	local client_node_count=1

	while read nodeentry; do
		# An entry in nodes section is of the form "nodename:role"
		local arr=(${nodeentry//:/ })
		local linode_id=${arr[0]}
		local role=${arr[1]}
		
		local private_ip=$(echo "$ipaddrs" | grep $linode_id | cut -d ' ' -f 2)
		local public_ip=$(echo "$ipaddrs" | grep $linode_id | cut -d ' ' -f 3)


		local new_public_host_name
		local new_private_host_name
		if [ "$role" == "nimbus" ]; then
			new_public_host_name=$NIMBUS_NODE_PUBLIC_HOSTNAME
			new_private_host_name=$NIMBUS_NODE_PRIVATE_HOSTNAME

		elif  [ "$role" == "supervisor" ]; then		
			new_public_host_name=$SUPERVISOR_NODES_PUBLIC_HOSTNAME_PREFIX$sup_node_counter
			new_private_host_name=$SUPERVISOR_NODES_PRIVATE_HOSTNAME_PREFIX$sup_node_counter
			
			sup_node_counter=$((sup_node_counter+1))

		elif  [ "$role" == "client" ]; then		
			new_public_host_name=$CLIENT_NODES_PUBLIC_HOSTNAME_PREFIX$client_node_count
			new_private_host_name=$CLIENT_NODES_PRIVATE_HOSTNAME_PREFIX$client_node_count
			
			client_node_count=$((client_node_count+1))
		fi

		echo "Changing hostname of $linode_id [$private_ip] to $new_private_host_name..."

		# IMPORTANT: Anything that eventually calls ssh inside a while read loop should do so with ssh -n option
		# to avoid terminating the while read loop. This is because ssh without -n option reads complete stdin by default,
		# as explained in http://stackoverflow.com/questions/346445/bash-while-read-loop-breaking-early
		set_hostname $new_private_host_name $private_ip $new_public_host_name $public_ip $NODE_USERNAME $1
		
		# TODO Need to check if hostname change failed

		insert_or_replace_in_section $stfile "hostnames" $linode_id "$linode_id $new_private_host_name $new_public_host_name"

	done <<< "$nodes" # The "$nodes" should be in double quotes because output is multline
}


#	$1 -> New private hostname for linode
#	$2 -> private IP address or hostname of linode
#	$3 -> New public hostname for linode
#	$4 -> public IP address or hostname of linode
# 	$5 -> SSH login username for VM
# 	$6 -> Cluster name, which is added as separate section in /etc/hosts
set_hostname() {

	# For proper changing of hostname, the following order should be followed:
	# 1. Add entry in /etc/hosts
	# 2. Modify /etc/hostname
	# 3. Modify current session using "hostname" command
	# Create a temporary shell script which does these changes, scp it to remote machine, and run the script.
	# This approach is to avoid all the confusing shell escaping involved in direct ssh commands.
	
	# Default ssh target is the private IP address.
	local target_ip=$2
	if [ "$CLUSTER_MANAGER_USES_PUBLIC_IP" == "true" ]; then
		target_ip=$4
	fi
	remote_copyfile ./textfileops.sh $target_ip $5 $NODE_ROOT_SSH_PRIVATE_KEY textfileops.sh
	remote_copyfile ./hostname_manager.sh $target_ip $5 $NODE_ROOT_SSH_PRIVATE_KEY hostname_manager.sh

	# Just FYI: In case NOPSWD is not configured in /etc/sudoers, then "sudo sh" will fail 
	# with "sudo: no tty present and no askpass program specified"
	ssh_command $target_ip $5 $NODE_ROOT_SSH_PRIVATE_KEY sh hostname_manager.sh "change-hostname" $6 $2 $1 $4 $3

	check_hostname=$(ssh_command $target_ip $5 $NODE_ROOT_SSH_PRIVATE_KEY hostname)
	if [ "x$check_hostname" == "x$1" ]; then
		echo "Verified new hostname"
		return 0
	fi

	echo "Hostname has not changed. Check on remote machine"
	return 1
}





#	$1 : Name of the cluster 
distribute_hostsfile() {
	local stfile="$(status_file)"
	# Note: output of get_section is multiline, so always use it inside double quotes such as "$entries"
	local ipaddrs=$(get_section $stfile "ipaddresses")
	local hostnames=$(get_section $stfile "hostnames")

	local hostsfile="$CLUSTER_CONF_DIR/$1.hosts"
	touch $hostsfile
	chmod go-rwx $hostsfile
	# Empty host file if it exists.
	> $hostsfile

	# Form a hosts file for the cluster.
	# Distribute it to every node in cluster, along with
	# a script which inserts those entries into the node's /etc/hosts
	# as a section.
	while read hostentry;
	do
		# An entry in hostnames section is of the form "linode_id   private_hostname  public_hostname"
		local arr=($hostentry)
		local linode_id=${arr[0]}
		local private_host_name=${arr[1]}
		local public_host_name=${arr[2]}

		local private_ip=$(echo "$ipaddrs" | grep $linode_id | cut -d ' ' -f 2)
		local public_ip=$(echo "$ipaddrs" | grep $linode_id | cut -d ' ' -f 3)
		echo "Node:$linode_id , Private hostname:$private_host_name, private IP:$private_ip , Public hostname:$public_host_name, public IP:$public_ip"

		echo "$public_ip $public_host_name" >> $hostsfile
		echo "$private_ip $private_host_name" >> $hostsfile

	done <<< "$hostnames" # The "$entries" should be in double quotes because output is multline

	# We also need to distribute the zk cluster's hosts file to all storm nodes.
	# To find the ZK cluster name, we can't include it directly with "source" or "." because its variable names
	# will clash with same variable names in storm-cluster.conf.
	# So instead, we include it in a subshell and get its value using "sh -c". 
	# Since it's a subshell, it won't get variables defined in this shell such as $ZOOKEEPER_CLUSTER. So we pass
	# that as a variable assignment for the subshell.
	# For some reason, this
	# command works correctly when sh -c 'cmd' is in single quotes but not when it's in double quotes??
	local zkhostsfile="$ZK_CLUSTER_CONF_DIR/$ZK_CLUSTER_NAME.hosts"

	while read ipentry;
	do
		local arr=($ipentry)
		local linode_id=${arr[0]}
		local private_ip=${arr[1]}
		local public_ip=${arr[2]}
		
		# Default ssh target is the private IP address.
		local target_ip=$private_ip
		if [ "$CLUSTER_MANAGER_USES_PUBLIC_IP" == "true" ]; then
			target_ip=$public_ip
		fi
		
		echo "Distributing hosts file to linode:$linode_id, IP:$target_ip"

		# TODO Check how to copy multiple files. scp supports it as "scp localfile1 localfile2 .... user@dest:dir", but
		# remote_copyfile should be changed to handle these variable number of arguments.
		remote_copyfile ./textfileops.sh $target_ip $NODE_USERNAME $NODE_ROOT_SSH_PRIVATE_KEY textfileops.sh
		remote_copyfile ./hostname_manager.sh $target_ip $NODE_USERNAME  $NODE_ROOT_SSH_PRIVATE_KEY hostname_manager.sh
		
		remote_copyfile $hostsfile $target_ip $NODE_USERNAME $NODE_ROOT_SSH_PRIVATE_KEY  "$1.hosts"
		remote_copyfile $zkhostsfile $target_ip $NODE_USERNAME $NODE_ROOT_SSH_PRIVATE_KEY  "$ZK_CLUSTER_NAME.hosts"

		ssh_command $target_ip $NODE_USERNAME $NODE_ROOT_SSH_PRIVATE_KEY sh hostname_manager.sh "hosts-file" $1 "$1.hosts"
		ssh_command $target_ip $NODE_USERNAME $NODE_ROOT_SSH_PRIVATE_KEY sh hostname_manager.sh "hosts-file" $ZK_CLUSTER_NAME "$ZK_CLUSTER_NAME.hosts"
		
	done <<< "$ipaddrs"

	# Add the host entries to this very cluster manager machine on which this script is running.
	echo $CLUSTER_MANAGER_NODE_PASSWORD|sudo -S sh hostname_manager.sh "hosts-file" $1 $hostsfile
}



# $1 : IP address of node
setup_users_and_authentication_for_image() {
	# Enable or disable password authentication for ssh.
	if [ "$IMAGE_DISABLE_SSH_PASSWORD_AUTHENTICATION" == "yes" ];  then
		echo "Disabling SSH password authentication"
		
		ssh_command $1 $NODE_USERNAME $IMAGE_ROOT_SSH_PRIVATE_KEY "sh -c
			\"grep -q 'PasswordAuthentication yes$\|PasswordAuthentication no$' /etc/ssh/sshd_config; 
			if [ $? -eq 1 ]; then 
				echo 'PasswordAuthentication no' >> /etc/ssh/sshd_config ;
			else 
				sed -r -i '/PasswordAuthentication yes$|PasswordAuthentication no$/ c PasswordAuthentication no' /etc/ssh/sshd_config ;
			fi\""
		
		ssh_command $1 $NODE_USERNAME $IMAGE_ROOT_SSH_PRIVATE_KEY "service ssh restart"
		
	elif [ "$IMAGE_DISABLE_SSH_PASSWORD_AUTHENTICATION" == "no" ];  then
		echo "Enabling SSH password authentication"
		
		ssh_command $1 $NODE_USERNAME $IMAGE_ROOT_SSH_PRIVATE_KEY "sh -c
			\"grep -q 'PasswordAuthentication yes$\|PasswordAuthentication no$' /etc/ssh/sshd_config; 
			if [ $? -eq 1 ]; then 
				echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config ;
			else 
				sed -r -i '/PasswordAuthentication yes$|PasswordAuthentication no$/ c PasswordAuthentication yes' /etc/ssh/sshd_config ;
			fi\""
		
		ssh_command $1 $NODE_USERNAME $IMAGE_ROOT_SSH_PRIVATE_KEY "service ssh restart"
			
	else
		echo "Unknown value '$IMAGE_DISABLE_SSH_PASSWORD_AUTHENTICATION' for IMAGE_DISABLE_SSH_PASSWORD_AUTHENTICATION. Leaving defaults unchanged."
	fi
	
	# Since SSH's been restarted wait for sometime before trying next SSH command. Otherwise next ssh/scp command sometimes fails.
	# Also on production Linode, SSH service may take upto 60-80 seconds to become available again after restart. So keep trying
	# to SSH until it succeeds.
	sleep 20
	
	local max_checks=24
	local wait_between_checks=10
	local check_count=1
	local ssh_available=0
	while [ $check_count -le $max_checks ]; do
		ssh_command $1 $NODE_USERNAME $IMAGE_ROOT_SSH_PRIVATE_KEY echo
		if [ $? -eq 0 ]; then
			echo "SSH is available after restart"
			ssh_available=1
			break
		fi
		check_count=$((check_count+1))
		echo "Waiting for SSH to be available"
		sleep $wait_between_checks
	done
	if [ $ssh_available -eq 0 ]; then
		echo "SSH is still not available after $((max_checks*wait_between_checks/60)) minutes. Aborting image creation"
		return 1
	fi	
	
	# Create IMAGE_ADMIN_USER as part of sudo group with password IMAGE_ADMIN_PASSWORD
	if [ ! -z "$IMAGE_ADMIN_USER" ];  then
		if [ "$IMAGE_ADMIN_USER" != "root" ]; then
			echo "Creating admin user $IMAGE_ADMIN_USER"
			
			ssh_command $1 $NODE_USERNAME $IMAGE_ROOT_SSH_PRIVATE_KEY \
				"adduser --gecos '' $IMAGE_ADMIN_USER; sleep 5; adduser $IMAGE_ADMIN_USER sudo; 
				echo $IMAGE_ADMIN_USER:$IMAGE_ADMIN_PASSWORD|chpasswd"


			# Configure public key authentication for IMAGE_ADMIN_USER.
			if [ ! -z "$IMAGE_ADMIN_SSH_AUTHORIZED_KEYS" ]; then
				if [ -f "$IMAGE_ADMIN_SSH_AUTHORIZED_KEYS" ]; then
					ssh_command $1 $NODE_USERNAME $IMAGE_ROOT_SSH_PRIVATE_KEY \
						mkdir -p "/home/$IMAGE_ADMIN_USER/.ssh"
						
					remote_copyfile $IMAGE_ADMIN_SSH_AUTHORIZED_KEYS $1 $NODE_USERNAME \
						$IMAGE_ROOT_SSH_PRIVATE_KEY "/home/$IMAGE_ADMIN_USER/.ssh/authorized_keys"
			
					ssh_command $1 $NODE_USERNAME $IMAGE_ROOT_SSH_PRIVATE_KEY \
						chown "$IMAGE_ADMIN_USER:$IMAGE_ADMIN_USER" "/home/$IMAGE_ADMIN_USER/.ssh/authorized_keys"
				fi
			fi
		fi
	fi
	
	# Create zookeeper user and group.
	if [ "$STORM_USER" != "root" ]; then
		echo "Creating user $STORM_USER:$STORM_USER"
		local install_dir=$(storm_install_dir)
		# --group automatically creates a system group with same name as username.
		# --gecos "" is to prevent the interactive prompting for full name and other details.
		ssh_command $1 $NODE_USERNAME $IMAGE_ROOT_SSH_PRIVATE_KEY \
			adduser --system --group --home $install_dir --no-create-home \
				--shell /bin/sh --gecos "" --disabled-password --disabled-login $STORM_USER
	fi
	
}




# $1 : IP address of node
# $2 : SSH username for node
install_software_on_node() {

	# Update repo information before installing.
	ssh_command $1 $2 $IMAGE_ROOT_SSH_PRIVATE_KEY apt-get -y update
	
	if [ "$UPGRADE_OS" == "yes" ]; then
		echo "Upgrading OS on $1..."

		ssh_command $1 $2 $IMAGE_ROOT_SSH_PRIVATE_KEY apt-get -y upgrade
	else	
		echo "Not upgrading OS on $1..."
	fi



	echo "Installing OpenJDK JRE 7 on $1..."
	ssh_command $1 $2 $IMAGE_ROOT_SSH_PRIVATE_KEY apt-get -y install "openjdk-7-jre-headless"



	echo "Installing Python 2.7 on $1..."
	ssh_command $1 $2 $IMAGE_ROOT_SSH_PRIVATE_KEY apt-get -y install "python2.7"



	echo "Installing Supervisord on $1..."
	ssh_command $1 $2 $IMAGE_ROOT_SSH_PRIVATE_KEY apt-get -y install supervisor


		
	# We want to insert correct values for environment variables in the image's supervisord.conf file.
	# So create a copy of the supervisord template specified in image conf, and do the replacement in the copy.
	local template_supervisord_conf="$SUPERVISORD_TEMPLATE_CONF"
	if [ "${template_supervisord_conf:0:1}" != "/" ]; then
		template_supervisord_conf=$(readlink -m "$IMAGE_CONF_DIR/$SUPERVISORD_TEMPLATE_CONF")
	fi
	local image_supervisord_conf="$IMAGE_CONF_DIR/storm-supervisord.conf"
	cp "$template_supervisord_conf" "$image_supervisord_conf"
		
	# Replace occurrences of $STORM_USER with its value. The sed is not passed with -r because $ is special
	# character meaning beginning of line in a regex. Not sure how exactly to escape a $ when using -r...\$ didn't work.
	sed -i "s/\$STORM_USER/$STORM_USER/g" $image_supervisord_conf

	# Replace STORM_INSTALL_DIR with the absolute directory path of storm home.
	local install_dir=$(storm_install_dir)
	# Since install_dir value will have / slashes, we use | as the sed delimiter to avoid sed errors.
	sed -i "s|\$STORM_INSTALL_DIR|$install_dir|g" $image_supervisord_conf

	remote_copyfile $image_supervisord_conf $1 $2 $IMAGE_ROOT_SSH_PRIVATE_KEY "/etc/supervisor/conf.d/storm-supervisord.conf"

	# From https://github.com/Supervisor/supervisor/blob/master/supervisor/supervisorctl.py, supervisor update 
	# first does the same thing as a reread and then restarts changed programs. So despite what many discussions 
	# say, there's no need to first reread and then update.
	ssh_command $1 $2 $IMAGE_ROOT_SSH_PRIVATE_KEY "supervisorctl update"
	

	# Install packages required for iptables firewall configuration.
	# The debconf commands are because iptables-persistent asks interactively to save
	# existing rules during installation.
	# kmod is required because /sbin/modprobe is not part of Linode's Debian distro.
	echo "Installing kmod,ipset and iptables-persistent"
	ssh_command $1 $2 $IMAGE_ROOT_SSH_PRIVATE_KEY sh -c \
		"\"DEBIAN_FRONTEND=noninteractive; export DEBIAN_FRONTEND;
		echo iptables-persistent iptables-persistent/autosave_v4 boolean false | debconf-set-selections;
		echo iptables-persistent iptables-persistent/autosave_v6 boolean false | debconf-set-selections;
		apt-get -y install kmod ipset iptables-persistent\""
	
	# Replace the package's init script with the one from 
	remote_copyfile "iptables-persistent" $1 $2 $IMAGE_ROOT_SSH_PRIVATE_KEY '~/iptables-persistent'
	
	#ssh_command $1 $2 $IMAGE_ROOT_SSH_PRIVATE_KEY sudo cp /etc/init.d/iptables-persistent /etc/init.d/iptables-persistent.original
	#remote_copyfile "iptables-persistent" $1 $2 $IMAGE_ROOT_SSH_PRIVATE_KEY /etc/init.d/iptables-persistent
	#ssh_command $1 $2 $IMAGE_ROOT_SSH_PRIVATE_KEY sudo chmod +x /etc/init.d/iptables-persistent
	
	#ssh_command $1 $2 $IMAGE_ROOT_SSH_PRIVATE_KEY sudo update-rc.d iptables-persistent enable
	
	#ssh_command $1 $2 $IMAGE_ROOT_SSH_PRIVATE_KEY sudo /etc/init.d/iptables-persistent save
	#ssh_command $1 $2 $IMAGE_ROOT_SSH_PRIVATE_KEY sudo /etc/init.d/iptables-persistent start
	
	# On Debian 8 + systemd, 'apt-get install iptables-persistent' no longer installs
	# "iptables-persistent" script but instead calls it "/usr/bin/netfilter-persistent".
	# A wrapper which calls "/usr/bin/netfilter-persistent" is installed in "/etc/init.d/netfilter-persistent".
	# "service netfilter-persistent cmd" executes "/etc/init.d/netfilter-persistent" which inturn executes
	# "/usr/bin/netfilter-persistent".
	ssh_command $1 $2 $IMAGE_ROOT_SSH_PRIVATE_KEY sh -c \
		"\"if [ -f '/etc/init.d/iptables-persistent' ]; then 
		     cp /etc/init.d/iptables-persistent /etc/init.d/iptables-persistent.original;
	         cp ~/iptables-persistent /etc/init.d/iptables-persistent;
	         chmod +x /etc/init.d/iptables-persistent;
	         update-rc.d iptables-persistent enable;
	         /etc/init.d/iptables-persistent save;
	         /etc/init.d/iptables-persistent start;
	     elif [ -f '/usr/sbin/netfilter-persistent' ]; then
             cp /usr/sbin/netfilter-persistent /usr/sbin/netfilter-persistent.original;
	         cp ~/iptables-persistent /usr/sbin/netfilter-persistent;
	         chmod +x /usr/sbin/netfilter-persistent;
	         update-rc.d -f netfilter-persistent remove;
			 update-rc.d netfilter-persistent defaults;
			 update-rc.d netfilter-persistent enable;
	         service netfilter-persistent save;
	         service netfilter-persistent start;
	     fi\""

	

	# Disable IPv6 to keep the firewall configuration tight.
	echo "Disabling IPv6"

	ssh_command $1 $2 $IMAGE_ROOT_SSH_PRIVATE_KEY \
		"sh -c \"echo 'net.ipv6.conf.all.disable_ipv6 = 1' >> /etc/sysctl.conf;echo 'net.ipv6.conf.default.disable_ipv6 = 1' >> /etc/sysctl.conf;echo 'net.ipv6.conf.lo.disable_ipv6 = 1' >> /etc/sysctl.conf\""
	ssh_command $1 $2 $IMAGE_ROOT_SSH_PRIVATE_KEY sysctl -p
}




# $1 : IP address of node
# $2 : SSH username for node
install_storm_on_node() {

	echo "Installing $INSTALL_STORM_DISTRIBUTION on $1..."

	local remote_path=$(basename $INSTALL_STORM_DISTRIBUTION)
	remote_copyfile $INSTALL_STORM_DISTRIBUTION $1 $2 $IMAGE_ROOT_SSH_PRIVATE_KEY $remote_path

	ssh_command $1 $2 $IMAGE_ROOT_SSH_PRIVATE_KEY tar -C $STORM_INSTALL_DIRECTORY -xzf $remote_path

	local install_dir=$(storm_install_dir)
	

	# Create the Storm local directory specified in storm.yaml.
	# The xargs at the end is to trim enclosing whitespaces.
	local storm_yaml_template="$STORM_YAML_TEMPLATE"
	if [ "${storm_yaml_template:0:1}" != "/" ]; then
		storm_yaml_template=$(readlink -m "$IMAGE_CONF_DIR/$STORM_YAML_TEMPLATE")
	fi
	local storm_local_dir=$(grep 'storm.local.dir' $storm_yaml_template|cut -d ':' -f 2|xargs)
	echo "Creating Storm local directory $storm_local_dir"
	ssh_command $1 $2 $IMAGE_ROOT_SSH_PRIVATE_KEY \
		"sh -c \"mkdir -p $storm_local_dir;chown -R $STORM_USER:$STORM_USER $storm_local_dir\""
	
	# Create the Storm log directory specified in storm.yaml.
	# The xargs at the end is to trim enclosing whitespaces.
	local storm_log_dir=$(grep 'storm.log.dir' $storm_yaml_template|cut -d ':' -f 2|xargs)
	echo "Creating Storm log directory $storm_log_dir"
	ssh_command $1 $2 $IMAGE_ROOT_SSH_PRIVATE_KEY \
		"sh -c \"mkdir -p $storm_log_dir;chown -R $STORM_USER:$STORM_USER $storm_log_dir\""
	
	# Copy template storm.yaml to installation directory.
	local remote_yaml_path=$install_dir/conf/storm.yaml
	echo "Copying template storm.yaml to $remote_yaml_path"
	remote_copyfile "$storm_yaml_template" $1 $2 $IMAGE_ROOT_SSH_PRIVATE_KEY $remote_yaml_path
	
	# Transfer ownership of the installed directory to ssh user for simplicity.
	echo "Storm installed in $install_dir. Changing owner to $STORM_USER:$STORM_USER..."
	ssh_command $1 $2 $IMAGE_ROOT_SSH_PRIVATE_KEY "chown -R $STORM_USER:$STORM_USER $install_dir"

}





#	$1 : Name of the cluster 
create_storm_configuration() {
	echo "Creating Storm configuration file..."

	local stfile="$(status_file)"

	# Every node's storm.yaml should have the nimbus node hostname, and list of zookeeper nodes.
	# Create a local copy of the template storm.yaml called <cluster>.storm.yaml and include all these entries, 
	# then distribute that file to all nodes.
	local cluster_cfg="$CLUSTER_CONF_DIR/$1.storm.yaml"
	local storm_yaml_template="$STORM_YAML_TEMPLATE"
	if [ ${storm_yaml_template:0:1} != "/" ]; then
		storm_yaml_template=$(readlink -m "$IMAGE_CONF_DIR/$STORM_YAML_TEMPLATE")
	fi
	cp $storm_yaml_template $cluster_cfg
	chmod go-rwx $cluster_cfg

	# Substitute actual cluster name in the zookeeper znode paths
	sed -i "s/\$CLUSTER_NAME/$CLUSTER_NAME/g" $cluster_cfg
	
	# Insert the nimbus.host value in storm.yaml.
	add_section $cluster_cfg "nimbus"
	
	local nimbus_hostname=$NIMBUS_NODE_PRIVATE_HOSTNAME
	insert_or_replace_in_section $cluster_cfg "nimbus" "nimbus.host" "nimbus.host: '$nimbus_hostname'"

	# Insert all the zookeeper nodes in storm.yaml
	add_section $cluster_cfg "zookeeper"		
	insert_bottom_of_section $cluster_cfg "zookeeper" "storm.zookeeper.servers:"

	local zkhostnames=$(get_section "$ZK_CLUSTER_CONF_DIR/$ZK_CLUSTER_NAME.info" "hostnames")

	while read zkhostentry; do
		local hostarr=($zkhostentry)
		local zk_private_hostname=${hostarr[1]}
		local zk_public_hostname=${hostarr[2]}
		
		local use_hostname=$zk_private_hostname
		
		echo "Adding zookeeper host $use_hostname to $cluster_cfg"
		insert_bottom_of_section $cluster_cfg "zookeeper" "  - '$use_hostname'"
	done <<< "$zkhostnames"
	
	# Insert the zookeeper cluster's configured client port in storm.yaml.
	# Default is 2181.
	local zk_client_port=$(grep '^clientPort' "$ZK_CLUSTER_CONF_DIR/zoo.cfg"|cut -d '=' -f2|xargs)
	if [ -z "$zk_client_port" ]; then
		zk_client_port='2181'
	fi
	insert_bottom_of_section $cluster_cfg "zookeeper" "storm.zookeeper.port: $zk_client_port"
}



#	$1 : Name of the cluster 
#	$2 : (Optional) Node role filter. The configuration gets distributed only to nodes with this role.
distribute_storm_configuration() {
	echo "Distributing storm configuration..."

	local stfile="$(status_file)"

	local nodes=$(get_section $stfile "nodes")
	if [ ! -z "$2" ]; then
		nodes=$(echo "$nodes"|grep "$2")
	fi

	local ipaddrs=$(get_section $stfile "ipaddresses")

	# Now we need the STORM installation directory on a node.
	local install_dir=$(storm_install_dir)
	local remote_cfg_path=$install_dir/conf/storm.yaml
	local cluster_cfg="$CLUSTER_CONF_DIR/$1.storm.yaml"

	while read nodeentry;
	do
		local node_arr=(${nodeentry//:/ })
		local linode_id=${node_arr[0]}

		local private_ip=$(echo "$ipaddrs" | grep $linode_id | cut -d ' ' -f 2)
		local public_ip=$(echo "$ipaddrs" | grep $linode_id | cut -d ' ' -f 3)

		local use_ip=$private_ip
		if [ "$CLUSTER_MANAGER_USES_PUBLIC_IP" == "true" ]; then
			use_ip=$public_ip
		fi
		
		echo "Copying $cluster_cfg to node $linode_id [$use_ip] $remote_cfg_path..."
		remote_copyfile $cluster_cfg $use_ip $NODE_USERNAME $NODE_ROOT_SSH_PRIVATE_KEY $remote_cfg_path
	done <<< "$nodes"
}




#	$1 : Name of the cluster 
#	$2: (Optional) filter for entries in "nodes" section. Storm services will be started only on these nodes.
start_storm() {
	# Start nimbus+webui services on nimbus node, because we want REST API access.
	# supervisor+logviewer services on supervisor nodes, and
	# web ui services on client nodes.
	
	# TODO The services to start on each type of node should be configurable.

	echo "Starting storm services on cluster..."
	local stfile="$(status_file)"
	local nodes=$(get_section $stfile "nodes")	
	if [ ! -z "$2" ]; then
		nodes=$(echo "$nodes"|grep "$2")
	fi

	local ipaddrs=$(get_section $stfile "ipaddresses")	

	local nimbus_ipaddr
	while read nodeentry; do
		# An entry in nodes section is of the form "nodename:role"
		local arr=(${nodeentry//:/ })
		local node=${arr[0]}
		local role=${arr[1]}
		
		local private_ip=$(echo "$ipaddrs" | grep $node | cut -d ' ' -f 2)
		local public_ip=$(echo "$ipaddrs" | grep $node | cut -d ' ' -f 3)

		local target_ip=$private_ip
		if [ "$CLUSTER_MANAGER_USES_PUBLIC_IP" == "true" ]; then
			target_ip=$public_ip
		fi

		if [ "$role" == "nimbus" ]; then
			
			echo "Starting nimbus service on $node [$target_ip]..."
			nimbus_ipaddr=$target_ip
			ssh_command $target_ip $NODE_USERNAME $NODE_ROOT_SSH_PRIVATE_KEY "supervisorctl start storm-nimbus"
	
		elif [ "$role" == "supervisor" ]; then

			echo "Starting supervisor service on $node [$target_ip]..."
			ssh_command $target_ip $NODE_USERNAME $NODE_ROOT_SSH_PRIVATE_KEY "supervisorctl start storm-supervisor storm-logviewer"

		elif [ "$role" == "client" ]; then

			# Storm ui can be installed on any machine, not mandatory on nimbus.
			echo "Starting ui service on client $node [$target_ip]..."
			ssh_command $target_ip $NODE_USERNAME $NODE_ROOT_SSH_PRIVATE_KEY "supervisorctl start storm-ui"
		fi

	done <<< "$nodes"

	# The actual Nimbus java process takes quite some time - 4-8 minutes - to actually come up and become ready.
	# We wait for it to become ready by checking if it's bound to the nimbus.thrift.port (default port 6627).
	# Do these checks only if nimbus service was actually started.
	if [ ! -z "$nimbus_ipaddr" ]; then
		local cluster_cfg="$CLUSTER_CONF_DIR/$1.storm.yaml"
		local nimbus_port=$(cat $cluster_cfg | grep 'nimbus.thrift.port'|cut -d ':' -f2|xargs) # xargs trims enclosing whitespaces
		if [ -z "$nimbus_port" ]; then
			nimbus_port='6627'
		fi
		# Try for upto 8 minutes (16 checks with 30 secs between checks)
		local max_checks=16
		local wait_between_checks=30
		local check_count=1
		local nimbus_ready=0
		while [ $check_count -le $max_checks ]; do
			ssh_command $nimbus_ipaddr $NODE_USERNAME $NODE_ROOT_SSH_PRIVATE_KEY "netstat -anp | grep java | grep $nimbus_port"
			if [ $? -eq 0 ]; then
				echo "Nimbus is ready"
				nimbus_ready=1
				break
			fi
			check_count=$((check_count+1))
			echo "Waiting for Nimbus service to be ready"
			sleep $wait_between_checks
		done
		if [ $nimbus_ready -eq 0 ]; then
			echo "Nimbus is still not ready after $((max_checks*wait_between_checks/60)) minutes. However, this is not necessarily an error. Proceeding..."
		fi	
	fi
}



#	$1 : Name of the cluster 
stop_storm() {
	# Stop the appropriate services on each node.

	echo "Stopping storm services on cluster..."
	local stfile="$(status_file)"
	local nodes=$(get_section $stfile "nodes")	
	local ipaddrs=$(get_section $stfile "ipaddresses")	

	local install_dir=$(storm_install_dir)

	# Clean shutdown of services:
	# First kill all topologies (and their respective workers) with "storm kill <topology>" for each topology returned
	# by "storm list".
	# Then periodically check "storm list" until there are no topologies. Only then stop only the "supervisor services" (not logviewer,
	# because we still want logs of the shutdown process itself) with pauses in between, so that they can make all their states consistent after each shutdown. 
	# Then shutdown the logviewer services on each node. 
	# Finally client nodes.
	# Last of all nimbus.
	
	echo "Killing all topologies..."
	kill_all_topologies

	echo "Stopping supervisor service on supervisor nodes..."
	local supervisor_nodes=$(echo "$nodes" | grep ':supervisor' | cut -d ':' -f1)
	while read supervisor_node; do
		local private_ip=$(echo "$ipaddrs" | grep $supervisor_node | cut -d ' ' -f 2)
		local public_ip=$(echo "$ipaddrs" | grep $supervisor_node | cut -d ' ' -f 3)
		
		local target_ip=$private_ip
		if [ "$CLUSTER_MANAGER_USES_PUBLIC_IP" == "true" ]; then
			target_ip=$public_ip
		fi
		
		echo "Stopping supervisor service on $supervisor_node [$target_ip]..."
		ssh_command $target_ip $NODE_USERNAME $NODE_ROOT_SSH_PRIVATE_KEY "supervisorctl stop storm-supervisor"
		
		sleep 20
	done <<< "$supervisor_nodes"



	echo "Stopping logviewer service on supervisor nodes..."
	while read supervisor_node; do
		local private_ip=$(echo "$ipaddrs" | grep $supervisor_node | cut -d ' ' -f 2)
		local public_ip=$(echo "$ipaddrs" | grep $supervisor_node | cut -d ' ' -f 3)
		
		local target_ip=$private_ip
		if [ "$CLUSTER_MANAGER_USES_PUBLIC_IP" == "true" ]; then
			target_ip=$public_ip
		fi
		
		echo "Stopping logviewer service on $supervisor_node [$target_ip]..."
		ssh_command $target_ip $NODE_USERNAME $NODE_ROOT_SSH_PRIVATE_KEY "supervisorctl stop storm-logviewer"
	done <<< "$supervisor_nodes"




	echo "Stopping ui service on client nodes..."
	local client_nodes=$(echo "$nodes" | grep ':client' | cut -d ':' -f1)
	while read client_node; do
		local private_ip=$(echo "$ipaddrs" | grep $client_node | cut -d ' ' -f 2)
		local public_ip=$(echo "$ipaddrs" | grep $client_node | cut -d ' ' -f 3)
		
		local target_ip=$private_ip
		if [ "$CLUSTER_MANAGER_USES_PUBLIC_IP" == "true" ]; then
			target_ip=$public_ip
		fi
		echo "Stopping ui service on $client_node [$target_ip]..."
		ssh_command $target_ip $NODE_USERNAME $NODE_ROOT_SSH_PRIVATE_KEY "supervisorctl stop storm-ui"
	done <<< "$client_nodes"




	local nimbus_ipaddr=$(get_nimbus_node_ipaddr)
	echo "Stopping nimbus service on nimbus node $nimbus_ipaddr..."
	ssh_command $nimbus_ipaddr $NODE_USERNAME $NODE_ROOT_SSH_PRIVATE_KEY "supervisorctl stop storm-nimbus"
	# Wait for nimbus service to shutdown cleanly. Shutdown is quick if there are no topologies running, but
	# slower if there are because nimbus has to first shutdown the topologies.
	echo "Waiting for nimbus node services to stop..."
	sleep 30	
}



kill_all_topologies() {
	# Kills all topologies, and then periodically checks list of topologies until it's empty.

	# We kill topologies by invoking Storm REST API. 
	# But to invoke it from cluster manager node, cluster manager should be in client's port 80 whitelist.
	# Instead of adding to the whitelist, we just invoke the  REST API remotely on the client itself.
	
	# curl sometimes shows an error "(23) Failed writing body" when piping output. From observations, it seems like it happens
	# if the target program does not read stdin (storm-api-helper.py does not read stdin if it doesn't recognize the command)
	# To avoid this problem entirely, first read curl output to a variable and then feed that variable to helper.

	local client_node_ssh_ip=$(get_client_node_ipaddr)
	local topology_data=$(ssh_command $client_node_ssh_ip $NODE_USERNAME $NODE_ROOT_SSH_PRIVATE_KEY "curl -s 'http://localhost/api/v1/topology/summary'")
	local topology_ids=$(echo $topology_data | ./storm-api-helper.py "topology-ids")
	if [ -z "$topology_ids" ]; then
		echo "No topologies to kill"
		return 0
	fi

	while read topology; do
		echo "Killing topology $topology"
		ssh_command $client_node_ssh_ip $NODE_USERNAME $NODE_ROOT_SSH_PRIVATE_KEY "curl -s -X POST http://localhost/api/v1/topology/$topology/kill/30"
		sleep 10
	done <<< "$topology_ids"
	
	local max_checks=6
	local time_between_checks=20
	local check_count=1
	local kill_success=0
	while [ $check_count -le $max_checks ]; do
		local topology_data=$(ssh_command $client_node_ssh_ip $NODE_USERNAME $NODE_ROOT_SSH_PRIVATE_KEY "curl -s 'http://localhost/api/v1/topology/summary'")
		local topology_ids=$(echo $topology_data | ./storm-api-helper.py "topology-ids")
		if [ -z "$topology_ids" ]; then
			echo "All topologies are killed"
			kill_success=1
			break
		fi
		check_count=$((check_count+1))
		echo "Waiting for topologies to be killed..."
		sleep $time_between_checks
	done

	if [ $kill_success -eq 0 ]; then
		echo "Some topologies could not be killed in time. Proceeding with shutdown"
	fi
}



# 	$1 : Name of cluster directory or Path of cluster configuration file.
# $2 : The API environment file
# $3 : Plans and counts for new supervisor nodes 
#		(ex: "2GB:1 4GB:1 8GB:1" adds 3 new supervisor nodes, a 2 GB, a 4 GB and a 8 GB)
add_nodes() {
	
	if ! load_cluster_conf "$1"; then
		return 1
	fi
	
	if ! load_api_env_configuration "$2"; then
		return 1
	fi


	local stfile="$(status_file)"
	# If the cluster does not exist, abort this addition.
	if [ ! -f "$stfile" ]; then
		echo "Cluster is not created. Nodes can be added only to existing clusters."
		return 1
	fi

	# Don't allow addition if cluster is creating/destroying/stopping etc.
	local cluster_status=$(get_cluster_status)
	if [[ "$cluster_status" != "running" && \
		  "$cluster_status" != "stopped" && \
		  "$cluster_status" != "created" ]]; then
		echo "Nodes can be added only to existing, running or stopped clusters."
		return 1
	fi

	echo "Adding $3 new supervisor nodes to cluster $CLUSTER_NAME..."

	# Validate the datacenter.
	linode_api linout linerr linret "datacenter-id" "$DATACENTER_FOR_CLUSTER"
	if [ $linret -eq 1 ]; then
		echo "Failed to find datacenter. Error:$linerr"
		return 1
	fi
	local dc_id=$linout
	echo "Datacenter ID=$dc_id"
	
	# Get the image id from the image info file. If there is no image info file,
	# then try to find using API. 
	local img_stfile="$(image_status_file)"
	local image_id
	if [ -f "$img_stfile" ]; then
		image_id=$(get_section $img_stfile "image")
	fi
	
	if [ -z "$image_id" ]; then
		echo "Unable to get image ID from image info file. Searching for image using label..."
		linode_api linout linerr linret "image-id" "$LABEL_FOR_IMAGE"
		if [ $linret -eq 1 ]; then
			echo "Failed to find image. Error:$linerr"
			return 1
		fi
		image_id=$(echo $linout|cut -d ',' -f1)
	fi
	
	if [ -z "$image_id" ]; then
		echo "Failed to find image."
		return 1
	fi
	
	echo "Image ID=$image_id"
	
	
	# Get the kernel ID.
	linode_api linout linerr linret "kernel-id" "$KERNEL_FOR_IMAGE"
	if [ $linret -eq 1 ]; then
		echo "Failed to find kernel. Error:$linerr"
		return 1
	fi
	local kernel_id=$(echo $linout|cut -d ',' -f1)
	echo "Kernel ID=$kernel_id"
	
	create_supervisor_nodes $CLUSTER_NAME "$3" $dc_id $image_id $kernel_id "new"
	if [ $? -eq 1 ]; then
		echo "Error during Supervisor nodes creation. Aborting"
		return 1
	fi

	start_nodes $CLUSTER_NAME ":supervisor:new"
	
	# Since nodes created from an image retain the image's host keys, they should
	# be changed to unique ones before doing anything else.
	change_hostkeys $CLUSTER_NAME ":supervisor:new"

	set_hostnames $CLUSTER_NAME ":supervisor:new"

	# If cluster is currently running, distribute hosts file to all nodes.
	# If cluster is currently stopped, it's not needed because start_cluster will again recreate the hosts file.
	local cluster_status=$(get_cluster_status)
	if [ "$cluster_status" == "running" ]; then
		distribute_hostsfile $CLUSTER_NAME
	fi

	# No need to recreate storm configuration; we just want to distribute it to the new nodes.
	distribute_storm_configuration $CLUSTER_NAME ":supervisor:new"

	# All storm nodes and zk nodes firewalls have to be updated to 
	# accept traffic from the new supervisor nodes.
	create_cluster_security_configurations $CLUSTER_NAME
	if [ "$cluster_status" == "running" ]; then
		# The new supervisor nodes have to be integrated with reverse web proxy running on client
		# node, to make their log files available via storm web UI.
		configure_client_reverse_proxy $CLUSTER_NAME
	
		distribute_cluster_security_configurations $CLUSTER_NAME
		update_security_status "unchanged"
	else
		# Mark security as changed, so that new configuration gets applied at next start.
		update_security_status "changed"
	fi
	
	if [ "$cluster_status" == "stopped" ]; then
		sleep 5
		stop_nodes $CLUSTER_NAME ":supervisor:new"

	elif [ "$cluster_status" == "running" ]; then
		start_storm $CLUSTER_NAME ":supervisor:new"
	fi

	# Strip out the ":new" suffix from newly created nodes.
	sed -r -i '/#START:nodes/,/#END:nodes/ s/:new//' $stfile

	# TODO Should the cluster be rebalanced?

	echo "Finished adding new supervisor nodes"
}



# Admin can modify the cluster's storm.yaml and call this to re-upload 
# it to entire cluster and restart zookeeper services.
# 	$1 : Name of cluster directory or Path of cluster configuration file.
update_storm_yaml() {

	if ! load_cluster_conf "$1"; then
		return 1
	fi
	

	local cluster_status=$(get_cluster_status)
	if [ "$cluster_status" == "running" ]; then
	
		# Stop Storm services on all nodes.
		stop_storm $CLUSTER_NAME
		
		# Distribute recreated storm configuration to all nodes.
		distribute_storm_configuration $CLUSTER_NAME

		# Restart Storm services on all nodes.
		start_storm $CLUSTER_NAME
		
		update_conf_status "unchanged"
	else
		# Mark configuration as changed, so that new configuration gets applied at next start.
		update_conf_status "changed"
	fi
}



#	$1 : Name of the cluster 
install_client_reverse_proxy() {
	echo "Installing reverse proxy web server on client node"
	
	local client_node_ssh_ip=$(get_client_node_ipaddr)
	local client_node_public_ip=$(get_client_node_public_ipaddr)
	
	# Install apache as reverse proxy server. Install curl so that cluster manager
	# can kill topologies by sending request to Storm ReST API from the client node.
	# Sending it from client node means cluster manager need not be in the client
	# whitelist.
	ssh_command $client_node_ssh_ip $NODE_USERNAME $NODE_ROOT_SSH_PRIVATE_KEY \
		"sh -c \"apt-get -y update;apt-get -y install apache2 curl\""
	
	# We need to enable the following apache modules:
	# - "proxy" and proxy_http to make apache act as reverse proxy for storm-ui webapp, 
	#   JSON REST API, and logviewer URLs of supervisor nodes
	#
	# - "substitute" to replace URLs which contain private hostnames of supervisor nodes
	#   with their proxied URLs in the REST API's JSON responses.
	#   Also to replace private hostnames of supervisor nodes in the HTML of logviewer
	#   webapps.
	#
	# - "headers" to unset the accept-encoding gzip header, without which substitute
	#   doesn't work.
	ssh_command $client_node_ssh_ip $NODE_USERNAME $NODE_ROOT_SSH_PRIVATE_KEY a2enmod proxy proxy_http substitute headers
}



#	$1 : Name of the cluster 
configure_client_reverse_proxy() {
	local stfile="$(status_file)"
	
	local client_node_ssh_ip=$(get_client_node_ipaddr)
	local client_node_public_ip=$(get_client_node_public_ipaddr)
	
	# Create "stormproxy.conf" with reverse proxy and substitution configuration.
	local storm_proxy_conf="$CLUSTER_CONF_DIR/$CLUSTER_NAME-stormproxy.conf"
	cp template-stormproxy.conf $storm_proxy_conf
	chmod go-rwx $storm_proxy_conf
	local ui_port=$(get_ui_port)
	sed -i "s/\$STORMUIPORT/$ui_port/g" $storm_proxy_conf

	# We have to insert a Substitute directive for each supervisor node:
	# Substitute "s|http:\/\/storm-cluster-sim1-private-supr1:8000|http:\/\/192.168.11.153\/storm-cluster-sim1-private-supr1|nq"
	# So we need list of supervisor nodes and their private hostnames.
	local nodes=$(get_section $stfile "nodes")
	local hostnames=$(get_section $stfile "hostnames")
	while read nodeentry
	do
		local arr=(${nodeentry//:/ })
		local linode_id=${arr[0]}
		local role=${arr[1]}
		
		if [ "$role" != "supervisor" ]; then
			continue
		fi
		
		# For every supervisor node's URL in the REST API JSON response,
		# replace with corresponding proxied URL 
		# like http://client/<supervisor_hostname>/
		local sup_private_hostname=$(echo "$hostnames" | grep $linode_id | cut -d ' ' -f 2)
		sed -i "/###JSONREPLACE/ i \\\tSubstitute \"s|http:\\\/\\\/$sup_private_hostname:8000|http:\\\/\\\/$client_node_public_ip\/$sup_private_hostname|nq\"" $storm_proxy_conf

		# For every supervisor node's logviewer app, create a corresponding proxied URL 
		# like http://client/<supervisor_hostname>/
		#
		# Accept-Encoding request header is unset to avoid accepting gzip, because it bypasses substitution filter. 
		# Substitute HTML too does not work unless encoding is unset.
		# 
		# The Substitute directive strips the leading slashes from URLs, thus turning them into relative
		# URLs.
		# For example, URLs like href="/download/..." which wrongly resolves to http://client/download
		# is substituted href="download/..." which correctly resolves to http://client/<supervisor>/download...
		cat >> $storm_proxy_conf <<-ENDLOCATIONPARA
			<Location "/$sup_private_hostname/">
			    ProxyPass "http://$sup_private_hostname:8000/"

			    RequestHeader unset Accept-Encoding
			    AddOutputFilterByType SUBSTITUTE text/html
			    Substitute 's|href="/|href="|nq'
			</Location>
			
		ENDLOCATIONPARA
	done <<< "$nodes"
	
	remote_copyfile $storm_proxy_conf $client_node_ssh_ip $NODE_USERNAME $NODE_ROOT_SSH_PRIVATE_KEY /etc/apache2/conf-available/stormproxy.conf
	ssh_command $client_node_ssh_ip $NODE_USERNAME $NODE_ROOT_SSH_PRIVATE_KEY a2enconf stormproxy.conf
	
	ssh_command $client_node_ssh_ip $NODE_USERNAME $NODE_ROOT_SSH_PRIVATE_KEY service apache2 restart
}
	

#	$1 : Name of the cluster 
create_cluster_security_configurations() {
	local stfile="$(status_file)"
	
	# The goal here is to create iptables rules and ipset files,
	# which are uploaded to each cluster node to be loaded by the "iptables-persistent" script
	# to configure that node's iptables firewall.
	#
	# Since client node is the main point of access for all users, its security 
	# is different from all other nodes and gets slightly different set of rules.
	#
	# 1. Create "$CLUSTER_NAME-whitelist.ipsets" that contains private IP addresses of all nodes of
	#    this cluster.
	# 2. We also need to whitelist ZK node private IP addresses. So run "zookeeper-cluster-linode.sh"
	#    to create the "$ZK_CLUSTER_NAME-whitelist.ipsets" that contains private IP addresses of all ZK 
	#    nodes.
	# 3. Create an empty "$CLUSTER_NAME-client-user-whitelist.ipsets" where admin can add whitelisted
	#    IP addresses who can access port 80. Admin can add entries to this file in the ipsets format,
	#    and update the client node with "storm-cluster-linode.sh update-user-whitelist" command.
	# 4. Create "$CLUSTER_NAME-rules.v4" from "template-storm-rules.v4", with placeholders substituted.
	# 5. Create "$CLUSTER_NAME-client-rules.v4" from "template-storm-client-rules.v4", with placeholders substituted.
	# 6. Create "$CLUSTER_NAME-rules.v6" from "template-storm-rules.v6", with placeholders substituted.
	
	local storm_cluster_whitelist_file="$CLUSTER_CONF_DIR/$CLUSTER_NAME-whitelist.ipsets"
	local storm_cluster_whitelist_name="$CLUSTER_NAME-wl"
	echo "create $storm_cluster_whitelist_name hash:ip family inet hashsize 1024 maxelem 65536" > $storm_cluster_whitelist_file
	chmod go-rwx $storm_cluster_whitelist_file
	local ipaddrs=$(get_section $stfile "ipaddresses")
	while read ipentry 
	do
		local arr=($ipentry)
		local linode_id=${arr[0]}
		local private_ip=${arr[1]}

		echo "add $storm_cluster_whitelist_name $private_ip" >> $storm_cluster_whitelist_file
	done <<< "$ipaddrs"

	./zookeeper-cluster-linode.sh "create-cluster-whitelist" "$ZK_CLUSTER_CONF_FILE"
	local zk_cluster_whitelist_file="$ZK_CLUSTER_CONF_DIR/$ZK_CLUSTER_NAME-whitelist.ipsets"
	
	local ipsets_file_for_all_nodes="$CLUSTER_CONF_DIR/$CLUSTER_NAME-rules.ipsets"
	cat $storm_cluster_whitelist_file $zk_cluster_whitelist_file > $ipsets_file_for_all_nodes
	
	chmod go-rwx $ipsets_file_for_all_nodes
	
	# The client user whitelist file contains user editable whitelists of users who're allowed
	# to access the web UI interface on client node.
	# Admin can create any kind of ipsets here, and should add those ipsets to the 
	# master whitelist "$CLUSTER_NAME-uwls".
	local storm_client_user_whitelist_file="$CLUSTER_CONF_DIR/$CLUSTER_NAME-client-user-whitelist.ipsets"
	local storm_client_user_master_whitelist_name="$CLUSTER_NAME-uwls"
	# Since this is a user-editable file, we don't want to overwrite it if it already exixts.
	if [ ! -f "$storm_client_user_whitelist_file" ]; then
		> $storm_client_user_whitelist_file
		chmod go-rwx $storm_client_user_whitelist_file
		
		printf "# Create custom ipsets based on your needs, include them under master whitelist $CLUSTER_NAME-uwls\n" >> $storm_client_user_whitelist_file
		printf "# and finally run ./storm-cluster-linode.sh update-user-whitelist <CLUSTER-CONF-FILE>\n\n" >> $storm_client_user_whitelist_file
		echo "# Example 1: An ipset that whitelists IP addresses:" >> $storm_client_user_whitelist_file
		echo "# create $CLUSTER_NAME-ipwl hash:ip family inet hashsize 1024 maxelem 65536" >> $storm_client_user_whitelist_file
		echo "#   add $CLUSTER_NAME-ipwl 192.168.1.98" >> $storm_client_user_whitelist_file
		printf "\n" >> $storm_client_user_whitelist_file
		echo "# Example 2: An ipset that whitelists IP address-MAC address pairs:" >> $storm_client_user_whitelist_file
		echo "# create $CLUSTER_NAME-ipmwl bitmap:ip,mac range 192.168.2.0/24" >> $storm_client_user_whitelist_file
		echo "#   add $CLUSTER_NAME-ipmwl 192.168.2.98,08:00:27:d6:26:b3" >> $storm_client_user_whitelist_file
		printf "\n# Add your ipsets to this master list:\n" >> $storm_client_user_whitelist_file
		echo "create $storm_client_user_master_whitelist_name list:set size 32" >> $storm_client_user_whitelist_file
		echo "#  Examples:" >> $storm_client_user_whitelist_file
		echo "#  add $storm_client_user_master_whitelist_name $CLUSTER_NAME-ipwl" >> $storm_client_user_whitelist_file
		echo "#  add $storm_client_user_master_whitelist_name $CLUSTER_NAME-ipmwl" >> $storm_client_user_whitelist_file
	fi

	local ipsets_file_for_client_node="$CLUSTER_CONF_DIR/$CLUSTER_NAME-client-rules.ipsets"
	cat $storm_cluster_whitelist_file $zk_cluster_whitelist_file $storm_client_user_whitelist_file > $ipsets_file_for_client_node
	chmod go-rwx $ipsets_file_for_client_node
	
	local template_v4_rules=$IPTABLES_V4_RULES_TEMPLATE
	if [ ${template_v4_rules:0:1} != "/" ]; then
		template_v4_rules=$(readlink -m "$CLUSTER_CONF_DIR/$IPTABLES_V4_RULES_TEMPLATE")
	fi
	local storm_iptables_v4_rules_file="$CLUSTER_CONF_DIR/$CLUSTER_NAME-rules.v4"
	cp $template_v4_rules $storm_iptables_v4_rules_file
	chmod go-rwx $storm_iptables_v4_rules_file
	sed -i "s/\$CLUSTER_NAME/$CLUSTER_NAME/g" $storm_iptables_v4_rules_file
	sed -i "s/\$ZK_CLUSTER_NAME/$ZK_CLUSTER_NAME/g" $storm_iptables_v4_rules_file

	local template_v6_rules=$IPTABLES_V6_RULES_TEMPLATE
	if [ ${template_v6_rules:0:1} != "/" ]; then
		template_v6_rules=$(readlink -m "$CLUSTER_CONF_DIR/$IPTABLES_V6_RULES_TEMPLATE")
	fi
	local storm_iptables_v6_rules_file="$CLUSTER_CONF_DIR/$CLUSTER_NAME-rules.v6"
	cp $template_v6_rules $storm_iptables_v6_rules_file
	chmod go-rwx $storm_iptables_v6_rules_file
	sed -i "s/\$CLUSTER_NAME/$CLUSTER_NAME/g" $storm_iptables_v6_rules_file
	sed -i "s/\$ZK_CLUSTER_NAME/$ZK_CLUSTER_NAME/g" $storm_iptables_v6_rules_file
	
	local template_client_v4_rules=$IPTABLES_CLIENT_V4_RULES_TEMPLATE
	if [ ${template_client_v4_rules:0:1} != "/" ]; then
		template_client_v4_rules=$(readlink -m "$CLUSTER_CONF_DIR/$IPTABLES_CLIENT_V4_RULES_TEMPLATE")
	fi
	local storm_client_iptables_v4_rules_file="$CLUSTER_CONF_DIR/$CLUSTER_NAME-client-rules.v4"
	cp $template_client_v4_rules $storm_client_iptables_v4_rules_file
	chmod go-rwx $storm_client_iptables_v4_rules_file
	sed -i "s/\$CLUSTER_NAME/$CLUSTER_NAME/g" $storm_client_iptables_v4_rules_file
	sed -i "s/\$ZK_CLUSTER_NAME/$ZK_CLUSTER_NAME/g" $storm_client_iptables_v4_rules_file
}

#	$1 : Name of the cluster 
distribute_cluster_security_configurations() { 
	local stfile="$(status_file)"

	local ipsets_file_for_all_nodes="$CLUSTER_CONF_DIR/$CLUSTER_NAME-rules.ipsets"
	local ipsets_file_for_client_node="$CLUSTER_CONF_DIR/$CLUSTER_NAME-client-rules.ipsets"
	
	local storm_iptables_v4_rules_file="$CLUSTER_CONF_DIR/$CLUSTER_NAME-rules.v4"
	local storm_client_iptables_v4_rules_file="$CLUSTER_CONF_DIR/$CLUSTER_NAME-client-rules.v4"
	local storm_iptables_v6_rules_file="$CLUSTER_CONF_DIR/$CLUSTER_NAME-rules.v6"
	
	local nodes=$(get_section $stfile "nodes")
	local ipaddrs=$(get_section $stfile "ipaddresses")
	while read nodeentry 
	do
		local node_arr=(${nodeentry//:/ })
		local linode_id=${node_arr[0]}
		local role=${node_arr[1]}
	
		local private_ip=$(echo "$ipaddrs" | grep $linode_id | cut -d ' ' -f 2)
		local public_ip=$(echo "$ipaddrs" | grep $linode_id | cut -d ' ' -f 3)
		
		local target_ip=$private_ip
		if [ "$CLUSTER_MANAGER_USES_PUBLIC_IP" == "true" ]; then
			target_ip=$public_ip
		fi
		
		remote_copyfile $storm_iptables_v6_rules_file $target_ip $NODE_USERNAME $NODE_ROOT_SSH_PRIVATE_KEY /etc/iptables/rules.v6
		
		if [ "$role" == "client" ]; then
			remote_copyfile $storm_client_iptables_v4_rules_file $target_ip $NODE_USERNAME $NODE_ROOT_SSH_PRIVATE_KEY /etc/iptables/rules.v4
			remote_copyfile $ipsets_file_for_client_node $target_ip $NODE_USERNAME $NODE_ROOT_SSH_PRIVATE_KEY /etc/iptables/rules.ipsets
		
		else
			remote_copyfile $storm_iptables_v4_rules_file $target_ip $NODE_USERNAME $NODE_ROOT_SSH_PRIVATE_KEY /etc/iptables/rules.v4
			remote_copyfile $ipsets_file_for_all_nodes $target_ip $NODE_USERNAME $NODE_ROOT_SSH_PRIVATE_KEY /etc/iptables/rules.ipsets
		
		fi
		
		# Apply the firewall configuration immediately.
		# One complication here is that ipset restore does not *overwrite* an existing set, but instead loads
		# the file as new sets (ipset supports duplicate sets with same name).
		# So for correct reloading, we have to "ipset destroy" all sets, and then reload.
		# But "ipset destroy" is not allowed as long as a set is in use by iptables rule.
		# So iptables has to be flushed first.
		# ssh_command $target_ip $NODE_USERNAME "sh -c \"iptables -F;ipset destroy;/etc/init.d/iptables-persistent reload\""
		#
		# On Debian 8 + systemd, 'apt-get install iptables-persistent' no longer installs
		# "iptables-persistent" script but instead calls it "/usr/bin/netfilter-persistent".
		# A wrapper which calls "/usr/bin/netfilter-persistent" is installed in "/etc/init.d/netfilter-persistent"
		# "service netfilter-persistent cmd" executes "/etc/init.d/netfilter-persistent" which inturn executes
		# "/usr/bin/netfilter-persistent".
		ssh_command $target_ip $NODE_USERNAME $NODE_ROOT_SSH_PRIVATE_KEY sh -c \
			"\"if [ -f '/etc/init.d/iptables-persistent' ]; then
			     /etc/init.d/iptables-persistent flush;
			     /etc/init.d/iptables-persistent reload;
			 elif [ -f '/usr/sbin/netfilter-persistent' ]; then
				 service netfilter-persistent flush;
			     service netfilter-persistent reload;
			 fi\""

		
	done <<< "$nodes"
	
	# Tell the zookeeper cluster to add this storm cluster's nodes to *its* whitelist.
	# It expects the path to be relative to scripts directory. example: storm-cluster1/storm-cluster1-whitelist.ipsets
	local storm_cluster_whitelist_file="$(basename $CLUSTER_CONF_DIR)/$CLUSTER_NAME-whitelist.ipsets"
	./zookeeper-cluster-linode.sh "add-whitelist" "$ZK_CLUSTER_CONF_FILE" "$storm_cluster_whitelist_file"
}


# 	$1 : Name of cluster directory or Path of cluster configuration file.
update_firewall() {
	if ! load_cluster_conf "$1"; then
		return 1
	fi
	
	create_cluster_security_configurations $CLUSTER_NAME
	
	local cluster_status=$(get_cluster_status)
	if [ "$cluster_status" == "running" ]; then
		distribute_cluster_security_configurations $CLUSTER_NAME
		update_security_status "unchanged"
	else
		# Mark security as changed, so that new configuration gets applied at next start.
		update_security_status "changed"
	fi
}



# 	$1 : Name of cluster directory or Path of cluster configuration file.
update_client_user_whitelist() {
	
	if ! load_cluster_conf "$1"; then
		return 1
	fi
	

	local cluster_status=$(get_cluster_status)
	if [ "$cluster_status" != "running" ]; then
		echo "Error: Client user whitelist can be updated only when cluster is running"
		return 1
	fi
	
	local storm_client_user_whitelist_file="$CLUSTER_CONF_DIR/$CLUSTER_NAME-client-user-whitelist.ipsets"

	local storm_cluster_whitelist_file="$CLUSTER_CONF_DIR/$CLUSTER_NAME-whitelist.ipsets"
	
	local zk_cluster_whitelist_file="$ZK_CLUSTER_CONF_DIR/$ZK_CLUSTER_NAME-whitelist.ipsets"
	
	local ipsets_file_for_client_node="$CLUSTER_CONF_DIR/$CLUSTER_NAME-client-rules.ipsets"
	
	cat $storm_cluster_whitelist_file $zk_cluster_whitelist_file $storm_client_user_whitelist_file > $ipsets_file_for_client_node
	
	local client_node_ip=$(get_client_node_ipaddr)
	remote_copyfile $ipsets_file_for_client_node $client_node_ip $NODE_USERNAME $NODE_ROOT_SSH_PRIVATE_KEY /etc/iptables/rules.ipsets
	
	# Apply the firewall configuration immediately.
	#ssh_command $client_node_ip $NODE_USERNAME $NODE_ROOT_SSH_PRIVATE_KEY \
	#	"sh -c \"/etc/init.d/iptables-persistent flush;/etc/init.d/iptables-persistent reload\""
	
	# On Debian 8 + systemd, 'apt-get install iptables-persistent' no longer installs
	# "iptables-persistent" script but instead calls it "/usr/bin/netfilter-persistent".
	# A wrapper which calls "/usr/bin/netfilter-persistent" is installed in "/etc/init.d/netfilter-persistent"
	# "service netfilter-persistent cmd" executes "/etc/init.d/netfilter-persistent" which inturn executes
	# "/usr/bin/netfilter-persistent".
	ssh_command $client_node_ip $NODE_USERNAME $NODE_ROOT_SSH_PRIVATE_KEY sh -c \
		"\"if [ -f '/etc/init.d/iptables-persistent' ]; then
			 /etc/init.d/iptables-persistent flush;
			 /etc/init.d/iptables-persistent reload;
		 elif [ -f '/usr/sbin/netfilter-persistent' ]; then
			 service netfilter-persistent flush;
			 service netfilter-persistent reload;
		 fi\""
	
	echo "Finished updating client user whitelist"
	
	return 0
}



# 	$1 : Name of cluster directory or Path of cluster configuration file.
describe_cluster() {

	if ! load_cluster_conf "$1"; then
		return 1
	fi
	

	local stfile="$(status_file)"
	# If the cluster does not exist, abort this operation.
	if [ ! -f "$stfile" ]; then
		echo "Cluster is not created. Only existing clusters can be described."
		return 1
	fi
	
	local cluster_status=$(get_cluster_status)
	printf "\nStatus: $cluster_status\n\n"
	
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
		  Linode ID:        $nimbus_linode_id
		  Private IP:       $nimbus_private_ip
		  Private hostname: $nimbus_private_host
		  Public IP:        $nimbus_public_ip
		  Public hostname:  $nimbus_public_host
		  
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
		  Linode ID:        $client_linode_id
		  Private IP:       $client_private_ip
		  Private hostname: $client_private_host
		  Public IP:        $client_public_ip
		  Public hostname:  $client_public_host
		  
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
			  Linode ID:        $sup_linode_id
			  Private IP:       $sup_private_ip
			  Private hostname: $sup_private_host
			  Public IP:        $sup_public_ip
			  Public hostname:  $sup_public_host
			  
		ENDSTANZA
	
	done <<< "$(echo "$nodes" | grep 'supervisor')"
}



# 	$1 : Name of cluster directory or Path of cluster configuration file.
# $2... : Command to be run on all nodes of cluster.
run_cmd() {
	if ! load_cluster_conf "$1"; then
		return 1
	fi

	local stfile="$(status_file)"
	# If the cluster does not exist, abort this addition.
	if [ ! -f "$stfile" ]; then
		echo "Cluster is not created. Commands can be run only on existing clusters."
		return 1
	fi
	
	local cluster_status=$(get_cluster_status)
	if [ "$cluster_status" != "running" ]; then
		echo "Cluster is not running. Commands can be run only on running clusters."
		return 1
	fi
	
	local ipaddrs=$(get_section $stfile "ipaddresses")
	
	while read ipentry;
	do
		local arr=($ipentry)
		local linode_id=${arr[0]}
		local private_ip=${arr[1]}
		local public_ip=${arr[2]}
		
		# Default ssh target is the private IP address.
		local target_ip=$private_ip
		if [ "$CLUSTER_MANAGER_USES_PUBLIC_IP" == "true" ]; then
			target_ip=$public_ip
		fi
		
		echo "Executing command on linode:$linode_id, IP:$target_ip"

		ssh_command $target_ip $NODE_USERNAME $NODE_ROOT_SSH_PRIVATE_KEY "${@:2}"
	done <<< "$ipaddrs"
	
}




# 	$1 : Name of cluster directory or Path of cluster configuration file.
# $2 : Destination directory where files are copied on all nodes of cluster.
# $3... : List of local files to upload
copy_files() {

	if ! load_cluster_conf "$1"; then
		return 1
	fi

	local stfile="$(status_file)"
	# If the cluster does not exist, abort this addition.
	if [ ! -f "$stfile" ]; then
		echo "Cluster is not created. Files can be copied only to existing cluster."
		return 1
	fi
	
	local cluster_status=$(get_cluster_status)
	if [ "$cluster_status" != "running" ]; then
		echo "Cluster is not running. Files can be copied only to running clusters."
		return 1
	fi
	
	local ipaddrs=$(get_section $stfile "ipaddresses")
	
	while read ipentry;
	do
		local arr=($ipentry)
		local linode_id=${arr[0]}
		local private_ip=${arr[1]}
		local public_ip=${arr[2]}
		
		# Default ssh target is the private IP address.
		local target_ip=$private_ip
		if [ "$CLUSTER_MANAGER_USES_PUBLIC_IP" == "true" ]; then
			target_ip=$public_ip
		fi
		
		for localfile in "${@:3}"; do
			local destfile="$2"/$(basename "$localfile")
			echo "Copying $localfile to linode:$linode_id, IP:$target_ip $destfile"
			remote_copyfile "$localfile" $target_ip $NODE_USERNAME $NODE_ROOT_SSH_PRIVATE_KEY "$destfile"
		done
	done <<< "$ipaddrs"
	
}


# 	$1 : The API environment configuration file
list_plans() {
	
	# Include the specified API environment variables.
	if ! load_api_env_configuration "$1"; then
		return 1
	fi
	
	./linode_api.py 'plans' 'table'
}




# 	$1 : The API environment configuration file
list_datacenters() {
	
	# Include the specified API environment variables.
	if ! load_api_env_configuration "$1"; then
		return 1
	fi

	
	./linode_api.py "datacenters" 'table'
}



# 	$1 : The API environment configuration file
# 	$2 : (Optional) A search string for distribution labels. Only matching distros are returned.
list_distributions() {
	
	# Include the specified API environment variables.
	if ! load_api_env_configuration "$1"; then
		return 1
	fi

	
	local filter=''
	if [ ! -z "$2" ]; then
		filter="$2"
	fi
	./linode_api.py "distributions" "$filter" 'table'
}


# 	$1 : The API environment configuration file
# 	$2 : (Optional) A search string for kernel labels. Only matching kernels are returned.
list_kernels() {
	
	# Include the specified API environment variables.
	if ! load_api_env_configuration "$1"; then
		return 1
	fi

	
	local filter=''
	if [ ! -z "$2" ]; then
		filter="$2"
	fi
	
	./linode_api.py "kernels" "$filter" 'table'
}


# $1 -> Image name
validate_image_name() {
	# - Shouldn't be empty.
	# - Only alphabets, digits, hyphens, underscores
	# - No length restriction, since image name isn't used as ipset name.
	# - Should be unique. 

	local invalid=0
	if [ "$1" == "" ]; then
		echo "Validation error: Image name should not be empty"
		invalid=1
		
	else
	
		# Should contain only alphabets, digits, hyphens and underscores.
		local strip_allowed=$(printf "$1"|tr -d "[=-=][_][:digit:][:alpha:]")
		local len_notallowedchars=$(printf "$strip_allowed"|wc -m)
		if [ $len_notallowedchars -gt 0 ]; then
			echo "Validation error: Image name can have only alphabets, digits, hyphens and underscores. No whitespaces or special characters."
			invalid=1
		fi
	fi

	return $invalid
}

# $1 -> Image name, or absolute or relative path of image directory
check_image_dir_exists() {
	
	# "dirname" lets us differentiate between a path with slashes, or just a simple
	# name. If there are no slashes, dirname simply returns ".".
	# "basename" extracts the last non slash component.
	# "readlink -m" converts relative path to absolute path, regardless of any missing
	#	path components.
	# "readlink -e" converts relative path to absolute path, but if any missing
	#	path components, it doesn't return the full path.
	local image_full_path=$(readlink -m "$1")
	IMAGE_NAME=$(basename "$image_full_path")
	local image_parent=$(dirname "$image_full_path")
	
	if [ -d "$image_full_path" ]; then
		return 0
	fi
	
	return 1
}


# $1 -> Image name, or absolute or relative path of image directory, or
#		absolute or relative path of image conf file in image directory.
load_image_conf() {
	
	if [ -z "$1" ]; then
		echo "Error: Provide an image name or image directory path or image configuration file path"
		return 1
	fi

	# readlink -m converts a name to an absolute path, even if some path components 
	# are non existent. 
	# A simple name like "stormimage1" is treated like a relative path and becomes <ABSOLUTE_CURRENT_DIR>/stormimage1
	# Similarly other relative paths with "./" or "../"
	local param_full_path=$(readlink -m "$1")
	
	if [ -d "$param_full_path" ]; then
		# Check that there is a $image_name.conf in the directory and it is
		# a proper image conf.
		IMAGE_NAME=$(basename "$param_full_path")
		IMAGE_CONF_FILE="$param_full_path/$IMAGE_NAME.conf"
		IMAGE_CONF_DIR="$(dirname $IMAGE_CONF_FILE)"
		
		if [ ! -f "$IMAGE_CONF_FILE" ]; then
			echo "Error: '$1' does not seem to be a valid image name or image directory. Could not find image configuration file '$IMAGE_CONF_FILE'"
			return 1
		fi
		
	elif [ -f "$param_full_path" ]; then
		# The given file may be any file at all, but what we want is a conf file with the correct image name.
		IMAGE_NAME=$(basename $(dirname "$param_full_path"))
		IMAGE_CONF_DIR=$(dirname "$param_full_path")
		IMAGE_CONF_FILE="$IMAGE_CONF_DIR/$IMAGE_NAME.conf"
		
		local param_basename=$(basename "$param_full_path")
		if [ "$param_basename" != "$IMAGE_NAME.conf" ]; then
			echo "Error: '$1' does not seem to be a valid image configuration filename. Expected image configuration filename '$IMAGE_CONF_FILE'"
			return 1
		fi 
		
		if [ ! -f "$IMAGE_CONF_FILE" ]; then
			echo "Error: Image configuration file '$IMAGE_CONF_FILE' does not exist."
			return 1
		fi
		
	else
		echo "Error: '$param_full_path' does not exist."
		return 1
	fi
		
	# Absolute paths of this script's directory, and the image conf file's directory.
	SCRIPT_DIR="$(pwd)"
	
	echo "SCRIPT_DIR=$SCRIPT_DIR"
	echo "IMAGE_NAME=$IMAGE_NAME"
	echo "IMAGE_CONF_DIR=$IMAGE_CONF_DIR"
	echo "IMAGE_CONF_FILE=$IMAGE_CONF_FILE"

	# Load the conf file as an environment variables file.
	source "$IMAGE_CONF_FILE"
	
	# Check if it's a proper conf file
	if ! validate_image_configuration; then
		return 1
	fi
	
	return 0
}




# Caller is expected to have included the image configuration file in environment
# prior to calling this.
validate_image_configuration() {
	local invalid=0
	
	if [ -z "$DISTRIBUTION_FOR_IMAGE" ]; then
		printf "Validation error: DISTRIBUTION_FOR_IMAGE should specify a distribution ID or label.\n \
			Run ./storm-cluster-linode.sh distributions API-CONF-FILE to list them.\n"
		invalid=1
	fi
	
	if [ -z "$LABEL_FOR_IMAGE" ]; then
		echo "Validation error: LABEL_FOR_IMAGE should specify a name for the label. Enclose in quotes if it contains spaces."
		invalid=1
	fi
	
	if [ -z "$KERNEL_FOR_IMAGE" ]; then
		printf "Validation error: KERNEL_FOR_IMAGE should specify a kernel ID or label.\n \
			Run ./storm-cluster-linode.sh kernels API-CONF-FILE to list them.\n"
		invalid=1
	fi
	
	if [ -z "$DATACENTER_FOR_IMAGE" ]; then
		printf "Validation error: DATACENTER_FOR_IMAGE should specify a datacenter ID or location or abbreviation.\n \
			Run ./storm-cluster-linode.sh datacenters API-CONF-FILE to list them.\n"
		invalid=1
	fi
	
	if [ -z "$IMAGE_ROOT_PASSWORD" ]; then
		echo "Validation error: IMAGE_ROOT_PASSWORD should specify a root password which contains at least two of these four character classes: lower case letters - upper case letters - numbers - punctuation"
		invalid=1
	fi
	
	if [ -z "$IMAGE_ROOT_SSH_PUBLIC_KEY" ]; then
		echo "Validation error: IMAGE_ROOT_SSH_PUBLIC_KEY should be the path of an SSH public key file (example: $HOME/.ssh/id_rsa.pub)"
		invalid=1
		
	elif [ ! -f "$IMAGE_ROOT_SSH_PUBLIC_KEY" ]; then
		echo "Validation error: IMAGE_ROOT_SSH_PUBLIC_KEY should be the path of an SSH public key file (example: $HOME/.ssh/id_rsa.pub)"
		invalid=1
	fi
	
	if [ -z "$IMAGE_ROOT_SSH_PRIVATE_KEY" ]; then
		echo "Validation error: IMAGE_ROOT_SSH_PRIVATE_KEY should be the path of an SSH private key file (example: $HOME/.ssh/id_rsa)"
		invalid=1
		
	elif [ ! -f "$IMAGE_ROOT_SSH_PRIVATE_KEY" ]; then
		echo "Validation error: IMAGE_ROOT_SSH_PRIVATE_KEY should be the path of an SSH private key file (example: $HOME/.ssh/id_rsa)"
		invalid=1
	fi
	
	if [ ! -z "$IMAGE_DISABLE_SSH_PASSWORD_AUTHENTICATION" ]; then
		if [[ "$IMAGE_DISABLE_SSH_PASSWORD_AUTHENTICATION" != "yes" && "$IMAGE_DISABLE_SSH_PASSWORD_AUTHENTICATION" != "no" ]]; then
			echo "Validation error: IMAGE_DISABLE_SSH_PASSWORD_AUTHENTICATION should be yes or no"
			invalid=1
		fi
	fi
	
	
	if [ -z "$STORM_USER" ]; then
		echo "Validation error: STORM_USER should not be empty."
		invalid=1
	fi
	
	if [ -z "$IMAGE_ADMIN_USER" ]; then
		echo "Validation error: IMAGE_ADMIN_USER should not be empty."
		invalid=1
	fi
	
	if [ -z "$IMAGE_ADMIN_PASSWORD" ]; then
		echo "Validation error: IMAGE_ADMIN_PASSWORD should not be empty."
		invalid=1
	fi
		
	if [ ! -z "$IMAGE_ADMIN_SSH_AUTHORIZED_KEYS" ]; then
		if [ ! -f "$IMAGE_ADMIN_SSH_AUTHORIZED_KEYS" ]; then
			echo "Validation error: IMAGE_ADMIN_SSH_AUTHORIZED_KEYS should be a valid public keys file."
			invalid=1
		fi
	fi
	
	if [ -z "$INSTALL_STORM_DISTRIBUTION" ]; then
		echo "Validation error: INSTALL_STORM_DISTRIBUTION should be a Storm distribution archive."
		invalid=1
	fi


	return $invalid
}


# $1 -> Cluster name, or absolute or relative path of cluster directory
check_cluster_dir_exists() {
	
	# "dirname" lets us differentiate between a path with slashes, or just a simple
	# name. If there are no slashes, dirname simply returns ".".
	# "basename" extracts the last non slash component.
	# "readlink -m" converts relative path to absolute path, regardless of any missing
	#	path components.
	# "readlink -e" converts relative path to absolute path, but if any missing
	#	path components, it doesn't return the full path.
	local cluster_full_path=$(readlink -m "$1")
	CLUSTER_NAME=$(basename "$cluster_full_path")
	local cluster_parent=$(dirname "$cluster_full_path")
	
	if [ -d "$cluster_full_path" ]; then
		return 0
	fi
	
	return 1
}


# $1 -> Cluster name
validate_cluster_name() {
	# - Shouldn't be empty.
	# - Only alphabets, digits, hyphens, underscores
	# - 25 character restriction, since cluster name is part of ipset names.
	# - Should be unique. 

	local invalid=0
	if [ "$1" == "" ]; then
		echo "Validation error: Cluster name should not be empty"
		invalid=1
		
	else
	
		# Should contain only alphabets, digits, hyphens and underscores.
		local strip_allowed=$(printf "$1"|tr -d "[=-=][_][:digit:][:alpha:]")
		local len_notallowedchars=$(printf "$strip_allowed"|wc -m)
		if [ $len_notallowedchars -gt 0 ]; then
			echo "Validation error: Cluster name can have only alphabets, digits, hyphens and underscores. No whitespaces or special characters."
			invalid=1
		fi
		
		# Should be maximum 25 characters at most.
		local len=$(printf "$1"|wc -m)
		if [ $len -gt 25 ]; then
			echo "Validation error: Cluster name cannot have more than 25 characters."
			invalid=1
		fi

	fi

	return $invalid
}



# Caller is expected to have included the cluster configuration file in environment
# prior to calling this.
validate_cluster_configuration() {
	local invalid=0

	
	if [ -z "$STORM_IMAGE_CONF" ]; then
		echo "Validation error: STORM_IMAGE_CONF should be the path of a image configuration file"
		invalid=1
		
	elif [ ! -f "$IMAGE_CONF_FILE" ]; then
		echo "Validation error: STORM_IMAGE_CONF should be the path of a image configuration file"
		invalid=1
	fi
	
	if [ ! -z "$NODE_ROOT_SSH_PUBLIC_KEY" ]; then
		
		if [ ! -f "$NODE_ROOT_SSH_PUBLIC_KEY" ]; then
			echo "Validation error: NODE_ROOT_SSH_PUBLIC_KEY should be the path of an SSH public key file (example: $HOME/.ssh/id_rsa.pub)"
			invalid=1
		fi
		
		if [ -z "$NODE_ROOT_SSH_PRIVATE_KEY" ]; then
			echo "Validation error: NODE_ROOT_SSH_PRIVATE_KEY should be the path of an SSH private key file (example: $HOME/.ssh/id_rsa)"
			invalid=1
		
		elif [ ! -f "$NODE_ROOT_SSH_PRIVATE_KEY" ]; then
			echo "Validation error: NODE_ROOT_SSH_PRIVATE_KEY should be the path of an SSH private key file (example: $HOME/.ssh/id_rsa)"
			invalid=1
		fi
	fi
	
	return $invalid
}



# Caller is expected to have included the cluster configuration file in environment
# prior to calling this.
load_api_env_configuration() {
	
	if [ -z "$1" ]; then
		echo "Error: Missing API configuration file"
		return 1
	fi
	
	source "$1"
	
	local invalid=0
	
	if [ -z "$LINODE_KEY" ]; then
		echo "Validation error: Invalid API configuration file - LINODE_KEY should not be empty"
		invalid=1
	fi
	
	if [ -z "$LINODE_API_URL" ]; then
		echo "Validation error: Invalid API configuration file - LINODE_API_URL should not be empty"
		invalid=1
	fi
	
	if [ -z "$CLUSTER_MANAGER_NODE_PASSWORD" ]; then
		echo "Validation error: CLUSTER_MANAGER_NODE_PASSWORD should be the password of the clustermgr user on cluster manager node."
		invalid=1
	fi
	
	
	return $invalid
}
		



storm_install_dir() {
	local storm_distribution="$INSTALL_STORM_DISTRIBUTION"
	local archive_root_dir=$(tar -tzf $storm_distribution|head -1|sed 's|/.*||')
	
	local storm_install_dir="$STORM_INSTALL_DIRECTORY"
	
	# The tr -s combines multiple slashes into 1 slash.
	local install_dir=$(echo "$storm_install_dir/$archive_root_dir"|tr -s '/')
	echo $install_dir
}


create_status_file() {
	local stfile=$(status_file)
	if [ ! -f "$stfile" ]; then
		touch "$stfile"
		
		# Allow read access to clusteruser so that they can get info about this cluster.
		chmod o+r-wx "$stfile"
	fi
}




# 	$1: section name
#	$2: line data to write
write_status() {
	local stfile=$(status_file)
	add_section $stfile $1
	insert_bottom_of_section $stfile $1 "$2"
}




# 	$1: New status of cluster "creating | created | starting | running | stopping | stopped"
update_cluster_status() {
	local stfile=$(status_file)
	add_section $stfile "status"
	# The 3rd arg "status:" is because insert or replace needs a search string to search and replace.
	insert_or_replace_in_section $stfile "status" "status:" "status:$1"
}




get_cluster_status() {
	local stfile=$(status_file)
	echo $(get_section $stfile "status" | cut -d ':' -f2)
}


# 	$1: New status of security configuration "changed | unchanged"
update_security_status() {
	local stfile=$(status_file)
	add_section $stfile "security"
	# The 3rd arg "status:" is because insert or replace needs a search string to search and replace.
	insert_or_replace_in_section $stfile "security" "status:" "status:$1"
}




get_security_status() {
	local stfile=$(status_file)
	echo $(get_section $stfile "security" | cut -d ':' -f2)
}


# 	$1: New status of security configuration "changed | unchanged"
update_conf_status() {
	local stfile=$(status_file)
	add_section $stfile "conf"
	# The 3rd arg "status:" is because insert or replace needs a search string to search and replace.
	insert_or_replace_in_section $stfile "conf" "status:" "status:$1"
}




get_conf_status() {
	local stfile=$(status_file)
	echo $(get_section $stfile "conf" | cut -d ':' -f2)
}


create_image_status_file() {
	local stfile=$(image_status_file)
	if [ ! -f "$stfile" ]; then
		touch "$stfile"
	fi
}


get_nimbus_node_ipaddr() {
	local stfile=$(status_file)
	local nimbus_node=$(get_section $stfile "nodes" | grep ':nimbus' | cut -d ':' -f1)
	if [ "$CLUSTER_MANAGER_USES_PUBLIC_IP" == "true" ]; then
		get_section $stfile "ipaddresses" | grep $nimbus_node | cut -d ' ' -f3
	else
		get_section $stfile "ipaddresses" | grep $nimbus_node | cut -d ' ' -f2
	fi
}


get_client_node_ipaddr() {
	local stfile=$(status_file)
	local nimbus_node=$(get_section $stfile "nodes" | grep ':client' | cut -d ':' -f1)
	if [ "$CLUSTER_MANAGER_USES_PUBLIC_IP" == "true" ]; then
		get_section $stfile "ipaddresses" | grep $nimbus_node | cut -d ' ' -f3
	else
		get_section $stfile "ipaddresses" | grep $nimbus_node | cut -d ' ' -f2
	fi
}

get_client_node_public_ipaddr() {
	local stfile=$(status_file)
	local nimbus_node=$(get_section $stfile "nodes" | grep ':client' | cut -d ':' -f1)
	get_section $stfile "ipaddresses" | grep $nimbus_node | cut -d ' ' -f3
}


# $1 : The REST endpoint. example: "/api/v1/topology/summary"
get_rest_url() {
	# The UI webapp is actually reverse proxied behind port 80 on client node.
	local client_ip=$(get_client_node_ipaddr)
	echo "http://$client_ip$1"
}

get_ui_port() {
	local ui_port=$(cat "$CLUSTER_CONF_DIR/$CLUSTER_NAME.storm.yaml" | grep 'ui.port'|cut -d ':' -f2|xargs) # xargs trims enclosing whitespaces
	if [ -z "$ui_port" ]; then
		ui_port='8080'
	fi
	echo "$ui_port"
}



status_file() {
	echo "$CLUSTER_CONF_DIR/$CLUSTER_NAME.info"
}



image_status_file() {
	echo "$IMAGE_CONF_DIR/$IMAGE_NAME.info"
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

#	$1 -> Path of local file to copy
#	$2 -> IP address or hostname of node
#	$3 -> SSH login username for node
#	$4 -> SSH private key for node
#	$5 -> Destination file path on node
remote_copyfile() {
	# If the destination file path has spaces in it, the spaces should be escaped using "\ " 
	# to avoid scp's "ambiguous target" error.
	# For example, "/dir with spaces/filename with spaces" should be specified as
	# "/dir\ with\ spaces/filename\ with\ spaces"
	local destfile=$(printf "$5"|sed 's/ /\\ /g')
	
	scp -i "$4" -o IdentitiesOnly=yes -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no "$1" $3@$2:"$destfile"
	return $?
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
	ssh -q -n -x -i "$3" -o IdentitiesOnly=yes -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no $2@$1 ${@:4}
}




case $1 in
	new-image-conf)
	create_new_image_conf "$2"
	;;

	create-image)
	create_storm_image "$2" "$3"
	;;
	
	delete-image)
	delete_storm_image "$2" "$3"
	;;

	new-cluster-conf)
	create_new_cluster_conf "$2"
	;;

	create)
	create_cluster "$2" "$3"
	;;

	start)
	start_cluster "$2" "$3"
	;;

	shutdown|stop)
	stop_cluster "$2" "$3"
	;;

	destroy)
	destroy_cluster "$2" "$3"
	;;

	add-nodes)
	add_nodes "$2" "$3" "$4"
	;;
	
	update-storm-yaml)
	update_storm_yaml "$2"
	;;
	
	update-firewall)
	update_firewall "$2"
	;;
	
	update-user-whitelist)
	update_client_user_whitelist "$2"
	;;
	
	describe)
	describe_cluster "$2"
	;;
	
	run)
	run_cmd "$2" "${@:3}"
	;;
	
	cp)
	copy_files "$2" "$3" "${@:4}"
	;;

	plans)
	list_plans "$2"
	;;
	
	datacenters)
	list_datacenters "$2"
	;;

	distributions)
	list_distributions "$2" "$3"
	;;
	
	kernels)
	list_kernels "$2" "$3"
	;;

	*)
	echo "Unknown command: $1"
	;;
esac


