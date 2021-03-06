#!/bin/bash

function usage {
	echo "usage: $0: <download-kubectl|download-minikube|download-gcloud|delete-all-apps|delete-all-test-apps|\
delete-all-stage-apps|delete-all-prod-apps|setup-namespaces|setup-prod-infra|setup-tools-infra-vsphere|setup-tools-infra-gce>"
	exit 1
}

function createNamespace() {
	local namespaceName="${1}"
	local folder=""
	if [ -d "tools" ]; then
		folder="tools/"
	fi
	mkdir -p "${folder}build"
	cp "${folder}k8s/namespace.yml" "${folder}build/namespace.yml"
	substituteVariables "name" "${namespaceName}" "${folder}build/namespace.yml"
	kubectl create -f "${folder}build/namespace.yml"
}

# shellcheck disable=SC2120
function createJenkins() {
	local appName="jenkins"
	local namespaceName="cloudpipelines-prod"
	local folder=""
	if [ -d "tools" ]; then
		folder="tools/"
	fi
	kubectl delete -f "${folder}k8s/${appName}-${CLOUD_TYPE}-pvc.yml" --namespace="${namespaceName}" --ignore-not-found
	kubectl create -f "${folder}k8s/${appName}-${CLOUD_TYPE}-pvc.yml" --namespace="${namespaceName}" --validate=false
	kubectl delete -f "${folder}k8s/${appName}-${CLOUD_TYPE}.yml" --namespace="${namespaceName}" --ignore-not-found
	kubectl create -f "${folder}k8s/${appName}-${CLOUD_TYPE}.yml" --namespace="${namespaceName}" --validate=false
	kubectl delete -f "${folder}k8s/${appName}-service.yml" --namespace="${namespaceName}" --ignore-not-found
	kubectl create -f "${folder}k8s/${appName}-service.yml" --namespace="${namespaceName}" --validate=false
}

# shellcheck disable=SC2120
function createArtifactory() {
	local appName="artifactory"
	local namespaceName="cloudpipelines-prod"
	local folder=""
	if [ -d "tools" ]; then
		folder="tools/"
	fi
	kubectl delete -f "${folder}k8s/${appName}.yml" --namespace="${namespaceName}" --ignore-not-found
	kubectl create -f "${folder}k8s/${appName}.yml" --namespace="${namespaceName}" --validate=false
	kubectl delete -f "${folder}k8s/${appName}-service.yml" --namespace="${namespaceName}" --ignore-not-found
	kubectl create -f "${folder}k8s/${appName}-service.yml" --namespace="${namespaceName}" --validate=false
}

function copyK8sYamls() {
	mkdir -p "${FOLDER}build"
	cp "${SCRIPTS}"/src/main/bash/k8s/*.* "${FOLDER}build/"
}

function system {
	unameOut="$(uname -s)"
	case "${unameOut}" in
		Linux*)	 machine=linux;;
		Darwin*)	machine=darwin;;
		*)		  echo "Unsupported system" && exit 1
	esac
	echo ${machine}
}

SYSTEM=$( system )

[[ $# -eq 1 ]] || usage

export ROOT_FOLDER
ROOT_FOLDER="$( pwd )/../"
export FOLDER
FOLDER="$( pwd )/"
if [ -d "tools" ]; then
	FOLDER="$( pwd )/tools/"
	ROOT_FOLDER="$( pwd )/"
fi

export PAAS_NAMESPACE="cloudpipelines-prod"
export PAAS_PROD_API_URL="192.168.99.100:8443"
export ENVIRONMENT="PROD"
export PAAS_TYPE="k8s"
export LANGUAGE_TYPE="jvm"
export PROJECT_TYPE="gradle"
export TOOLS_REPO="${TOOLS_REPO:-https://github.com/CloudPipelines/scripts}"
export SCRIPTS

function fetchAndSourceScripts() {
	tmpDir="$(mktemp -d)"
	SCRIPTS="${tmpDir}"
	trap '{ rm -rf ${tmpDir}; }' EXIT
	git clone "${TOOLS_REPO}" "${tmpDir}"

	pushd "${ROOT_FOLDER}tools/k8s"

		# shellcheck source=/dev/null
		source "${SCRIPTS}"/src/main/bash/pipeline-k8s.sh

		# Overridden functions
		function outputFolder() {
			echo "${FOLDER}build"
		}
		export -f outputFolder

		function mySqlDatabase() {
			echo "github"
		}
		export -f mySqlDatabase

		function waitForAppToStart() {
			echo "not waiting for the app to start"
		}
		export -f waitForAppToStart
	popd
}

case $1 in
	download-kubectl)
		curl -LO "https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/${SYSTEM}/amd64/kubectl"
		chmod +x ./kubectl
		sudo mv ./kubectl /usr/local/bin/kubectl
		;;

	download-minikube)
		curl -Lo minikube "https://storage.googleapis.com/minikube/releases/v0.20.0/minikube-${SYSTEM}-amd64" && chmod +x minikube && sudo mv minikube /usr/local/bin/
		;;

	download-gcloud)
		if [[ "${OSTYPE}" == linux* ]]; then
			OS_TYPE="linux"
		else
			OS_TYPE="darwin"
		fi
		GCLOUD_VERSION="${GCLOUD_VERSION:-172.0.1}"
		GCLOUD_ARCHIVE="${GCLOUD_ARCHIVE:-google-cloud-sdk-${GCLOUD_VERSION}-${OS_TYPE}-x86_64.tar.gz}"
		GCLOUD_PARENT_PATH="${GCLOUD_PARENT_PATH:-${HOME}/gcloud}"
		GCLOUD_PATH="${GCLOUD_PATH:-${GCLOUD_PARENT_PATH}/google-cloud-sdk}"
		if [[ -x "${GCLOUD_PATH}" ]]; then
			echo "gcloud already downloaded - skipping..."
			exit 0
		fi
		wget -P "${GCLOUD_PARENT_PATH}/" \
                "https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/${GCLOUD_ARCHIVE}"
		pushd "${GCLOUD_PARENT_PATH}/" || exit
		tar xvf "${GCLOUD_ARCHIVE}"
		rm -vf -- "${GCLOUD_ARCHIVE}"
		echo "Running the installer"
		"${GCLOUD_PATH}/install.sh"
		popd || exit
		;;

	delete-all-apps)
		kubectl delete pods,deployments,services,persistentvolumeclaims,secrets,replicationcontrollers --namespace=cloudpipelines-test --all
		kubectl delete pods,deployments,services,persistentvolumeclaims,secrets,replicationcontrollers --namespace=cloudpipelines-stage --all
		kubectl delete pods,deployments,services,persistentvolumeclaims,secrets,replicationcontrollers --namespace=cloudpipelines-prod --all
		;;

	delete-all-test-apps)
		kubectl delete pods,deployments,services,persistentvolumeclaims,secrets,replicationcontrollers --namespace=cloudpipelines-test --all
		;;

	delete-all-stage-apps)
		kubectl delete pods,deployments,services,persistentvolumeclaims,secrets,replicationcontrollers --namespace=cloudpipelines-stage --all
		;;

	delete-all-prod-apps)
		kubectl delete pods,deployments,services,persistentvolumeclaims,secrets,replicationcontrollers --namespace=cloudpipelines-prod --all
		;;

	setup-namespaces)
		fetchAndSourceScripts
		mkdir -p build
		createNamespace "cloudpipelines-test"
		createNamespace "cloudpipelines-stage"
		createNamespace "cloudpipelines-prod"
		;;

	setup-prod-infra)
		fetchAndSourceScripts
		copyK8sYamls
		deployService "github-rabbitmq" "rabbitmq" "cloudpipelines/github-analytics-stub-runner-boot-classpath-stubs:latest"
		deployService "github-eureka" "eureka" "cloudpipelines/github-eureka:latest"
		export MYSQL_USER
		MYSQL_USER=username
		export MYSQL_PASSWORD
		MYSQL_PASSWORD=password
		export MYSQL_ROOT_PASSWORD
		MYSQL_ROOT_PASSWORD=rootpassword
		deployService "mysql-github-analytics" "mysql"
		;;

	setup-tools-infra-vsphere)
		export CLOUD_TYPE=vpshere
		# shellcheck disable=SC2119
		createArtifactory
		# shellcheck disable=SC2119
		createJenkins
		;;

	setup-tools-infra-gce)
		export CLOUD_TYPE=gce
		# shellcheck disable=SC2119
		createArtifactory
		# shellcheck disable=SC2119
		createJenkins
		;;

	*)
		usage
		;;
esac
