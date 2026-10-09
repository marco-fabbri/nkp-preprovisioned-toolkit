#!/usr/bin/env bash
# The Cluster UUID the summary prints must be the UID of the Cluster API cluster
# object (what the Nutanix licensing knowledge base asks for), never the UID of
# the kube-system namespace, which NKP uses for monitoring and which a licence
# issued for it is rejected with "License key is not valid for this cluster".
set -euo pipefail
cd "$(dirname "$0")/../.."
task=ansible/roles/kommander_deploy/tasks/main.yml
grep -q 'clusters.cluster.x-k8s.io' "$task" || { echo "FAIL: $task must read the Cluster UUID from clusters.cluster.x-k8s.io"; exit 1; }
if grep -n -E 'namespace[[:space:]]*$|^[[:space:]]*- kube-system[[:space:]]*$' "$task" | grep -q .; then
  echo "FAIL: $task still reads a namespace UID for the Cluster UUID"; exit 1
fi
grep -q "get cluster -o jsonpath='{.items\[0\].metadata.uid}'" README.md || { echo "FAIL: README.md must show the Cluster API command for the Cluster UUID"; exit 1; }
echo "cluster uuid source: Cluster API cluster object (task and README agree)"
