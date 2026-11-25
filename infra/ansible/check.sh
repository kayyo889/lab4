#!/bin/sh
set -eu
python3 -m pip install -r requirements.txt
ansible-galaxy collection install -r requirements.yml
for environment in staging qa; do
  ansible-inventory -i "inventories/$environment/hosts.yml" --graph
  ansible-playbook -i "inventories/$environment/hosts.yml" site.yml --syntax-check
done
