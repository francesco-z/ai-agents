package main

import (
	"context"
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"

	"k8s.io/client-go/tools/clientcmd"
	clientcmdapi "k8s.io/client-go/tools/clientcmd/api"
)

func TestCheckRequest(t *testing.T) {
	cases := []struct {
		method, url string
		allow       bool
	}{
		{"GET", "/version", true},
		{"GET", "/api", true},
		{"GET", "/api/v1", true},
		{"GET", "/apis", true},
		{"GET", "/apis/apps/v1", true},
		{"GET", "/api/v1/namespaces", true},
		{"GET", "/api/v1/namespaces/secrets", true}, // a namespace named "secrets"
		{"GET", "/api/v1/namespaces/default/pods", true},
		{"GET", "/api/v1/namespaces/default/pods/web-0", true},
		{"GET", "/api/v1/namespaces/default/pods/web-0/log?tailLines=10", true},
		{"GET", "/api/v1/namespaces/default/configmaps/proxy", true},
		{"GET", "/apis/apps/v1/namespaces/default/deployments", true},
		{"GET", "/api/v1/watch/namespaces/default/pods", true},

		{"POST", "/api/v1/namespaces/default/pods", false},
		{"PUT", "/api/v1/namespaces/default/pods/web-0", false},
		{"PATCH", "/apis/apps/v1/namespaces/default/deployments/web", false},
		{"DELETE", "/api/v1/namespaces/default/pods/web-0", false},
		{"HEAD", "/api/v1/namespaces/default/pods", false},
		{"GET", "/api/v1/secrets", false},
		{"GET", "/api/v1/namespaces/default/secrets", false},
		{"GET", "/api/v1/namespaces/default/secrets/db", false},
		{"GET", "/api/v1/watch/secrets", false},
		{"GET", "/api/v1/watch/namespaces/default/secrets", false},
		{"GET", "/api/v1/namespaces/default/pods/web-0/exec?command=sh", false},
		{"GET", "/api/v1/namespaces/default/pods/web-0/attach", false},
		{"GET", "/api/v1/namespaces/default/pods/web-0/portforward", false},
		{"GET", "/api/v1/namespaces/default/services/web/proxy/admin", false},
		{"GET", "/api/v1/nodes/node-1/proxy/logs/", false},
		{"GET", "/api/v1/proxy/namespaces/default/services/web", false},
		{"GET", "/api/v1/namespaces/default/pods/../secrets", false},
		{"GET", "/api/v1/namespaces/default/pods%2F..%2Fsecrets", false},
		{"GET", "/api/v1//secrets", false},
		{"GET", "/logs/", false},
		{"GET", "/metrics", false},
		{"GET", "/", false},
	}
	for _, c := range cases {
		req := httptest.NewRequest(c.method, "http://cluster"+c.url, nil)
		if err := checkRequest(req); (err == nil) != c.allow {
			t.Errorf("%s %s: allow=%v, got err=%v", c.method, c.url, c.allow, err)
		}
	}

	up := httptest.NewRequest("GET", "http://cluster/api/v1/namespaces/default/pods", nil)
	up.Header.Set("Connection", "Upgrade")
	up.Header.Set("Upgrade", "websocket")
	if checkRequest(up) == nil {
		t.Error("upgrade request allowed")
	}
}

// The guard must sit on the client newCluster builds: denied requests never
// reach the API server.
func TestClusterClientIsGuarded(t *testing.T) {
	var hits atomic.Int32
	api := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		hits.Add(1)
		w.Write([]byte(`{}`))
	}))
	defer api.Close()

	cfg := clientcmdapi.NewConfig()
	cfg.Clusters["c"] = &clientcmdapi.Cluster{Server: api.URL}
	cfg.AuthInfos["u"] = &clientcmdapi.AuthInfo{Token: "t"}
	cfg.Contexts["ctx"] = &clientcmdapi.Context{Cluster: "c", AuthInfo: "u"}
	cl, err := newCluster(clientcmd.NewNonInteractiveClientConfig(*cfg, "ctx", &clientcmd.ConfigOverrides{}, nil))
	if err != nil {
		t.Fatal(err)
	}
	ctx := context.Background()

	if _, err := cl.raw(ctx, "/api/v1/namespaces/default/secrets", nil, ""); err == nil {
		t.Error("secrets read allowed")
	}
	if _, err := cl.rc.Post().AbsPath("/api/v1/namespaces/default/pods").Body([]byte(`{}`)).DoRaw(ctx); err == nil {
		t.Error("POST allowed")
	}
	if _, err := cl.rc.Delete().AbsPath("/api/v1/namespaces/default/pods/web-0").DoRaw(ctx); err == nil {
		t.Error("DELETE allowed")
	}
	if n := hits.Load(); n != 0 {
		t.Fatalf("%d denied requests reached the API server", n)
	}
	if _, err := cl.raw(ctx, "/api/v1/namespaces/default/pods", nil, ""); err != nil {
		t.Fatalf("pod list denied: %v", err)
	}
	if hits.Load() != 1 {
		t.Fatal("allowed request did not reach the API server")
	}
}
