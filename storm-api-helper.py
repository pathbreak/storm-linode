#!/usr/bin/python

# Python helper module to extract information from the JSON responses returned by Storm UI REST API
# See https://github.com/apache/storm/blob/master/STORM-UI-REST-API.md for API documentation

import sys
import json

def print_topology_names():
	input_text=sys.stdin.read()
	obj=json.loads(input_text)
	# If there are no topologies, the json is an empty topologies list {"topologies":[]}
	for topology in obj['topologies']:
		print topology['name']


def print_topology_ids():
	input_text=sys.stdin.read()
	obj=json.loads(input_text)
	# If there are no topologies, the json is an empty topologies list {"topologies":[]}
	for topology in obj['topologies']:
		print topology['id']


if (len(sys.argv) > 1):
	delegates = {
		'topology-names' 	: print_topology_names,
		'topology-ids'	 	: print_topology_ids,
	}
	func = delegates.get(sys.argv[1], lambda:"nothing")
	func()
	



