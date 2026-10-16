package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"slices"
	"sort"
	"strings"
	"text/tabwriter"

	"k8s.io/apimachinery/pkg/api/meta"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"k8s.io/client-go/discovery"
	"k8s.io/client-go/discovery/cached/memory"
	"k8s.io/client-go/rest"
	"k8s.io/client-go/restmapper"
	"k8s.io/client-go/tools/clientcmd"
	"sigs.k8s.io/yaml"
)

type cluster struct {
	rc        rest.Interface
	disc      discovery.CachedDiscoveryInterface
	mapper    meta.RESTMapper
	namespace string
}

func clientConfig(context string) clientcmd.ClientConfig {
	return clientcmd.NewNonInteractiveDeferredLoadingClientConfig(
		clientcmd.NewDefaultClientConfigLoadingRules(),
		&clientcmd.ConfigOverrides{CurrentContext: context})
}

// newCluster is the only place an API client is built, and it always carries
// the readOnly guard.
func newCluster(cc clientcmd.ClientConfig) (*cluster, error) {
	cfg, err := cc.ClientConfig()
	if err != nil {
		return nil, err
	}
	ns, _, err := cc.Namespace()
	if err != nil {
		return nil, err
	}
	cfg.UserAgent = "k8s-readonly-mcp/" + serverVersion
	cfg.Wrap(func(rt http.RoundTripper) http.RoundTripper { return readOnly{rt} })
	dc, err := discovery.NewDiscoveryClientForConfig(cfg)
	if err != nil {
		return nil, err
	}
	disc := memory.NewMemCacheClient(dc)
	mapper := restmapper.NewShortcutExpander(restmapper.NewDeferredDiscoveryRESTMapper(disc), disc, nil)
	return &cluster{rc: dc.RESTClient(), disc: disc, mapper: mapper, namespace: ns}, nil
}

func listContexts() (string, error) {
	cfg, err := clientcmd.NewDefaultClientConfigLoadingRules().Load()
	if err != nil {
		return "", err
	}
	names := make([]string, 0, len(cfg.Contexts))
	for n := range cfg.Contexts {
		names = append(names, n)
	}
	sort.Strings(names)
	var b bytes.Buffer
	w := tabwriter.NewWriter(&b, 0, 4, 2, ' ', 0)
	fmt.Fprintln(w, "CURRENT\tNAME\tCLUSTER\tNAMESPACE")
	for _, n := range names {
		c, cur := cfg.Contexts[n], ""
		if n == cfg.CurrentContext {
			cur = "*"
		}
		fmt.Fprintf(w, "%s\t%s\t%s\t%s\n", cur, n, c.Cluster, c.Namespace)
	}
	w.Flush()
	return b.String(), nil
}

func (cl *cluster) resolve(resource string) (schema.GroupVersionResource, bool, error) {
	gvr, err := cl.mapper.ResourceFor(schema.ParseGroupResource(strings.ToLower(resource)).WithVersion(""))
	if err != nil {
		return gvr, false, err
	}
	gvk, err := cl.mapper.KindFor(gvr)
	if err != nil {
		return gvr, false, err
	}
	m, err := cl.mapper.RESTMapping(gvk.GroupKind(), gvk.Version)
	if err != nil {
		return gvr, false, err
	}
	return gvr, m.Scope.Name() == meta.RESTScopeNameNamespace, nil
}

func apiPath(gvr schema.GroupVersionResource, ns, name string) string {
	p := "/api/" + gvr.Version
	if gvr.Group != "" {
		p = "/apis/" + gvr.Group + "/" + gvr.Version
	}
	if ns != "" {
		p += "/namespaces/" + ns
	}
	p += "/" + gvr.Resource
	if name != "" {
		p += "/" + name
	}
	return p
}

func (cl *cluster) raw(ctx context.Context, path string, q url.Values, accept string) ([]byte, error) {
	req := cl.rc.Get().AbsPath(path)
	for k, v := range q {
		req.Param(k, v[0])
	}
	if accept != "" {
		req.SetHeader("Accept", accept)
	}
	return req.DoRaw(ctx)
}

func (cl *cluster) yaml(ctx context.Context, path string, q url.Values) (string, error) {
	b, err := cl.raw(ctx, path, q, "application/json")
	if err != nil {
		return "", err
	}
	var obj map[string]any
	if err := json.Unmarshal(b, &obj); err != nil {
		return "", err
	}
	dropManagedFields(obj)
	items, _ := obj["items"].([]any)
	for _, it := range items {
		if m, ok := it.(map[string]any); ok {
			dropManagedFields(m)
		}
	}
	out, err := yaml.Marshal(obj)
	if err != nil {
		return "", err
	}
	if md, _ := obj["metadata"].(map[string]any); md["continue"] != nil {
		out = append(out, "# truncated: more items exist; narrow the selector or raise limit\n"...)
	}
	return string(out), nil
}

func dropManagedFields(obj map[string]any) {
	if md, ok := obj["metadata"].(map[string]any); ok {
		delete(md, "managedFields")
	}
}

// table asks the API server for the same server-side table kubectl get prints.
func (cl *cluster) table(ctx context.Context, path string, q url.Values, withNamespace bool) (string, error) {
	q.Set("includeObject", "Metadata")
	b, err := cl.raw(ctx, path, q, "application/json;as=Table;v=v1;g=meta.k8s.io,application/json")
	if err != nil {
		return "", err
	}
	var t metav1.Table
	if err := json.Unmarshal(b, &t); err != nil || t.Kind != "Table" {
		return cl.yaml(ctx, path, q) // some aggregated APIs cannot render tables
	}
	var buf bytes.Buffer
	w := tabwriter.NewWriter(&buf, 0, 4, 2, ' ', 0)
	var cols []int
	var header []string
	if withNamespace {
		header = append(header, "NAMESPACE")
	}
	for i, c := range t.ColumnDefinitions {
		if c.Priority == 0 {
			cols = append(cols, i)
			header = append(header, strings.ToUpper(c.Name))
		}
	}
	fmt.Fprintln(w, strings.Join(header, "\t"))
	for _, r := range t.Rows {
		var cells []string
		if withNamespace {
			var m metav1.PartialObjectMetadata
			_ = json.Unmarshal(r.Object.Raw, &m)
			cells = append(cells, m.Namespace)
		}
		for _, i := range cols {
			if i < len(r.Cells) {
				cells = append(cells, fmt.Sprint(r.Cells[i]))
			}
		}
		fmt.Fprintln(w, strings.Join(cells, "\t"))
	}
	w.Flush()
	if len(t.Rows) == 0 {
		return "No resources found.\n", nil
	}
	if t.Continue != "" {
		buf.WriteString("# truncated: more items exist; narrow the selector or raise limit\n")
	}
	return buf.String(), nil
}

func (cl *cluster) apiResources() (string, error) {
	lists, err := cl.disc.ServerPreferredResources()
	if lists == nil && err != nil {
		return "", err
	}
	var b bytes.Buffer
	w := tabwriter.NewWriter(&b, 0, 4, 2, ' ', 0)
	fmt.Fprintln(w, "NAME\tSHORTNAMES\tAPIVERSION\tNAMESPACED\tKIND")
	for _, l := range lists {
		for _, r := range l.APIResources {
			if slices.Contains(r.Verbs, "list") {
				fmt.Fprintf(w, "%s\t%s\t%s\t%t\t%s\n", r.Name, strings.Join(r.ShortNames, ","), l.GroupVersion, r.Namespaced, r.Kind)
			}
		}
	}
	w.Flush()
	if err != nil {
		fmt.Fprintf(&b, "# partial: %v\n", err)
	}
	return b.String(), nil
}
