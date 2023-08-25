kubectl apply -f deploy/crds/zuul-ci_v1alpha2_zuul_crd.yaml
kubectl apply -f deploy/rbac-admin.yaml
kubectl apply -f deploy/operator.yaml
kubectl create secret generic zuul-nodepool-config --from-file=nodepool.yaml
kubectl create secret generic zuul-tenant-config --from-file=tenant.yaml
kubectl create secret generic executor-secrets --from-file=keys/id_rsa
