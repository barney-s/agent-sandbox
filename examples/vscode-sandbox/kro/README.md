
This example uses a ResourceGraphDefinition (RGD) to define an DevContainer CRD.
For more details on RGD please look at [KRO Overview](https://kro.run/docs/overview)

## Install KRO

Follow instructions to [Install KRO](https://kro.run/docs/getting-started/Installation)

## Administrator: Install ResourceGraphDefinition
The administrator installs the RGD in the cluster first before the user can consume it:

```
kubectl apply -f rgd.yaml
```

Validate the RGD is installed correctly:

```
kubectl get rgd

NAME            APIVERSION   KIND             STATE    AGE
devcontainer    v1alpha1     DevContainer   Active   6m38s
```

Validate that the new CRD is installed correctly
```
kubectl get crd

NAME                                   CREATED AT
devcontainers.custom.agents.x-k8s.io   2025-09-20T05:03:49Z  # << THIS
resourcegraphdefinitions.kro.run       2025-09-20T04:35:37Z
sandboxes.agents.x-k8s.io              2025-09-19T22:40:05Z
```

## User: Create DevContainer

The user creates a `DevContainer` resource something like this:

```
kubectl apply -f instance.yaml
```

```yaml
apiVersion: custom.agents.x-k8s.io/v1alpha1
kind: DevContainer
metadata:
  name: demo
spec:
  source:
    giturl: https://github.com/kubernetes-sigs/agent-sandbox.git
  devcontainerDir: examples/envbuilder-sandbox
```

They can then check the status of the applied resource:

```
kubectl get devcontainers
kubectl get devcontainers demo -o yaml
```

Once done, the user can delete the `DevContainer` instance:

```
kubectl delete devcontainer demo
```

## User: Accesing Devcontainer

Verify sandbox and pod are running:

```
kubectl get sandbox devc-demo
kubectl get pod devc-demo
```

Port forward the vscode server port.

```
 kubectl port-forward --address 0.0.0.0 pod/devc-demo 13337
```

Connect to the vscode-server on a browser via  http://localhost:13337 or <machine-dns>:13337

If should ask for a password.

#### Getting vscode password

In a separate terminal connect to the devcontainer pod and get the password.

```
kubectl exec  devc-demo   --  cat /root/.config/code-server/config.yaml 
```

Use the password and connect to vscode.

## User: Use gemini-cli

Gemini cli is preinstalled. Open a teminal in vscode and use Gemini cli.