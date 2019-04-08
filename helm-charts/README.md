# Hyperledger Fabric Helm Charts

This directory contains [Helm Charts](https://github.com/kubernetes/helm/blob/master/docs/charts.md) for creating an Hyperledger Fabric network developed in a sandbox.

## Kubernetes

Obtain a Kubernetes cluster and set `KUBECONFIG` to point to it.

### Install Helm

1. Download and extract [Helm](https://github.com/kubernetes/helm#install) for your platform.
2. Follow the instruction on how to set up help for your specific platform.
3. Initialise helm
```bash
helm init
```

### Deploy the Charts

Deploy all of the charts by running the following commands:

```bash
./deploy_charts.sh start
```

### Clean the environment

Clean up the environment by running the following commands:

```bash
./deploy_charts.sh clean
```

## Deploying the Charts Manually

Use the following instructions to deploy each chart manually.

 > **Note:** Give the charts time to install before moving on to the next chart.
 >
 >Use the command `kubectl get pods -a` to check on the status of the containers and ensure that none complete with an `Error` status.  
 >
 >Additional information can be obtained for a pod by using the command `kubectl logs <pod_name>`.

* Deploy the blockchain network chart by running the following commands:

  ```bash
  cd ./blockchain
  helm install --name blockchain .
  ```