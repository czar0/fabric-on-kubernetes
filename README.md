**v1.4**
# Deploying Hyperledger Fabric on a Kubernetes cluster
A collection of kubernetes configurations and helm charts used to deploy a blockchain network.

The current configuration of the network is limited to:
- 2 organisations
- 2 peers (1 for each org)
- (optional) 2 couchdb state for the peers
- 1 ca
- 1 orderer (SOLO)

Therefore it is meant to be used mostly for development purposes.

Tested on IBM Cloud > IBM Container Service > Free cluster
## Prerequisites
- [Kubernetes](https://kubernetes.io/docs/setup/release/)
- [Helm](https://github.com/helm/helm)

## Deployment
### Using a single script
```bash
cd dev/scripts
./create_all [--with-couchdb]
```

### Using helm
**Note: Limited only to the creation of the network. Configuration of channel and chaincode no included yet.**

Follow the [README](helm-charts/README.md)

## Cleanup
### Using a single script
```bash
cd dev/scripts
./delete_all
```

### Using helm
Follow the [README](helm-charts/README.md)