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

	# ZK_IMAGE_CONF may be a path that is relative to the cluster conf file, such
	# as "../zk-image1/zk-image1.conf" or "../zk-image1" or "/home/clustermgr/storm-linode/zk-image1"
	# We need to resolve it to its absolute path by prefixing it with  $CLUSTER_CONF_DIR
	# to get "$CLUSTER_CONF_DIR/../zk-image1/zk-image1.conf"
	if [ -z "$ZK_IMAGE_CONF" ]; then
		echo "Error: ZK_IMAGE_CONF should be a Zookeeper image directory or image configuration file"
		return 1
	fi
	
	local zk_image_conf
	if [ "${ZK_IMAGE_CONF:0:1}" == "/" ]; then
		# It's an absolute path. Retain as it is.
		zk_image_conf="$ZK_IMAGE_CONF"
	else
		# It's a relative path. Convert to absolute by prefixing with cluster conf dir.
		zk_image_conf="$(readlink -m $CLUSTER_CONF_DIR/$ZK_IMAGE_CONF)"
	fi
	
	if ! load_image_conf "$zk_image_conf"; then
		echo "Error: Change value of ZK_IMAGE_CONF to an existing Zookeeper image directory or image configuration file path."
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
	
	cp zk-image-example.conf "$1/$IMAGE_NAME.conf"
	cp template_zoo.cfg "$1/zoo.cfg"
	cp template_zk_log4j.properties "$1/log4j.properties"
	cp template-zk-supervisord.conf "$1/zk-supervisord.conf"
	
	chmod go-rwx $1/*
	
	echo "Created image directory '$1'"
	echo "Edit $1/$IMAGE_NAME.conf to enter mandatory properties, and then create the image with "
	echo "    zookeeper-cluster-linode.sh create-image $1 <API-ENV-CONF-FILE>"
}




# 	$1 : Name of image directory or Path of image configuration file.
#	$2 : Name of API environment configuration file containing API endpoint and key.
create_zk_image() {
	
	
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
		
		# The number of image limit does not seem to be consistent.
		# Disabling the check.
		#if [ $num_images -eq 3 ]; then
		#	printf "Error: Cannot create image because account limit of 3 images have already been created.\n"
		#	printf "Please delete an image using 'delete-image' or from 'Linode Manager' before retrying.\n"
		#	return 1
		#fi
		
		if [ $total_image_size -ge 9000 ]; then
			printf "Warning: Total size of existing images $total_image_size MB is close to limit of 10240 MB.\n"
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
	
	linode_api linout linerr linret "update-node" $temp_linode_id "zktmp-$temp_linode_id" "temporary"
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

	#echo "Installing prerequisite software"
	install_software_on_node $ipaddr $NODE_USERNAME

	#echo "Installing Zookeeper software"
	install_zookeeper_on_node $ipaddr $NODE_USERNAME
	
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
	

	printf "\n\nFinished creating Zookeeper template image $image_id\n"
	return 0
}



# 	$1 : Name of image directory or Path of image configuration file.
#	$2 : Name of API environment configuration file containing API endpoint and key.
delete_zk_image() {
	
	if ! load_image_conf "$1"; then
		return 1
	fi

	# Include API endpoint configuration file.
	if ! load_api_env_configuration "$2"; then
		return 1
	fi
	
	local stfile="$(image_status_file)"
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

	printf "\n\nFinished deleting Zookeeper image $image_id\n"
	return 0
}



# $1 : Cluster name, or a target directory as absolute or relative path
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
	
	cp zk-cluster-example.conf "$1/$CLUSTER_NAME.conf"
	chmod go-rwx "$1/$CLUSTER_NAME.conf"
	
	echo "Created cluster directory $1. "
	echo "Edit $1/$CLUSTER_NAME.conf to enter mandatory properties, and then create the cluster with "
	echo "    zookeeper-cluster-linode.sh create $1 <API-ENV-CONF-FILE>"
	
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

	echo "Creating Zookeeper cluster $CLUSTER_NAME..."
	
	create_status_file

	update_cluster_status "creating"

	create_new_nodes $CLUSTER_NAME

	start_nodes $CLUSTER_NAME

	# Wait for sometime after nodes have booted up for SSH daemon to come up.
	sleep 15
	
	# Since nodes created from an image retain the image's host keys, they should
	# be changed to unique ones before doing anything else.
	change_hostkeys $CLUSTER_NAME
	
	set_hostnames $CLUSTER_NAME

	distribute_hostsfile $CLUSTER_NAME
	
	# zkdatadir/myid has to be created uniquely in each node.
	# zoo.cfg should contain list of all zk nodes, and distributed to each node.
	assign_zk_node_ids $CLUSTER_NAME
	create_zk_configuration $CLUSTER_NAME
	distribute_zk_configuration $CLUSTER_NAME
	#configure_zookeeper_cluster $CLUSTER_NAME

	# Configure firewall and security on all nodes.
	create_cluster_security_configurations $CLUSTER_NAME
	distribute_cluster_security_configurations $CLUSTER_NAME
	update_security_status "unchanged"
	
	# create may be called either independently or while starting cluster.
	# When called independently, after creation, we can shutdown all nodes.
	# When called by cluster startup, don't shutdown nodes since it's wasteful.
	if [ "$3" != "--dontshutdown" ]; then
		sleep 5
		stop_nodes $CLUSTER_NAME
	fi

	update_cluster_status "created"
	
	echo "Zookeeper cluster successfully created"
}




# 	$1 : Name of cluster directory or Path of cluster configuration file.
#	$2 : The API environment configuration file
start_cluster() {

	echo "Starting Zookeeper cluster $1..."

	if ! load_cluster_conf "$1"; then
		return 1
	fi
	

	if ! load_api_env_configuration "$2"; then
		return 1
	fi
	
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
		# So everything is done by create_cluster, and this function should just start zookeeper service on all nodes.
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

		# So cluster is created, but it's "stopped". We need to start all nodes, get new IP addresses,
		# and distribute hosts file.
		start_nodes $CLUSTER_NAME
		
		# Wait for sometime after nodes have booted up for SSH daemon to come up.
		sleep 15
		
		# The cluster zoo.cfg may have been changed by admin.
		# If so, it should  be distributed.
		local conf_status=$(get_conf_status)
		if [ "$conf_status" == "changed" ]; then
			echo "Zoo.cfg has changed. Applying new configuration"
			distribute_zk_configuration $CLUSTER_NAME
			
			update_conf_status "unchanged"
		fi
		
		# The cluster security configuration may have changed if another cluster
		# requested itself to be whitelisted, or if admin updated the firewall rules. 
		# If so, security configuration should  be recreated and uploaded.
		local security_status=$(get_security_status)
		if [ "$security_status" == "changed" ]; then
			echo "Security configuration has changed. Applying new configuration"
			distribute_cluster_security_configurations $CLUSTER_NAME
			
			update_security_status "unchanged"
		fi
	fi

	# For newly created or restarted, we need to start the zookeeper services.
	# zoo.cfg need not be updated even if node IP addresses have changed, because it uses hostnames, not IP addresses.
	start_zookeeper $CLUSTER_NAME

	update_cluster_status "running"
	
	echo "Zookeeper cluster $CLUSTER_NAME is running"

	return 0
}



# 	$1 : Name of cluster directory or Path of cluster configuration file.
#	$2 : The API environment configuration file
stop_cluster() {

	echo "Stopping cluster $1..."

	if ! load_cluster_conf "$1"; then
		return 1
	fi

	if ! load_api_env_configuration "$2"; then
		return 1
	fi

	update_cluster_status "stopping"

	# First stop zookeeper on all nodes, so that entire ensemble can save whatever state it should.
	stop_zookeeper $CLUSTER_NAME

	# Wait some time before stopping the nodes.
	sleep 10

	stop_nodes $CLUSTER_NAME

	update_cluster_status "stopped"
	
	echo "Zookeeper cluster $CLUSTER_NAME is stopped"
}




#	$1: cluster name
start_nodes() {
	local stfile="$(status_file)"
	local nodes=$(get_section $stfile nodes)
	local boot_jobs=''
	
	for node in $nodes
	do
		echo "Starting linode $node..."
		
		linode_api linout linerr linret "boot" $node
		if [ $linret -eq 1 ]; then
			echo "Failed to boot. Error:$linerr"
			return 1
		fi
		local boot_job_id=$linout
		boot_jobs="$boot_jobs $boot_job_id:$node"
	done
	
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





#	$1: cluster name
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

	echo "Creating $CLUSTER_SIZE new nodes in datacenter $dc_id based on image $image_id..."
	
	
	for i in $CLUSTER_SIZE; do
		plan=$(echo $i|cut -d ':' -f1)
		count=$(echo $i|cut -d ':' -f2)
		
		local plan_id
		case $plan in
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
				echo "Invalid plan $plan. Aborting..."
				return 1
				;;
		esac
		
		echo "Creating $count $plan linodes (plan ID $plan_id)"
		
		local node_count=1
		while [ $node_count -le $count ]; do
			# Create linode with specified plan and datacenter. The 0 at the end
			# avoids validating datacenter id for every iteration. 
			linode_api linout linerr linret "create-node" $plan_id $dc_id 0
			if [ $linret -eq 1 ]; then
				echo "Failed to create $plan linode #$node_count. Error:$linerr"
				return 1
			fi
			local linode_id=$linout
			
			printf "\n\nCreated linode $linode_id\n"

			# Store created linode's instance ID in status file.
			# No need to store additional data like plan ID or datacenter ID
			# because both are available from "linode.list" if required
			write_status "nodes" $linode_id
			node_count=$((node_count+1))

			linode_api linout linerr linret "update-node" $linode_id "zk-$linode_id" "$CLUSTER_NAME"
			if [ $linret -eq 1 ]; then
				echo "Failed to update node label $linode_id. Error:$linerr"
				return 1
			fi
			
			# Create a disk from distribution.
			echo "Creating disk from Zookeeper image for linode $linode_id"
			linode_api linout linerr linret "create-disk-from-image" $linode_id $image_id \
				"Zookeeper" $NODE_DISK_SIZE "$NODE_ROOT_PASSWORD" "$NODE_ROOT_SSH_PUBLIC_KEY"
				
			if [ $linret -eq 1 ]; then
				echo "Failed to create image. Error:$linerr"
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
			echo "Finished creating disk $disk_id from Zookeeper image for linode $linode_id"
			
			
			# Create a swap disk sized according to the linode's RAM.
			# The linode distributions are configured to expect /dev/sdb block device
			# as swap space. If a swap disk is not part of the configuration, everything
			# still succeeds but the dashboard shows a misconfiguration warning, and
			# performance may also suffer.
			echo "Creating swap disk"
			linode_api linout linerr linret "create-swap-disk" $linode_id 
				
			if [ $linret -eq 1 ]; then
				echo "Failed to create swap disk. Error:$linerr"
				return 1
			fi
			local swap_disk_id=$(echo $linout|cut -d ',' -f1)
			local create_swap_disk_job_id=$(echo $linout|cut -d ',' -f2)

			local disk_result
			wait_for_job $create_swap_disk_job_id $linode_id 
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
			linode_api linout linerr linret "create-config" $linode_id $kernel_id \
				"$disk_id,$swap_disk_id" "Zookeeper-configuration" 0
			if [ $linret -eq 1 ]; then
				echo "Failed to create configuration. Error:$linerr"
				return 1
			fi
			local config_id=$linout
			echo "Finished creating configuration $config_id for linode $linode_id"
			
			# Add a private IP for this linode.
			echo "Creating private IP for linode"
			linode_api linout linerr linret "add-private-ip" $linode_id
			if [ $linret -eq 1 ]; then
				echo "Failed to add private IP address. Error:$linerr"
				return 1
			fi
			local private_ip=$linout
			echo "Private IP address $private_ip created for linode $linode_id"

			# Get its public IP
			linode_api linout linerr linret "public-ip" $linode_id
			if [ $linret -eq 1 ]; then
				echo "Failed to get public IP address. Error:$linerr"
				return 1
			fi
			local public_ip=$linout
			echo "Public IP address is $public_ip for linode $linode_id"
			
			insert_or_replace_in_section $stfile "ipaddresses" $linode_id "$linode_id $private_ip $public_ip"
		done
	done
	
}



add_nodes() {
	# One candidate implementation that can be tried out is described in https://gist.github.com/miketheman/6057930.
	# Basically, add new nodes to zoo.cfg of followers, and restart followers.
	# Finally, add new nodes to zoo.cfg of leader and restart leader.
	
	# Another possibility is "dynamic reconfiguration" (https://zookeeper.apache.org/doc/trunk/zookeeperReconfig.html#ch_reconfig_format)
	# but it's available only from >= 3.5.0
	
	# Another possibility from http://stackoverflow.com/questions/11375126/zookeeper-adding-peers-dynamically ...
	# setup a new cluster, snapshot the existing one, restore from snapshot on new cluster, update all clients.
	return 1
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
	while read node;
	do
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
		delete_line $stfile "myids" $node
	done <<< "$nodes"

	# Don't delete status file if there are any failures above
	if [ $failures -eq 0 ]; then	
		echo "Deleting cluster status file..."
		rm -f $stfile

		echo "Deleting cluster hosts file..."
		rm -f "$CLUSTER_CONF_DIR/$CLUSTER_NAME.hosts"

		echo "Deleting cluster ZK cfg file..."
		rm -f "$CLUSTER_CONF_DIR/zoo.cfg"
		
		echo "Deleting security configuration files..."
		rm -f "$CLUSTER_CONF_DIR/$CLUSTER_NAME-all-whitelists.ipsets"  
		rm -f "$CLUSTER_CONF_DIR/$CLUSTER_NAME-rules.v6" 
		rm -f "$CLUSTER_CONF_DIR/$CLUSTER_NAME-rules.ipsets"  
		rm -f "$CLUSTER_CONF_DIR/$CLUSTER_NAME-whitelist.ipsets"
		rm -f "$CLUSTER_CONF_DIR/$CLUSTER_NAME-rules.v4"
		
		# Delete the host entries from this cluster manager machine on which this script is running.
		echo "$CLUSTER_MANAGER_NODE_PASSWORD"|sudo -S sh hostname_manager.sh "delete-cluster" $CLUSTER_NAME
		
		echo "Zookeeper cluster $CLUSTER_NAME is destroyed"
		
	else
		echo "Leaving cluster status file intact, because some nodes could not be destroyed"
	fi
}



#	$1 : Name of cluster as in cluster conf file.
stop_nodes() {
	local stfile="$(status_file)"
	local nodes=$(get_section $stfile "nodes")
	local shutdown_jobs=''

	for node in $nodes
	do
		echo "Shutting down $node"
		linode_api linout linerr linret "shutdown" $node
		if [ $linret -eq 1 ]; then
			echo "Failed to shutdown. Error:$linerr"
			return 1
		fi
		local shutdown_job_id=$linout
		shutdown_jobs="$shutdown_jobs $shutdown_job_id:$node"
	done
	
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
change_hostkeys() {
	local stfile="$(status_file)"

	local ipaddrs=$(get_section $stfile "ipaddresses")

	while read entry;
	do
		# An entry in ipaddresses section is of the form "linode_id private_ipaddress public_ipaddress"
		local arr=($entry)
		local linode_id=${arr[0]}
		local private_ip=${arr[1]}
		local public_ip=${arr[2]}
		
		echo "Changing host keys of $linode_id..."

		# Default ssh target is the private IP address.
		local target_ip=$private_ip
		if [ "$CLUSTER_MANAGER_USES_PUBLIC_IP" == "true" ]; then
			target_ip=$public_ip
		fi

		ssh_command $target_ip $NODE_USERNAME $NODE_ROOT_SSH_PRIVATE_KEY "sh -c
			\"rm /etc/ssh/ssh_host_*;/usr/sbin/dpkg-reconfigure openssh-server\""
			
	done <<< "$ipaddrs" # The "$ipaddrs" should be in double quotes because output is multline
}



#	$1 : Name of the cluster 
set_hostnames() {
	local stfile="$(status_file)"
	# Note: output of get_section is multiline, so always use it inside double quotes such as "$entries"
	local entries=$(get_section $stfile "ipaddresses")

	add_section $stfile "hostnames"

	local node_count=1

	while read entry;
	do
		# An entry in ipaddresses section is of the form "linode_id private_ipaddress public_ipaddress"
		local arr=($entry)
		local linode_id=${arr[0]}
		local private_ip=${arr[1]}
		local public_ip=${arr[2]}

		local new_public_host_name=$PUBLIC_HOST_NAME_PREFIX$node_count
		local new_private_host_name=$PRIVATE_HOST_NAME_PREFIX$node_count
		echo "Changing hostname of $linode_id [$private_ip] to $new_private_host_name..."

		# IMPORTANT: Anything that eventually calls ssh inside a while read loop should do so with ssh -n option
		# to avoid terminating the while read loop. This is because ssh without -n option reads complete stdin by default,
		# as explained in http://stackoverflow.com/questions/346445/bash-while-read-loop-breaking-early
		set_hostname $new_private_host_name $private_ip $new_public_host_name $public_ip $NODE_USERNAME $1
		
		insert_or_replace_in_section $stfile "hostnames" $linode_id "$linode_id $new_private_host_name $new_public_host_name"
		node_count=$((node_count+1))
	done <<< "$entries" # The "$entries" should be in double quotes because output is multline
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
	chmod go-rwx "$hostsfile"
	
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

		remote_copyfile ./textfileops.sh $target_ip $NODE_USERNAME $NODE_ROOT_SSH_PRIVATE_KEY textfileops.sh
		remote_copyfile ./hostname_manager.sh $target_ip $NODE_USERNAME  $NODE_ROOT_SSH_PRIVATE_KEY hostname_manager.sh
		remote_copyfile $hostsfile $target_ip $NODE_USERNAME  $NODE_ROOT_SSH_PRIVATE_KEY "$CLUSTER_NAME.hosts"

		ssh_command $target_ip $NODE_USERNAME $NODE_ROOT_SSH_PRIVATE_KEY sh hostname_manager.sh "hosts-file" $1 "$CLUSTER_NAME.hosts"
		
	done <<< "$ipaddrs"

	# Add the host entries to this very cluster manager machine on which this script is running.
	echo "$CLUSTER_MANAGER_NODE_PASSWORD"|sudo -S sh hostname_manager.sh "hosts-file" $1 $hostsfile
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
						chown -R "$IMAGE_ADMIN_USER:$IMAGE_ADMIN_USER" "/home/$IMAGE_ADMIN_USER/.ssh"
				fi
			fi
		fi
	fi
	
	# Create zookeeper user and group.
	if [ "$ZOOKEEPER_USER" != "root" ]; then
		echo "Creating user $ZOOKEEPER_USER:$ZOOKEEPER_USER"
		local install_dir=$(zk_install_dir)
		# --group automatically creates a system group with same name as username.
		# --gecos "" is to prevent the interactive prompting for full name and other details.
		ssh_command $1 $NODE_USERNAME $IMAGE_ROOT_SSH_PRIVATE_KEY \
			adduser --system --group --home $install_dir --gecos "" --no-create-home --shell /bin/sh \
				--disabled-password --disabled-login $ZOOKEEPER_USER
	fi
	
	return 0
}


# $1 : IP address of node
# $2 : SSH username for node
install_software_on_node() {
	
	# Disable IPv6 both to keep the firewall configuration tight and because
	# apt-get seems to hang on security.ubuntu.com domains when it's enabled.
	echo "Disabling IPv6"

	ssh_command $1 $2 $IMAGE_ROOT_SSH_PRIVATE_KEY \
		"sh -c \"echo 'net.ipv6.conf.all.disable_ipv6 = 1' >> /etc/sysctl.conf;echo 'net.ipv6.conf.default.disable_ipv6 = 1' >> /etc/sysctl.conf;echo 'net.ipv6.conf.lo.disable_ipv6 = 1' >> /etc/sysctl.conf\""
	ssh_command $1 $2 $IMAGE_ROOT_SSH_PRIVATE_KEY sysctl -p
	
	# Update repo information before installing.
	ssh_command $1 $2 $IMAGE_ROOT_SSH_PRIVATE_KEY apt-get -y update
	
	if [ "$UPGRADE_OS" == "yes" ]; then
		echo "Upgrading OS on $1..."

		ssh_command $1 $2 $IMAGE_ROOT_SSH_PRIVATE_KEY apt-get -y upgrade
	else	
		echo "Not upgrading OS on $1..."
	fi



	echo "Installing OpenJDK JRE 7 on $1..."
	ssh_command $1 $2 $IMAGE_ROOT_SSH_PRIVATE_KEY apt-get -y install openjdk-7-jre-headless



	# Install service supervisor package
	echo "Installing Supervisord on $1..."
	ssh_command $1 $2 $IMAGE_ROOT_SSH_PRIVATE_KEY apt-get -y install supervisor
	
	local image_supervisord_conf="$IMAGE_CONF_DIR/zk-supervisord.conf"
	# Replace occurrences of $ZOOKEEPER_USER with its value. The sed is not passed with -r because $ is special
	# character meaning beginning of line in a regex. Not sure how exactly to escape a $ when using -r...\$ didn't work.
	sed -i "s/\$ZOOKEEPER_USER/$ZOOKEEPER_USER/g" "$image_supervisord_conf"

	# Replace ZK_INSTALL_DIR with the absolute directory path of storm home.
	local install_dir=$(zk_install_dir)
	# Since install_dir value will have / slashes, we use | as the sed delimiter to avoid sed errors.	
	sed -i "s|\$ZK_INSTALL_DIR|$install_dir|g" "$image_supervisord_conf"

	remote_copyfile "$image_supervisord_conf" $1 $2 $IMAGE_ROOT_SSH_PRIVATE_KEY "/etc/supervisor/conf.d/zk-supervisord.conf"

	# From https://github.com/Supervisor/supervisor/blob/master/supervisor/supervisorctl.py, supervisor update 
	# first does the same thing as a reread and then restarts changed programs. So despite what many discussions 
	# say, there's no need to first reread and then update.
	ssh_command $1 $2 $IMAGE_ROOT_SSH_PRIVATE_KEY "supervisorctl update"
	

	# Install packages required for iptables firewall configuration.
	# The debconf commands are because iptables-persistent asks interactively to save
	# existing rules during installation.
	# kmod is required because /sbin/modprobe is not part of Linode's Debian distro.
	echo "Installing kmod, ipset and iptables-persistent"
	ssh_command $1 $2 $IMAGE_ROOT_SSH_PRIVATE_KEY sh -c \
		"DEBIAN_FRONTEND=noninteractive; export DEBIAN_FRONTEND;
		echo iptables-persistent iptables-persistent/autosave_v4 boolean false | debconf-set-selections;
		echo iptables-persistent iptables-persistent/autosave_v6 boolean false | debconf-set-selections;
		apt-get -y install kmod ipset iptables-persistent"
	
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

	
}




# $1 : IP address of node
# $2 : SSH username for node
install_zookeeper_on_node() {
	
	echo "Installing $INSTALL_ZOOKEEPER_DISTRIBUTION on $1..."

	local remote_path=$(basename "$INSTALL_ZOOKEEPER_DISTRIBUTION")
	remote_copyfile "$INSTALL_ZOOKEEPER_DISTRIBUTION" $1 $2 $IMAGE_ROOT_SSH_PRIVATE_KEY $remote_path

	ssh_command $1 $2 $IMAGE_ROOT_SSH_PRIVATE_KEY tar -C $ZOOKEEPER_INSTALL_DIRECTORY -xzf $remote_path

	# The tr -s / combines multiple slashes into a single slash.
	local install_dir=$(zk_install_dir)

	
	# Create ZK data directory.
	# Though zoo.cfg is a simple key=value format file, so it can't be directly loaded as a bash script always
	# because it can contain keys with periods in their names, which are not supported by shell.
	# So parsing it instead.
	local dataDir=$(grep 'dataDir=' "$IMAGE_CONF_DIR/zoo.cfg"|cut -d '=' -f 2)
	echo "Creating ZK data directory $dataDir"
	ssh_command $1 $2 $IMAGE_ROOT_SSH_PRIVATE_KEY "sh -c \"mkdir -p $dataDir;chown -R $ZOOKEEPER_USER:$ZOOKEEPER_USER $dataDir\""
	
	# Copy template zoo.cfg to installation directory.
	local remote_cfg_path=$install_dir/conf/zoo.cfg
	echo "Copying template ZK configuration to $remote_cfg_path"
	remote_copyfile "$IMAGE_CONF_DIR/zoo.cfg" $1 $2 $IMAGE_ROOT_SSH_PRIVATE_KEY $remote_cfg_path
	
	# Create java.env with JVM heap settings in installation directory.
	# If the values are percentages, then they are dynamically calculated later on at cluster
	# creation time based on the individual node's plan. Since java.env should not be invalid and Xm values
	# can't be percentages, set them to a default value of 1536M (which is 75% of the lowest linode 2GB RAM plan).
	# The single quotes around $JVMFLAGS is to ensure that JVMFLAGS value remains enclosed in single quotes "-Xms -Xmx"
	# Otherwise, it gives an error "-Xmx is unknown command" due to the space char in the middle.
	local min_heap="$ZOOKEEPER_MIN_HEAP_SIZE"
	local min_heap_value="$(echo $min_heap | tr -d '%kKmMgG')"
	local min_heap_units="$(echo $min_heap | tr -d '[:digit:]')"
	local max_heap="$ZOOKEEPER_MAX_HEAP_SIZE"
	local max_heap_value="$(echo $max_heap | tr -d '%kKmMgG')"
	local max_heap_units="$(echo $max_heap | tr -d '[:digit:]')"
	if [ "$min_heap_units" == "%" ]; then 
		min_heap="1536M"
	fi
	if [ "$max_heap_units" == "%" ]; then 
		max_heap="1536M"
	fi
	local java_env_contents="export JVMFLAGS=\'-Xms$min_heap -Xmx$max_heap\'"
	ssh_command $1 $2 $IMAGE_ROOT_SSH_PRIVATE_KEY "sh -c \"echo $java_env_contents > $install_dir/conf/java.env\""

	# ZK logging is seriously screwed up.
	# It has a conf/log4j.properties with properties like zookeeper.log.dir that at first looks like the
	# log directory that'll be used. Also, "tracing" in their terminology means whatever is output to stdout.
	# But zkServer.sh ignores all that and instead uses 2 env variables ZOO_LOG_DIR and ZOO_LOG4J_PROP(default "INFO,CONSOLE")
	# These variables can be set in conf/zookeeper-env.sh.
	# 	
	# So the approach here is 
	# 1. Read the template log4j properties and get log directory and logger configuration from it.
	# 2. Set ZOO_LOG_DIR and ZOO_LOG4J_PROP to those values in conf/zookeeper-env.sh.
	# Copy template log4j.properties to VM.
	local remote_log4j_path=$install_dir/conf/log4j.properties
	echo "Copying template ZK log4j properties to $remote_log4j_path"
	remote_copyfile "$IMAGE_CONF_DIR/log4j.properties" $1 $2 $IMAGE_ROOT_SSH_PRIVATE_KEY $remote_log4j_path

	# Create the log file directory specified in template log4j properties, and change its ownership.
	local log_dir=$(grep 'zookeeper.log.dir=' "$IMAGE_CONF_DIR/log4j.properties"|cut -d '=' -f 2)
	if [ -z "$log_dir" ]; then
		echo "$IMAGE_CONF_DIR/log4j.properties does not specify a logging directory. Setting to default /var/log/zk"
		log_dir=/var/log/zk

	elif [[ $log_dir =~ ^\.{1,2}$|^\.{1,2}/.* ]]; then
		# If log_dir is a relative path starting with . or .., prefix it with installation directory so that it resolves correctly.
		log_dir=$install_dir/$log_dir
	fi
	echo "Creating ZK logging directory $log_dir"
	ssh_command $1 $2 $IMAGE_ROOT_SSH_PRIVATE_KEY "sh -c \"mkdir -p $log_dir;chown -R $ZOOKEEPER_USER:$ZOOKEEPER_USER $log_dir\""

	# Create conf/zookeeper-env.sh and set the logging variables used by zkServer.sh.
	local root_logger_value=$(grep '^log4j.rootLogger' "$IMAGE_CONF_DIR/log4j.properties" | head -1 | cut -d '=' -f 2)
	ssh_command $1 $2 $IMAGE_ROOT_SSH_PRIVATE_KEY "sh -c \"printf 'export ZOO_LOG_DIR=$log_dir\nexport ZOO_LOG4J_PROP=$remote_log4j_path\n' > $install_dir/conf/zookeeper-env.sh\""

	# Transfer ownership of the installed directory to zk user.
	echo "Changing ownership of $install_dir to $ZOOKEEPER_USER..."
	ssh_command $1 $2 $IMAGE_ROOT_SSH_PRIVATE_KEY "chown -R $ZOOKEEPER_USER:$ZOOKEEPER_USER $install_dir"
}


#	$1 : Name of the cluster 
assign_zk_node_ids() {
	echo "Assigning unique 'myid' to all nodes in zookeeper cluster..."

	local stfile="$(status_file)"

	local ipaddrs=$(get_section $stfile "ipaddresses")

	add_section $stfile "myids"
	
	# We need the zk datadir from image's zoo.cfg.
	local dataDir=$(grep 'dataDir=' "$IMAGE_CONF_DIR/zoo.cfg"|cut -d '=' -f 2)
	local zk_node_id=1
	while read ipentry;
	do
		# An entry in hostnames section is of the form "linode_id private_hostname public_hostname"
		local arr=($ipentry)
		local linode_id=${arr[0]}
		local private_ip=${arr[1]}
		local public_ip=${arr[2]}

		local target_ip=$private_ip
		if [ "$CLUSTER_MANAGER_USES_PUBLIC_IP" == "true" ]; then
			target_ip=$public_ip
		fi

		echo "Creating myid=$zk_node_id in linode:$linode_id, IP:$target_ip"
		ssh_command $target_ip $NODE_USERNAME $NODE_ROOT_SSH_PRIVATE_KEY "printf $zk_node_id > $dataDir/myid"

		insert_or_replace_in_section $stfile "myids" $linode_id "$linode_id $zk_node_id"
		
		zk_node_id=$((zk_node_id+1))

	done <<< "$ipaddrs"
}


#	$1 : Name of the cluster 
create_zk_configuration() {
	echo "Creating zookeeper configuration file..."

	local stfile="$(status_file)"

	local hostnames=$(get_section $stfile "hostnames")
	local myids=$(get_section $stfile "myids")

	# Every node's zoo.cfg should list all the other nodes in the format 
	# server.<myid>=<host>:<port_to_connect_to_leader>:<leader_election_port>
	# Create a local copy of the image's zoo.cfg called <cluster>.zoo.cfg and include all these entries.
	local cluster_cfg="$CLUSTER_CONF_DIR/zoo.cfg"
	local zk_conf_template="$IMAGE_CONF_DIR/zoo.cfg"
	cp "$zk_conf_template" "$cluster_cfg"
	chmod go-rwx "$cluster_cfg"
	
	add_section $cluster_cfg "nodes"

	# Assign a unique myid to each node in cluster.
	while read hostentry;
	do
		# An entry in hostnames section is of the form "linode_id private_hostname public_hostname"
		local arr=($hostentry)
		local linode_id=${arr[0]}
		local private_host_name=${arr[1]}
		local public_host_name=${arr[2]}

		local use_host_name=$private_host_name
		
		# An entry in myids section is of the form "linode_id myid"
		local zk_node_id=$(echo "$myids" | grep $linode_id | cut -d ' ' -f 2)
		
		local cfg_entry="server.$zk_node_id=$use_host_name:$ZOOKEEPER_LEADER_CONNECTION_PORT:$ZOOKEEPER_LEADER_ELECTION_PORT"
		insert_bottom_of_section $cluster_cfg "nodes" $cfg_entry

	done <<< "$hostnames"
}


#	$1 : Name of the cluster 
distribute_zk_configuration() {
	echo "Distributing zookeeper configuration..."

	local stfile="$(status_file)"

	local ipaddrs=$(get_section $stfile "ipaddresses")

	local cluster_cfg="$CLUSTER_CONF_DIR/zoo.cfg"
	
	# In addition to zoo.cfg, if the image conf specified min/max heap sizes
	# as percentages, we have to dynamically create $install_dir/conf/java.env
	# on each node based on that node's memory.
	local img_min_heap="$ZOOKEEPER_MIN_HEAP_SIZE"
	local img_max_heap="$ZOOKEEPER_MAX_HEAP_SIZE"
	local img_min_heap_units="$(echo $img_min_heap|tr -d '[:digit:]')"
	local img_min_heap_value="$(echo $img_min_heap|tr -d '%kKmMgG')"
	local img_max_heap_units="$(echo $img_max_heap|tr -d '[:digit:]')"
	local img_max_heap_value="$(echo $img_max_heap|tr -d '%kKmMgG')"
	local calc_min_heap=0
	if [ "$img_min_heap_units" == "%" ]; then
		calc_min_heap=1
	fi
	local calc_max_heap=0
	if [ "$img_max_heap_units" == "%" ]; then
		calc_max_heap=1
	fi

	local linout linerr linret
	
	# Now we need the ZK installation directory on a node.
	local install_dir=$(zk_install_dir)
	local remote_cfg_path=$install_dir/conf/zoo.cfg
	while read entry;
	do
		local arr=($entry)
		local linode_id=${arr[0]}
		local private_ip=${arr[1]}
		local public_ip=${arr[2]}

		local target_ip=$private_ip
		if [ "$CLUSTER_MANAGER_USES_PUBLIC_IP" == "true" ]; then
			target_ip=$public_ip
		fi

		echo "Copying $cluster_cfg to node $linode_id [$target_ip] $remote_cfg_path..."
		remote_copyfile $cluster_cfg $target_ip $NODE_USERNAME $NODE_ROOT_SSH_PRIVATE_KEY $remote_cfg_path
		
		if [ $calc_min_heap -eq 1 -o $calc_max_heap -eq 1 ]; then
			linode_api linout linerr linret "ram" $linode_id
			if [ $linret -eq 1 ]; then
				# It's not a fatal error, because the image has a valid heap size.
				echo "Failed to get RAM of linode $linode_id. Heap settings are unchanged. Error:$linerr"
				continue
			fi
			
			# The RAM value is in MB.
			local ram=$linout
			local min_heap=$img_min_heap
			if [ $calc_min_heap -eq 1 ]; then
				# This is always an integer division. min_heap will be in MB.
				min_heap=$((ram * img_min_heap_value / 100))
			fi
			local max_heap=$img_max_heap
			if [ $calc_max_heap -eq 1 ]; then
				# This is always an integer division. max_heap will be in MB.
				max_heap=$((ram * img_max_heap_value / 100))
			fi
			
			local java_env_contents="export JVMFLAGS=\'-Xms${min_heap}M -Xmx${max_heap}M\'"
			ssh_command $target_ip $NODE_USERNAME $NODE_ROOT_SSH_PRIVATE_KEY "sh -c \"echo $java_env_contents > $install_dir/conf/java.env\""
		fi
		
	done <<< "$ipaddrs"
}



# Admin can modify the cluster's zoo.cfg and call this to re-upload 
# it to entire cluster and restart zookeeper services.
# 	$1 : Name of cluster directory or Path of cluster configuration file.
update_zk_configuration() {
	if ! load_cluster_conf "$1"; then
		return 1
	fi

	local cluster_status=$(get_cluster_status)
	if [ "$cluster_status" == "running" ]; then
		# First stop zookeeper on all nodes, so that entire ensemble can save whatever state it should.
		stop_zookeeper $CLUSTER_NAME

		# Distribute modified zoo.cfg to all nodes.
		distribute_zk_configuration $CLUSTER_NAME
		
		# Restart zookeeper on all nodes.
		start_zookeeper $CLUSTER_NAME

		update_conf_status "unchanged"
	else
		# Mark configuration as changed, so that new configuration gets applied at next start.
		update_conf_status "changed"
	fi
}





#	$1 : Name of the cluster 
create_cluster_security_configurations() {
	local stfile="$(status_file)"
	
	# Zookeeper whitelists are of 2 types
	# 1) the whitelist consisting of nodes of zk cluster itself
	# 2) the whitelists of other clusters which use this zk cluster
	#
	# The final rules.ipsets that is uploaded to all zk nodes should be a combination
	# of all these ipsets, and a meta list (ie, an ipset "list:set") made up of these cluster sets.
	#
	# rules.v4 then just has to allow the list of sets. It need not list each and every cluster set.
	#
	# IMPORTANT: Whitelist names can't be >31 characters.
	
	create_cluster_whitelist_internal $1
	local zk_cluster_whitelist_file="$CLUSTER_CONF_DIR/$CLUSTER_NAME-whitelist.ipsets"
	
	local ipsets_file="$CLUSTER_CONF_DIR/$CLUSTER_NAME-rules.ipsets"
	cat $zk_cluster_whitelist_file > $ipsets_file
	chmod go-rwx "$ipsets_file"
	
	local all_whitelists_file="$CLUSTER_CONF_DIR/$CLUSTER_NAME-all-whitelists.ipsets"
	echo "create all-whitelists list:set size 32" > $all_whitelists_file
	echo "add all-whitelists $CLUSTER_NAME-wl" >> $all_whitelists_file
	chmod go-rwx "$all_whitelists_file"
	
	local other_cluster_whitelists=$(get_section $stfile "whitelisted-clusters")
	if [ "$other_cluster_whitelists" != "" ]; then
		while read other_cluster_whitelist_file
		do
			local whitelist_name=$(cat $other_cluster_whitelist_file|grep create|cut -d ' ' -f2)
			echo "add all-whitelists $whitelist_name" >> $all_whitelists_file
			
			cat $other_cluster_whitelist_file >> $ipsets_file
		done <<< "$other_cluster_whitelists"
	fi
	
	cat $all_whitelists_file >> $ipsets_file
	
	# Make a copy of the referred v4 rules file into the cluster conf directory.
	local template_v4_rules_file="$IPTABLES_V4_RULES_TEMPLATE"
	if [ "${template_v4_rules_file:0:1}" != "/" ]; then
		template_v4_rules_file=$(readlink -m "$CLUSTER_CONF_DIR/$template_v4_rules_file")
	fi
	
	local cluster_v4_rules_file="$CLUSTER_CONF_DIR/$CLUSTER_NAME-rules.v4"
	
	cp "$template_v4_rules_file" "$cluster_v4_rules_file"
	chmod go-rwx "$cluster_v4_rules_file"
	
	sed -i "s/\$CLUSTER_NAME/$CLUSTER_NAME/g" "$cluster_v4_rules_file"

	# Make a copy of the referred v6 rules file into the cluster conf directory.
	local template_v6_rules_file="$IPTABLES_V6_RULES_TEMPLATE"
	if [ "${template_v6_rules_file:0:1}" != "/" ]; then
		template_v6_rules_file=$(readlink -m "$CLUSTER_CONF_DIR/$template_v6_rules_file")
	fi
	
	local cluster_v6_rules_file="$CLUSTER_CONF_DIR/$CLUSTER_NAME-rules.v6"
	
	cp "$template_v6_rules_file" "$cluster_v6_rules_file"
	chmod go-rwx "$cluster_v6_rules_file"
	sed -i "s/\$CLUSTER_NAME/$CLUSTER_NAME/g" "$cluster_v6_rules_file"

}


#	$1 : Name of the cluster 
distribute_cluster_security_configurations() { 
	local stfile="$(status_file)"

	local ipsets_file="$CLUSTER_CONF_DIR/$CLUSTER_NAME-rules.ipsets"
	
	local zk_iptables_v4_rules_file="$CLUSTER_CONF_DIR/$CLUSTER_NAME-rules.v4"
	local zk_iptables_v6_rules_file="$CLUSTER_CONF_DIR/$CLUSTER_NAME-rules.v6"
	
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
		
		echo "Distributing security files to linode:$linode_id, IP:$target_ip"
		
		remote_copyfile $ipsets_file $target_ip $NODE_USERNAME $NODE_ROOT_SSH_PRIVATE_KEY /etc/iptables/rules.ipsets
		remote_copyfile $zk_iptables_v4_rules_file $target_ip $NODE_USERNAME $NODE_ROOT_SSH_PRIVATE_KEY /etc/iptables/rules.v4
		remote_copyfile $zk_iptables_v6_rules_file $target_ip $NODE_USERNAME $NODE_ROOT_SSH_PRIVATE_KEY /etc/iptables/rules.v6
		
		# Apply the firewall configuration immediately.
		# The flush is to remove iptables rule that refer to a ipset, because we can't delete ipset otherwise.
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
		
	done <<< "$ipaddrs"
}


# 	$1 : Name of cluster directory or Path of cluster configuration file.
create_cluster_whitelist() {
	
	if ! load_cluster_conf "$1"; then
		return 1
	fi
	
	create_cluster_whitelist_internal $CLUSTER_NAME	
}


#	$1 : the cluster name as in the cluster conf file.
create_cluster_whitelist_internal() {
	local stfile="$(status_file)"
	
	local zk_cluster_whitelist_file="$CLUSTER_CONF_DIR/$1-whitelist.ipsets"
	
	if [ -f "$zk_cluster_whitelist_file" ]; then
		return
	fi
	
	# An ipset name shouldn't be >31 characters.So minimize any suffix.
	local zk_cluster_whitelist_name="$1-wl"
	echo "create $zk_cluster_whitelist_name hash:ip family inet hashsize 1024 maxelem 65536" > $zk_cluster_whitelist_file
	local ipaddrs=$(get_section $stfile "ipaddresses")
	while read ipentry 
	do
		local arr=($ipentry)
		local linode_id=${arr[0]}
		local private_ip=${arr[1]}

		echo "add $zk_cluster_whitelist_name $private_ip" >> $zk_cluster_whitelist_file
	done <<< "$ipaddrs"	
}


# 	$1 : Name of cluster directory or Path of cluster configuration file.
#	$2 : the path of ipsets whitelist file of other cluster, relative to script directory.
add_to_whitelist() {

	if ! load_cluster_conf "$1"; then
		return 1
	fi
	
	local stfile=$(status_file)
	if [ ! -f "$stfile" ]; then
		echo "Zookeeper cluster does not exist. Aborting"
		return 1
	fi
	
	local cluster_status=$(get_cluster_status)
	if [[ "$cluster_status" != "running" && "$cluster_status" != "created"  && "$cluster_status" != "stopped" ]]; then
		echo "Zookeeper cluster should be created, running or stopped to add to its whitelist. Aborting"
		return 1
	fi
	
	add_section $stfile "whitelisted-clusters"
	
	# A ZK cluster may be shared by multiple storm or other clusters.
	# Each client cluster should tell this ZK cluster to whitelist client
	# nodes in iptables of zk nodes.
	# 
	# This script should maintain a list of all such client clusters
	# who tell it to whitelist them.
	insert_or_replace_in_section $stfile "whitelisted-clusters" $2 "$2"

	create_cluster_security_configurations $CLUSTER_NAME
	
	# When should this configuration be applied? If cluster is running,
	# it should be applied immediately, otherwise at next startup.
	if [ "$cluster_status" == "running" ]; then
		distribute_cluster_security_configurations $CLUSTER_NAME
		update_security_status "unchanged"
	else
		# Set security status to "changed" so that it gets applied at next
		# cluster start.
		update_security_status "changed"
	fi
}


# 	$1 : Name of cluster directory or Path of cluster configuration file.
#	$2 : the name of whitelist file of other cluster, in ipsets format.
remove_from_whitelist() {

	if ! load_cluster_conf "$1"; then
		return 1
	fi

	
	local stfile=$(status_file)
	if [ ! -f "$stfile" ]; then
		echo "Zookeeper cluster does not exist. Aborting"
		return 1
	fi
	
	local cluster_status=$(get_cluster_status)
	if [[ "$cluster_status" != "running" && "$cluster_status" != "created"  && "$cluster_status" != "stopped" ]]; then
		echo "Zookeeper cluster should be created, running or stopped to remove from its whitelist. Aborting"
		return 1
	fi
	
	
	delete_line $stfile "whitelisted-clusters" "$2"

	create_cluster_security_configurations $CLUSTER_NAME
	
	# When should this configuration be applied? If cluster is running,
	# it should be applied immediately, otherwise at next startup.
	local cluster_status=$(get_cluster_status)
	if [ "$cluster_status" == "running" ]; then
		distribute_cluster_security_configurations $CLUSTER_NAME
		update_security_status "unchanged"
	else
		# Set security status to "changed" so that it gets applied at next
		# cluster start.
		update_security_status "changed"
	fi
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



#	$1 : Name of the cluster 
start_zookeeper() {
	echo "Starting zookeeper service on cluster..."

	local stfile="$(status_file)"
	# Note: output of get_section is multiline, so always use it inside double quotes such as "$entries"
	local ipaddrs=$(get_section $stfile "ipaddresses")

	while read ipentry;
	do
		local arr=($ipentry)
		local linode_id=${arr[0]}
		local private_ip=${arr[1]}
		local public_ip=${arr[2]}

		local target_ip=$private_ip
		if [ "$CLUSTER_MANAGER_USES_PUBLIC_IP" == "true" ]; then
			target_ip=$public_ip
		fi

		echo "Starting zookeeper service on $linode_id [$target_ip]..."
		
		# When running under supervision, according to https://groups.google.com/d/msg/storm-user/_L6i2JLjQwA/H1LMX2s6JV4J,
		# it's preferable to use start-foreground (this is configured in zk-supervisord.conf)
		ssh_command $target_ip $NODE_USERNAME $NODE_ROOT_SSH_PRIVATE_KEY "supervisorctl start zookeeper"
	done <<< "$ipaddrs"
}



#	$1 : Name of the cluster 
stop_zookeeper() {
	echo "Stopping zookeeper service on cluster..."
	
	local stfile="$(status_file)"
	# Note: output of get_section is multiline, so always use it inside double quotes such as "$entries"
	local ipaddrs=$(get_section $stfile "ipaddresses")

	while read ipentry;
	do
		local arr=($ipentry)
		local linode_id=${arr[0]}
		local private_ip=${arr[1]}
		local public_ip=${arr[2]}

		local target_ip=$private_ip
		if [ "$CLUSTER_MANAGER_USES_PUBLIC_IP" == "true" ]; then
			target_ip=$public_ip
		fi

		echo "Stopping zookeeper service on $linode_id [$target_ip]..."

		ssh_command $target_ip $NODE_USERNAME $NODE_ROOT_SSH_PRIVATE_KEY "supervisorctl stop zookeeper"


		# Give some time for each node to become aware of another node stopping
		# and take recovery action.
		echo "Waiting sometime before stopping service on next node"
		sleep 10
	done <<< "$ipaddrs"
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
			  Linode ID:        $zk_linode_id
			  Private IP:       $zk_private_ip
			  Private hostname: $zk_private_host
			  Public IP:        $zk_public_ip
			  Public hostname:  $zk_public_host
			  ZK ID:            $zk_id

		ENDSTANZA
	
	done <<< "$(echo "$nodes")"
	
	return 0
}




# 	$1 : Name of cluster directory or Path of cluster configuration file.
# $2... : Command to be run on all nodes of cluster.
run_cmd() {

	if ! load_cluster_conf "$1"; then
		return 1
	fi

	local stfile="$(status_file)"
	if [ ! -f "$stfile" ]; then
		echo "Cluster is not created. Command can be run only on existing cluster."
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
	if [ ! -f "$stfile" ]; then
		echo "Cluster is not created. Files can be copied only to existing cluster."
		return 1
	fi
	
	local cluster_status=$(get_cluster_status)
	if [ "$cluster_status" != "running" ]; then
		echo "Cluster is not running. Files can be copied only to running cluster."
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
	
	./linode_api.py 'datacenters' 'table'
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
	# A simple name like "zkimage1" is treated like a relative path and becomes <ABSOLUTE_CURRENT_DIR>/zkimage1
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
			Run ./zookeeper-cluster-linode.sh distributions API-CONF-FILE to list them.\n"
		invalid=1
	fi
	
	if [ -z "$LABEL_FOR_IMAGE" ]; then
		echo "Validation error: LABEL_FOR_IMAGE should specify a name for the label. Enclose in quotes if it contains spaces."
		invalid=1
	fi
	
	if [ -z "$KERNEL_FOR_IMAGE" ]; then
		printf "Validation error: KERNEL_FOR_IMAGE should specify a kernel ID or label.\n \
			Run ./zookeeper-cluster-linode.sh kernels API-CONF-FILE to list them.\n"
		invalid=1
	fi
	
	if [ -z "$DATACENTER_FOR_IMAGE" ]; then
		printf "Validation error: DATACENTER_FOR_IMAGE should specify a datacenter ID or location or abbreviation.\n \
			Run ./zookeeper-cluster-linode.sh datacenters API-CONF-FILE to list them.\n"
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
	
	if [ -z "$ZOOKEEPER_USER" ]; then
		echo "Validation error: ZOOKEEPER_USER should not be empty."
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

	if [ -z "$INSTALL_ZOOKEEPER_DISTRIBUTION" ]; then
		echo "Validation error: INSTALL_ZOOKEEPER_DISTRIBUTION should be a Zookeeper distribution archive."
		invalid=1
		
	elif [ ! -f "$INSTALL_ZOOKEEPER_DISTRIBUTION" ]; then
		echo "Validation error: Zookeeper distribution archive path INSTALL_ZOOKEEPER_DISTRIBUTION does not exist."
		invalid=1
		
	elif ! tar -tzf "$INSTALL_ZOOKEEPER_DISTRIBUTION" >/dev/null ; then
		echo "Validation error: INSTALL_ZOOKEEPER_DISTRIBUTION does not seem to be a valid archive file."
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
	
	if [ -z "$ZK_IMAGE_CONF" ]; then
		echo "Validation error: ZK_IMAGE_CONF should be the path of a image configuration file"
		invalid=1
		
	elif [ ! -f "$IMAGE_CONF_FILE" ]; then
		echo "Validation error: ZK_IMAGE_CONF should be the path of a image configuration file"
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
		echo "Validation error: Invalid API configuration file - CLUSTER_MANAGER_NODE_PASSWORD should be the password of the clustermgr user on cluster manager node."
		invalid=1
	fi
	
	
	return $invalid
}
		



zk_install_dir() {
	local zk_distribution="$INSTALL_ZOOKEEPER_DISTRIBUTION"
	local archive_root_dir=$(tar -tzf $zk_distribution|head -1|sed 's|/.*||')
	
	local zk_install_dir="$ZOOKEEPER_INSTALL_DIRECTORY"
	
	local install_dir=$(echo "$zk_install_dir/$archive_root_dir"|tr -s '/')
	
	echo $install_dir
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
		echo "Job $1 did not complete even after 8 minutes. Aborting"
		
	elif [ $job_status -eq 2 ]; then
		echo "Job $1 failed. Error:$linerr"
	fi
	
	return $job_status
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



status_file() {
	echo "$CLUSTER_CONF_DIR/$CLUSTER_NAME.info"
}



create_image_status_file() {
	local stfile=$(image_status_file)
	if [ ! -f "$stfile" ]; then
		touch "$stfile"
	fi
}



image_status_file() {
	echo "$IMAGE_CONF_DIR/$IMAGE_NAME.info"
}



#	$1 -> Path of local file to copy
#	$2 -> IP address or hostname of node
#	$3 -> SSH login username for node
#	$4 -> SSH private key file for node
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
#	$2 -> SSH username for node
#	$3 -> SSH private key file for node
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
	return $?
}



case $1 in
	new-image-conf)
	create_new_image_conf "$2"
	;;

	create-image)
	create_zk_image "$2" "$3"
	;;

	delete-image)
	delete_zk_image "$2" "$3"
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

	update-zoo-cfg)
	update_zk_configuration "$2"
	;;
	
	update-firewall)
	update_firewall "$2"
	;;
	
	create-cluster-whitelist)
	create_cluster_whitelist "$2"
	;;
	
	add-whitelist) 
	add_to_whitelist "$2" "$3"
	;;
	
	remove-whitelist) 
	remove_from_whitelist "$2" "$3"
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


