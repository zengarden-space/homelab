#!/bin/bash

ansible-playbook -i hosts.yaml install-k3s.yaml -K
