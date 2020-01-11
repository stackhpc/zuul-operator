image:
	podman build -f build/Dockerfile -t docker.io/zuul/zuul-operator .

install:
	kubectl apply -f deploy/crds/zuul-ci_v1alpha1_zuul_crd.yaml -f deploy/rbac.yaml -f deploy/operator.yaml

deploy-cr:
	kubectl apply -f deploy/crds/zuul-ci_v1alpha1_zuul_cr.yaml
