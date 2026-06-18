# Lab 1 — RBAC + Gatekeeper (W10)

> GitOps-only: mọi thứ qua ArgoCD — không `kubectl apply` tay.
> Repo: https://github.com/hunghk43/temp-w10

---

## Cấu trúc repo

```
.
├── rbac/
│   ├── roles.yaml            # Role (alice) + ClusterRole (bob, carol)
│   └── rolebindings.yaml     # 3 binding gán user vào role
├── gatekeeper/
│   ├── templates/            # 5 ConstraintTemplate (Rego)
│   │   ├── no-latest-tag.yaml
│   │   ├── required-resources.yaml
│   │   ├── no-root-user.yaml
│   │   ├── no-host-network.yaml
│   │   └── allowed-registry.yaml   # Lab 1.3 custom policy
│   ├── constraints/          # 5 Constraint tương ứng
│   │   ├── no-latest-tag.yaml
│   │   ├── required-resources.yaml
│   │   ├── no-root-user.yaml
│   │   ├── no-host-network.yaml
│   │   └── allowed-registry.yaml
│   ├── test-violations.yaml  # 5 Pod vi phạm → expect REJECT
│   └── test-valid.yaml       # 1 Pod hợp lệ → expect PASS
├── argocd/
│   ├── root.yaml             # App-of-Apps
│   └── apps/
│       ├── rbac.yaml
│       ├── gatekeeper-controller.yaml   # sync-wave: 0
│       ├── gatekeeper-templates.yaml    # sync-wave: 1
│       └── gatekeeper-constraints.yaml  # sync-wave: 2
└── img/                      # Evidence screenshots
```

---

## Lab 1.1 — RBAC

### Thiết kế phân quyền

| User  | Kind        | Role/ClusterRole | Scope      | Quyền                                    |
|-------|-------------|------------------|------------|------------------------------------------|
| alice | User        | developer (Role) | ns `demo`  | CRUD deploy/pod/service/rollout          |
| bob   | User        | sre (ClusterRole)| cluster    | get/list/watch tất cả + delete pod + scale |
| carol | User        | viewer (ClusterRole) | cluster | get/list/watch only                    |

- alice → `Role` (namespace-scoped) vì chỉ làm việc trong `demo`
- bob/carol → `ClusterRole` vì cần quyền toàn cụm
- carol không có create/delete/update bất kỳ resource nào

### Files

- `rbac/roles.yaml` — định nghĩa 3 role
- `rbac/rolebindings.yaml` — gán alice/bob/carol
- `argocd/apps/rbac.yaml` — ArgoCD App sync-wave: 0

### Nghiệm thu Lab 1.1

Chạy 4 lệnh sau sau khi ArgoCD sync:

```bash
# 1. alice tạo deploy trong ns demo → YES
kubectl auth can-i create deploy -n demo --as alice

# 2. alice tạo deploy trong ns kube-system → NO
kubectl auth can-i create deploy -n kube-system --as alice

# 3. bob xem pods toàn cụm → YES
kubectl auth can-i get pods -A --as bob

# 4. carol xóa node → NO
kubectl auth can-i delete nodes --as carol
```

| Lệnh | Kỳ vọng |
|------|---------|
| `can-i create deploy -n demo --as alice` | yes |
| `can-i create deploy -n kube-system --as alice` | no |
| `can-i get pods -A --as bob` | yes |
| `can-i delete nodes --as carol` | no |

Evidence: `img/lab1.1-rbac-auth-can-i.png`

---

## Lab 1.2 — Gatekeeper

### 4 luật enforcement (namespace `demo`)

| # | Rule | ConstraintTemplate | Risk |
|---|------|--------------------|------|
| 1 | Cấm image tag `:latest` | `K8sNoLatestTag` | F-01 |
| 2 | Bắt buộc `resources.limits` (cpu + memory) | `K8sRequiredResources` | F-02 |
| 3 | Cấm `runAsUser: 0` (root) | `K8sNoRootUser` | F-04 |
| 4 | Cấm `hostNetwork: true` | `K8sNoHostNetwork` | — |

### Thứ tự deploy (sync-wave)

```
wave 0 → gatekeeper-controller   (helm chart install)
wave 1 → gatekeeper-templates    (ConstraintTemplate CRDs)
wave 2 → gatekeeper-constraints  (Constraint objects)
```

### Nghiệm thu Lab 1.2

```bash
# --- EXPECT REJECT ---

# Luật 1: image :latest
kubectl apply -n demo -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: test-latest
spec:
  containers:
  - name: app
    image: nginx:latest
    resources:
      limits:
        cpu: 100m
        memory: 64Mi
EOF

# Luật 2: thiếu resources.limits
kubectl apply -n demo -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: test-no-limits
spec:
  containers:
  - name: app
    image: nginx:1.25.3
EOF

# Luật 3: runAsUser: 0
kubectl apply -n demo -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: test-root
spec:
  securityContext:
    runAsUser: 0
  containers:
  - name: app
    image: nginx:1.25.3
    resources:
      limits:
        cpu: 100m
        memory: 64Mi
EOF

# Luật 4: hostNetwork: true
kubectl apply -n demo -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: test-hostnet
spec:
  hostNetwork: true
  containers:
  - name: app
    image: nginx:1.25.3
    resources:
      limits:
        cpu: 100m
        memory: 64Mi
EOF

# --- EXPECT PASS ---
kubectl apply -f gatekeeper/test-valid.yaml
```

Hoặc dùng file có sẵn:

```bash
# Test tất cả vi phạm cùng lúc (expect: tất cả bị reject)
kubectl apply -f gatekeeper/test-violations.yaml

# Test pod hợp lệ (expect: created)
kubectl apply -f gatekeeper/test-valid.yaml
```

| Test | Kỳ vọng |
|------|---------|
| Pod image `:latest` | reject |
| Pod thiếu `resources.limits` | reject |
| Pod `runAsUser: 0` | reject |
| Pod `hostNetwork: true` | reject |
| Pod hợp lệ (pinned + limits + non-root) | pass |

Evidence: `img/lab1.2-gatekeeper-reject.png`, `img/lab1.2-gatekeeper-pass.png`

---

## Lab 1.3 — Custom Policy (Registry Whitelist)

### Mô tả

Chặn tất cả image không xuất phát từ `ghcr.io/hunghk43/`. Chỉ registry của repo cá nhân được phép pull.

- ConstraintTemplate: `K8sAllowedRegistry` (tự viết Rego)
- Constraint: `allowed-registry` — `enforcementAction: deny`
- Parameter: `allowedRegistries: ["ghcr.io/hunghk43/"]`

### Rego logic

```rego
_is_allowed(image) {
  registry := input.parameters.allowedRegistries[_]
  startswith(image, registry)
}
```

### Nghiệm thu Lab 1.3

```bash
# EXPECT REJECT: image từ docker.io
kubectl apply -n demo -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: test-bad-registry
spec:
  securityContext:
    runAsUser: 1000
    runAsNonRoot: true
  containers:
  - name: app
    image: docker.io/nginx:1.25.3
    resources:
      limits:
        cpu: 100m
        memory: 64Mi
EOF

# EXPECT PASS: image từ ghcr.io/hunghk43/
kubectl apply -f gatekeeper/test-valid.yaml
```

| Test | Kỳ vọng |
|------|---------|
| Pod image `docker.io/nginx:1.25.3` | reject |
| Pod image `ghcr.io/hunghk43/w10-api:0.0.3` | pass |

Evidence: `img/lab1.3-custom-policy-reject.png`, `img/lab1.3-custom-policy-pass.png`

---

## Checklist nộp bài

- [x] `rbac/roles.yaml` — 3 role (Role + 2 ClusterRole)
- [x] `rbac/rolebindings.yaml` — 3 binding (RoleBinding + 2 ClusterRoleBinding)
- [x] `argocd/apps/rbac.yaml` — ArgoCD App for RBAC
- [x] `gatekeeper/templates/` — 5 ConstraintTemplate (4 luật + 1 custom)
- [x] `gatekeeper/constraints/` — 5 Constraint với `enforcementAction: deny`
- [x] `argocd/apps/gatekeeper-controller.yaml` — sync-wave: 0
- [x] `argocd/apps/gatekeeper-templates.yaml` — sync-wave: 1
- [x] `argocd/apps/gatekeeper-constraints.yaml` — sync-wave: 2
- [x] `auth can-i` 4 lệnh trả đúng kỳ vọng
- [x] 4 constraint reject vi phạm, pass pod hợp lệ
- [x] Lab 1.3 custom Rego policy — reject registry ngoài whitelist
- [x] Platform W9 vẫn Synced/Healthy sau khi bật enforce
- [ ] Evidence screenshots trong `img/`
