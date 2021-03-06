#!/bin/bash
set -e
[[ "$is_debug" -eq "true" ]] && set -x

BRANCH=${BITRISE_GIT_BRANCH-`git branch --show-current`}

if [ -d "./.scannerwork" ]
then
	pushd .scannerwork
	TASK_ID=`cat report-task.txt | grep ceTaskId | sed s/ceTaskId=//`
	popd
else
	echo -e "no scanner report"
	if [ "$fail_on_missing_task" -eq "true" ]
	then
	  exit 1
	else
	  exit 0
	fi
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
analysis_ready=false
function check {
	until [[ $counter -eq 5 ]]
	do
		echo "checking status - attempt $counter"
		wget -qO "$BITRISE_DEPLOY_DIR/task_detail.json" --header "$HEADER" "https://sonarcloud.io/api/ce/task?organization=$organisation_key&id=$TASK_ID"
		if [[ $(cat "$BITRISE_DEPLOY_DIR/task_detail.json" | jq -e '.task.status == "SUCCESS"') == "true" ]]
		then
			echo "get task detail"
			ANALYSIS_ID=$(cat "$BITRISE_DEPLOY_DIR/task_detail.json" | jq -e .task.analysisId | sed 's/"//g')
			analysis_ready=true
			break
		else
			echo "analysis in progress"
			sleep 3
			counter=$(($counter+1))
		fi
	done
}

function printPRUrl {
	if [[ ! -z "$$BITRISE_PULL_REQUEST" ]]; then
		echo "https://sonarcloud.io/dashboard?id=$project_key&pullRequest=$BITRISE_PULL_REQUEST"
	fi
}

function getByBranch {
	if [[ ! -z $BITRISE_PULL_REQUEST ]]; then
	BRANCH_URL="https://sonarcloud.io/api/qualitygates/project_status?projectKey=$project_key&organization=$organisation_key&id=$BITRISE_PULL_REQUEST"
	else
	BRANCH_URL="https://sonarcloud.io/api/qualitygates/project_status?projectKey=$project_key&organization=$organisation_key&branch=$BRANCH"
	fi
	
	echo "wget -qO- --header '$HEADER' '$BRANCH_URL'"
	wget -qO "$BITRISE_DEPLOY_DIR/quality_gate.json" --header "$HEADER" "$BRANCH_URL"
	cat ${BITRISE_DEPLOY_DIR}/quality_gate.json | jq -e '.projectStatus.status != "ERROR"'
	if [ $? -eq 0 ]
	then
	  echo "Quality gate PASSED"
	  printPRUrl
	else
	  echo "Quality gate FAILED"
	  echo $(jq . "$BITRISE_DEPLOY_DIR/quality_gate.json")
	  printPRUrl
	  exit 1
	fi
}

echo "fetch quality gate result for $BRANCH, store in $BITRISE_DEPLOY_DIR"
	
check

if [[ $analysis_ready ]]; then
	echo "get branch status"
	getByBranch
else
	echo "Quality gate did not respond in time"
	exit 1
fi

