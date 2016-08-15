#!/usr/bin/python

import urllib
import urllib2
import json
import os
import sys
import re
import datetime
import operator

# TODO Check out the requests module which claims it's better than ("the thoroughly broken") urllib2


API_PRODUCTION_URL = 'https://api.linode.com/'
API_SIMULATOR_URL = 'http://localhost:5000/'
api_key = None
url = API_SIMULATOR_URL
LOG = False

def linode_request(action, params):
	data={
		'api_key' : api_key,
		'api_action' : action
	}
	if params is not None:
		data.update(params)
	data = urllib.urlencode(data)
	req = urllib2.Request(url, data)
	response = urllib2.urlopen(req)
	response = response.read()	
	respobj = json.loads(response)
	if LOG:
		log(req, respobj)
	return respobj


def is_error(response):
	if response['ERRORARRAY']:
		return (True, response['ERRORARRAY'])
		
	return (False, None)
	
def log(req, resp):
	with open('linode_api.log', 'a') as log_file:
		log_file.write("\n\n----%s\n[REQUEST] %s %s\n[RESPONSE]\n" 
			% (str(datetime.datetime.now()), req.get_full_url(), req.get_data()))
		json.dump(resp, log_file, indent=4, separators=(',',':'))
		
		
def list_datacenters(format='raw'):
	data = linode_request('avail.datacenters', None)
	dcs = data['DATA']
	
	if format == 'table':
		print '%-5s%-30s%-14s' % ('ID', 'Location', 'Abbreviation')
		print '-'*50
		dcs = sorted(dcs, key=operator.itemgetter('DATACENTERID'))
		for dc in dcs:
			print '%-5d%-30s%-9s' % (dc['DATACENTERID'], dc['LOCATION'], dc['ABBR'])
		
		
	elif format == 'raw':
		print json.dumps(data, indent=4, separators=(',',':'))
	
	
# This returns the data centter id given a location or abbr or the ID itself.
def get_datacenter(datacenter):
	dcs = linode_request('avail.datacenters', None)['DATA']
	if datacenter.isdigit():
		datacenter = int(datacenter)
		for dc in dcs:
			if dc['DATACENTERID'] == datacenter:
				# It's a valid datacenter.
				return datacenter
		return None
	
	datacenter = datacenter.lower()
	for dc in dcs:
		if dc['LOCATION'].lower() == datacenter or dc['ABBR'].lower() == datacenter:
			return dc['DATACENTERID']
	
	return None


def list_plans(format='table'):
	data=linode_request('avail.linodeplans', None)
	plans=data['DATA']
	if format=='table':
		for plan in plans:
			print '%d\t%s\t%d GB RAM\t%d GB HD\t$%f/hr\t$%d/month' % (plan['PLANID'], plan['LABEL'], plan['RAM']/1024, plan['DISK'], plan['HOURLY'], plan['PRICE'])

	elif format=='raw':
		print json.dumps(data, indent=4, separators=(',',':'))				


def list_distributions(filter=None, format='raw'):
	data=linode_request('avail.distributions', None)
	distros=data['DATA']
	if filter and filter is not '':
		filter=filter.lower()
		filtered=list()
		for distro in distros:
			if (filter in distro['LABEL'].lower()):
				filtered.append(distro)
		distros = filtered
		
	if format=='table':
		print '%-5s%-30s%-9s' % ('ID', 'LABEL', '64/32-bit')
		print '-'*45
		distros = sorted(distros, key=operator.itemgetter('LABEL'))
		for distro in distros:
			print '%-5d%-30s%-9s' % (distro['DISTRIBUTIONID'], distro['LABEL'], '64-bit' if distro['IS64BIT']==1 else '32-bit')
			
	elif format=='raw':
		print json.dumps(distros, indent=4, separators=(',',':'))


# This returns the distribution id and label given its label or just the ID itself.
def find_distribution(distribution):
	distros = linode_request('avail.distributions', None)['DATA']
	if distribution.isdigit():
		distribution = int(distribution)
		for distro in distros:
			if distro['DISTRIBUTIONID'] == distribution:
				# It's a valid distribution.
				return (distribution, distro['LABEL'])
				
		return (None, None)
	
	distribution = distribution.lower()
	for distro in distros:
		if distro['LABEL'].lower() == distribution:
			return (distro['DISTRIBUTIONID'], distro['LABEL'])
	
	return (None, None)


def list_all_stackscripts(filter=None):
	data=linode_request('avail.stackscripts', None)
	scripts=data['DATA']
	if filter is None:
		print json.dumps(scripts, indent=4, separators=(',',':'))	
		return 


#		filter=filter.lower()
#		filtered=list()
#		for distro in distros:
#			if (filter in distro['LABEL'].lower()):
#				filtered.append(distro)
#		print json.dumps(filtered, indent=4, separators=(',',':'))



def list_mystackscripts():
	data=linode_request('stackscript.list', None)
	scripts=data['DATA']
	print json.dumps(scripts, indent=4, separators=(',',':'))	


def stackscript(script_id):
	data=linode_request('stackscript.list', {'StackScriptID':script_id})
	script=data['DATA']
	print json.dumps(script, indent=4, separators=(',',':'))	




def list_kernels(version_filter_regex=None, format='raw'):
	data=linode_request('avail.kernels', None)
	kernels=data['DATA']
	if version_filter_regex and version_filter_regex is not '':
		filtered=list()
		for kernel in kernels:
			if re.search(version_filter_regex, kernel['LABEL']):
				filtered.append(kernel)
		kernels = filtered
		
	if format == 'table':
		print '%-5s%-50s%-5s%-5s' % ('ID', 'LABEL', 'KVM', 'Xen')
		print '-'*65
		kernels = sorted(kernels, key=operator.itemgetter('LABEL'))
		for kernel in kernels:
			print '%-5d%-50s%-5s%-5s' % (kernel['KERNELID'], kernel['LABEL'], 'Y' if kernel['ISKVM']==1 else 'N',
				'Y' if kernel['ISXEN']==1 else 'N')
		
	elif format == 'raw':
		print json.dumps(kernels, indent=4, separators=(',',':'))


# This returns the kernel id and label given its partial/full label or just the ID itself.
def find_kernel(kernel):
	kernels = linode_request('avail.kernels', None)['DATA']
	if kernel.isdigit():
		kernel = int(kernel)
		for k in kernels:
			if k['KERNELID'] == kernel:
				# It's a valid kernel.
				return (kernel, k['LABEL'])
				
		return (None, None)
	
	kernel = kernel.lower()
	for k in kernels:
		# Return the first partial or full match
		if kernel in k['LABEL'].lower():
			return (k['KERNELID'], k['LABEL'])
	
	return (None, None)



def list_nodes(linode_id=None):
	if linode_id:
		data=linode_request('linode.list', {'LinodeID':linode_id})
	else:
		data=linode_request('linode.list', None)
		
	nodes=data['DATA']
	print json.dumps(nodes, indent=4, separators=(',',':'))


def get_node_memory(linode_id):
	resp = linode_request('linode.list', {'LinodeID':linode_id})
	nodes = resp['DATA']
	if nodes and len(nodes) > 0:
		return nodes[0]["TOTALRAM"]
		
	return None


def list_jobs(linode_id):
	data=linode_request('linode.job.list', {'LinodeID':int(linode_id)})
	jobs=data['DATA']
	print json.dumps(jobs, indent=4, separators=(',',':'))



def list_ip_addresses(linode_id):
	if linode_id == -1:
		data=linode_request('linode.ip.list', None)
	else:
		data=linode_request('linode.ip.list', {'LinodeID':linode_id})
	addresses=data['DATA']
	print json.dumps(addresses, indent=4, separators=(',',':'))


def get_public_ip_address(linode_id):
	resp = linode_request('linode.ip.list', {'LinodeID':linode_id})
	addresses = resp['DATA']
	for address in addresses:
		if address['ISPUBLIC'] == 1:
			return address['IPADDRESS']
			
	return None

def add_private_ip(linode_id):
	resp = linode_request('linode.ip.addprivate', {'LinodeID':linode_id})
	iserr, errors = is_error(resp)
	if iserr:
		return (False, errors)
	
	address = resp['DATA']
		
	return (True, address['IPADDRESS'])
		

def job(linode_id, job_id):
	data=linode_request('linode.job.list', {'LinodeID':linode_id, 'JobID':job_id})
	job=data['DATA']
	print json.dumps(job, indent=4, separators=(',',':'))


def is_job_finished(linode_id, job_id):
	# Return values:
	#	False, None : Job is not finished
	#	True, True : Job is successfully completed
	#	True, False: Job failed
	#	None, None : No such job
	data = linode_request('linode.job.list', {'LinodeID':linode_id, 'JobID':job_id})
	jobs = data['DATA']
	if jobs: 
		job = jobs[0]
		if job['HOST_SUCCESS'] == '':
			return (False, None)
	
		return (True, False if job['HOST_SUCCESS'] == 0 else True)
		
	return (None,None)
		

def list_disks(linode_id):
	data=linode_request('linode.disk.list', {'LinodeID':linode_id})
	disks=data['DATA']
	print json.dumps(disks, indent=4, separators=(',',':'))


def list_configs(linode_id):
	data=linode_request('linode.config.list', {'LinodeID':linode_id})
	configs=data['DATA']
	print json.dumps(configs, indent=4, separators=(',',':'))



def create_node(plan, datacenter, do_validations=True):
	if do_validations:
		datacenter = get_datacenter(datacenter)
		if datacenter is None:
			return (False, ['Invalid datacenter'])
		
	resp = linode_request('linode.create', 
		{
			'PLANID' : plan,
			'DATACENTERID' : datacenter
		}
	)
	
	iserr, errors = is_error(resp)
	if iserr:
		return (False, errors)
		
	linode_id = resp['DATA']['LinodeID']
	return (True, linode_id)



def update_node(linode_id, label, display_group):
	resp = linode_request('linode.update', 
		{
			'LinodeID' : linode_id,
			'Label' : label,
			'lpm_displayGroup' : display_group
		}
	)
	
	iserr, errors = is_error(resp)
	if iserr:
		return (False, errors)
		
	linode_id = resp['DATA']['LinodeID']
	return (True, linode_id)



def delete_node(linode_id, skip_checks):
	resp = linode_request('linode.delete', 
		{
			'LinodeID' : linode_id,
			'skipChecks' : skip_checks
		}
	)
	
	iserr, errors = is_error(resp)
	if iserr:
		return (False, errors)
		
	linode_id = resp['DATA']['LinodeID']
	return (True, linode_id)


# skip_checks should be 0 to not skip checks, or 1 to skip.
def delete_all_nodes(skip_checks):
	linodes = linode_request('linode.list', None)['DATA']
	
	deleted_linodes = []
	all_errors = []
	
	for linode in linodes:
		linode_id = linode['LINODEID']
		resp = linode_request('linode.delete', 
			{
				'LinodeID' : linode_id,
				'skipChecks' : skip_checks
			}
		)
		
		iserr, errors = is_error(resp)
		if iserr:
			all_errors.append(errors)
		else:	
			deleted_linodes.append(linode_id)
	
	return (deleted_linodes, all_errors)


def create_disk(linode_id, distribution, disk_size, root_password, root_ssh_key_file):
	# From https://www.linode.com/api/linode/linode.disk.create
	# 'distribution' is optional. If distribID is not included, it boots up, goes 
	# into kernel panic due to missing init, and keeps rebooting.
	# 'distribution' may be an id or just a label that matches an entry in avail.distributions. 
	# Find its actual ID and check for validity.
	distribution_id = ''
	if distribution:
		distribution_id, distribution_label = find_distribution(distribution)
		if distribution_id is None:
			return (False, ['Invalid distribution'])

	public_key = ''
	if root_ssh_key_file:
		with open(root_ssh_key_file, 'r') as idfile:
			public_key = idfile.read()
			
		public_key = public_key.replace('\n', '')
	
	params={
		'LinodeID' : linode_id,
		'FromDistributionID' : distribution_id,
		'rootPass' : root_password,
		'rootSSHKey' : public_key,
		'Label' : distribution_label,
		'Type' : 'ext4',
		'Size' : disk_size
	}
	print params
	resp=linode_request('linode.disk.create', params)
	print resp



def create_swap_disk(linode_id):
	# From https://www.linode.com/api/linode/linode.disk.create
	
	# Calculate swap size based on RAM.
	# - 2GB of RAM or less            = 2 x RAM
	# - 2GB to 8GB of RAM             = RAM
	# - 8GB to 64GB of RAM            = At least 4 GB to 0.5 x RAM
	# - 64GB of RAM or more           = At least 4 GB
	# References:
	#	http://askubuntu.com/questions/49109/i-have-16gb-ram-do-i-need-32gb-swap and 
	#	https://access.redhat.com/documentation/en-US/Red_Hat_Enterprise_Linux/7/html/Installation_Guide/sect-disk-partitioning-setup-x86.html#sect-recommended-partitioning-scheme-x86
	ram_mb = int(get_node_memory(linode_id))
	swap_disk_size_mb = 2048
	if 1024 <= ram_mb <= 2048:
		swap_disk_size_mb = 2 * ram_mb
		
	elif 4096 <= ram_mb <= 8192:
		swap_disk_size_mb = ram_mb
		
	elif 8192 < ram_mb <= 32768:
		swap_disk_size_mb = ram_mb / 2;
	
	elif ram_mb > 32768:
		swap_disk_size_mb = 32768;
	
	params={
		'LinodeID' : linode_id,
		'Type' : 'swap',
		'Size' : swap_disk_size_mb,
		'Label' : 'swapdisk'
	}
	resp = linode_request('linode.disk.create', params)
	iserr, errors = is_error(resp)
	if iserr:
		return (False, errors)
	
	job_id = resp['DATA']['JobID']
	disk_id = resp['DATA']['DiskID']
	return (True, (disk_id, job_id) )




def create_disk_from_distribution(linode_id, distribution, disk_size, root_password, root_ssh_key_file):
	# 'distribution' may be an id or just a label that matches an entry in avail.distributions. 
	# Find its actual ID and check for validity.
	distribution_id, distribution_label = find_distribution(distribution)
	if distribution_id is None:
		return (False, ['Invalid distribution'])
		
	public_key = ''
	if root_ssh_key_file:
		with open(root_ssh_key_file, 'r') as idfile:
			public_key = idfile.read()
			
		public_key = public_key.replace('\n', '')
	
	# From https://www.linode.com/api/linode/linode.disk.createfromdistribution
	params={
		'LinodeID' : linode_id,
		'DistributionID' : distribution_id,
		'rootPass' : root_password, 
		'rootSSHKey' : public_key,
		'Label' : distribution_label,
		'Size' : disk_size
	}
	resp = linode_request('linode.disk.createfromdistribution', params)
	iserr, errors = is_error(resp)
	if iserr:
		return (False, errors)
	
	job_id = resp['DATA']['JobID']
	disk_id = resp['DATA']['DiskID']
	return (True, (disk_id, job_id) )


def create_disk_from_stackscript(linode_id, stackscript_id, distribution, root_password, root_ssh_key_file):
	# 'distribution' may be an id or just a label that matches an entry in avail.distributions. 
	# Find its actual ID and check for validity.
	distribution_id, distribution_label = find_distribution(distribution)
	if distribution_id is None:
		return (False, ['Invalid distribution'])
		
	public_key = ''
	if root_ssh_key_file:
		with open(root_ssh_key_file, 'r') as idfile:
			public_key = idfile.read()
			
		public_key = public_key.replace('\n', '')
	

	# From https://www.linode.com/api/linode/linode.disk.createfromstackscript
	params={
		'LinodeID' : linode_id,
		'StackScriptID' : stackscript_id,
		'StackScriptUDFResponses' : '{}',
		'DistributionID' : distribution_id,
		'rootPass' : root_password,
		'rootSSHKey' : public_key,
		'Label' : distribution_label,
		'Size' : '5000'
	}
	print params
	resp=linode_request('linode.disk.createfromstackscript', params)
	print resp


def create_diskimage(linode_id, disk_id, image_label):
	# https://www.linode.com/api/linode/linode.disk.imagize
	resp=linode_request('linode.disk.imagize', 
		{
			'LinodeID' : linode_id,
			'DiskID' : disk_id,
			'Label' : image_label
		}
	)
	iserr, errors = is_error(resp)
	if iserr:
		return (False, errors)
	
	job_id = resp['DATA']['JobID']
	image_id = resp['DATA']['ImageID']
	return (True, (image_id, job_id))


def list_diskimages():
	# https://www.linode.com/api/image/image.list
	data=linode_request('image.list', None)
	print json.dumps(data, indent=4, separators=(',',':'))


# This returns the image id and image label given its label or just the ID itself.
def find_image(image):
	images = linode_request('image.list', None)['DATA']
	if image.isdigit():
		image = int(image)
		for img in images:
			if img['IMAGEID'] == image:
				# It's a valid image.
				return (image, img['LABEL'])
				
		return (None, None)
	
	image = image.lower()
	for img in images:
		if img['LABEL'].lower() == image:
			return (img['IMAGEID'], img['LABEL'])
	
	return (None, None)


def delete_image(image_id):
	resp = linode_request('image.delete', {'ImageID':image_id})
	iserr, errors = is_error(resp)
	if iserr:
		return (False, errors)
	
	return (True, image_id)
	

def create_disk_from_image(linode_id, image_id, label, disk_size, root_password, root_ssh_key_file):
	# Note: This assumes the image_id is valid.
	
	public_key = ''
	if root_ssh_key_file:
		with open(root_ssh_key_file, 'r') as idfile:
			public_key = idfile.read()
		
		public_key = public_key.replace('\n', '')
	

	# From https://www.linode.com/api/linode/linode.disk.createfromimage
	params={
		'ImageID' : image_id,
		'LinodeID' : linode_id,
		'rootPass' : root_password,
		'rootSSHKey' : public_key,
		'Label' : label,
		'Size' : disk_size
	}
	resp = linode_request('linode.disk.createfromimage', params)
	iserr, errors = is_error(resp)
	if iserr:
		return (False, errors)
	
	# For 'creatediskfromimage', the returned keys are uppercase, not lowercase.
	job_id = resp['DATA']['JOBID']
	disk_id = resp['DATA']['DISKID']
	return (True, (disk_id, job_id) )


def create_config(linode_id, kernel, disks, config_label, do_validations=True):
	if do_validations:
		kernel_id, kernel_label = find_kernel(kernel)
		if kernel_id is None:
			return (False, ['Invalid kernel'])
	else:
		kernel_id = kernel
	
	linode_id = int(linode_id)
	
	params={
		'LinodeID' : linode_id,
		'KernelID' : kernel_id, 
		'Label' : config_label,
		'DiskList' : disks
	}
	resp = linode_request('linode.config.create', params)
	iserr, errors = is_error(resp)
	if iserr:
		return (False, errors)
	
	config_id = resp['DATA']['ConfigID']
	return (True, config_id )

	


def create_stackscript(script_file):
	with open(script_file, 'r') as script:
		script_contents=script.read()

	# https://www.linode.com/api/stackscript/stackscript.create
	params={
		'Label' : 'install-zk',
		'Description' : 'Testing stackscript',
		'DistributionIDList' : '124',
		'isPublic' : 0,
		'script' : script_contents
	}
	resp=linode_request('stackscript.create', params)
	print resp




def boot_node(linode_id, config_id=None):
	params = {'LinodeID':linode_id}
	if config_id:
		params['ConfigID'] = config_id
		
	resp = linode_request('linode.boot', params)
	iserr, errors = is_error(resp)
	if iserr:
		return (False, errors)
	
	job_id = resp['DATA']['JobID']
	return (True, job_id)




def shutdown_node(linode_id):
	resp = linode_request('linode.shutdown', {'LinodeID':linode_id})
	iserr, errors = is_error(resp)
	if iserr:
		return (False, errors)
	
	job_id = resp['DATA']['JobID']
	return (True, job_id)



def clone_node(linode_id):
	params={
		'LinodeID' : linode_id,
		'DatacenterID' : 9, # Note: It seems it's possible to clone a linode to a different datacenter.
		'PlanID' : 1
	}
	resp=linode_request('linode.clone', params)
	print resp
#=============================================================

if len(sys.argv) <= 1:
	print "No command"
	sys.exit(0)

api_key = os.getenv('LINODE_KEY', None)
if (api_key is None):
	print "Error : LINODE_KEY environment var is not defined"
	sys.exit(1)

url = os.getenv('LINODE_API_URL', None)
if (url is None):
	print "Error : LINODE_API_URL environment var is not defined"
	sys.exit(1)

#if url == API_PRODUCTION_URL:
	#print >> sys.stderr, "**** CAUTION: USING PRODUCTION URL"

cmd=sys.argv[1]
if (cmd == 'datacenters'):
	format = 'raw'
	if len(sys.argv) > 2:
		format = sys.argv[2]
	
	list_datacenters(format)

elif (cmd == 'datacenter-id'):
	# Checks the input argument and returns the numeric datacenter ID
	# if it's valid.
	#
	# Args: Either a numeric datacenter ID (in which case it's just checked for validity
	#		or a datacenter name or abbreviation which should match output of avail.datacenters.
	#		
	# Output: The datacenter ID or nothing
	# Returns: 0 on success or 1 on failure. Error details on stderr
	dc_id = get_datacenter(sys.argv[2])
	if dc_id is None:
		print >> sys.stderr, "Invalid datacenter:", sys.argv[2]
		sys.exit(1)
		
	print dc_id
	sys.exit(0)
	
elif (cmd == 'plans'):
	if len(sys.argv) > 2:
		list_plans(sys.argv[2])
	else:
		list_plans()

elif (cmd == 'nodes'):
	if len(sys.argv) >= 3:
		list_nodes(int(sys.argv[2]))
	else:
		list_nodes()


elif (cmd == 'ram'):
	mem = get_node_memory(int(sys.argv[2]))
	if mem is None:
		print >> sys.stderr, "Unable to get memory for linode:", sys.argv[2]
		sys.exit(1)
		
	print mem
	sys.exit(0)
	
elif (cmd == 'distributions'):
	filter = None
	if len(sys.argv) > 2:
		filter = sys.argv[2]
	
	format = 'raw'
	if len(sys.argv) > 3:
		format = sys.argv[3]
	
	list_distributions(filter, format)

elif (cmd == 'distribution-id'): 
	# Checks the input argument and returns the numeric distribution ID
	# if it's valid.
	#
	# Args: Either a numeric distribution ID (in which case it's just checked for validity
	#		or a distribution label which should match output of avail.distributions.
	#		
	# Output: The distribution ID or nothing
	# Returns: 0 on success or 1 on failure. Error details on stderr
	dist_id, dist_label = find_distribution(sys.argv[2])
	if dist_id is None:
		print >> sys.stderr, "Invalid distribution:", sys.argv[2]
		sys.exit(1)
		
	print "%d,%s" % (dist_id,dist_label)
	sys.exit(0)

	
elif (cmd == 'kernels'):
	filter = None
	if len(sys.argv) > 2:
		filter = sys.argv[2]
		
	format = 'raw'
	if len(sys.argv) > 3:
		format = sys.argv[3]
	
	list_kernels(filter, format)

elif (cmd == 'kernel-id'): 
	# Checks the input argument and returns the numeric kernel ID
	# if it's valid.
	#
	# Args: Either a numeric kernel ID (in which case it's just checked for validity
	#		or a partial/full kernel label which should match output of avail.kernels.
	#		
	# Output: The kernel ID, or nothing
	# Returns: 0 on success or 1 on failure. Error details on stderr
	kernel_id, kernel_label = find_kernel(sys.argv[2])
	if kernel_id is None:
		print >> sys.stderr, "Invalid kernel:", sys.argv[2]
		sys.exit(1)
		
	print "%d,%s" % (kernel_id,kernel_label)
	sys.exit(0)

elif (cmd == 'stackscripts'):
	if len(sys.argv) > 2:
		list_all_stackscripts(sys.argv[2])
	else:
		list_all_stackscripts()

elif (cmd == 'my-stackscripts'):
	list_mystackscripts()

elif (cmd == 'stackscript'):
	stackscript(int(sys.argv[2]))

elif (cmd == 'jobs'):
	list_jobs(sys.argv[2])

elif (cmd == 'job'):
	job(linode_id, int(sys.argv[2]))

elif (cmd == 'job-status'):
	# Output: 0 if not finished, 1 if finished successfully, 2 if finished but failed
	#			No output if error
	#
	# Return codes: 0 on valid job id, 1 on invalid inputs data
	
	finished, success = is_job_finished(int(sys.argv[2]), int(sys.argv[3]))
	if finished is None:
		print >> sys.stderr, "Invalid data: Linode=%s, Job=%s" % (sys.argv[2], sys.argv[3])
		sys.exit(1)
		
	if finished == False:
		print 0
	else:
		if success:
			print 1
		else:
			print 2
	sys.exit(0)	

elif (cmd == 'disks'):
	list_disks(int(sys.argv[2]))


elif (cmd == 'ips'):
	if len(sys.argv) >= 3:
		list_ip_addresses(int(sys.argv[2]))
	else:
		list_ip_addresses(-1)


elif (cmd == 'public-ip'):
	# Output: If linode has atleast 1 public IP address, the first one
	#		  is output.
	# Return code: 0 if IP address was printed, 1 if there was no public IP address.
	ipaddr = get_public_ip_address(int(sys.argv[2]))
	if ipaddr == None:
		sys.exit(1)
		
	print ipaddr
	sys.exit(0)
	
	
elif (cmd == 'add-private-ip'):
	# Output: The private IP address.
	# Return code: 0 if IP address was printed. 1 on failures, errors on stderr
	success, data = add_private_ip(int(sys.argv[2]))
	if not success:
		print >>sys.stderr, data
		sys.exit(1)
		
	ipaddr = data
	print ipaddr
	sys.exit(0)
		
elif (cmd == 'create-node'):
	# Output: The linode ID or nothing on failure
	# Returns: 0 on success or 1 on failure. Error details on stderr
	plan = int(sys.argv[2])
	datacenter = sys.argv[3]
	do_validations = True
	if len(sys.argv) >= 5:
		if int(sys.argv[4]) == 0:
			do_validations = False
			
	success, data = create_node(plan, datacenter, do_validations)
	if not success:
		print >>sys.stderr, data
		sys.exit(1)
	
	linode_id = data
	print linode_id
	sys.exit(0)



elif (cmd == 'update-node'):
	# Output: The linode ID or nothing on failure
	# Returns: 0 on success or 1 on failure. Error details on stderr
	linode_id = int(sys.argv[2])
	label = sys.argv[3]
	display_group = sys.argv[4]

	success, data = update_node(linode_id, label, display_group)
	if not success:
		print >>sys.stderr, data
		sys.exit(1)
	
	linode_id = data
	print linode_id
	sys.exit(0)
	
	

elif (cmd == 'delete-node'):
	# Output: Nothing
	# Returns: 0 on success or 1 on failure. Error details on stderr
	linode_id = int(sys.argv[2])
	skip_checks = int(sys.argv[3])
	success, data = delete_node(linode_id, skip_checks)
	if not success:
		print >>sys.stderr, data
		sys.exit(1)
	
	sys.exit(0)

elif (cmd == 'delete-all-nodes'):
	# Output: Comma separated list of deleted nodes
	# Returns: 0 on complete success or 1 if there are any errors. Error details on stderr
	skip_checks = sys.argv[2]
	deleted_nodes, all_errors = delete_all_nodes(skip_checks)
	
	
	print ','.join([str(id) for id in deleted_nodes])
	
	if all_errors:
		print >>sys.stderr, all_errors
		sys.exit(1)
	
	sys.exit(0)


elif (cmd == 'create-disk'):
	create_disk(linode_id)

elif (cmd == 'create-disk-from-distribution'):
	# Output: "<disk-ID>,<job-ID>" on success, or nothing on failure
	# Returns: 0 on success or 1 on failure. Error details on stderr
	linode_id = int(sys.argv[2])
	distribution = sys.argv[3]
	disk_size = int(sys.argv[4])
	root_password = sys.argv[5]
	root_ssh_key_file = sys.argv[6]
	
	success, data = create_disk_from_distribution(linode_id, distribution, disk_size, root_password, root_ssh_key_file)
	if not success:
		print >>sys.stderr, data
		sys.exit(1)
	
	disk_id = data[0]
	job_id = data[1]
	print "%d,%d" % (disk_id, job_id)
	sys.exit(0)

elif (cmd == 'create-swap-disk'):
	# Output: "<disk-ID>,<job-ID>" on success, or nothing on failure
	# Returns: 0 on success or 1 on failure. Error details on stderr
	linode_id = int(sys.argv[2])
	
	success, data = create_swap_disk(linode_id)
	if not success:
		print >>sys.stderr, data
		sys.exit(1)
	
	disk_id = data[0]
	job_id = data[1]
	print "%d,%d" % (disk_id, job_id)
	sys.exit(0)

elif (cmd == 'create-disk-from-stackscript'):
	create_disk_from_stackscript(linode_id, int(sys.argv[2]))

elif (cmd == 'configs'):
	list_configs(int(sys.argv[2]))

elif (cmd == 'create-config'):
	# Input: disks should be a single argument with comma separated list of disk IDs
	# Output: <config-ID> on success, or nothing on failure
	# Returns: 0 on success or 1 on failure. Error details on stderr
	linode_id = int(sys.argv[2])
	kernel = sys.argv[3] 
	disks = sys.argv[4] 
	config_label = sys.argv[5] 
	do_validations = True
	if len(sys.argv) >= 7:
		if int(sys.argv[6]) == 0:
			do_validations = False
	
	success, data = create_config(linode_id, kernel, disks, config_label, do_validations)
	if not success:
		print >>sys.stderr, data
		sys.exit(1)
	
	config_id = data
	print config_id
	sys.exit(0)

elif (cmd == 'create-stackscript'):
	create_stackscript(sys.argv[2])

elif (cmd == 'boot'):
	linode_id = int(sys.argv[2])
	config_id = None
	if len(sys.argv) >= 4:
		config_id = int(sys.argv[3])
	success, data = boot_node(linode_id, config_id)
	if not success:
		print >>sys.stderr, data
		sys.exit(1)
	
	job_id = data
	print job_id
	sys.exit(0)

elif (cmd == 'shutdown'):
	success, data = shutdown_node(int(sys.argv[2]))
	if not success:
		print >>sys.stderr, data
		sys.exit(1)
	
	job_id = data
	print job_id
	sys.exit(0)

elif (cmd == 'clone'):
	clone_node(linode_id)

elif (cmd == 'create-image'):
	linode_id = int(sys.argv[2])
	disk_id = int(sys.argv[3])
	image_label = sys.argv[4]
	
	success, data = create_diskimage(linode_id, disk_id, image_label)
	if not success:
		print >>sys.stderr, data
		sys.exit(1)
	
	image_id = data[0]
	job_id = data[1]
	print "%d,%d" % (image_id, job_id)
	
	sys.exit(0)

elif (cmd == 'create-disk-from-image'):
	
	linode_id = int(sys.argv[2])
	image_id = int(sys.argv[3]) 
	label = sys.argv[4]
	disk_size = sys.argv[5]
	root_password = sys.argv[6] 
	root_ssh_key_file = sys.argv[7]
	
	success, data = create_disk_from_image(linode_id, image_id, label, disk_size, root_password, root_ssh_key_file)
	if not success:
		print >>sys.stderr, data
		sys.exit(1)
	
	disk_id = data[0]
	job_id = data[1]
	print "%d,%d" % (disk_id, job_id)
	sys.exit(0)

elif (cmd == 'images'):
	list_diskimages()

elif (cmd == 'image-id'): 
	# Checks the input argument and returns the numeric image ID
	# if it's valid.
	#
	# Args: Either a numeric image ID (in which case it's just checked for validity
	#		or a image label which should match output of "image.list"
	#		
	# Output: The image ID or nothing
	# Returns: 0 on success or 1 on failure. Error details on stderr
	image_id, image_label = find_image(sys.argv[2])
	if image_id is None:
		print >> sys.stderr, "Invalid image:", sys.argv[2]
		sys.exit(1)
		
	print "%d,%s" % (image_id, image_label)
	sys.exit(0)

elif (cmd == 'delete-image'): 
	# Output: Nothing
	# Return: 0 if successfully deleted image, 1 if failed. Errors on stderr.
	image_id = int(sys.argv[2])
	success, data = delete_image(image_id)
	if not success:
		print >>sys.stderr, data
		sys.exit(1)
	
	sys.exit(0)
	
elif (cmd == 'api'):
	# Send details direct to API.
	# sys.argv[2] should be the api_action
	# sys.argv[3] should be the appropriate params in JSON format. Keys and string values should be in double quotes.
	#		Example:	./linode_api.py api test.echo  '{"foo":"bar"}'
	params = None	
	if len(sys.argv) > 3:
		params = json.loads(sys.argv[3])	
		
	resp = linode_request(sys.argv[2], params)
	print json.dumps(resp, indent=4, separators=(',',':'))				

