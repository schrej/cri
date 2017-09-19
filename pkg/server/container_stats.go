/*
Copyright 2017 The Kubernetes Authors.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package server

import (
	"fmt"

	tasks "github.com/containerd/containerd/api/services/tasks/v1"
	"golang.org/x/net/context"
	"k8s.io/kubernetes/pkg/kubelet/apis/cri/v1alpha1/runtime"
)

// ContainerStats returns stats of the container. If the container does not
// exist, the call returns an error.
func (c *criContainerdService) ContainerStats(ctx context.Context, in *runtime.ContainerStatsRequest) (*runtime.ContainerStatsResponse, error) {
	// Validate the stats request
	if in.GetContainerId() == "" {
		return nil, fmt.Errorf("invalid container stats request")
	}
	containerID := in.GetContainerId()
	_, err := c.containerStore.Get(containerID)
	if err != nil {
		return nil, fmt.Errorf("failed to find container %q: %v", containerID, err)
	}
	request := &tasks.MetricsRequest{Filters: []string{"id==" + containerID}}
	resp, err := c.taskService.Metrics(ctx, request)
	if err != nil {
		return nil, fmt.Errorf("failed to fetch metrics for tasks: %v", err)
	}

	var cs runtime.ContainerStats
	if err := c.getContainerMetrics(containerID, resp.Metrics[0], &cs); err != nil {
		return nil, fmt.Errorf("failed to decode container metrics: %v", err)
	}
	return &runtime.ContainerStatsResponse{Stats: &cs}, nil
}
