/*
Copyright 2025 The Kubernetes Authors.

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

package e2e

import (
	"context"
	"testing"
	"time"

	"github.com/kubernetes-sigs/agent-sandbox/test/e2e/framework"
	"k8s.io/apiextensions-apiserver/pkg/client/clientset/clientset"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

func TestControllerWithExtensions(t *testing.T) {
	f := framework.New(t)
	cs, err := clientset.NewForConfig(f.Client.Config())
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()

	_, err = cs.ApiextensionsV1().CustomResourceDefinitions().Get(ctx, "sandboxclaims.extensions.agents.x-k8s.io", metav1.GetOptions{})
	if err != nil {
		t.Errorf("want sandboxclaims crd, got: %v", err)
	}
	_, err = cs.ApiextensionsV1().CustomResourceDefinitions().Get(ctx, "sandboxtemplates.extensions.agents.x-k8s.io", metav1.GetOptions{})
	if err != nil {
		t.Errorf("want sandboxtemplates crd, got: %v", err)
	}
	_, err = cs.ApiextensionsV1().CustomResourceDefinitions().Get(ctx, "sandboxwarmpools.extensions.agents.x-k8s.io", metav1.GetOptions{})
	if err != nil {
		t.Errorf("want sandboxwarmpools crd, got: %v", err)
	}
}
