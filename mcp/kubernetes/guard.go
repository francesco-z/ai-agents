package main

import (
	"fmt"
	"net/http"
	"path"
	"strings"
)

// readOnly wraps the transport of the only API client this server builds (see
// newCluster), so every request to any cluster passes through checkRequest.
// The tools are a convenience; this is the boundary.
type readOnly struct{ next http.RoundTripper }

func (t readOnly) RoundTrip(req *http.Request) (*http.Response, error) {
	if err := checkRequest(req); err != nil {
		return nil, err
	}
	return t.next.RoundTrip(req)
}

// Subresources that execute or tunnel instead of reading; some accept GET.
var blockedSubresources = map[string]bool{"exec": true, "attach": true, "portforward": true, "proxy": true}

func checkRequest(req *http.Request) error {
	deny := func(why string) error {
		return fmt.Errorf("read-only guard: %s %s denied: %s", req.Method, req.URL.Path, why)
	}
	if req.Method != http.MethodGet {
		return deny("only GET is allowed")
	}
	if req.Header.Get("Upgrade") != "" || strings.Contains(strings.ToLower(req.Header.Get("Connection")), "upgrade") {
		return deny("connection upgrades are not allowed")
	}
	p := req.URL.Path
	// Escaped or non-canonical paths could be read differently by the API server.
	if req.URL.RawPath != "" || path.Clean(p) != p {
		return deny("path must be plain and canonical")
	}

	segs := strings.Split(strings.TrimPrefix(p, "/"), "/")
	var rest []string
	switch {
	case p == "/version":
		return nil
	case segs[0] == "api" && len(segs) >= 2: // /api/v1/...
		rest = segs[2:]
	case segs[0] == "apis" && len(segs) >= 3: // /apis/<group>/<version>/...
		rest = segs[3:]
	case segs[0] == "api" || segs[0] == "apis": // discovery
		return nil
	default:
		return deny("not an API resource path")
	}
	if len(rest) > 0 && rest[0] == "watch" {
		rest = rest[1:]
	}
	if len(rest) >= 3 && rest[0] == "namespaces" {
		rest = rest[2:]
	}
	switch {
	case len(rest) == 0:
		return nil
	case rest[0] == "secrets":
		return deny("secrets are never read")
	case rest[0] == "proxy":
		return deny("proxying is not a read")
	case len(rest) >= 3 && blockedSubresources[rest[2]]:
		return deny("subresource " + rest[2] + " is not a read")
	}
	return nil
}
