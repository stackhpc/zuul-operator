To run the functional tests locally with kind::

  ./restart.sh

  ansible-playbook -i tools/inventory -e @tools/vars.yaml \
    -e ansible_python_interpreter=`which python3` \
    playbooks/zuul-operator-functional/run.yaml

  # Start zuul-operator interactively while the above command is
  # running.

  ansible-playbook -i tools/inventory -e @tools/vars.yaml \
    -e ansible_python_interpreter=`which python3` \
    playbooks/zuul-operator-functional/test.yaml
