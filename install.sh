kubectl apply -f deploy/crds/zuul-ci_v1alpha2_zuul_crd.yaml
kubectl apply -f deploy/rbac-admin.yaml
kubectl apply -f deploy/operator.yaml
kubectl create ns zuul
kubectl -n zuul create secret generic zuul-nodepool-config --from-file=nodepool.yaml
kubectl -n zuul create secret generic zuul-tenant-config --from-file=tenant.yaml
kubectl -n zuul create secret generic executor-secrets --from-file=keys/id_rsa
