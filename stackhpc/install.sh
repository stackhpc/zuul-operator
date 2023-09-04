kubectl apply -f "database/*.yaml"
kubectl apply -f ../deploy/crds/zuul-ci_v1alpha2_zuul_crd.yaml
kubectl apply -f ../deploy/rbac-admin.yaml
kubectl apply -f ../deploy/operator.yaml
kubectl create secret generic zuul-nodepool-config --from-file=deploy-zuul/nodepool.yaml
kubectl create secret generic zuul-tenant-config --from-file=deploy-zuul/main.yaml
kubectl create secret generic github-secrets --from-file=github-secrets
kubectl create secret generic gh-key --from-file=keys
kubectl apply -f deploy-zuul/zuul.yaml
