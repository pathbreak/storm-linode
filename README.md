# Overview

A set of scripts to create [Apache Storm clusters](http://storm.apache.org/) and [Apache Zookeeper](https://zookeeper.apache.org/) on Linode's cloud using their API.

# What problems does it solve?

+   Helps you create large Storm clusters on Linode's affordable cloud.

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

        wget https://raw.githubusercontent.com/pathbreak/storm-linode/release-0.1.0/cluster_manager.sh
        wget https://raw.githubusercontent.com/pathbreak/storm-linode/release-0.1.0/linode_api.py
        wget https://raw.githubusercontent.com/pathbreak/storm-linode/release-0.1.0/api_env_example.conf
        chmod +x *.sh *.py
        sudo apt-get install python2.7 curl
        cp api_env_example.conf api_env_linode.conf

2.  Open **api_env_linode.conf** in an editor and set `LINODE_KEY` to the API key generated in Step 1.

3.  Open **cluster_manager.sh** in an editor and set `ROOT_PASSWORD`. Change other configuration properties if required. Their descriptions are in the comments.

4.  Setup the Cluster Manager Linode:

        ./cluster_manager.sh create-linode api_env_linode.conf
