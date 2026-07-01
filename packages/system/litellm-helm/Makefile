export NAME ?= litellm-helm
export NAMESPACE ?= cozy-litellm

include ../../../scripts/package.mk

update:
	rm -rf charts
	helm pull oci://ghcr.io/berriai/litellm-helm --version 1.90.2 --untar --untardir charts
	patch --no-backup-if-mismatch -p1 -d charts/litellm-helm < patches/cross-cluster-db-values.patch
