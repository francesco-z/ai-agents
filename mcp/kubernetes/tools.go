package main

import (
	"context"
	"encoding/json"
	"fmt"
	"net/url"
	"strconv"
	"strings"
)

func prop(typ, desc string) map[string]any { return map[string]any{"type": typ, "description": desc} }

func inputSchema(required []string, props map[string]any) map[string]any {
	s := map[string]any{"type": "object", "properties": props}
	if len(required) > 0 {
		s["required"] = required
	}
	return s
}

var (
	readOnlyHint = map[string]any{"readOnlyHint": true}
	contextProp  = prop("string", "kubeconfig context; empty means current-context")
)

var toolDefs = []map[string]any{
	{
		"name":        "list_contexts",
		"description": "List kubeconfig contexts with their cluster and default namespace (* marks current-context).",
		"inputSchema": inputSchema(nil, map[string]any{}),
		"annotations": readOnlyHint,
	},
	{
		"name":        "api_resources",
		"description": "Like `kubectl api-resources`: listable resource types in the cluster.",
		"inputSchema": inputSchema(nil, map[string]any{"context": contextProp}),
		"annotations": readOnlyHint,
	},
	{
		"name": "get",
		"description": "Like `kubectl get`. Without name: a table (same columns as kubectl). With name or output=yaml: YAML " +
			"without managedFields. Secrets are refused.",
		"inputSchema": inputSchema([]string{"resource"}, map[string]any{
			"context":        contextProp,
			"resource":       prop("string", "resource type: plural, singular, short name or resource.group (pods, deploy, ingresses.networking.k8s.io)"),
			"name":           prop("string", "object name; empty lists"),
			"namespace":      prop("string", "namespace; empty means the context's default"),
			"all_namespaces": prop("boolean", "list across all namespaces"),
			"label_selector": prop("string", "e.g. app=web,tier!=db"),
			"field_selector": prop("string", "e.g. status.phase=Running"),
			"output":         map[string]any{"type": "string", "enum": []string{"table", "yaml"}, "description": "default: table for lists, yaml for one object"},
			"limit":          prop("integer", "max items in a list (default 200)"),
		}),
		"annotations": readOnlyHint,
	},
	{
		"name":        "logs",
		"description": "Like `kubectl logs`: container logs of one pod (capped at 256 KiB).",
		"inputSchema": inputSchema([]string{"pod"}, map[string]any{
			"context":       contextProp,
			"namespace":     prop("string", "namespace; empty means the context's default"),
			"pod":           prop("string", "pod name"),
			"container":     prop("string", "container; required if the pod has several"),
			"tail_lines":    prop("integer", "last N lines (default 200)"),
			"since_seconds": prop("integer", "only logs newer than this"),
			"previous":      prop("boolean", "logs of the previous, terminated container"),
		}),
		"annotations": readOnlyHint,
	},
}

func (s *server) cluster(name string) (*cluster, error) {
	if cl, ok := s.clusters[name]; ok {
		return cl, nil
	}
	cl, err := newCluster(clientConfig(name))
	if err != nil {
		return nil, err
	}
	s.clusters[name] = cl
	return cl, nil
}

func (s *server) call(ctx context.Context, name string, raw json.RawMessage) (string, error) {
	var a struct {
		Context       string `json:"context"`
		Resource      string `json:"resource"`
		Name          string `json:"name"`
		Namespace     string `json:"namespace"`
		AllNamespaces bool   `json:"all_namespaces"`
		LabelSelector string `json:"label_selector"`
		FieldSelector string `json:"field_selector"`
		Output        string `json:"output"`
		Limit         int    `json:"limit"`
		Pod           string `json:"pod"`
		Container     string `json:"container"`
		TailLines     int    `json:"tail_lines"`
		SinceSeconds  int    `json:"since_seconds"`
		Previous      bool   `json:"previous"`
	}
	if len(raw) > 0 {
		if err := json.Unmarshal(raw, &a); err != nil {
			return "", fmt.Errorf("invalid arguments: %w", err)
		}
	}
	for _, v := range []string{a.Name, a.Namespace, a.Pod, a.Container} {
		if strings.Contains(v, "/") {
			return "", fmt.Errorf("invalid name %q", v)
		}
	}

	if name == "list_contexts" {
		return listContexts()
	}
	cl, err := s.cluster(a.Context)
	if err != nil {
		return "", err
	}
	ns := a.Namespace
	if ns == "" {
		ns = cl.namespace
	}

	switch name {
	case "api_resources":
		return cl.apiResources()
	case "get":
		gvr, namespaced, err := cl.resolve(a.Resource)
		if err != nil {
			return "", err
		}
		if !namespaced || a.AllNamespaces {
			ns = ""
		}
		p := apiPath(gvr, ns, a.Name)
		if a.Name != "" || a.Output == "yaml" {
			q := url.Values{}
			if a.Name == "" {
				q = listQuery(a.LabelSelector, a.FieldSelector, a.Limit)
			}
			return cl.yaml(ctx, p, q)
		}
		return cl.table(ctx, p, listQuery(a.LabelSelector, a.FieldSelector, a.Limit), namespaced && ns == "")
	case "logs":
		if a.TailLines == 0 {
			a.TailLines = 200
		}
		q := url.Values{"tailLines": {strconv.Itoa(a.TailLines)}, "limitBytes": {strconv.Itoa(256 << 10)}}
		if a.Container != "" {
			q.Set("container", a.Container)
		}
		if a.SinceSeconds > 0 {
			q.Set("sinceSeconds", strconv.Itoa(a.SinceSeconds))
		}
		if a.Previous {
			q.Set("previous", "true")
		}
		b, err := cl.raw(ctx, "/api/v1/namespaces/"+ns+"/pods/"+a.Pod+"/log", q, "")
		return string(b), err
	}
	return "", fmt.Errorf("unknown tool %q", name)
}

func listQuery(labels, fields string, limit int) url.Values {
	if limit <= 0 {
		limit = 200
	}
	q := url.Values{"limit": {strconv.Itoa(limit)}}
	if labels != "" {
		q.Set("labelSelector", labels)
	}
	if fields != "" {
		q.Set("fieldSelector", fields)
	}
	return q
}
