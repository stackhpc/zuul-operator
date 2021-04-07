image:
	podman build -f build/Dockerfile -t docker.io/zuul/zuul-operator .

install:
	kubectl apply -f deploy/crds/zuul-ci_v1alpha2_zuul_crd.yaml -f deploy/rbac-admin.yaml -f deploy/operator.yaml

deploy-cr:
	kubectl apply -f deploy/crds/zuul-ci_v1alpha2_zuul_cr.yaml
