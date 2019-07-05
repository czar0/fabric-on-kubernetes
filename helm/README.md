# Hyperledger Fabric Helm Charts

This directory contains [Helm Charts](https://github.com/kubernetes/helm/blob/master/docs/charts.md) for creating an Hyperledger Fabric network developed in a sandbox.

## Setup your environment

### Kubernetes

Obtain a Kubernetes cluster and set `KUBECONFIG` to point to it.

```bash
export KUBECONFIG=<your kubernetes config file>
```

### Helm

1. Download and extract [Helm](https://github.com/kubernetes/helm#install) for your platform
2. Follow the instruction on how to set up help for your specific platform
3. Initialise helm and upgrade the tiller if exists

```bash
helm init [--tiller-namespace <namespace>] --upgrade
```

## Configurable and interactive setup (for PROD)

Complete setup with volumes attached to single components and data persistency

This setup includes:

- Data persistency for ledger (blockchain and state)

- Resources such as volumes, secrets and config are attached to single components (and not shared)

- Private keys, certificates and configuration files stored as secrets

- Configurations of environment variables stored as `ConfigMap`

- CA equipped with PostgreSQL/MySQL database for storing certificates

- Registration and enrollment of users is done dynamically

Deploy all the official charts by running the following commands:

```bash
./deploy.sh start -i
# or alternatively
./deploy.sh start prod
```

## Simple setup (for STAG)

Standard 2-orgs-1-peer not-extandable setup with one unique shared volume; no secrets; no data persistency

Deploy all the local charts by running the following commands:

```bash
./deploy_charts.sh start
```

## Wipe all

Clean up the environment by running the following commands:

```bash
./deploy_charts.sh clean <namespace>
```

## Run commands

This example is made for the `Production` extandable configuration, but can be easily changed to support the `Staging` one.

1. Set some environment variables

    ```bash
    export namespaece=<k8s namespace where to set up the network>
    export channel_name=<channel name id>
    export chaincode_name=<chaincode name id>
    export peer_address=<full address of the peer including port>
    export orderer_address=<full address of the orderer including port>

    # e.g.
    export namespaece=blockchain
    export channel_name="mychannel"
    export chaincode_name="mychaincode"
    export peer_address=org1peer1-hlf-peer:30110
    export orderer_address=orderer-hlf-ord:31010
    ```

1. Copy the cloud/remote config, add to a file and export it as `KUBECONFIG` variable

    ```bash
    export KUBECONFIG=<rancher configuration file>
    ```

2. Retrieve the CLI container name

    ```bash
    cli_pod=$(kubectl get pods --namespace $namespace -l "app=hlf-tools,release=cli" -o jsonpath="{.items[0].metadata.name}")
    ```

3. Run an invoke:

    ```bash
    kubectl exec --namespace $namespace $cli_pod -- bash -c "CORE_PEER_LOCALMSPID=Org1MSP CORE_PEER_MSPCONFIGPATH=/var/hyperledger/admin_msp CORE_PEER_ADDRESS=$peer_address peer chaincode invoke -o $orderer_address -C $channel_name -n $chaincode_name -c '{\"Args\":[\"put\",\"a\",\"10\"]}'"
    ```

4. Run a query:

    ```bash
    kubectl exec --namespace blockchain $cli_pod -- bash -c "CORE_PEER_LOCALMSPID=Org1MSP CORE_PEER_MSPCONFIGPATH=/var/hyperledger/admin_msp CORE_PEER_ADDRESS=$peer_address peer chaincode invoke -o $orderer_adddress -C $channel_name -n $chaincode_name -c '{\"Args\":[\"get\",\"a\"]}'"
    ```

**Note: Chaincode cointainer is hidden, but the log get attached to the peer, so that you can see the output of your commands there.**

## References

[hlf-peer](https://github.com/helm/charts/tree/master/stable/hlf-peer)

[hlf-couchdb](https://github.com/helm/charts/tree/master/stable/hlf-couchdb)

[hlf-ca](https://github.com/helm/charts/tree/master/stable/hlf-ca)

[hlf-ord](https://github.com/helm/charts/tree/master/stable/hlf-ord)