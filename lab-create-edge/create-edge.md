# Create an Edge Node to Access Your Cluster

## Before You Begin
An Edge Node is a compute instance that serves as a place for useers to accessing the cluster.  In this exercise, the edge node will also be playing the role of a bastion.  A bastion enables you to protect sensitive resources by placing them in private networks that can't be accessed directly from the public internet. You expose a single, known public entry point that you audit regularly, harden,and secure. This allows you to avoid exposing the more sensitive parts of the topology, without compromising access to them.  For more information about bastions, you can refer to the [OCI documentation](https://docs.oracle.com/en/solutions/set-resources-to-provision-deploy-cloud-environment/index.html#GUID-8A2C8FB7-66E8-4838-8162-09EDDC834BE2).

In the context of this tutorial, the edge node will be a simple compute node that provides access to the Big Data Service cluster nodes.  This can be important because cluster nodes are only accessible thru private IP addresses (unless you decide to assign a public IP to a node).  You can also configure it as a Hadoop gateway with Cloudera Manager roles deployed to it (e.g. HDFS, Spark, Hive).  This allows you to easily access HDFS and run jobs from the edge node.

### Objectives
The goal for this tutorial is to create an edge node to your Hadoop cluster.  From this node, you will connect to the cluster to view its contents, run jobs, and more.  This eliminates the need to connect directly to the cluster nodes from a public network.

To create the edge node, you will:
1. Log into Oracle Cloud Infrastructure and create a Compute node in the same subnet as your Big Data Service cluster
1. Enable Connectivity from the edge node to the BDS Cluster
1. Update the edge node with required software (e.g. Kerberos, Java)
1. Connect to Cloudera Manager and add that new Compute Node to the cluster - deploying only gateway roles to it

You can stop after step 2 if you do not want to access HDFS and submit jobs from the edge node.

## Requirements

To complete this lab, you need to have the following:

* Login credentials and a tenancy name for the Oracle Cloud Infrastructure Console
* Private key required to access the BDS cluster
* Privileges to create a Compute Node
* Oracle Big Data Service Hadoop cluster deployed 
* Admin credentials for Cloudera Manager on your source cluster


## Create an OCI Compute Instance

* From your browser, [login to Oracle Cloud Infrastructure](https://console.us-ashburn-1.oraclecloud.com/)
    * Enter your **Tenancy** and then click **Continue**.
    * Enter your OCI user name and password

    Ensure that you are creating the compute instance in the same region as your Big Data Service cluster
* Select **Compute >> Instances**
* Click **Create Instance**
* In the **Create Compute Instance** page, complete the fields similar to the example below.  You will want to use Oracle Linux 7.x.  Size the VM based on your requirements.  In this example, the bastion will only be used for accessing the cluster and submitting jobs, therefore it is sized for that use case.  

    In addition, the edge node should be added to the same VCN subnet as your Big Data Service cluster:
    * **Name your instance:** `myedge`
    * **Operating System:** `Oracle Linux 7.7` (this matches the BDS Cluster OS)
    * **Avaiability Domain:** `AD 1`  (choose what is appropriate for your deployment)
    * **Instance Type:** `Virtual Machine`
    * **Instance Shape:** `VM.Standard2.1 (VirtualMachine)` (choose what is appropriate for your deployment)
    * **Configure networking**
        * **Virtual cloud network compartment:**  `mycompartment`
        * **Virtual cloud network:** `mynetwork`
        * **Subnet compartment:** `mycompartment`
        * **Subnet:** `Public Subnet-mynetwork (Regional)`
        * **Use network security groups to control traffic:** `enable if used`
        * **Assign public IP address:** `yes`
    * **Boot Volume**
        * **Custom boot volume size:** Change this value based on requirements
        * Specify values for encryption based on your requirements
    * **Add SSH key**
        * Select the public key that you plan to use for this edge node host.  The key is used for connecting to the host.
    * Click **Create**

### Capture Edge node Instance Details
Once the Edge node creation is complete, save the key information required to access the cluster:
* **Public IP Address**
* **Private IP Adress**
* **Internal FQDN**

This information will be used to 1) add the host to the cluster and 2) access the host from a client

## Enable Connectivity from the Edge node to the BDS Cluster
To enable connectivity from the edge node to the BDS Cluster, copy the private key used during BDS cluster creation to ~/opc/.ssh on the edge node. Then, log into the edge node and test connectivity.

* Copy the private key used during BDS cluster creation and copy it to ~/opc/.ssh.  The example below is using scp (secure copy):
    
    scp -i `your-private-key` `your-private-key` opc@`your-public-ip`:~/.ssh/

* Connect to `myedge` using SSH:

    ssh -i `your-private-key` opc@`your-public-ip`

Once connected to the edge node, connect to the first utility node on the Hadoop cluster.  You can find the utility node IP address by performing the following tasks:
* In a browser, log into your tenancy on OCI using the following URL:

    https://console.us-ashburn-1.oraclecloud.com/

* Select **Big Data** from the navigation menu
* Click `mycluster` in the list of Big Data Service clusters
* Locate the IP address of the first utility node and first master node.  Save these IP addresses.
* Return to your terminal and ensure that you can log into that utility node using the IP address:

    ssh -i ~opc/.ssh/`your-private-key` opc@`your-utility-node1-ip`

To make subsequent connections to the cluster nodes easier, create an SSH configuration file.  Return to the edge node node by typing `exit` from the utility node.  Make sure you update `your-private-key` and `your-*-node-ip` to match your configuration in the script below.  Then, create the configuration file:

```bash
cd ~opc/.ssh

echo "Host myclustun0
   Hostname `your-utility-node-ip`
   ServerAliveInterval 50
   User opc
   UserKnownHostsFile /dev/null
   StrictHostKeyChecking no
   IdentityFile ~opc/.ssh/your-private-key
   
   Host myclustmn0
   Hostname `your-master-node-ip`
   ServerAliveInterval 50
   User opc
   UserKnownHostsFile /dev/null
   StrictHostKeyChecking no
   IdentityFile ~opc/.ssh/your-private-key" >> config
chmod 644 config
```
You can now connect to the utility node more easily, using just the hostname:

    ssh myclustun0

Copy this file to the root users .ssh home.  This will allow secure copy to work in the next sections:
```bash
sudo cp ~opc/.ssh/config /root/.ssh/
```

### Update /etc/hosts on the Edge node
Update the **/etc/hosts** file on the edge node to include the the cluster nodes.  

**Note:** The IP addresses in the /etc/hosts file on the utility and master nodes will be different than the IP addresses added to the edge node. The IPs in the cluster nodes' /etc/hosts files are private IP addresses used for intra-cluster communication.  You will use the public IP addresses that were added to the SSH config file in the previous section.

To update the /etc/hosts file, you will:
1. Backup the **/etc/hosts** file on `myedge` to `/etc/hosts.edge`
1. Log into the utility node and create a `customerhosts` file that uses the customer IP addresses for the cluster
1. Return the edge node and copy the generated file
1. Add the result to the edge node's /etc/hosts file

```bash
# connect to myedge
ssh myedge

# backup /etc/hosts
sudo cp /etc/hosts /etc/hosts.edge

# connect to the utility node
ssh myclustun0

# chagnge to root user
sudo bash

# Connect to the utility node and generate an hosts file that uses customer IPs
# Command that will generate the IP address will be saved to a file and executed using dcli
# Prior to running, ensure that the command below matches your-utility-node-ip from above.  You may need to select a different field (i.e. change -f 2 to -f 1)
#    echo `hostname -I | cut -d " " -f 2`

# Generate the script
echo 'echo `hostname -I | cut -d " " -f 2` `hostname -f` `hostname -a`' > gethostmap
chmod +x gethostmap

# run the script on each node to gather the customer IPs
dcli -x gethostmap | cut -d ':' -f 2 | awk '{$1=$1};1' > customerhosts

# review the generated file and ensure the ips match the customer IPs
cat customerhosts

# Return edge node, copy the file and update /etc/hosts
exit
exit
scp myclustun0:customerhosts ~opc
cat ~opc/customerhosts | sudo tee -a /etc/hosts
```

**Before (example):**
```bash
$ cat /etc/hosts
127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4
::1         localhost localhost.localdomain localhost6 localhost6.localdomain6
10.0.0.9 myedge.sub12052130070.mynetwork.oraclevcn.com myedge
```
**After (example with changes to ip addresses and hosts)**
```bash
cat /etc/hosts
127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4
::1         localhost localhost.localdomain localhost6 localhost6.localdomain6
10.0.0.9 myedge.sub12052130070.mynetwork.oraclevcn.com myedge.sub12052130070.mynetwork.oraclevcn.com. myedge
10.0.0.5 myclustmn0.bmbdcsad1.bmbdcs.oraclevcn.com myclustmn0.bmbdcsad1.bmbdcs.oraclevcn.com. myclustmn0
10.0.0.7 myclustun0.bmbdcsad1.bmbdcs.oraclevcn.com myclustun0.bmbdcsad1.bmbdcs.oraclevcn.com. myclustun0
10.0.0.2 myclustun1.bmbdcsad1.bmbdcs.oraclevcn.com myclustun1.bmbdcsad1.bmbdcs.oraclevcn.com. myclustun1
10.0.0.6 myclustwn0.bmbdcsad1.bmbdcs.oraclevcn.com myclustwn0.bmbdcsad1.bmbdcs.oraclevcn.com. myclustwn0
10.0.0.3 myclustwn1.bmbdcsad1.bmbdcs.oraclevcn.com myclustwn1.bmbdcsad1.bmbdcs.oraclevcn.com. myclustwn1
10.0.0.8 myclustwn2.bmbdcsad1.bmbdcs.oraclevcn.com myclustwn2.bmbdcsad1.bmbdcs.oraclevcn.com. myclustwn2
10.0.0.4 myclustmn1.bmbdcsad1.bmbdcs.oraclevcn.com myclustmn1.bmbdcsad1.bmbdcs.oraclevcn.com. myclustmn1
```
Your edge node will now be able to communicate with the cluster using both SSH and other protocols.

## Update the Edge node with Required Software
Now that connectivity to the cluster is configured, install and configure the required software for the ede node:
* Kerberos
* Cloudera Manager Agents
* Java 8

### Install Core Software
The core software will be installed from Oracle's software repository.  The Big Data Service specific repository is on the first master node of the cluster.  Ensure that you have updated your VCN's security list to enable connectivity to the first master node on port 80 in order to access the Big Data Service repository (see [Create a Virtual Cloud Network in tutorial Preparing for Big Data Service](?lab=preparing-for-big-data-service#CreateaVCN)).  

Copy the **bda.repo** file from a cluster node to the edge node.  On the edge node:

* Make Big Data Service software available to the edge node via YUM.  Copy the **bda.repo** file to the edge node as the root user.  From the edge node:
```bash
# copy the repo file from the first master node
sudo scp myclustmn0:/etc/yum.repos.d/bda.repo /etc/yum.repos.d/
```
**Note:** Ensure that the `baseurl` the bda.repo file includes "/bda" at the end.  It should look similar to the following:
`baseurl=http://myclustmn0.bmbdcsad1.bmbdcs.oraclevcn.com/bda`
* Now that the Big Data Service software repo is available, install Kerberos, Cloudera Manager Agents and the Oracle JDK (v8).  As the opc user on the edge node node, run the following commands:
    ```bash
    # install software
    sudo yum clean all
    sudo yum install -y krb5-workstation krb5-libs jdk1.8

    # set JAVA_HOME
    export JAVA_HOME=/usr/java/latest 
    echo "export JAVA_HOME=/usr/java/latest" | sudo tee -a /etc/profile.d/mystartup.sh
    sudo chmod 644 /etc/profile.d/mystartup.sh

    # install CLoudera Manager Agents
    sudo yum install -y cloudera-manager-agent
    ```
### Configure the Core Software
There are configuration files that must be updated for each of the newly installed packages:
* Java:  Java Cryptography Extension (JCE) unlimited strength jurisdiction policy files.  This is required for Kerberos access to the cluster.

    ```bash
    # Enable Java processes to access Kerberized cluster
    sudo scp myclustun0:/usr/java/latest/jre/lib/security/*.jar /usr/java/latest/jre/lib/security/
    ```
* Keberos:  Kerberos configuration file

    ```bash
    # Configuration file for Kerberos
    sudo scp myclustun0:/etc/krb5.conf /etc/
    ```
* Cloudera Manager Agent: Configuration files and PEM file
Update the Cloudera Manager configuration so that it can connect to the Cloudera Manager Server.

    ```bash
    # Cloudera Manager Agent configuration file 
    sudo scp myclustun0:/etc/cloudera-scm-agent/config.ini /etc/cloudera-scm-agent/

    # SSH key file required for agents to communicate to CLoudera Manager
    sudo mkdir -p /opt/cloudera/security/x509/
    sudo scp myclustun0:/opt/cloudera/security/x509/agents.pem /opt/cloudera/security/x509/
    ```
* Start the Cloudera Manager Agents
    ```bash
    # Start agent and enable autostart
    sudo systemctl start cloudera-scm-agent
    sudo systemctl enable cloudera-scm-agent
    ````

## Enable Cluster Nodes to Access Edge node
There will be three things to do in order to enable the cluster nodes to connect to the edge node:
1. Update the edge node's host firewall to allow Apache Spark to run in client mode. 
1. Update the **authorized_keys** file for both the opc and root user (which will enable dcli to work)
1. Update /etc/hosts on the Hadoop cluster nodes with the edge node IP.  

Update the edge node's host firewall to allow Apache Spark to run in client mode.  This can be a range of ports.  Below, the firewall is updated to trust sources coming from all of the VCN hosts.  You may want to make this more restrictive:
```
sudo firewall-cmd --zone=trusted --add-source=10.0.0.0/16 --permanent						
sudo firewall-cmd --reload
```

Next, update the **authorized_keys** file for both the opc and root user so that SSH connections can be made from the cluster to the edge node.  Copy the id_rsa.pub file from a cluster node to the edge node and then update authorized_keys:
```bash
ssh myedge
scp myclustun0:.ssh/id_rsa.pub ~opc
cat id_rsa.pub |tee -a ~/.ssh/authorized_keys
cat id_rsa.pub |sudo tee -a /root/.ssh/authorized_keys
```

While on the edge node, copy the edge node IP and hostname from the **/etc/hosts** file:

```bash
cat /etc/hosts
```
Find the line containing the hostname and IP address and save it.  Next, log into the utility node and add that line to each cluster node's /etc/hosts file.  The command below is using an example host/IP mapping.  Update to match your results:

```bash
# Get the line from /etc/hosts
grep myedge /etc/hosts

# Log into the utility node and add a line to each /etc/hosts file
# Example:
# 10.0.0.9 myedge.sub12052130070.mynetwork.oraclevcn.com myedge.sub12052130070.mynetwork.oraclevcn.com. myedge
#
# Ensure you add a map for the hostname ending in ".".  We'll use the example from above.  Replace the ip/host appropriately
ssh myclustun0
dcli "echo '10.0.0.9 myedge.sub12052130070.mynetwork.oraclevcn.com myedge.sub12052130070.mynetwork.oraclevcn.com. myedge' | sudo tee -a /etc/hosts"
```

## Add Gateway Roles to Edge node from Cloudera Manager
The edge node node will now be updated with the gateway roles that will allow it to submit jobs and access the HDFS file system.  This will be done using Cloudera Manager.

* Log into Cloudera Manager.  Enter the admin id and password used when creating the cluster:

    https://`your-utility-node1-ip`:7183

* Click menu item **Hosts >> Add Hosts**
* Select **Add hosts to cluster** `mycluster`.  Click **Continue**
* Specify Hosts
    * Select **Currently Managed**
    * Select **Hostname** `myedge`
    * Click **Continue**
* Install Parcels
    * The parcels will be distributed, unpacked and activated. This will take some time.  When complete, click **Continue**
* Inspect Hosts for Correctness
    * This can take a few minutes.  Click **Skip Host Inspection** and then click **Continue**
* Select Host Template

    Create a new Gateway template. It will only contain Gateway roles; no data or processing will take place on this node.

    * Click **Create** a new Host Template
    * **Template Name:** `mygatewayroles`
    * Select Gateway roles for the following services:
        * HDFS
        * Hive
        * Spark
        * Yarn
    * Click **Create**
    * Select Host Template `mygatewayroles` and then click **Continue**
* Command Details
    * The roles are created and the client configuration is then deployed.  
    * When complete, click **Continue** and then click **Finish**

## Test the Edge node
Log into the edge node and run a couple of tests against your cluster.
```bash
# Log into the edge node
ssh myedge

# Get a kerberos ticket for the bds user.  Use the password provided during setup
kinit bds
Password for bds@BDACLOUDSERVICE.ORACLE.COM:

# Review hdfs data at the root directory
hadoop fs -ls /

# Submit a spark job that will calculate pi
spark-submit --class org.apache.spark.examples.SparkPi --master yarn --deploy-mode client /opt/cloudera/parcels/CDH/jars/spark-examples_*.jar 10

```

## Summary
You can now connect to the cluster from the edge node and submit jobs.
**This completes the tutorial!**