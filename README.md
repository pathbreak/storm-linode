# Overview

A set of scripts to create [Apache Storm clusters](http://storm.apache.org/) and [Apache Zookeeper](https://zookeeper.apache.org/) on Linode's cloud using their API.

# What problems does it solve?

+   Helps you create large Storm clusters on Linode's affordable cloud.

+   Allows you to expand a Storm cluster with just 1 command. 

    All necessary configuration and security changes are taken care of by the scripts.

+   Linode's fast network enables downloading large datasets quickly.

+   Far quicker than manually creating Virtualbox VM clusters on your dev machine, and far more performant too.

+   Creates necessary configuration files like /etc/hosts, storm.yaml and zoo.cfg dynamically. 

    No need to edit dozens of configuration files. Much less scope for configuration bugs.
    
+   All nodes are secured using tight firewall rules and key based SSH authentication.

# Prerequisites

+   A workstation running Ubuntu 14.04 LTS or Debian 8

# Step 1 - Get a Linode API key

See [Generating an API key](https://www.linode.com/docs/platform/api/api-key).

# Step 2 - Setup a Cluster Manager Linode

1.  Run these commands on your workstation:

        git clone "https://github.com/pathbreak/storm-linode"
        cd storm-linode
        git checkout $(git tag -l "release*" | head -n1)

        chmod +x *.sh *.py
        sudo apt-get install python2.7 curl
        cp api_env_example.conf api_env_linode.conf
        nano -Y sh api_env_linode.conf

2.  Set `LINODE_KEY` to the API key generated in Step 1 and close editor.

3.  Open **cluster_manager.sh** in an editor and set `ROOT_PASSWORD`. 

    Change other configuration properties if required. Their descriptions are in the comments.

4.  Setup the Cluster Manager Linode:

        ./cluster_manager.sh create-linode api_env_linode.conf
        
    Note down the public IP address of the Cluster Manager Linode.

5.  Log in to the Cluster Manager as **root** using the *clustermgrroot* private key, change its hostname and assign passwords to users:

        ssh -i ~/.ssh/clustermgrroot root@PUBLIC-IP-OF-CLUSTER-MANAGER-LINODE
        sed -i -r "s/127.0.1.1.*$/127.0.1.1\tclustermgr/" /etc/hosts
        echo clustermgr > /etc/hostname
        hostname clustermgr
        passwd clustermgr
        passwd clustermgrguest
        rm cluster_manager.sh
        exit
        
6.  Log in to the Cluster Manager as **clustermgr** using the *clustermgr* private key:

        ssh -i ~/.ssh/clustermgr clustermgr@PUBLIC-IP-OF-CLUSTER-MANAGER-LINODE
        cd storm-linode
        cp api_env_example.conf api_env_linode.conf
        nano -Y sh api_env_linode.conf
        
    Set `LINODE_KEY` to the API key generated in Step 1.
    Set `CLUSTER_MANAGER_NODE_PASSWORD` to *clustermgr* user's password.
    Save and close the editor.
    
# Step 3 - Create a Zookeeper Image

1.  Log in to the Cluster Manager as **clustermgr** using the *clustermgr* private key:

        ssh -i ~/.ssh/clustermgr clustermgr@PUBLIC-IP-OF-CLUSTER-MANAGER-LINODE
        cd storm-linode
        ./zookeeper-cluster-linode.sh new-image-conf zk-image1
        nano -Y sh ./zk-image1/zk-image1.conf
    
    Set configuration properties. All are explained in detail in the comments. Mandatory are `IMAGE_ROOT_PASSWORD` and `IMAGE_ADMIN_PASSWORD`.
    
2.  Edit the other files in that image directory if required. 

    **zoo.cfg** is the [Zookeeper configuration file](https://zookeeper.apache.org/doc/current/zookeeperAdmin.html#sc_configuration). Not necessary to enter any node list in this file. Script will take care of it later.

3.  Create the image:

        ./zookeeper-cluster-linode.sh create-image zk-image1/zk-image1.conf api_env_linode.conf

# Step 4 - Create a Zookeeper Cluster

1.  Log in to the Cluster Manager as **clustermgr** using the *clustermgr* private key:

        ssh -i ~/.ssh/clustermgr clustermgr@PUBLIC-IP-OF-CLUSTER-MANAGER-LINODE
        cd storm-linode
        ./zookeeper-cluster-linode.sh new-cluster-conf zk-cluster1
        nano -Y sh ./zk-cluster1/zk-cluster1.conf
    
    Set configuration properties. All are explained in detail in the comments. 
    Mandatory are `CLUSTER_NAME` and `ZK_IMAGE_CONF`.
    `CLUSTER_SIZE` controls the cluster sizing.
    
2.  Create the cluster:

        ./zookeeper-cluster-linode.sh create zk-cluster1/zk-cluster1.conf  api_env_linode.conf

# Step 5 - Create a Storm Image

1.  Log in to the Cluster Manager as **clustermgr** using the *clustermgr* private key:

        ssh -i ~/.ssh/clustermgr clustermgr@PUBLIC-IP-OF-CLUSTER-MANAGER-LINODE
        cd storm-linode
        ./storm-cluster-linode.sh new-image-conf storm-image1
        nano -Y sh ./storm-image1/storm-image1.conf
    
    Set configuration properties. All are explained in detail in the comments. Mandatory are `IMAGE_ROOT_PASSWORD` and `IMAGE_ADMIN_PASSWORD`.
    
2.  Edit the other files in that image directory if required. 

    **template-storm.yaml** is the [Storm configuration file](http://storm.apache.org/documentation/Configuration.html) with reasonable defaults. 

3.  Create the image:

        ./storm-cluster-linode.sh create-image  storm-image1/storm-image1.conf api_env_linode.conf

# Step 6 - Create a Storm Cluster

1.  Log in to the Cluster Manager as **clustermgr** using the *clustermgr* private key:

        ssh -i ~/.ssh/clustermgr clustermgr@PUBLIC-IP-OF-CLUSTER-MANAGER-LINODE
        cd storm-linode
        ./storm-cluster-linode.sh new-cluster-conf storm-cluster1
        nano -Y sh ./storm-cluster1/storm-cluster1.conf
    
    Set configuration properties. All are explained in detail in the comments. 
    Mandatory are `CLUSTER_NAME`, `STORM_IMAGE_CONF` and `ZOOKEEPER_CLUSTER`.
    `NIMBUS_NODE`, `SUPERVISOR_NODES` and `CLIENT_NODE` control the cluster sizing.
    
2.  Create the cluster:

        ./storm-cluster-linode.sh create storm-cluster1/storm-cluster1.conf  api_env_linode.conf

# Step 7 - Start a Storm Cluster

Log in to the Cluster Manager as **clustermgr** using the *clustermgr* private key:

    ssh -i ~/.ssh/clustermgr clustermgr@PUBLIC-IP-OF-CLUSTER-MANAGER-LINODE
    cd storm-linode
    ./storm-cluster-linode.sh start storm-cluster1/storm-cluster1.conf  api_env_linode.conf
    
# Monitor a Storm Cluster

Only whitelisted IP addresses can monitor a Storm Cluster using its Storm UI web application.

1.  Log in to the Cluster Manager as **clustermgr** using the *clustermgr* private key:

        ssh -i ~/.ssh/clustermgr clustermgr@PUBLIC-IP-OF-CLUSTER-MANAGER-LINODE
        cd storm-linode

2.  Open *[your-cluster]/[your-cluster]-client-user-whitelist.ipsets* in an editor.

    It's an [ipsets](http://ipset.netfilter.org/ipset.man.html) list of whitelisted IP addresses.
    
    Uncomment the line that creates the *[your-cluster]-ipwl* ipset.

    Add the IP addresses to whitelist under it.

    Finally add *[your-cluster]-ipwl* to the master ipset *[your-cluster]-uwls*

3.  Run this command to update firewall rules across all nodes of the cluster:

        ./storm-cluster-linode.sh update-user-whitelist storm-cluster1/storm-cluster1.conf    
        
4.  Open Storm UI web app at `http://public-IP-of-client-node` from any of these whitelisted machines.

# Test a Storm cluster

1.  Log in to the Cluster Manager as **clustermgr** using the *clustermgr* private key:

        ssh -i ~/.ssh/clustermgr clustermgr@PUBLIC-IP-OF-CLUSTER-MANAGER-LINODE
        cd storm-linode
        ./storm-cluster-linode.sh describe storm-cluster1/storm-cluster1.conf
    
    Note down the private IP address of client node.
    
2.  Log in from cluter manager node to the client node as **clusteradmin** using the *clusteradmin* private key:

        ssh -i ~/.ssh/clusteradmin clusteradmin@<client-node-ip-address>
        cd /opt/apache-storm-0.9.5/bin
        ./storm jar ../examples/storm-starter/storm-starter-topologies-0.9.5.jar storm.starter.WordCountTopology "wordcount" 
        
3.  Open Storm UI web app at `http://public-IP-of-client-node` from one of the whitelisted machines, and verify that wordcount topology is being executed.

# Start a new topology

Develop your topology and package it as a JAR.
Then follow the same steps as [Test a Storm cluster](#test-a-storm-cluster) but submit your JAR and your topology class instead of wordcount.

# Expand a Storm cluster

1.  Log in to the Cluster Manager as **clustermgr** using the *clustermgr* private key:

        ssh -i ~/.ssh/clustermgr clustermgr@PUBLIC-IP-OF-CLUSTER-MANAGER-LINODE
        cd storm-linode
        
2.  Expand nodes by specifying number of new nodes and their plans in `plan:count plan:count....` syntax:
        
        ./storm-cluster-linode.sh add-nodes storm-cluster1/storm-cluster1.conf  api_env_linode.conf "2GB:1 4GB:2"
        
3.  Rebalance topologies after adding to distribute tasks to new nodes.

# Describe a Storm cluster

For user with *clustermgr* authorization, log in to the Cluster Manager Linode as *clustermgr* using *clustermgr* authorized private key:

        ssh -i ~/.ssh/clustermgr clustermgr@PUBLIC-IP-OF-CLUSTER-MANAGER-LINODE
        cd storm-linode
        ./storm-cluster-linode.sh describe <target-cluster-conf-file>

For user with *clustermgrguest* authorization, log in to the Cluster Manager Linode as *clustermgrguest* using *clustermgrguest* authorized private key:

        ssh -i ~/.ssh/clustermgrguest clustermgrguest@PUBLIC-IP-OF-CLUSTER-MANAGER-LINODE
        cd storm-linode
        ./cluster_info.sh list
        ./cluster_info.sh info <target_cluster>
        
# Stop a Storm cluster

Log in to the Cluster Manager as **clustermgr** using the *clustermgr* private key:

        ssh -i ~/.ssh/clustermgr clustermgr@PUBLIC-IP-OF-CLUSTER-MANAGER-LINODE
        cd storm-linode
        ./storm-cluster-linode.sh stop storm-cluster1/storm-cluster1.conf api_env_linode.conf

# Destroy a Storm cluster

Log in to the Cluster Manager as **clustermgr** using the *clustermgr* private key:

        ssh -i ~/.ssh/clustermgr clustermgr@PUBLIC-IP-OF-CLUSTER-MANAGER-LINODE
        cd storm-linode
        ./storm-cluster-linode.sh destroy storm-cluster1/storm-cluster1.conf api_env_linode.conf

# Run a command on all nodes of Storm cluster
        
Log in to the Cluster Manager as **clustermgr** using the *clustermgr* private key:

        ssh -i ~/.ssh/clustermgr clustermgr@PUBLIC-IP-OF-CLUSTER-MANAGER-LINODE
        cd storm-linode
        ./storm-cluster-linode.sh run storm-cluster1/storm-cluster1.conf "<cmds>"

The commands are run as root user on each node.

# Copy file(s) to all nodes of Storm cluster
        
Log in to the Cluster Manager as **clustermgr** using the *clustermgr* private key:

        ssh -i ~/.ssh/clustermgr clustermgr@PUBLIC-IP-OF-CLUSTER-MANAGER-LINODE
        cd storm-linode
        ./storm-cluster-linode.sh cp storm-cluster1/storm-cluster1.conf "." "<files>"

The files are copied as root user on each node.

# Delete a Storm image

Log in to the Cluster Manager as **clustermgr** using the *clustermgr* private key:

        ssh -i ~/.ssh/clustermgr clustermgr@PUBLIC-IP-OF-CLUSTER-MANAGER-LINODE
        cd storm-linode
        ./storm-cluster-linode.sh delete-image storm-image1/storm-image1.conf api_env_linode.conf

# Describe a Zookeeper cluster

For user with *clustermgr* authorization, log in to the Cluster Manager Linode as *clustermgr* using *clustermgr* authorized private key:

        ssh -i ~/.ssh/clustermgr clustermgr@PUBLIC-IP-OF-CLUSTER-MANAGER-LINODE
        cd storm-linode
        ./zookeepercluster-linode.sh describe <target-cluster-conf-file>

For user with *clustermgrguest* authorization, log in to the Cluster Manager Linode as *clustermgrguest* using *clustermgrguest* authorized private key:

        ssh -i ~/.ssh/clustermgrguest clustermgrguest@PUBLIC-IP-OF-CLUSTER-MANAGER-LINODE
        cd storm-linode
        ./cluster_info.sh list
        ./cluster_info.sh info <target_cluster>
        
# Stop a Zookeeper cluster

Log in to the Cluster Manager as **clustermgr** using the *clustermgr* private key:

        ssh -i ~/.ssh/clustermgr clustermgr@PUBLIC-IP-OF-CLUSTER-MANAGER-LINODE
        cd storm-linode
        ./zookeeper-cluster-linode.sh stop zk-cluster1/zk-cluster1.conf api_env_linode.conf

# Destroy a Zookeeper cluster

Log in to the Cluster Manager as **clustermgr** using the *clustermgr* private key:

        ssh -i ~/.ssh/clustermgr clustermgr@PUBLIC-IP-OF-CLUSTER-MANAGER-LINODE
        cd storm-linode
        ./zookeeper-cluster-linode.sh destroy zk-cluster1/zk-cluster1.conf api_env_linode.conf

# Run a command on all nodes of Zookeeper cluster
        
Log in to the Cluster Manager as **clustermgr** using the *clustermgr* private key:

        ssh -i ~/.ssh/clustermgr clustermgr@PUBLIC-IP-OF-CLUSTER-MANAGER-LINODE
        cd storm-linode
        ./zookeeper-cluster-linode.sh run zk-cluster1/zk-cluster1.conf  "<cmds>"

The commands are run as root user on each node.

# Copy file(s) to all nodes of Zookeeper cluster
        
Log in to the Cluster Manager as **clustermgr** using the *clustermgr* private key:

        ssh -i ~/.ssh/clustermgr clustermgr@PUBLIC-IP-OF-CLUSTER-MANAGER-LINODE
        cd storm-linode
        ./zookeeper-cluster-linode.sh cp zk-cluster1/zk-cluster1.conf  "." "<files>"

The files are copied as root user on each node.

# Delete a Zookeeper image

Log in to the Cluster Manager as **clustermgr** using the *clustermgr* private key:

        ssh -i ~/.ssh/clustermgr clustermgr@PUBLIC-IP-OF-CLUSTER-MANAGER-LINODE
        cd storm-linode
        ./zookeeper-cluster-linode.sh delete-image zk-image1/zk-image1.conf api_env_linode.conf

# License

MIT
