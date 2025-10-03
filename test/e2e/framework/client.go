// Copyright 2025 The Kubernetes Authors.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package framework

import (
	"context"
	"fmt"
	"testing"
	"time"

	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	apiextensionsv1 "k8s.io/apiextensions-apiserver/pkg/apis/apiextensions/v1"
	k8serrors "k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/types"
	"sigs.k8s.io/agent-sandbox/test/e2e/framework/predicates"
	"sigs.k8s.io/controller-runtime/pkg/client"
)

// ClusterClient is an abstraction layer for test cases to interact with the cluster.
type ClusterClient struct {
	*testing.T
	client client.Client
}

// CreateWithCleanup creates the specified object and cleans up the object after
// the test completes.
func (cl *ClusterClient) CreateWithCleanup(ctx context.Context, obj client.Object) error {
	cl.Helper()
	nn := types.NamespacedName{Name: obj.GetName(), Namespace: obj.GetNamespace()}
	cl.Logf("Creating object %T (%s)", obj, nn.String())
	if err := cl.client.Create(ctx, obj); err != nil {
		return fmt.Errorf("CreateWithCleanup %T (%s): %w", obj, nn.String(), err)
	}
	cl.Cleanup(func() {
		cl.Helper()
		cl.Logf("Deleting object %T (%s)", obj, nn.String())
		// Use context.Background because test context is done during cleanup
		if err := cl.client.Delete(context.Background(), obj); err != nil && !k8serrors.IsNotFound(err) {
			cl.Errorf("CreateWithCleanup %T (%s): %s", obj, nn.String(), err)
		}
	})
	return nil
}

// ValidateObject verifies the specified object exists and satisfies the provided
// predicates.
func (cl *ClusterClient) ValidateObject(ctx context.Context, obj client.Object, p ...predicates.ObjectPredicate) error {
	cl.Helper()
	nn := types.NamespacedName{Name: obj.GetName(), Namespace: obj.GetNamespace()}
	cl.Logf("ValidateObject %T (%s)", obj, nn.String())
	if err := cl.client.Get(ctx, nn, obj); err != nil {
		return fmt.Errorf("ValidateObject %T (%s): %w", obj, nn.String(), err)
	}
	for _, predicate := range p {
		if err := predicate(obj); err != nil {
			return fmt.Errorf("ValidateObject %T (%s): %w", obj, nn.String(), err)
		}
	}
	return nil
}

// WaitForObject waits for the specified object to exist and satisfy the provided
// predicates.
func (cl *ClusterClient) WaitForObject(ctx context.Context, obj client.Object, p ...predicates.ObjectPredicate) error {
	cl.Helper()
	// Static 30 second timeout, this can be adjusted if needed
	timeoutCtx, cancel := context.WithTimeout(ctx, 30*time.Second)
	defer cancel()
	var validationErr error
	for {
		select {
		case <-timeoutCtx.Done():
			return fmt.Errorf("timed out waiting for object: %w", validationErr)
		default:
			if validationErr = cl.ValidateObject(timeoutCtx, obj, p...); validationErr == nil {
				return nil
			}
			// Simple sleep for fixed duration (basic MVP)
			time.Sleep(time.Second)
		}
	}
}

// validateAgentSandboxInstallation verifies agent-sandbox system components are
// installed.
func (cl *ClusterClient) validateAgentSandboxInstallation(ctx context.Context) error {
	cl.Helper()
	// verify CRDs exist
	crds := []string{
		"sandboxes.agents.x-k8s.io",
		"sandboxclaims.extensions.agents.x-k8s.io",
		"sandboxtemplates.extensions.agents.x-k8s.io",
	}
	for _, name := range crds {
		crd := &apiextensionsv1.CustomResourceDefinition{}
		crd.Name = name
		if err := cl.ValidateObject(ctx, crd); err != nil {
			return fmt.Errorf("expected %T (%s) to exist: %w", crd, name, err)
		}
	}
	// verify agent-sandbox-system namespace exists
	ns := &corev1.Namespace{}
	ns.Name = "agent-sandbox-system"
	if err := cl.ValidateObject(ctx, ns); err != nil {
		return fmt.Errorf("expected %T (%s) to exist: %w", ns, ns.Name, err)
	}
	// verify agent-sandbox-controller exists
	ctrlNN := types.NamespacedName{
		Name:      "agent-sandbox-controller",
		Namespace: ns.Name,
	}
	ctrl := &appsv1.StatefulSet{}
	ctrl.Name = ctrlNN.Name
	ctrl.Namespace = ctrlNN.Namespace
	if err := cl.ValidateObject(ctx, ctrl); err != nil {
		return fmt.Errorf("expected %T (%s) to exist: %w", ctrl, ctrlNN.String(), err)
	}
	return nil
}
