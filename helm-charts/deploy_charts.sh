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

KUBECONFIG_FOLDER=../cs-offerings/kube-configs

#
# checkDependencies: Checks to ensure required tools are installed.
#
function checkDependencies() {
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
function colorEcho() {
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
function cleanEnvironment() {
    HELM_RELEASES=$(helm list | tail -n +2 | awk '{ print $1 }')

    # Delete any existing releases
    if [[ ! -z ${HELM_RELEASES// /} ]]; then
        echo -n "Deleting the following helm releases: "
        echo ${HELM_RELEASES}...
        helm delete --purge ${HELM_RELEASES}
        sleep 2
    fi

    # Wipe the /shared persistent volume if it exists (it should be removed with chart removal)
    # kubectl delete pv --all
    # kubectl delete pvc --all

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
function getPodStatus() {
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
function checkPodStatus() {
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
function lintChart() {
    LINT_OUTPUT=$(helm lint .)

    if [[ ${?} -ne 0 ]]; then
        colorEcho "\n$(basename $0): error: '$(basename $(pwd))' linting failed with errors:" 131
        colorEcho "${LINT_OUTPUT}" 131
        exit -1
    fi
}

#
# startNetwork: Starts the CA, orderer, and peer containers.
#
function startNetwork() {
    cleanEnvironment
    
    RELEASE_NAME="fabric"
    TOTAL_RUNNING=4
    TOTAL_COMPLETED=1

    # Move into the directory
    pushd blockchain-network >/dev/null 2>&1

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

#
# Clean up and deploy the charts
#
checkDependencies

"$@"