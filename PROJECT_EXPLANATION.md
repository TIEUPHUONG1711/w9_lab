# W9 GitOps Lab - Kiến Thức + Trình Bày Cho Mentor

## 🎯 PHẦN I: HIỂU TOÀN BỘ PROJECT (Chi tiết)

### 1. Mục Đích Project Là Gì?

**Tóm tắt ngắn:**
- Deploy một ứng dụng Flask API với **chiến lược Canary** (từng phần, không one-shot)
- Sử dụng **GitOps** để quản lý infrastructure từ Git repository
- Setup **Monitoring + Alerting** tự động để theo dõi sức khỏe ứng dụng
- Khi ứng dụng có vấn đề → gửi **email alert** tự động

**Tại sao lại làm vậy?**
- **Canary deployment**: Giảm rủi ro - nếu phiên bản mới có bug, chỉ 1-5% user bị ảnh hưởng, còn lại không
- **GitOps**: Toàn bộ infrastructure được quản lý bằng code + Git (dễ audit, dễ rollback, dễ collaborate)
- **Auto-healing**: Khi tài nguyên bị xóa/fail, hệ thống tự động khôi phục lại trạng thái mong muốn

---

### 2. Các Thành Phần Chính (Architecture)

Hiểu project qua **5 lớp**:

```
┌─────────────────────────────────────────────────────┐
│  Layer 1: GitHub Repository (Git)                    │
│  - Toàn bộ manifests (YAML) lưu trữ đây             │
│  - Từ đây, ArgoCD sẽ pull và sync xuống cluster    │
└─────────────────────────────────────────────────────┘
                         ↓
┌─────────────────────────────────────────────────────┐
│  Layer 2: ArgoCD (GitOps Controller)                │
│  - Giám sát Git thay đổi                             │
│  - Tự động apply manifests lên Kubernetes cluster  │
│  - Prune resource nếu xóa từ Git                    │
└─────────────────────────────────────────────────────┘
                         ↓
┌─────────────────────────────────────────────────────┐
│  Layer 3: Kubernetes Cluster                         │
│  - Chạy ứng dụng thực tế                             │
│  ├─ demo namespace: Rollout API (canary)            │
│  ├─ monitoring namespace: Prometheus + Alertmanager │
│  └─ argocd namespace: ArgoCD controller             │
└─────────────────────────────────────────────────────┘
                         ↓
┌─────────────────────────────────────────────────────┐
│  Layer 4: Prometheus (Monitoring)                    │
│  - Thu thập metrics từ ứng dụng (success-rate, ...)│
│  - Lưu trữ time-series data                         │
│  - Evaluate rules (ví dụ: nếu error > 20% → alert)│
└─────────────────────────────────────────────────────┘
                         ↓
┌─────────────────────────────────────────────────────┐
│  Layer 5: Alertmanager + Email                      │
│  - Nhận alert từ Prometheus                          │
│  - Gửi email thông báo đến tp17112k4@gmail.com     │
└─────────────────────────────────────────────────────┘
```

---

### 3. Công Nghệ & Khái Niệm Chính

| Công nghệ | Mục đích | Vị trí trong project |
|-----------|---------|-----------------|
| **Kubernetes (K8s)** | Nền tảng chạy ứng dụng | Toàn bộ |
| **Argo Rollouts** | Chiến lược deploy (canary) | `k8s-api/api.yaml` |
| **ArgoCD** | GitOps - quản lý infra từ Git | `argocd/` folder |
| **Prometheus** | Thu thập & lưu metrics | `argocd/apps/kube-prometheus-stack.yaml` |
| **Alertmanager** | Gửi email alert | Config trong Prometheus stack |
| **Flask** | Ứng dụng chính | `app/app.py` |
| **Docker** | Container image | `app/Dockerfile` |

---

### 4. Cấu Trúc Thư Mục - Mỗi Folder Làm Gì?

```
gitops/
├── app/
│   ├── app.py           → Flask API (ứng dụng chính)
│   └── Dockerfile       → Build Docker image
│
├── k8s-api/
│   ├── api.yaml         → Argo Rollout definition (canary deployment)
│   ├── analysis.yaml    → Tiêu chí success/fail của canary (via Prometheus)
│   └── servicemonitor.yaml → Báo cho Prometheus biết scrape metrics từ đây
│
├── argocd/
│   ├── root.yaml        → "Root Application" - khai báo tất cả ứng dụng con
│   └── apps/
│       ├── api.yaml     → ArgoCD Application - sync k8s-api/ từ Git
│       ├── backend.yaml → ArgoCD Application - sync backend
│       ├── frontend.yaml → ArgoCD Application - sync frontend
│       ├── argo-rollouts.yaml → ArgoCD Application - cài Argo Rollouts
│       ├── kube-prometheus-stack.yaml → ArgoCD Application - cài Prometheus + Alertmanager
│       └── monitoring/  → Folder cho monitoring extras
│           ├── app.yaml → ArgoCD Application - sync monitoring resources
│           ├── alertmanager-smtp-secret.yaml → Secret chứa mật khẩu SMTP
│           └── prometheusrule-test-alert.yaml → Test alert rule (vector(1))
│
├── k8s/
│   ├── namespace.yaml   → Tạo namespaces (không sử dụng nhiều)
│   ├── backend/         → Backend resources (không sync đủ)
│   └── frontend/        → Frontend resources (không sync đủ)
│
├── instruction/
│   └── W9-chieu-obs-canary.html → Yêu cầu assignment (slide HTML)
│
└── scripts/
    └── create_sealedsecret.ps1 → PowerShell helper (tạo SealedSecret)
```

---

### 5. Workflow Hoạt Động - Từ Code Đến Alert

#### Step 1️⃣: Push Code vào Git
```bash
# Bạn sửa file (ví dụ: k8s-api/api.yaml)
# Rồi commit + push
git add .
git commit -m "Fix ERROR_RATE"
git push origin main
```

#### Step 2️⃣: ArgoCD Phát Hiện & Sync
```
ArgoCD (trong cluster)
  ↓ mỗi 3 phút check Git
  ↓ thấy file thay đổi
  ↓ apply changes xuống cluster
  ↓ Kubernetes tạo Rollout mới
```

#### Step 3️⃣: Argo Rollouts Canary Deploy
```
Stable:  100% traffic → app:v2 (old)
Canary:  5% traffic  → app:v3 (new)
         ↓ chờ 10 phút, theo dõi metrics...
         ↓ nếu success-rate >= 0.8 → promote
Stable:  100% traffic → app:v3 (new)
         ✅ Deploy thành công!
```

#### Step 4️⃣: Prometheus Thu Thập Metrics
```
Prometheus (mỗi 15 giây)
  ↓ scrape metrics từ app
  ↓ tính success-rate = (requests_ok / requests_total)
  ↓ lưu vào database time-series
  ↓ evaluate alert rules
```

#### Step 5️⃣: Alert Firing & Email
```
nếu success_rate < 0.8:
  → FireTest alert fires
  ↓ gửi đến Alertmanager
  ↓ Alertmanager routing rules
  ↓ gửi email SMTP → tp17112k4@gmail.com
  ✅ Bạn nhận được alert!
```

---

### 6. Các File Quan Trọng - Cần Hiểu Sâu

#### **k8s-api/api.yaml** (Argo Rollout)
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: api
  namespace: demo
spec:
  # Chiến lược: Canary - 5% traffic → 10% → 20% → 100%
  strategy:
    canary:
      steps:
        - setWeight: 5
        - pause: {duration: 10m}  # Chờ 10 phút
        - setWeight: 10
        - pause: {duration: 5m}
      analysis:
        templates:
          - name: api-success-rate  # Xem analysis.yaml
            requiredForProgression: true  # Phải pass thì mới continue
  
  # Ứng dụng
  spec:
    containers:
      - name: api
        image: gcr.io/...api:latest
        env:
          - name: ERROR_RATE
            value: "0"           # 0% errors (nếu "0.5" = 50% fail)
          - name: VERSION
            value: "v3"          # Version tag
```

**Tại sao quan trọng?**
- Nếu `ERROR_RATE: "0.5"` → khi canary chạy, error cao → analysis fail → rollback
- Đây là nơi kiểm soát hành vi của app để test canary

---

#### **k8s-api/analysis.yaml** (AnalysisTemplate)
```yaml
apiVersion: argoproj.io/v1alpha1
kind: AnalysisTemplate
metadata:
  name: api-success-rate
spec:
  metrics:
    - name: success-rate
      provider:
        prometheus:
          # Query Prometheus: tính success-rate
          query: |
            sum(rate(flask_http_request_total{status=~"2.*|3.*"}[5m])) /
            sum(rate(flask_http_request_total[5m]))
      
      # Tiêu chí pass/fail
      successCriteria: result[0] >= 0.8  # >= 80% requests success
      failureLimit: 1                      # 1 lần fail → abort canary
```

**Tại sao quan trọng?**
- Định nghĩa "deployment thành công = gì?"
- Nếu success-rate < 80% → rollout tự động rollback (không bao giờ reach 100% traffic)

---

#### **argocd/apps/api.yaml** (ArgoCD Application)
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: api  # Tên trong ArgoCD UI
spec:
  source:
    repoURL: https://github.com/TIEUPHUONG1711/w9_lab.git
    targetRevision: HEAD  # Lấy commit mới nhất từ main
    path: k8s-api         # Sync toàn bộ files từ k8s-api/

  destination:
    namespace: demo       # Apply vào namespace "demo"
  
  syncPolicy:
    automated:
      prune: true        # Xóa resource nếu không có trong Git
      selfHeal: true     # Auto-sync nếu cluster state khác Git
```

**Tại sao quan trọng?**
- Kết nối Git → Cluster
- Nếu edit api.yaml trong k8s-api/ → ArgoCD tự động pull & apply

---

#### **argocd/apps/kube-prometheus-stack.yaml** (Prometheus + Alertmanager)
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: kube-prometheus-stack
spec:
  source:
    chart: kube-prometheus-stack
    repoURL: https://prometheus-community.github.io/helm-charts
    
    # Helm values - cấu hình Alertmanager
    helm:
      values: |
        alertmanager:
          config:
            receivers:
              - name: email
                email_configs:
                  - to: tp17112k4@gmail.com
                    from: xxx@gmail.com
                    smarthost: smtp.gmail.com:587
                    auth_username: xxx@gmail.com
                    auth_password: <base64-encoded-password>  # Từ Secret
```

**Tại sao quan trọng?**
- Cấu hình email destination
- Alertmanager sẽ dùng cấu hình này để gửi email khi alert fire

---

#### **argocd/apps/monitoring/alertmanager-smtp-secret.yaml** (Secret)
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: alertmanager-smtp-secret
  namespace: monitoring
type: Opaque
data:
  smtp_password: <base64-encoded-real-password>  # Mật khẩu thực
```

**Tại sao quan trọng?**
- Chứa mật khẩu SMTP (base64 encoded, không plain text)
- Alertmanager khi gửi email sẽ sử dụng password từ Secret này

---

### 7. Các Khái Niệm Quan Trọng

#### **Canary Deployment**
```
Bình thường (All-at-once):    Canary:
v1 → [STOP] → v2              v1 (100%)
  ❌ Nếu v2 bug, 100% user               ↓
     bị ảnh hưởng              v1 (95%) + v2 (5%)
                                ↓ 5 phút test...
                               v1 (90%) + v2 (10%)
                                ↓
                               v2 (100%)
                               ✅ Tỷ lệ bị ảnh hưởng = 5%, thời gian = 20 phút
```

#### **GitOps Principle**
```
Truyền thống:                  GitOps:
người kỹ sư → kubectl apply    người kỹ sư → push Git
              ↓                         ↓
            cluster          ArgoCD Controller
              ↑                         ↓
             (nếu fail,                cluster
              phải fix thủ công)
                               ✅ Tự động, idempotent, dễ audit
```

#### **Prometheus Metrics & Queries**
```
flask_http_request_total{status="200"} = 950 requests
flask_http_request_total{status="500"} = 50 requests
Total = 1000 requests

success_rate = 950 / 1000 = 0.95 (95%)
nếu success_rate >= 0.8 → canary progress
nếu success_rate < 0.8 → canary abort & rollback
```

---

## 🎯 PHẦN II: TRÌNH BÀY CHO MENTOR (Ngắn Gọn 2-3 Phút)

### **Pitch Ngắn Gọn (1 Phút)**

> "Dự án này là một **GitOps lab** sử dụng Kubernetes, ArgoCD, và Argo Rollouts để implement **canary deployment** với **auto-healing**.
>
> **Mục tiêu chính:**
> 1. Deploy một Flask API một cách **an toàn** (canary: chỉ 5% traffic lúc đầu)
> 2. Tự động **rollback nếu metrics xấu** (ví dụ: error rate > 20%)
> 3. Khi có sự cố → **gửi email alert** tự động
>
> **Tech stack:**
> - **Kubernetes**: Nền tảng
> - **ArgoCD**: GitOps controller (Git → Cluster)
> - **Argo Rollouts**: Canary + analysis hooks
> - **Prometheus + Alertmanager**: Monitoring + email alerts
> - **Flask**: Ứng dụng demo
>
> **Công việc đã hoàn tất:**
> ✅ API chạy Healthy (ERROR_RATE=0, VERSION=v3)
> ✅ ArgoCD sync toàn bộ resources từ Git
> ✅ Prometheus collect metrics từ app
> ✅ Alertmanager + email config đã deployed
> ✅ Test alert rule sẵn sàng trigger email"

---

### **Pitch Chi Tiết (3 Phút)**

#### **Mục đích & Tại sao?**
- **Vấn đề**: Deploy phiên bản mới có rủi ro cao (1 bug → tất cả user gặp sự cố)
- **Giải pháp**: Canary deployment (50% user cũ, 50% người mới → nếu có bug, phát hiện sớm → rollback)
- **Bonus**: Monitoring + auto-alert giúp phát hiện sự cố mà không cần con người giám sát 24/7

#### **Kiến trúc 5 Lớp**
1. **Git Repository** → Lưu trữ toàn bộ code (ứng dụng + infrastructure)
2. **ArgoCD** → Giám sát Git, tự động apply manifests lên cluster
3. **Kubernetes Cluster** → Chạy ứng dụng
4. **Prometheus** → Thu thập metrics (success-rate, error rate)
5. **Alertmanager** → Gửi email khi metrics xấu

#### **Workflow Cụ Thể**
```
Bạn push code → ArgoCD detect → Rollout start canary
  ↓
5% traffic to new version (v3) → Prometheus monitor
  ↓
success_rate >= 80%? 
  ├─ YES → 100% traffic to v3 (✅ success)
  └─ NO  → Rollback to v2 (⚠️ abort canary)
  
Nếu metric xấu →
  Prometheus fires alert → Alertmanager routes to email
    → Gmail SMTP server sends email to tp17112k4@gmail.com
```

#### **Công Việc Đã Hoàn Tất**
1. **Fix API Rollout**: ERROR_RATE=0 (không inject error), VERSION=v3
2. **Setup GitOps**: ArgoCD Applications sync k8s-api/, monitoring/, kube-prometheus-stack
3. **Monitoring Setup**: Prometheus scrape flask metrics, Alertmanager configured for email
4. **Email Alert**: SMTP Secret deployed, test rule (vector(1)) ready to fire

#### **Kết Quả Hiện Tại**
- **Rollout api**: Healthy ✅
- **ArgoCD Applications**: Synced ✅
- **Prometheus Metrics**: Collecting ✅
- **Email Config**: Active ✅
- **Test Alert**: Ready to trigger ✅

---

### **Trả Lời Câu Hỏi Phổ Biến Từ Mentor**

#### ❓ "Sự khác biệt giữa Canary vs Blue-Green?"

| | Canary | Blue-Green |
|---|--------|-----------|
| **Traffic % lúc đầu** | 5% new | 50% new |
| **Thời gian** | 20+ phút (từng bước) | 5 phút (1 lần chuyển) |
| **Rủi ro** | Thấp (chỉ 5% user bị ảnh hưởng) | Cao (50% user bị ảnh hưởng) |
| **Khi phát hiện bug** | Tự động rollback | Phải switch thủ công |

> **Canary tốt hơn vì:** Rủi ro thấp, tự động rollback, dễ phát hiện metric xấu

---

#### ❓ "ArgoCD vs kubectl apply - cái nào tốt hơn?"

```
kubectl apply:
  - Manual → easy to miss changes
  - Hard to rollback
  - No audit trail
  
ArgoCD (GitOps):
  - Automatic → Git is single source of truth
  - Easy to rollback (just revert commit)
  - Full audit trail in Git history
  ✅ BETTER for production
```

---

#### ❓ "Prometheus scrape metrics từ đâu?"

```
App (Flask) exposes metrics endpoint:
  GET http://api:5000/metrics
  
Response:
  flask_http_request_total{status="200"} 950
  flask_http_request_total{status="500"} 50
  
Prometheus (every 15 sec):
  → curl http://api:5000/metrics
  → parse & store in time-series DB
  → use in queries (alerting rules, dashboards)
```

---

#### ❓ "Nếu secret SMTP bị lộ thì sao?"

> "Hiện tại, password được base64 encode và commit vào Git (không hoàn toàn secure).
>
> Giải pháp tốt hơn:
> 1. **SealedSecret** (kubeseal) → mã hóa Secret, chỉ cluster có thể decrypt
> 2. **ExternalSecret** + AWS Secrets Manager / Vault
> 3. **ArgoCD Notifications** (built-in, không cần store password)
>
> Trong lab này, chúng ta dùng cách 1 là đủ (hoặc cách 2 cho production)"

---

## 🎯 PHẦN III: CHEAT SHEET - Lệnh Hay Dùng

```bash
# Kiểm tra Rollout status
kubectl get rollout -n demo
kubectl get rollout api -n demo -o yaml | grep -A10 'status:'

# Kiểm tra ArgoCD Applications
kubectl get applications -n argocd
kubectl get applications api -n argocd -o jsonpath='{.status.sync.status} {.status.health.status}'

# Kiểm tra Prometheus targets (metrics sources)
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
# Rồi mở http://localhost:9090/targets

# Kiểm tra Alertmanager (alert status)
kubectl port-forward -n monitoring svc/kube-prometheus-stack-alertmanager 9093:9093
# Rồi mở http://localhost:9093

# View Alertmanager logs (xem email sent?)
kubectl logs -n monitoring -l app.kubernetes.io/name=alertmanager -f

# Force ArgoCD sync (nếu stuck)
kubectl -n argocd annotate application api argocd.argoproj.io/refresh=hard --overwrite

# View AnalysisRun (canary evaluation)
kubectl get analysisrun -n demo -o yaml
```

---

## 📝 Kết Luận

**Để mentor hiểu toàn bộ:**
1. **Start với "why"** → Tại sao cần canary? (reduce risk)
2. **Explain architecture** → 5 lớp: Git → ArgoCD → K8s → Prometheus → Alert
3. **Dive deep vào flow** → Push Git → ArgoCD sync → Rollout canary → Monitor → Alert
4. **Show code** → Chỉ ra k8s-api/api.yaml, analysis.yaml, argocd/apps/
5. **Validate status** → Chỉ metrics & logs chứng minh system đang chạy
6. **Answer questions** → Chuẩn bị sẵn câu trả lời về Canary vs Blue-Green, GitOps benefits, v.v.

**Mentor sẽ impress với:**
- ✅ Hiểu rõ GitOps concept & lợi ích
- ✅ Biết cách debugging (logs, metrics, ArgoCD status)
- ✅ Có thể giải thích từng thành phần & tác dụng của nó
- ✅ Prepared answers cho follow-up questions
