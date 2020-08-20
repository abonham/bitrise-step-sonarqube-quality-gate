#!/bin/bash
set -e
[[ "$is_debug" -eq "true" ]] && set -ux

BRANCH=${BITRISE_GIT_BRANCH-`git branch --show-current`}

if [ -d "./.scannerwork" ]
then
	pushd .scannerwork
	TASK_ID=`cat report-task.txt | grep ceTaskId | sed s/ceTaskId=//`
	popd
else
	echo -e "no scanner report"
	exit 1
fi

if [ -z "$TASK_ID" ]
then
	echo -e "no task id"
	exit 1
fi

BITRISE_DEPLOY_DIR=${BITRISE_DEPLOY_DIR:-"./.scannerwork"}
HEADER="Authorization: Basic $(echo -n "$SONAR_TOKEN:" | base64)"

counter=0
max_attempts=5
function check {
	[[ ${counter} -eq ${max_attempts} ]] && exit 1
	wget -qO "$BITRISE_DEPLOY_DIR/task_detail.json" --header "$HEADER" "https://sonarcloud.io/api/ce/task?organization=$organisation_key&id=$TASK_ID"
	if [ $(cat "$BITRISE_DEPLOY_DIR/task_detail.json" | jq '.task.status == "SUCCESS"') ]
	then
		echo "get task detail"
		ANALYSIS_ID=$(cat "$BITRISE_DEPLOY_DIR/task_detail.json" | jq .task.analysisId | sed 's/"//g')
	else
		echo "analysis in progress"
		sleep 3
		counter=$(($counter+1))
	fi
}

function getByBranch {
	BRANCH_URL="https://sonarcloud.io/api/qualitygates/project_status?projectKey=$project_key&organization=$organisation_key&branch=$BRANCH"
	echo "wget -qO- --header $HEADER $BRANCH_URL"
	wget -qO "$BITRISE_DEPLOY_DIR/quality_gate.json" --header "$HEADER" "$BRANCH_URL"
	cat ${BITRISE_DEPLOY_DIR}/quality_gate.json | jq '.projectStatus.status != "ERROR"'
}

if:IsSet() {
  [[ ${!1-x} == x ]] && return 1 || return 0
}

echo "fetch quality gate result for ${BRANCH}, store in $BITRISE_DEPLOY_DIR"

until if:IsSet ANALYSIS_ID
do
	echo "checking status - attempt $counter"
	check
done

echo "get branch status"
getByBranch