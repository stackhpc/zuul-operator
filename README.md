Zuul Operator
=============

## Build the image

```shell
$ make image
```

## Install the operator

```shell
$ make install
kubectl apply -f deploy/crds/zuul-ci_v1alpha2_zuul_crd.yaml -f deploy/rbac.yaml -f deploy/operator.yaml
```

Look for operator pod and check it's output

```shell
$ kubectl get pods
NAME                            READY     STATUS    RESTARTS   AGE
zuul-operator-c64756f66-rbdmg   2/2       Running   0          3s
$ kubectl logs zuul-operator-c64756f66-rbdmg
[...]
{"level":"info","ts":1554197305.5853095,"logger":"cmd","msg":"Go Version: go1.10.3"}
{"level":"info","ts":1554197305.5854425,"logger":"cmd","msg":"Go OS/Arch: linux/amd64"}
{"level":"info","ts":1554197305.5854564,"logger":"cmd","msg":"Version of operator-sdk: v0.6.0"}
{"level":"info","ts":1554197305.5855,"logger":"cmd","msg":"Watching namespace.","Namespace":"default"}
[...]
```

## Usage

```
$ kubectl apply -f - <<EOF
apiVersion: operator.zuul-ci.org/v1alpha2
kind: Zuul
metadata:
  name: example-zuul
spec:

EOF
zuul.zuul-ci.org/example-zuul created
```
