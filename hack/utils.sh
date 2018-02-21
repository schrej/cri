#!/bin/bash

# Copyright 2017 The Kubernetes Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"/..

# Not from vendor.conf.
CRITOOL_VERSION=8ec2cbda446377cab11a5ef8ef92e115aa628a91
CRITOOL_REPO=github.com/kubernetes-incubator/cri-tools

# upload_logs_to_gcs uploads test logs to gcs.
# Var set:
# 1. Bucket: gcs bucket to upload logs.
# 2. Dir: directory name to upload logs.
# 3. Test Result: directory of the test result.
upload_logs_to_gcs() {
  local -r bucket=$1
  local -r dir=$2
  local -r result=$3
  if ! gsutil ls "gs://${bucket}" > /dev/null; then
    create_ttl_bucket ${bucket}
  fi
  local -r upload_log_path=${bucket}/${dir}
  gsutil cp -r "${result}" "gs://${upload_log_path}"
  echo "Test logs are uploaed to:
    http://gcsweb.k8s.io/gcs/${upload_log_path}/"
}

# create_ttl_bucket create a public bucket in which all objects
# have a default TTL (30 days).
# Var set:
# 1. Bucket: gcs bucket name.
create_ttl_bucket() {
  local -r bucket=$1
  gsutil mb "gs://${bucket}"
  local -r bucket_rule=$(mktemp)
  # Set 30 day TTL for logs inside the bucket.
  echo '{"rule": [{"action": {"type": "Delete"},"condition": {"age": 30}}]}' > ${bucket_rule}
  gsutil lifecycle set "${bucket_rule}" "gs://${bucket}"
  rm "${bucket_rule}"

  gsutil -m acl ch -g all:R "gs://${bucket}"
  gsutil defacl set public-read "gs://${bucket}"
}

# sha256 generates a sha256 checksum for a file.
# Var set:
# 1. Filename.
sha256() {
  if which sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{ print $1 }'
  else
    shasum -a256 "$1" | awk '{ print $1 }'
  fi
}

# Takes a prefix ($what) and a $repo and sets `$what_VERSION` and
# `$what_REPO` from vendor.conf, where `$what_REPO` defaults to $repo
# but is overridden by the 3rd field of vendor.conf.
from-vendor() {
    local what=$1
    local repo=$2
    local vendor=$(dirname "${BASH_SOURCE[0]}")/../vendor.conf
    setvars=$(awk -v REPO=$repo -v WHAT=$what -- '
                  BEGIN { rc=1 }                        # Assume we did not find what we were looking for.
                  // {
                     if ($1 == REPO) {
                        if ($3 != "") { REPO = $3 };    # Override repo.
                        printf("%s_VERSION=%s; %s_REPO=%s\n", WHAT, $2, WHAT, REPO);
                        rc=0;                           # Note success for use in END block.
                        exit                            # No point looking further.
                     }
                 }
                 END { exit rc }                        # Exit with the desired code.
                 ' $vendor)
    if [ $? -ne 0 ] ; then
        echo "failed to get version of $repo from $vendor" >&2
        exit 1
    fi
    eval $setvars
}

from-vendor RUNC       github.com/opencontainers/runc
from-vendor CNI        github.com/containernetworking/plugins
from-vendor CONTAINERD github.com/containerd/containerd
from-vendor KUBERNETES k8s.io/kubernetes

# k8s.io is actually a redirect, but we do not handle the go-import
# metadata which `go get` and `vndr` etc do. Handle it manually here.
if [ x"$KUBERNETES_REPO" = "xk8s.io" ] ; then
    KUBERNETES_REPO="https://github.com/kubernetes/kubernetes"
fi
