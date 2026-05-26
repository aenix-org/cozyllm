export NAME ?= holmesgpt
export NAMESPACE ?= cozy-holmesgpt

include ../../../scripts/package.mk

generate:
	cozyvalues-gen --values values.yaml --schema values.schema.json --readme README.md
