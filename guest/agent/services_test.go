package main

import "testing"

func TestParseServiceListFiltersNodePortAndLoadBalancer(t *testing.T) {
	body := []byte(`{
		"items": [
			{
				"metadata": {"name": "kubernetes", "namespace": "default"},
				"spec": {"type": "ClusterIP", "ports": [{"port": 443, "protocol": "TCP"}]}
			},
			{
				"metadata": {"name": "nginx", "namespace": "default"},
				"spec": {
					"type": "NodePort",
					"ports": [
						{"name": "http", "port": 80, "nodePort": 30080, "protocol": "TCP"},
						{"name": "metrics", "port": 9113, "protocol": "TCP"}
					]
				}
			},
			{
				"metadata": {"name": "traefik", "namespace": "kube-system"},
				"spec": {
					"type": "LoadBalancer",
					"ports": [
						{"name": "web", "port": 80, "nodePort": 30779, "protocol": "TCP"},
						{"name": "websecure", "port": 443, "nodePort": 31204, "protocol": "TCP"}
					]
				}
			},
			{
				"metadata": {"name": "dns", "namespace": "kube-system"},
				"spec": {
					"type": "NodePort",
					"ports": [{"port": 53, "nodePort": 30053, "protocol": "UDP"}]
				}
			}
		]
	}`)
	got, err := parseServiceList(body)
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 3 {
		t.Fatalf("len %d: %+v", len(got), got)
	}
	if got[0].Name != "nginx" || got[0].Type != "NodePort" || len(got[0].Ports) != 1 || got[0].Ports[0].NodePort != 30080 {
		t.Fatalf("nginx %+v", got[0])
	}
	if got[1].Name != "traefik" || got[1].Type != "LoadBalancer" || len(got[1].Ports) != 2 {
		t.Fatalf("traefik %+v", got[1])
	}
	if got[2].Name != "dns" || got[2].Ports[0].Protocol != "UDP" || got[2].Ports[0].NodePort != 30053 {
		t.Fatalf("dns %+v", got[2])
	}
}

func TestParseServiceListEmptyAndInvalid(t *testing.T) {
	got, err := parseServiceList([]byte(`{"items":[]}`))
	if err != nil || len(got) != 0 {
		t.Fatalf("empty %+v err %v", got, err)
	}
	if _, err := parseServiceList([]byte(`not-json`)); err == nil {
		t.Fatal("expected invalid JSON error")
	}
	if _, err := parseServiceList(nil); err == nil {
		t.Fatal("expected nil body error")
	}
}
