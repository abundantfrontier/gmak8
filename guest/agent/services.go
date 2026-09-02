package main

import "encoding/json"

// ServiceListReport is GET /services. Only NodePort and LoadBalancer with a nodePort.
type ServiceListReport struct {
	Items []Service `json:"items"`
}

type Service struct {
	Namespace string        `json:"namespace"`
	Name      string        `json:"name"`
	Type      string        `json:"type"`
	Ports     []ServicePort `json:"ports"`
}

type ServicePort struct {
	Name     string `json:"name,omitempty"`
	Port     int    `json:"port"`
	NodePort int    `json:"nodePort,omitempty"`
	Protocol string `json:"protocol,omitempty"`
}

func (h *realHost) Services() ServiceListReport {
	out, err := runK3sKubectl(h.k3sPath, h.kubeconfigPath, "get", "svc", "-A", "-o", "json")
	if err != nil {
		return ServiceListReport{Items: []Service{}}
	}
	return ServiceListReport{Items: parseServiceList(out)}
}

func parseServiceList(data []byte) []Service {
	var list struct {
		Items []struct {
			Metadata struct {
				Name      string `json:"name"`
				Namespace string `json:"namespace"`
			} `json:"metadata"`
			Spec struct {
				Type  string `json:"type"`
				Ports []struct {
					Name     string `json:"name"`
					Port     int    `json:"port"`
					NodePort int    `json:"nodePort"`
					Protocol string `json:"protocol"`
				} `json:"ports"`
			} `json:"spec"`
		} `json:"items"`
	}
	if err := json.Unmarshal(data, &list); err != nil {
		return []Service{}
	}
	items := make([]Service, 0)
	for _, item := range list.Items {
		if item.Spec.Type != "NodePort" && item.Spec.Type != "LoadBalancer" {
			continue
		}
		var ports []ServicePort
		for _, p := range item.Spec.Ports {
			if p.NodePort <= 0 {
				continue
			}
			ports = append(ports, ServicePort{
				Name:     p.Name,
				Port:     p.Port,
				NodePort: p.NodePort,
				Protocol: p.Protocol,
			})
		}
		if len(ports) == 0 {
			continue
		}
		items = append(items, Service{
			Namespace: item.Metadata.Namespace,
			Name:      item.Metadata.Name,
			Type:      item.Spec.Type,
			Ports:     ports,
		})
	}
	return items
}
