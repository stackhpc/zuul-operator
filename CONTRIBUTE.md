# Developper documentation

The zuul operator is a container application that manages a
zuul service described by a high level description (named CR).
Its goal is to create the kubernetes resources and to perform
the runtime operations.

To describe the kubernetes resources such as Deployment and Service,
the zuul operator uses the Dhall language to convert the CR input
into the kubernetes resources.

To apply and manage the resources, the zuul operator uses Ansible
through the operator-framework to execute the roles/zuul when
a Zuul CR is requested.

The following sections explain how to evaluate the Dhall configuration
and the Ansible task locally, outside of a kubernetes pod.
This simplifies the development and contribution process.


## Setup tools

Install the `dhall-to-yaml` and `yaml-to-dhall` tool by following this tutorial:
https://docs.dhall-lang.org/tutorials/Getting-started_Generate-JSON-or-YAML.html#installation

Or use the zuul-operator image:

```bash
CR="podman"
alias dhall-to-yaml="$CR run --rm --entrypoint dhall-to-yaml -i docker.io/zuul/zuul-operator"
alias yaml-to-dhall="$CR run --rm --entrypoint yaml-to-dhall -i docker.io/zuul/zuul-operator"
```

## Evaluate the dhall expression manually

First you need to convert a CR spec to a dhall record, for example using the test file `playbooks/files/cr_spec.yaml`:

```bash
INPUT=$(yaml-to-dhall "(./conf/zuul/input.dhall).Input.Type" < playbooks/files/cr_spec.yaml)
```

Then you can evaluate the resources function, for example to get the scheduler service:

```bash
dhall-to-yaml --explain <<< "(./conf/zuul/resources.dhall ($INPUT)).Components.Zuul.Scheduler"
```

Or get all the kubernetes resources:

```bash
dhall-to-yaml <<< "(./conf/zuul/resources.dhall ($INPUT)).List"
```

## Run the ansible roles locally

Given a working `~/.kube/config` context, you can execute the Ansible roles directly using:

```bash
export ANSIBLE_CONFIG=playbooks/files/ansible.cfg
ansible-playbook -v playbooks/files/local.yaml
```

Then cleanup the resources using:

```bash
ansible-playbook -v playbooks/files/local.yaml -e k8s_state=absent
```


## Run the integration test locally

First you need to build the operator image:

```bash
make build
```

Or you can update an existing image with the local dhall and ansible content:

```bash
./playbooks/files/update-operator.sh
```

Then you can run the job using:

```bash
ansible-playbook -e @playbooks/files/local-vars.yaml -v playbooks/zuul-operator-functional/run.yaml
ansible-playbook -e @playbooks/files/local-vars.yaml -v playbooks/zuul-operator-functional/test.yaml
```

Alternatively, you can run the job without using the operator pod by including the ansible role directly.
To do that run the playbooks with:

```
ansible-playbook -e use_local_role=true ...
```

## Delete all kubernetes resources

To wipe your namespace run this command:

```bash
kubectl delete $(for obj in statefulset deployment service secret; do kubectl get $obj -o name; done)
```
