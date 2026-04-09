#!/usr/bin/env python3
# tools/k8s-generator.py
#
# Reads docker-compose.yml from the repository root and writes one YAML file
# per service into the k8s/ directory.  Each file contains a Deployment and,
# when the service exposes ports, a ClusterIP Service separated by "---".
#
# Usage:
#   pip install pyyaml
#   python3 tools/k8s-generator.py

import os
import sys

import yaml

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
COMPOSE_PATH = os.path.join(REPO_ROOT, "docker-compose.yml")
OUTPUT_DIR = os.path.join(REPO_ROOT, "k8s")


def _container_port(port_spec: str | int) -> int:
    """Return the container-side port from a docker-compose port mapping.

    Handles both "host:container" and bare "container" forms.
    """
    s = str(port_spec)
    # strip protocol suffix (e.g. "8080:8080/tcp")
    s = s.split("/")[0]
    if ":" in s:
        return int(s.rsplit(":", 1)[-1])
    return int(s)


def _resolve_image(service_name: str, service: dict) -> str:
    """Return the image reference to embed in the pod spec.

    Services with a build directive have no registry image defined in
    docker-compose.yml; fall back to <service-name>:latest as a placeholder
    that a CI pipeline would replace with an actual registry URI.
    """
    return service.get("image") or f"{service_name}:latest"


def _build_env_list(service: dict) -> list[dict]:
    """Convert docker-compose environment block to a K8s env list."""
    env_raw = service.get("environment", {})
    if isinstance(env_raw, dict):
        return [{"name": k, "value": str(v)} for k, v in env_raw.items()]
    # list form: ["KEY=VALUE", ...]
    result = []
    for entry in env_raw:
        k, _, v = str(entry).partition("=")
        result.append({"name": k, "value": v})
    return result


def build_deployment(service_name: str, service: dict) -> dict:
    """Return a K8s Deployment manifest dict for one docker-compose service."""
    image = _resolve_image(service_name, service)

    ports_raw = service.get("ports", [])
    container_ports = [_container_port(p) for p in ports_raw]

    env_list = _build_env_list(service)

    container_spec: dict = {
        "name": service_name,
        "image": image,
    }
    if container_ports:
        container_spec["ports"] = [{"containerPort": p} for p in container_ports]
    if env_list:
        container_spec["env"] = env_list

    return {
        "apiVersion": "apps/v1",
        "kind": "Deployment",
        "metadata": {
            "name": service_name,
            "labels": {"app": service_name},
        },
        "spec": {
            "replicas": 1,
            "selector": {
                "matchLabels": {"app": service_name},
            },
            "template": {
                "metadata": {
                    # app label is required for Istio sidecar injection selector
                    "labels": {"app": service_name},
                },
                "spec": {
                    "containers": [container_spec],
                },
            },
        },
    }


def build_service(service_name: str, service: dict) -> dict | None:
    """Return a K8s Service manifest dict, or None if no ports are exposed."""
    ports_raw = service.get("ports", [])
    if not ports_raw:
        return None

    svc_ports = []
    for p in ports_raw:
        cport = _container_port(p)
        svc_ports.append(
            {
                "name": f"port-{cport}",
                "port": cport,
                "targetPort": cport,
                "protocol": "TCP",
            }
        )

    return {
        "apiVersion": "v1",
        "kind": "Service",
        "metadata": {
            "name": service_name,
            "labels": {"app": service_name},
        },
        "spec": {
            "selector": {"app": service_name},
            "ports": svc_ports,
            "type": "ClusterIP",
        },
    }


def main() -> None:
    with open(COMPOSE_PATH, encoding="utf-8") as fh:
        compose = yaml.safe_load(fh)

    services: dict = compose.get("services", {})
    if not services:
        print("No services found in docker-compose.yml", file=sys.stderr)
        sys.exit(1)

    os.makedirs(OUTPUT_DIR, exist_ok=True)

    generated = 0
    for service_name, service in services.items():
        deployment = build_deployment(service_name, service)
        svc = build_service(service_name, service)

        docs = [deployment]
        if svc is not None:
            docs.append(svc)

        output_path = os.path.join(OUTPUT_DIR, f"{service_name}.yaml")
        with open(output_path, "w", encoding="utf-8") as fh:
            yaml.dump_all(
                docs,
                fh,
                default_flow_style=False,
                allow_unicode=True,
                sort_keys=False,
            )
        print(f"  wrote {output_path}")
        generated += 1

    print(f"\n{generated} manifest(s) written to {OUTPUT_DIR}/")


if __name__ == "__main__":
    main()
