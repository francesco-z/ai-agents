// Command k8s-readonly-mcp is a stdio MCP server with read-only Kubernetes
// tools. It speaks MCP's newline-delimited JSON-RPC directly so the whole
// server stays small enough to audit; the read-only and no-secrets rules live
// in guard.go, below every tool.
package main

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"io"
	"log"
	"os"
	"slices"
	"time"
)

const serverVersion = "0.1.0"

// Newest first; an unknown client version gets the newest. Clients that open
// with server/discover get method-not-found and fall back to initialize.
var supportedProtocols = []string{"2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"}

type request struct {
	ID     json.RawMessage `json:"id,omitempty"`
	Method string          `json:"method"`
	Params json.RawMessage `json:"params,omitempty"`
}

type rpcError struct {
	Code    int    `json:"code"`
	Message string `json:"message"`
}

type response struct {
	JSONRPC string          `json:"jsonrpc"`
	ID      json.RawMessage `json:"id"`
	Result  any             `json:"result,omitempty"`
	Error   *rpcError       `json:"error,omitempty"`
}

func main() {
	log.SetPrefix("k8s-readonly-mcp: ")
	s := &server{clusters: map[string]*cluster{}}
	in := bufio.NewReader(os.Stdin)
	out := json.NewEncoder(os.Stdout)
	for {
		line, err := in.ReadBytes('\n')
		if len(bytes.TrimSpace(line)) > 0 {
			if resp := s.handle(line); resp != nil {
				if err := out.Encode(resp); err != nil {
					log.Fatal(err)
				}
			}
		}
		if err == io.EOF {
			return
		}
		if err != nil {
			log.Fatal(err)
		}
	}
}

type server struct {
	clusters map[string]*cluster
}

func (s *server) handle(line []byte) *response {
	var req request
	if err := json.Unmarshal(line, &req); err != nil {
		return &response{JSONRPC: "2.0", ID: json.RawMessage("null"), Error: &rpcError{-32700, "parse error"}}
	}
	if req.ID == nil {
		return nil // notification
	}
	result, rerr := s.dispatch(req)
	return &response{JSONRPC: "2.0", ID: req.ID, Result: result, Error: rerr}
}

func (s *server) dispatch(req request) (any, *rpcError) {
	switch req.Method {
	case "initialize":
		var p struct {
			ProtocolVersion string `json:"protocolVersion"`
		}
		_ = json.Unmarshal(req.Params, &p)
		v := supportedProtocols[0]
		if slices.Contains(supportedProtocols, p.ProtocolVersion) {
			v = p.ProtocolVersion
		}
		return map[string]any{
			"protocolVersion": v,
			"capabilities":    map[string]any{"tools": map[string]any{}},
			"serverInfo":      map[string]any{"name": "k8s-readonly", "version": serverVersion},
			"instructions": "Read-only Kubernetes access over the local kubeconfig. Start with list_contexts; " +
				"pass context explicitly. Writes, exec/attach/port-forward/proxy and Secrets are refused.",
		}, nil
	case "ping":
		return map[string]any{}, nil
	case "tools/list":
		return map[string]any{"tools": toolDefs}, nil
	case "tools/call":
		var p struct {
			Name      string          `json:"name"`
			Arguments json.RawMessage `json:"arguments"`
		}
		if err := json.Unmarshal(req.Params, &p); err != nil {
			return nil, &rpcError{-32602, "invalid params"}
		}
		ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
		defer cancel()
		text, err := s.call(ctx, p.Name, p.Arguments)
		if err != nil {
			text = err.Error()
		}
		return map[string]any{
			"content": []map[string]any{{"type": "text", "text": text}},
			"isError": err != nil,
		}, nil
	default:
		return nil, &rpcError{-32601, "method not found: " + req.Method}
	}
}
