# This should be called with root privileges.

. ./textfileops.sh


# Inserts or replaces an entry inside $1 section in /etc/hosts.
# 	$1 : cluster name
# 	$2 : IP address
# 	$3 : new hostname
insert_entry_in_etc_hosts() {
	add_section /etc/hosts $1	
	insert_or_replace_in_section /etc/hosts $1 $2 "$2 $3"
}

# 	$1 : cluster name
# 	$2 : private IP address
# 	$3 : new private hostname
# 	$4 : public IP address
# 	$5 : new public hostname
change_hostname() {
	insert_entry_in_etc_hosts $1 $2 $3
	insert_entry_in_etc_hosts $1 $4 $5
	echo $3 > /etc/hostname
	hostname $3
}

# $1 : cluster name
# $2 : cluster hosts file to be included in /etc/hosts
update_cluster_hosts() {
	replace_section_with_file /etc/hosts $1 $2
}


# $1 : cluster name
delete_cluster_hosts() {
	delete_section /etc/hosts $1
}


case $1 in
	change-hostname)
	change_hostname $2 $3 $4 $5 $6
	;;

	hosts-file)
	update_cluster_hosts $2 $3
	;;
	
	delete-cluster)
	delete_cluster_hosts $2
	;;

	*)
	echo "Unknown command: $1"
	;;
esac
