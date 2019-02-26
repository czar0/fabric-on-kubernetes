#!/bin/bash

#
# deploy_charts.sh: Deploys the Helm Charts required to create an IBM Blockchain Platform
#                   development sandbox using IBM Container Service.
#
# Contributors:     Eddie Allen
#                   Mihir Shah
#                   Dhyey Shah
#
# Version:          7 December 2017
#

KUBECONFIG_FOLDER=$PWD/../dev/kube-configs
CONFIG_PATH=$PWD/../sampleconfig
FABRIC_VERSION=1.4

#
# checkDependencies: Checks to ensure required tools are installed.
#
 checkDependencies() {
    type kubectl >/dev/null 2>&1 || { echo >&2 "I require kubectl but it is not installed.  Aborting."; exit 1; }
    type helm >/dev/null 2>&1 || { echo >&2 "I require helm but it is not installed.  Aborting."; exit 1; }
}

#
# colorEcho:  Prints the user specified string to the screen using the specified color.
#             If no color is provided, the default no color option is used.
#
# Parameters: ${1} - The string to print.
#             ${2} - The color to use for printing the string.
#
#             NOTE: The following color options are available:
#
#                   [0|1]30, [dark|light] black
#                   [0|1]31, [dark|light] red
#                   [0|1]32, [dark|light] green
#                   [0|1]33, [dark|light] brown
#                   [0|1]34, [dark|light] blue
#                   [0|1]35, [dark|light] purple
#                   [0|1]36, [dark|light] cyan
#
 colorEcho() {
    # Check for proper usage
    if [[ ${#} == 0 || ${#} > 2 ]]; then
        echo "usage: ${FUNCNAME} <string> [<0|1>3<0-6>]"
        return -1
    fi

    # Set default color to white
    MSSG=${1}
    CLRCODE=${2}
    LIGHTDARK=1
    MSGCOLOR=0

    # If color code was provided, then set it
    if [[ ${#} == 2 ]]; then
        LIGHTDARK=${CLRCODE:0:1}
        MSGCOLOR=${CLRCODE:1}
    fi

    # Print out the message
    echo -e -n "${MSSG}" | awk '{print "\033['${LIGHTDARK}';'${MSGCOLOR}'m" $0 "\033[1;0m"}'
}

#
# cleanEnvironment: Cleans the services, volumes, and pods from the Kubernetes cluster.
#
 cleanEnvironment() {
    HELM_RELEASES=$(helm list | tail -n +2 | awk '{ print $1 }')

    # Delete any existing releases
    if [[ ! -z ${HELM_RELEASES// /} ]]; then
        echo -n "Deleting the following helm releases: "
        echo ${HELM_RELEASES}...
        helm delete --purge ${HELM_RELEASES}
        sleep 2
    fi

    # Wipe the /shared persistent volume if it exists (it should be removed with chart removal)
    # kubectl delete pv,pvc --all

    echo "Checking if all deployments are deleted"

    NUM_PENDING=$(kubectl get deployments | grep blockchain | wc -l | awk '{print $1}')
    while [ "${NUM_PENDING}" != "0" ]; do
        echo "Waiting for all blockchain deployments to be deleted. Remaining = ${NUM_PENDING}"
        NUM_PENDING=$(kubectl get deployments | grep blockchain | wc -l | awk '{print $1}')
        sleep 1;
    done

    NUM_PENDING=$(kubectl get svc | grep blockchain | wc -l | awk '{print $1}')
    while [ "${NUM_PENDING}" != "0" ]; do
        echo "Waiting for all blockchain services to be deleted. Remaining = ${NUM_PENDING}"
        NUM_PENDING=$(kubectl get svc | grep blockchain | wc -l | awk '{print $1}')
        sleep 1;
    done

    while [ "$(kubectl get pods | grep utils | wc -l | awk '{print $1}')" != "0" ]; do
        echo "Waiting for util pod to be deleted."
        sleep 1;
    done

    echo "All blockchain deployments & services have been removed"
}

#
# getPods: Updates the pod status variables.
#
 getPodStatus() {
    PODS=$(kubectl get pods -a)
    PODS_RUNNING=$(echo "${PODS}" | grep Running | wc -l)
    PODS_COMPLETED=$(echo "${PODS}" | grep Completed | wc -l)
    PODS_ERROR=$(echo "${PODS}" | grep Error | wc -l)
}

#
# checkPodStatus: Checks the status of all pods ensure the correct number are running,
#                 completed, and that none completed with errors.
#
# Parameters:     $1 - The expected number of pods in the 'Running' state.
#                 $2 - The expected number of pods in the 'Completed' state.
#
 checkPodStatus() {
    # Ensure arguments were passed
    if [[ ${#} -ne 2 ]]; then
        echo "Usage: ${FUNCNAME} <num_running_pods> <num_completed_pods>"
        return -1
    fi

    NUM_RUNNING=${1}
    NUM_COMPLETED=${2}

    # Get the status of the pods
    getPodStatus

    # Wait for the pods to initialize
    while [ "${PODS_RUNNING}" -ne ${NUM_RUNNING} ] || [ "${PODS_COMPLETED}" -ne ${NUM_COMPLETED} ]; do
        if [ "${PODS_ERROR}" -gt 0 ]; then
            colorEcho "\n$(basename $0): error: the following pods failed with errors:" 131
            colorEcho "$(echo "$PODS" | grep Error)" 131

            # Show the logs for failed pods
            for i in $(echo "$PODS" | grep Error | awk '{print $1}'); do
                # colorEcho "\n$ kubectl describe pod ${i}" 132
                # kubectl describe pod "${i}"

                if [[ ${i} =~ .*channel-create.* ]]; then
                    colorEcho "\n$ kubectl logs ${i} createchanneltx" 132
                    kubectl logs "${i}" "createchanneltx"

                    colorEcho "\n$ kubectl logs ${i} createchannel" 132
                    kubectl logs "${i}" "createchannel"
                else
                    colorEcho "\n$ kubectl logs ${i}" 132
                    kubectl logs "${i}"
                fi
            done

            exit -1
        fi

        colorEcho "Waiting for the pods to initialize..." 134
        sleep 2

        getPodStatus
    done

    colorEcho "Pods initialized successfully!\n" 134
}

#
# lintChart: Lints the helm chart in the current working directory.
#
 lintChart() {
    LINT_OUTPUT=$(helm lint .)

    if [[ ${?} -ne 0 ]]; then
        colorEcho "\n$(basename $0): error: '$(basename $(pwd))' linting failed with errors:" 131
        colorEcho "${LINT_OUTPUT}" 131
        exit -1
    fi
}

startNetworkLocalCharts() {
    RELEASE_NAME="fabric"
    TOTAL_RUNNING=6
    TOTAL_COMPLETED=2

    # Move into the directory
    pushd blockchain >/dev/null 2>&1

    # Install the chart
    lintChart
    colorEcho "\n$ helm install --name ${RELEASE_NAME} ." 132
    helm install --name ${RELEASE_NAME} .

    # Copy config
    UTILSSTATUS=$(kubectl get pods -a utils | grep utils | awk '{print $3}')
    while [ "${UTILSSTATUS}" != "Running" ]; do
        echo "Waiting for utils pod to start. Status = ${UTILSSTATUS}"
        sleep 5
        if [ "${UTILSSTATUS}" == "Error" ]; then
            echo "There is an error in utils pod. Please run 'kubectl logs utils' or 'kubectl describe pod utils'."
            exit 1
        fi
        UTILSSTATUS=$(kubectl get pods -a utils | grep utils | awk '{print $3}')
    done

    sleep 2

    echo "Copying configuration data to shared volume"
    test -d "../../sampleconfig" && echo Exists || echo Does not exist
    kubectl cp ../../sampleconfig utils:/shared/config

    # Ensure the correct number of pods are running and completed
    checkPodStatus ${TOTAL_RUNNING} ${TOTAL_COMPLETED}

    popd >/dev/null 2>&1
}

startNetworkOfficialCharts() {
    local base_path="${PWD}/hlf"
    local cryptos_path="${base_path}/cryptos"

    if [ -d "$cryptos_path" ]; then
        rm -rf $cryptos_path
    fi

    colorEcho "=======================================================" 136
    colorEcho "===== Fabric on Kubernetes - Official Helm Charts =====" 136
    colorEcho "=======================================================" 136

    echo
    colorEcho "Setting up the network" 134
    echo

    read -p "Fabric version [1.4]: " version
    version=${version:-"1.4"}
    colorEcho $version 132

    read -p "Organisations [1]: " orgs
    orgs=${orgs:-1}
    colorEcho $orgs 132

    read -p "Peers per org [1]: " peers
    peers=${peers:-1}
    colorEcho $peers 132

    read -p "CAs per org [1]: " cas
    cas=${cas:-1}
    colorEcho $cas 132

    read -p "Orderers per org [1]: " orderers
    orderers=${orderers:-1}
    colorEcho $orderers 132

    colorEcho "================================" 136
    colorEcho "==== Configuring Kubernetes ====" 136
    colorEcho "================================" 136
    
    read -p "Namespace [blockchain]: " namespace
    namespace=${namespace:-blockchain}
    colorEcho $namespace 132

    colorEcho "===============================" 134
    colorEcho "==== Certificate Authority ====" 134
    colorEcho "===============================" 134

    local ca_port="7054"

    read -p "CA name [ca]: " ca_name
    ca_name=${ca_name:-ca}
    colorEcho $ca_name 132

    colorEcho "Create and set up CA" 134
    helm install stable/hlf-ca --namespace $namespace --name $ca_name --set image.tag=${version},config.hlfToolsVersion=${version},service.port=${ca_port},caName=${ca_name},postgresql.enabled=true

    ca_pod=$(kubectl get pods --namespace $namespace -l "app=hlf-ca,release=${ca_name}" -o jsonpath="{.items[0].metadata.name}")
    status=$(kubectl describe pod --namespace $namespace -l "app=hlf-ca,release=${ca_name}" | grep -m2 "Ready" | tail -n1 |  awk '{print $2}')
    while [ "${status}" != "True" ]; do
        colorEcho "Waiting for $ca_pod to start. Status = ${status}" 135
        sleep 5
        if [ "${status}" == "Error" ]; then
            colorEcho "There is an error in $ca_pod. Please run 'kubectl logs $ca_pod' or 'kubectl describe pod $ca_pod'." 131
            exit 1
        fi
        status=$(kubectl describe pod --namespace $namespace -l "app=hlf-ca,release=${ca_name}" | grep -m2 "Ready" | tail -n1 |  awk '{print $2}')
    done

    kubectl exec --namespace $namespace $ca_pod -- bash -c 'fabric-ca-client enroll -d -u http://$CA_ADMIN:$CA_PASSWORD@$SERVICE_DNS:7054'
    kubectl exec --namespace $namespace $ca_pod -- cat /var/hyperledger/fabric-ca/msp/signcerts/cert.pem
    kubectl exec --namespace $namespace $ca_pod -- fabric-ca-client getcacert -u http://$CA_ADMIN:$CA_PASSWORD@$SERVICE_DNS:7054

    org_msp="Org1MSP"

    colorEcho "Register organisation admin" 134
    read -p "Admin name [org1-admin]: " admin_name
    admin_name=${admin_name:-org1-admin}
    colorEcho $admin_name 132

    read -p "Admin secret [OrgAdm1nPW]: " admin_secret
    admin_secret=${admin_secret:-OrgAdm1nPW}
    colorEcho $admin_secret 132

    colorEcho "Register the Organisation Admin identity" 134
    kubectl exec --namespace $namespace $ca_pod -- fabric-ca-client register --id.name $admin_name --id.secret $admin_secret --id.attrs 'admin=true:ecert'

    colorEcho "Enroll the Organisation Admin identity in $org_msp" 134
    kubectl exec --namespace $namespace $ca_pod -- fabric-ca-client enroll -u http://${admin_name}:${admin_secret}@$SERVICE_DNS:7054 -M $org_msp

    colorEcho "Copying credentials to local" 134
    kubectl cp --namespace $namespace $ca_pod:/var/hyperledger/fabric-ca/$org_msp ${cryptos_path}/${org_msp} 1>/dev/null

    mkdir -p ${cryptos_path}/${org_msp}/admincerts
    cp ${cryptos_path}/${org_msp}/signcerts/* ${cryptos_path}/${org_msp}/admincerts

    colorEcho "Add org-admincert secret" 134
    org_cert=$(ls ${cryptos_path}/${org_msp}/admincerts/*.pem)
    kubectl create secret generic --namespace $namespace hlf--org-admincert --from-file=cert.pem=$org_cert

    colorEcho "Add org-adminkey secret" 134
    org_key=$(ls ${cryptos_path}/${org_msp}/keystore/*_sk)
    kubectl create secret generic --namespace $namespace hlf--org-adminkey --from-file=key.pem=$org_key

    colorEcho "Add cacert secret" 134
    ca_cert=$(ls ${cryptos_path}/${org_msp}/cacerts/*.pem)
    kubectl create secret generic --namespace $namespace hlf--ca-cert --from-file=cacert.pem=$ca_cert

    colorEcho "=================" 134
    colorEcho "==== Orderer ====" 134
    colorEcho "=================" 134

    colorEcho "Register Orderer to CA" 134
    read -p "Orderer name [orderer]: " orderer_name
    orderer_name=${orderer_name:-orderer}
    colorEcho $orderer_name 132

    read -p "Orderer secret [orderer_pw]: " orderer_secret
    orderer_secret=${orderer_secret:-orderer_pw}
    colorEcho $orderer_secret 132

    orderer_msp="OrdererMSP"
    orderer_port="31010"
    ord_type="solo"

    colorEcho "Register $orderer_name" 134
    kubectl exec --namespace $namespace $ca_pod -- fabric-ca-client register --id.name $orderer_name --id.secret $orderer_secret --id.type orderer

    colorEcho "Enroll $orderer_name" 134
    kubectl exec --namespace $namespace $ca_pod -- fabric-ca-client enroll -d -u http://${orderer_name}:${orderer_secret}@$SERVICE_DNS:7054 -M $orderer_msp

    colorEcho "Copying credentials to local" 134
    kubectl cp --namespace $namespace $ca_pod:/var/hyperledger/fabric-ca/${orderer_msp} ${cryptos_path}/${orderer_msp} 1>/dev/null

    mkdir -p ${cryptos_path}/${orderer_msp}/admincerts
    cp ${cryptos_path}/${orderer_msp}/signcerts/* ${cryptos_path}/${orderer_msp}/admincerts

    colorEcho "Add orderer public certificate" 134
    orderer_cert=$(ls ${cryptos_path}/${orderer_msp}/admincerts/*.pem)
    kubectl create secret generic --namespace $namespace hlf--${orderer_name}-idcert --from-file=cert.pem=${orderer_cert}

    colorEcho "Add orderer signining private key" 134
    orderer_key=$(ls ${cryptos_path}/${orderer_msp}/keystore/*_sk)
    kubectl create secret generic --namespace $namespace hlf--${orderer_name}-idkey --from-file=key.pem=${orderer_key}

    colorEcho "==============" 134
    colorEcho "==== Peer ====" 134
    colorEcho "==============" 134

    colorEcho "Register Peer to CA" 134
    read -p "Peer name [org1peer1]: " peer_name
    peer_name=${peer_name:-org1peer1}
    colorEcho $peer_name 132

    read -p "Peer secret [org1peer1_pw]: " peer_secret
    peer_secret=${peer_secret:-org1peer1_pw}
    colorEcho $peer_secret

    peer_msp="Org1MSP"
    peer_port="30110"

    colorEcho "Register $peer_name" 134
    kubectl exec --namespace $namespace $ca_pod -- fabric-ca-client register --id.name $peer_name --id.secret $peer_secret --id.type peer

    colorEcho "Enroll $peer_name" 134
    kubectl exec --namespace $namespace $ca_pod -- fabric-ca-client enroll -d -u http://${peer_name}:${peer_secret}@$SERVICE_DNS:${ca_port} -M ${peer_msp}_${peer_name}

    colorEcho "Copying credentials to local" 134
    kubectl cp --namespace $namespace $ca_pod:/var/hyperledger/fabric-ca/${peer_msp}_${peer_name} ${cryptos_path}/${peer_msp}_${peer_name} 1>/dev/null

    mkdir -p ${cryptos_path}/${peer_msp}_${peer_name}/admincerts
    cp ${cryptos_path}/${peer_msp}_${peer_name}/signcerts/* ${cryptos_path}/${peer_msp}_${peer_name}/admincerts

    colorEcho "Add peer public certificate" 134
    peer_cert=$(ls ${cryptos_path}/${peer_msp}_${peer_name}/signcerts/*.pem)
    kubectl create secret generic --namespace $namespace hlf--${peer_name}-idcert --from-file=cert.pem=${peer_cert}

    colorEcho "Add peer signining private key" 134
    peer_key=$(ls ${cryptos_path}/${peer_msp}_${peer_name}/keystore/*_sk)
    kubectl create secret generic --namespace $namespace hlf--${peer_name}-idkey --from-file=key.pem=${peer_key}

    colorEcho "Create and set up CouchDB state to attach to ${peer_name}" 134
    helm install stable/hlf-couchdb --namespace $namespace --name cdb-${peer_name} --set image.tag=0.4.14

    # sleep 20
    
    # cdb_pod=$(kubectl get pods --namespace $namespace -l "app=hlf-couchdb,release=cdb-${peer_name}" -o jsonpath="{.items[0].metadata.name}")
    # status=$(kubectl describe pod --namespace $namespace -l "app=hlf-couchdb,release=cdb-${peer_name}" | grep -m2 "Ready" | tail -n1 |  awk '{print $2}')
    # while [ "${status}" != "True" ]; do
    #     echo "Waiting for cdb-${peer_name} to start. Status = ${status}"
    #     sleep 5
    #     if [ "${status}" == "Error" ]; then
    #         echo "There is an error in cdb-${peer_name}. Please run 'kubectl logs cdb-${peer_name}' or 'kubectl describe pod cdb-${peer_name}'."
    #         exit 1
    #     fi
    #     status=$(kubectl describe pod --namespace $namespace -l "app=hlf-couchdb,release=cdb-${peer_name}" | grep -m2 "Ready" | tail -n1 |  awk '{print $2}')
    # done
    
    read -p "Channel [mychannel]: " channel_name
    channel_name=${channel_name:-mychannel}
    colorEcho $channel_name 132

    # generate channel config
    # $1: channel_name
    # $2: base path
    # $3: configtx.yml, crypto-config.yml path
    # $4: certificates output directory
    generate_channeltx $channel_name ${base_path} ${base_path}/config $cryptos_path

    kubectl create secret generic --namespace $namespace hlf--${channel_name}-genesis --from-file=genesis.block=${base_path}/channels/$channel_name/${channel_name}_genesis.block
    kubectl create secret generic --namespace $namespace hlf--${channel_name}-channel --from-file=${base_path}/channels/$channel_name/${channel_name}.tx
    kubectl create secret generic --namespace $namespace hlf--${channel_name}-org1anchors --from-file=${base_path}/channels/$channel_name/${org_msp}_anchors.tx

    colorEcho "Create and set up Orderer" 134
    helm install stable/hlf-ord --namespace $namespace --name $orderer_name --set image.tag=${version},ord.mspID=$orderer_msp,service.port=${orderer_port},ord.type=${ord_type},secrets.ord.cert=hlf--${orderer_name}-idcert,secrets.ord.key=hlf--${orderer_name}-idkey,secrets.ord.caCert=hlf--ca-cert,secrets.genesis=hlf--${channel_name}-genesis,secrets.adminCert=hlf--org-admincert
    
    colorEcho "Create and set up Peer" 134
    helm install stable/hlf-peer --namespace $namespace --name $peer_name --set image.tag=${version},peer.couchdbInstance=cdb-${peer_name},peer.mspID=${peer_msp},service.portRequest=${peer_port},secrets.peer.cert=hlf--${peer_name}-idcert,secrets.peer.key=hlf--${peer_name}-idkey,secrets.peer.caCert=hlf--ca-cert,secrets.channel=hlf--${channel_name}-channel,secrets.adminCert=hlf--org-admincert,secrets.adminKey=hlf--org-adminkey

    peer_pod=$(kubectl get pods --namespace $namespace -l "app=hlf-peer,release=${peer_name}" -o jsonpath="{.items[0].metadata.name}")

    # colorEcho "Create channel" 134
    # kubectl exec --namespace $namespace $peer_pod -- peer channel create -o ${orderer_name}-hfl-ord:${orderer_port} -c $channel_name -f /hl_config/channel/${channel_name}.tx

    # colorEcho "Fetch channel" 134
    # kubectl exec --namespace $namespace $peer_pod -- peer fetch config /hl_config/channel/${channel_name}.block -c $channel_name -o ${orderer_name}:${orderer_port}

    # colorEcho "Join channel" 134
    # kubectl exec --namespace $namespace $peer_pod -- peer channel join -b /hl_config/channel/${channel_name}.block
}

generate_channeltx() {
    if [ -z "$1" ]; then
		colorEcho "Channel name missing" 131
		exit 1
	fi
    if [ -z "$2" ]; then
		colorEcho "Base path missing" 131
		exit 1
	fi
    if [ -z "$3" ]; then
		colorEcho "Config path missing" 131
		exit 1
	fi
    if [ -z "$4" ]; then
		colorEcho "Crypto material path missing" 131
		exit 1
	fi

	local channel_name="$1"
    local base_path="$2"
    local config_path="$3"
    local cryptos_path="$4"
    local channel_dir="${base_path}/channels/${channel_name}"
    local org_msp=Org1MSP

    if [ -d "$channel_dir" ]; then
        rm -rf $channel_dir
    fi
    mkdir -p $channel_dir

    colorEcho "Generating crypto-config" 136
	colorEcho "Channel: $channel_name" 132
	colorEcho "Base path: $base_path" 132
	colorEcho "Config path: $config_path" 132
	colorEcho "Channel dir: $channel_dir" 132
	colorEcho "Cryptos path: $cryptos_path" 132

	# generate genesis block for orderer
	docker run --rm -v ${config_path}/configtx.yaml:/configtx.yaml \
                    -v ${channel_dir}:/channels/${channel_name} \
                    -v ${cryptos_path}:/cryptos \
                    -e FABRIC_CFG_PATH=/ \
                    hyperledger/fabric-tools:$FABRIC_VERSION \
                    configtxgen -profile OneOrgOrdererGenesis -outputBlock /channels/${channel_name}/${channel_name}_genesis.block /configtx.yaml
	if [ "$?" -ne 0 ]; then
		colorEcho "Failed to generate orderer genesis block..." 131
		exit 1
	fi

	# generate channel configuration transaction
	docker run --rm -v ${config_path}/configtx.yaml:/configtx.yaml \
                    -v ${channel_dir}:/channels/${channel_name} \
                    -v ${cryptos_path}:/cryptos \
                    -e FABRIC_CFG_PATH=/ \
                    hyperledger/fabric-tools:$FABRIC_VERSION \
                    configtxgen -profile OneOrgChannel -outputCreateChannelTx /channels/${channel_name}/${channel_name}.tx -channelID $channel_name /configtx.yaml
	if [ "$?" -ne 0 ]; then
		colorEcho "Failed to generate channel configuration transaction..." 131
		exit 1
	fi

	# generate anchor peer transaction
	docker run --rm -v ${config_path}/configtx.yaml:/configtx.yaml \
                    -v ${channel_dir}:/channels/${channel_name} \
                    -v ${cryptos_path}:/cryptos \
                    -e FABRIC_CFG_PATH=/ \
                    hyperledger/fabric-tools:$FABRIC_VERSION \
                    configtxgen -profile OneOrgChannel -outputAnchorPeersUpdate /channels/${channel_name}/${org_msp}_anchors.tx -channelID $channel_name -asOrg $org_msp /configtx.yaml
	if [ "$?" -ne 0 ]; then
		colorEcho "Failed to generate anchor peer update for $org_msp..." 131
		exit 1
	fi
}

generate_cryptos() {
    if [ -z "$1" ]; then
		colorEcho "Config path missing" 131
		exit 1
	fi

    local config_path="$1"

	# remove previous crypto material and config transactions
	rm -fr ${config_path}/crypto-config
	mkdir -p ${config_path}/crypto-config

	# generate crypto material
	docker run --rm -v ${config_path}/crypto-config.yaml:/crypto-config.yaml \
                    -v ${config_path}/crypto-config:/crypto-config \
                    hyperledger/fabric-tools:$FABRIC_VERSION \
                    cryptogen generate --config=/crypto-config.yaml --output=/crypto-config
	if [ "$?" -ne 0 ]; then
		colorEcho "Failed to generate crypto material..." 131
		exit 1
	fi
}

printHelp () {
  echo "Command not implemented - I know, I am not so helpful :)"
}

readonly func="$1"
shift

if [ "$func" == "dep" ]; then
    checkDependencies
elif [ "$func" == "start" ]; then
    if [ "$1" = "--exp" ] || [ "$1" = "-e" ]; then
        shift
        startNetworkOfficialCharts
    fi
    startNetworkLocalCharts
elif [ "$func" == "clean" ]; then
    cleanEnvironment
else
    printHelp
    exit 1
fi