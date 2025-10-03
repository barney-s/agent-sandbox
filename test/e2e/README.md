# E2E testing

This guide provides instructions for running e2e tests.

## Prerequisites

See the [development guide](../../docs/development.md) for prerequisite tools
and for instructions on how to build/deploy agent-sandbox.

## Running the e2e tests

The e2e tests assume that the cluster is created and that the kubeconfig for the
cluster lives in `bin/KUBECONFIG`. This can be used to connect the e2e tests to
an arbitrary cluster, but for the sake of this guide we will use a
[kind cluster](https://github.com/kubernetes-sigs/kind).

First create a kind cluster and install `agent-sandbox`:

```shell
make deploy-kind
```

Next, run the e2e tests on the newly created kind cluster:

```shell
go test ./test/e2e/... --parallel=1
```

Note: the `--parallel=1` argument makes sure only a single test runs at a time.
