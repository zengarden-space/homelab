┌─────────────────────────────────────────────────────────────────┐
│ COMPLETE IP ALLOCATION SCHEME                                   │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│ WIREGUARD VPN NETWORK (10.99.0.0/16)                            │
│   10.99.0.0/24     - Infrastructure                             │
│     10.99.0.1      - Oracle K3s Master (VPN server)             │
│   10.99.1.0/24     - Homelab Users                              │
│     10.99.1.10-254 - Developer laptops/workstations             │
│   10.99.2.0/24     - Break-glass Emergency Access               │
│     10.99.2.10-20  - Emergency admin access                     │
│   10.99.10.0/24    - Site-to-Site                               │
│     10.99.10.1     - MikroTik Router (homelab gateway)          │
│                                                                 │
│ ORACLE CLOUD PRODUCTION (10.0.0.0/16)                           │
│   10.0.1.0/24      - K3s Control Plane                          │
│     10.0.1.10      - K3s Master VM (+ WireGuard server)         │
│   10.0.2.0/24      - K3s Workers                                │
│     10.0.2.11      - K3s Worker 1                               │
│     10.0.2.12      - K3s Worker 2                               │
│   10.0.10.0/24     - Container Registry (optional)              │
│     10.0.10.10     - Harbor registry or OCIR                    │
│                                                                 │
│ ORACLE K3S POD/SERVICE NETWORKS                                 │
│   10.44.0.0/16     - Pod network (ClusterIP)                    │
│   10.45.0.0/16     - Service network (ClusterIP)                │
│                                                                 │
│ HOMELAB PHYSICAL NETWORKS (192.168.0.0/16)                      │
│   192.168.88.0/24  - Home WiFi/Ethernet (VLAN88)                │
│     192.168.88.1   - MikroTik gateway                           │
│   192.168.99.0/24  - HomeAssistant/IoT (VLAN99)                 │
│     192.168.99.1   - MikroTik gateway                           │
│   192.168.77.0/24  - K3s Cluster (VLAN77)                       │
│     192.168.77.1   - MikroTik gateway                           │
│     192.168.77.11  - blade001 (Compute Blade CM5)               │
│     192.168.77.12  - blade002 (Compute Blade CM5)               │
│     192.168.77.13  - blade003 (Compute Blade CM5)               │
│     192.168.77.14  - blade004 (Compute Blade CM5)               │
│     192.168.77.15  - blade005 (Compute Blade CM5, master)       │
│   192.168.100.0/24 - Management VLAN (VLAN100)                  │
│     192.168.100.1  - MikroTik (admin access)                    │
│     192.168.100.10 - Mac Mini (admin workstation)               │
│                                                                 │
│ HOMELAB K3S POD/SERVICE NETWORKS                                │
│   10.42.0.0/16     - Pod network                                │
│   10.43.0.0/16     - Service network                            │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘

KEY DESIGN PRINCIPLES:
  • No IP overlap between any networks
  • Oracle uses 10.0.x.x, Homelab uses 192.168.x.x
  • VPN uses 10.99.x.x for clear separation
  • Different pod networks per cluster (10.42 vs 10.44)
```

## Complete Network Topology
```
┌──────────────────────────────────────────────────────────────────────────┐
│                          INTERNET                                        │
│                             │                                            │
│              ┌──────────────┴───────────────┐                            │
│              │                              │                            │
│      ┌───────▼─────────┐          ┌────────▼─────────┐                  │
│      │ Home ISP        │          │ Oracle Cloud     │                  │
│      │ (Dynamic IP)    │          │ (Static IP)      │                  │
│      └───────┬─────────┘          │ 203.0.113.10     │                  │
│              │                    └────────┬─────────┘                  │
│              │                             │                            │
│   ┌──────────▼─────────────┐               │                            │
│   │ MIKROTIK CHATEAU LTE18 │               │                            │
│   │ Homelab Router         │◄──────────────┘                            │
│   │ VLANs + Firewall       │    WireGuard VPN                           │
│   └──────────┬─────────────┘    (UDP 51820)                             │
│              │                                                           │
│    ┌─────────┼──────────┬──────────┬──────────┐                         │
│    │         │          │          │          │                         │
│ ┌──▼───┐ ┌──▼───┐  ┌──▼───┐  ┌───▼────┐ ┌───▼────┐                    │
│ │VLAN88│ │VLAN99│  │VLAN77│  │VLAN100 │ │  eth3  │                    │
│ │ Home │ │ IoT  │  │ K3s  │  │  Mgmt  │ │blade005│                    │
│ └──┬───┘ └──┬───┘  └──┬───┘  └───┬────┘ └────────┘                    │
│    │        │         │          │                                      │
│  WiFi    WiFi      Zyxel      Mac Mini                                  │
│  Switch  Devices   5-port      (Admin)                                  │
│   │        │       PoE Sw                                               │
│   │        │         │                                                  │
│  PCs     HA      blade001-004                                           │
│ Phones   Smart    (CM5 Cluster)                                         │
│          Home                                                           │
│                                                                         │
└──────────────────────────────────────────────────────────────────────────┘

                              │
                              │ WireGuard VPN Tunnel
                              │ (Encrypted, 10.99.0.0/16)
                              │
┌─────────────────────────────▼─────────────────────────────────────────────┐
│                    ORACLE CLOUD VCN (10.0.0.0/16)                        │
│                                                                           │
│  ┌────────────────────────────────────────────────────────────────────┐  │
│  │ PUBLIC SUBNET (10.0.1.0/24)                                        │  │
│  │                                                                    │  │
│  │  ┌──────────────────────────────────────────────────────────┐     │  │
│  │  │ K3s Master VM (ARM 4 OCPU, 12GB RAM)                     │     │  │
│  │  │ Private IP: 10.0.1.10                                    │     │  │
│  │  │ Public IP: 203.0.113.10                                  │     │  │
│  │  │ VPN IP: 10.99.0.1                                        │     │  │
│  │  │                                                          │     │  │
│  │  │ Services:                                                │     │  │
│  │  │   • K3s Control Plane (6443)                            │     │  │
│  │  │   • WireGuard Server (51820/udp) ◄─── PUBLIC            │     │  │
│  │  │   • etcd                                                │     │  │
│  │  └──────────────────────────────────────────────────────────┘     │  │
│  └────────────────────────────────────────────────────────────────────┘  │
│                                                                           │
│  ┌────────────────────────────────────────────────────────────────────┐  │
│  │ PRIVATE SUBNET (10.0.2.0/24)                                       │  │
│  │                                                                    │  │
│  │  ┌─────────────────────────┐  ┌─────────────────────────┐        │  │
│  │  │ K3s Worker 1            │  │ K3s Worker 2            │        │  │
│  │  │ ARM 6 OCPU, 9GB RAM     │  │ ARM 6 OCPU, 9GB RAM     │        │  │
│  │  │ Private: 10.0.2.11      │  │ Private: 10.0.2.12      │        │  │
│  │  │ (No public IP)          │  │ (No public IP)          │        │  │
│  │  └─────────────────────────┘  └─────────────────────────┘        │  │
│  └────────────────────────────────────────────────────────────────────┘  │
│                                                                           │
│  ┌────────────────────────────────────────────────────────────────────┐  │
│  │ PRIVATE SUBNET (10.0.10.0/24) - Optional                          │  │
│  │  ┌─────────────────────────┐                                      │  │
│  │  │ Container Registry      │                                      │  │
│  │  │ 10.0.10.10              │                                      │  │
│  │  │ (Harbor or OCIR)        │                                      │  │
│  │  └─────────────────────────┘                                      │  │
│  └────────────────────────────────────────────────────────────────────┘  │
│                                                                           │
│  Oracle Free Tier: 4 ARM OCPU total, 24GB RAM total                     │
│  VM Split (3-node):                                                      │
│    Master/Hub:  A1.Flex 1 OCPU, 6 GB RAM, 50 GB storage                 │
│    Worker-1:    A1.Flex 1 OCPU, 6 GB RAM, 50 GB storage                 │
│    Worker-2:    A1.Flex 2 OCPU, 12 GB RAM, 100 GB storage               │
│  Total: 4 OCPU, 24 GB RAM, 200 GB storage ✅ Fits Always Free           │
│                                                                          │
│  Note: A1.Flex OCPU increments are integers (1, 2, 3, 4)                │
│        1.5 OCPU splits are NOT available in Oracle Cloud                │
└───────────────────────────────────────────────────────────────────────────┘
```

## WireGuard VPN Hub-and-Spoke Topology
```
┌──────────────────────────────────────────────────────────────────┐
│ WIREGUARD VPN ARCHITECTURE (Hub-and-Spoke)                      │
└──────────────────────────────────────────────────────────────────┘

                    ┌─────────────────────────┐
                    │  WIREGUARD HUB          │
                    │  Oracle K3s Master VM   │
                    │                         │
                    │  Public: 203.0.113.10   │
                    │  Private: 10.0.1.10     │
                    │  VPN: 10.99.0.1         │
                    │  Port: 51820/udp        │
                    └────────────┬────────────┘
                                 │
                                 │ All peers connect here
                                 │
         ┌───────────────────────┼───────────────────────┐
         │                       │                       │
         │                       │                       │
    ┌────▼─────┐          ┌─────▼──────┐         ┌─────▼──────┐
    │ SPOKE 1  │          │  SPOKE 2   │         │  SPOKE 3   │
    │ MikroTik │          │ Developer  │         │ Break-Glass│
    │          │          │  Laptop    │         │  Emergency │
    │10.99.10.1│          │ 10.99.1.10 │         │ 10.99.2.10 │
    │          │          │            │         │            │
    │Site-2-Site         │Remote Access│         │Emergency   │
    └────┬─────┘          └────────────┘         └────────────┘
         │
         │ Routes entire homelab
         │
    ┌────▼──────────────────────────┐
    │   HOMELAB NETWORKS            │
    │   192.168.77.0/24 (K3s)       │
    │   192.168.88.0/24 (Home)      │
    │   192.168.99.0/24 (IoT)       │
    │   192.168.100.0/24 (Mgmt)     │
    └───────────────────────────────┘


PEER CONFIGURATIONS:

┌─────────────────────────────────────────────────────────────┐
│ HUB: Oracle K3s Master (10.99.0.1)                          │
├─────────────────────────────────────────────────────────────┤
│ [Interface]                                                 │
│ Address = 10.99.0.1/16                                      │
│ ListenPort = 51820                                          │
│ PrivateKey = <oracle-private-key>                          │
│                                                             │
│ [Peer] # MikroTik Site-to-Site                             │
│ PublicKey = <mikrotik-public-key>                          │
│ AllowedIPs = 10.99.10.1/32, 192.168.77.0/24,               │
│              192.168.88.0/24, 192.168.99.0/24,              │
│              192.168.100.0/24                               │
│ # No Endpoint - MikroTik initiates                         │
│                                                             │
│ [Peer] # Developer 1                                       │
│ PublicKey = <dev1-public-key>                              │
│ AllowedIPs = 10.99.1.10/32                                 │
│                                                             │
│ [Peer] # Break-Glass Admin                                 │
│ PublicKey = <admin-public-key>                             │
│ AllowedIPs = 10.99.2.10/32                                 │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ SPOKE: MikroTik Router (10.99.10.1)                         │
├─────────────────────────────────────────────────────────────┤
│ [Interface]                                                 │
│ Address = 10.99.10.1/24                                     │
│ PrivateKey = <mikrotik-private-key>                        │
│                                                             │
│ [Peer] # Oracle Hub                                        │
│ PublicKey = <oracle-public-key>                            │
│ Endpoint = 203.0.113.10:51820                              │
│ AllowedIPs = 10.0.0.0/16, 10.99.0.0/16                     │
│ PersistentKeepalive = 25                                   │
│                                                             │
│ # Routes homelab subnets through VPN                       │
│ PostUp = ip route add 10.0.0.0/16 via 10.99.0.1            │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ SPOKE: Developer Laptop (10.99.1.10)                        │
├─────────────────────────────────────────────────────────────┤
│ [Interface]                                                 │
│ Address = 10.99.1.10/32                                     │
│ PrivateKey = <dev-private-key>                             │
│ DNS = 1.1.1.1                                               │
│                                                             │
│ [Peer] # Oracle Hub                                        │
│ PublicKey = <oracle-public-key>                            │
│ Endpoint = 203.0.113.10:51820                              │
│ AllowedIPs = 10.0.1.10/32,        # Oracle K3s API         │
│              192.168.77.0/24,      # Homelab K3s           │
│              192.168.88.0/24       # Homelab services      │
│ PersistentKeepalive = 25                                   │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ SPOKE: Break-Glass Emergency (10.99.2.10)                   │
├─────────────────────────────────────────────────────────────┤
│ [Interface]                                                 │
│ Address = 10.99.2.10/32                                     │
│ PrivateKey = <emergency-private-key>                       │
│                                                             │
│ [Peer] # Oracle Hub                                        │
│ PublicKey = <oracle-public-key>                            │
│ Endpoint = 203.0.113.10:51820                              │
│ AllowedIPs = 0.0.0.0/0            # FULL ACCESS            │
│ PersistentKeepalive = 25                                   │
│                                                             │
│ # Emergency access to EVERYTHING                           │
│ # Activate manually, revoke after use                      │
└─────────────────────────────────────────────────────────────┘
```

## Homelab Physical Network
```
┌──────────────────────────────────────────────────────────────────┐
│ MIKROTIK CHATEAU LTE18 - PHYSICAL PORT LAYOUT                   │
└──────────────────────────────────────────────────────────────────┘

Port Assignments:
  eth1 (1Gbps)   → VLAN100 Management → Mac Mini
  eth2 (1Gbps)   → VLAN77 K3s → Zyxel PoE Switch → blade001-004
  eth3 (1Gbps)   → VLAN77 K3s → blade005 (direct)
  eth4 (1Gbps)   → VLAN99 IoT/HA → HomeAssistant devices
  eth5 (2.5Gbps) → VLAN88 Home → Gigabit switch → Home devices
  
  wlan1 (2.4GHz) → "Home-WiFi" (VLAN88) + "IoT-WiFi" (VLAN99)
  wlan2 (5GHz)   → "Home-WiFi-5G" (VLAN88) + "IoT-WiFi-5G" (VLAN99)
  
  lte1           → Cellular WAN (failover)


┌──────────────────────────────────────────────────────────────────┐
│ VLAN SEGMENTATION & FIREWALL RULES                              │
└──────────────────────────────────────────────────────────────────┘

VLAN88 (Home Network - 192.168.88.0/24)
  ├─ Devices: Laptops, phones, PCs, TVs
  ├─ Access: Internet (full), K3s services (limited)
  └─ Firewall: Can access VLAN77:80,443 | Block VLAN99,100

VLAN99 (IoT/HomeAssistant - 192.168.99.0/24)
  ├─ Devices: Smart home, sensors, HomeAssistant
  ├─ Access: Internet only, isolated from other VLANs
  └─ Firewall: Block all other VLANs | Internet only

VLAN77 (K3s Cluster - 192.168.77.0/24)
  ├─ Devices: 5x Compute Blade CM5
  ├─ Access: Internet, VPN to Oracle, limited to VLAN88
  └─ Firewall: Allow VPN | Block VLAN88→77 except specific ports

VLAN100 (Management - 192.168.100.0/24)
  ├─ Devices: Mac Mini admin workstation
  ├─ Access: ALL VLANs (admin access), VPN break-glass
  └─ Firewall: Can access everything | Nothing can access it


┌──────────────────────────────────────────────────────────────────┐
│ K3S CLUSTER PHYSICAL LAYOUT                                      │
└──────────────────────────────────────────────────────────────────┘

                  MikroTik eth2 & eth3
                  (VLAN77 - 192.168.77.0/24)
                         │
            ┌────────────┴────────────┐
            │                         │
    ┌───────▼──────┐          ┌──────▼──────┐
    │ Zyxel        │          │ blade005    │
    │ GS1200-5HPV2 │          │ (Master)    │
    │ 60W PoE+     │          │ .77.15      │
    │              │          │ Direct link │
    └───────┬──────┘          └─────────────┘
            │
    ┌───────┼────────┬────────┬────────┐
    │       │        │        │        │
┌───▼──┐ ┌──▼──┐ ┌──▼──┐ ┌───▼──┐
│blade1│ │blade2│ │blade3│ │blade4│
│ 001  │ │ 002  │ │ 003  │ │ 004  │
│.77.11│ │.77.12│ │.77.13│ │.77.14│
│Worker│ │Worker│ │Worker│ │Worker│
└──────┘ └──────┘ └──────┘ └──────┘

Each Compute Blade:
  • Raspberry Pi CM5 (Cortex-A76 quad-core @ 2.4GHz)
  • 4GB or 8GB RAM
  • NVMe SSD (M.2 2230/2242/2260/2280)
  • Powered via PoE+ (802.3at, up to 30W)
  • Actual power: 4-7W typical, up to 10W with NVMe
  • Gigabit Ethernet
  • Total cluster: 28-40W under load
```

## Access Control Matrix
```
┌──────────────────────────────────────────────────────────────────────┐
│ WHO CAN ACCESS WHAT                                                  │
├──────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ HOME DEVICES (VLAN88)                                                │
│   Can access:                                                        │
│     ✓ Internet (full)                                                │
│     ✓ K3s services on VLAN77 ports 80,443 (HTTP/HTTPS)             │
│   Cannot access:                                                     │
│     ✗ K3s nodes directly (SSH, kubectl)                             │
│     ✗ IoT VLAN (VLAN99)                                             │
│     ✗ Management VLAN (VLAN100)                                     │
│     ✗ Oracle Cloud (no VPN access)                                  │
│                                                                      │
│ IOT DEVICES (VLAN99)                                                 │
│   Can access:                                                        │
│     ✓ Internet only                                                  │
│   Cannot access:                                                     │
│     ✗ Any other VLAN (fully isolated)                               │
│                                                                      │
│ K3S CLUSTER (VLAN77)                                                 │
│   Can access:                                                        │
│     ✓ Internet (pull images, updates)                               │
│     ✓ Oracle Cloud K3s (via VPN)                                    │
│     ✓ Container registry                                            │
│   Cannot access:                                                     │
│     ✗ Home VLAN (except responses)                                  │
│     ✗ IoT VLAN                                                      │
│     ✗ Management VLAN                                               │
│                                                                      │
│ MANAGEMENT VLAN (VLAN100)                                            │
│   Can access:                                                        │
│     ✓ Everything (admin access)                                     │
│     ✓ All VLANs                                                     │
│     ✓ Router management                                             │
│     ✓ Via VPN: Oracle Cloud (break-glass)                           │
│                                                                      │
│ DEVELOPERS (VPN 10.99.1.0/24)                                        │
│   Can access:                                                        │
│     ✓ Oracle K3s API (kubectl)                                      │
│     ✓ Homelab K3s API (via VPN → MikroTik → VLAN77)                │
│     ✓ Gitea (if exposed)                                            │
│     ✓ ArgoCD dashboards                                             │
│   Cannot access:                                                     │
│     ✗ SSH to nodes (firewall blocked)                               │
│     ✗ Home network (VLAN88)                                         │
│     ✗ Management VLAN                                               │
│                                                                      │
│ BREAK-GLASS ADMIN (VPN 10.99.2.0/24)                                │
│   Can access:                                                        │
│     ✓ EVERYTHING (emergency only)                                   │
│     ✓ SSH to all nodes                                              │
│     ✓ kubectl to all clusters                                       │
│     ✓ All homelab VLANs                                             │
│     ✓ Router management                                             │
│   Restrictions:                                                      │
│     ⚠️  Manually activated (add peer to WireGuard)                  │
│     ⚠️  Time-limited (revoke after use)                             │
│     ⚠️  Fully audited (all actions logged)                          │
│                                                                      │
│ ARGOCD (192.168.77.x)                                                │
│   Can access:                                                        │
│     ✓ Homelab K3s API (in-cluster)                                  │
│     ✓ Oracle K3s API (via VPN)                                      │
│     ✓ Gitea (for GitOps pulls)                                      │
│   Uses:                                                              │
│     ✓ ServiceAccount tokens (RBAC limited)                          │
│     ✓ Cannot create/modify RBAC, nodes, CRDs                        │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘
```

## Data Flow Examples
```
┌──────────────────────────────────────────────────────────────────┐
│ EXAMPLE 1: Developer Deploys to Oracle Cloud                    │
└──────────────────────────────────────────────────────────────────┘

1. Developer pushes code to Gitea (homelab)
   Developer Laptop → Gitea (192.168.77.x or via domain)

2. Gitea webhook triggers (if exposed via Cloudflare Tunnel)
   OR ArgoCD polls every 3 minutes

3. ArgoCD (homelab) detects change
   ArgoCD (192.168.77.x) → Git pull from Gitea

4. ArgoCD syncs to Oracle cluster
   ArgoCD → MikroTik (10.99.10.1) →
   VPN tunnel → Oracle (10.99.0.1) →
   K3s API (10.0.1.10:6443)

5. Oracle K3s applies manifests
   K3s Master → Workers → Pull images → Deploy pods

Flow: Homelab → VPN → Oracle
Encryption: End-to-end via WireGuard


┌──────────────────────────────────────────────────────────────────┐
│ EXAMPLE 2: Developer Accesses Oracle K3s                         │
└──────────────────────────────────────────────────────────────────┘

1. Developer connects to WireGuard VPN
   Laptop → Oracle (203.0.113.10:51820)
   Gets VPN IP: 10.99.1.10

2. Developer runs kubectl
   kubectl get pods → 10.0.1.10:6443

3. Oracle firewall checks source
   Source: 10.99.1.10 ✓ (allowed)
   Destination: 10.0.1.10:6443 ✓ (K3s API)

4. K3s RBAC checks token
   ServiceAccount permissions validated
   Operation allowed/denied based on role

Flow: Laptop → VPN → Oracle K3s API
Security: WireGuard encryption + K8s RBAC


┌──────────────────────────────────────────────────────────────────┐
│ EXAMPLE 3: Oracle K3s Pulls Image from Homelab Registry         │
└──────────────────────────────────────────────────────────────────┘

Scenario: Harbor running on homelab K3s

1. Oracle K3s tries to pull image
   imagePullPolicy triggers on Worker (10.0.2.11)

2. Worker tries to reach registry
   10.0.2.11 → 192.168.77.x:5000 (Harbor)

3. Traffic routes through VPN
   Oracle Worker → Oracle Master (10.0.1.10) →
   VPN (10.99.0.1 → 10.99.10.1) → MikroTik →
   VLAN77 → Harbor

4. Harbor authenticates & serves image
   Registry → reverse path → Oracle Worker

5. Worker starts container
   Image cached locally for future use

Flow: Oracle → VPN → MikroTik → Homelab
Alternative: Use OCIR (Oracle Container Registry) to avoid this


┌──────────────────────────────────────────────────────────────────┐
│ EXAMPLE 4: Emergency Break-Glass Access                          │
└──────────────────────────────────────────────────────────────────┘

Scenario: Production Oracle cluster is down, normal access fails

1. Admin generates emergency WireGuard keys
   wg genkey → emergency-private.key
   wg pubkey → emergency-public.key

2. Admin adds peer via Oracle Console SSH
   Login to Oracle Console → SSH to Master VM
   Add [Peer] with emergency-public.key
   AllowedIPs = 10.99.2.10/32
   wg-quick restart

3. Admin connects with emergency config
   Laptop → Oracle VPN (10.99.2.10)

4. Admin has full access
   ssh ubuntu@10.0.1.10 ✓
   ssh ubuntu@10.0.2.11 ✓
   kubectl --all-namespaces ✓
   Can fix the issue

5. After incident resolved
   Remove [Peer] from WireGuard config
   Document incident
   Review what went wrong

Flow: Direct emergency access bypassing normal controls
Audit: All actions logged in multiple places
```

## Security Boundaries
```
┌──────────────────────────────────────────────────────────────────┐
│ DEFENSE IN DEPTH - 8 LAYERS                                      │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│ LAYER 1: Network Perimeter                                      │
│   • Oracle Security Lists: Only UDP 51820 allowed               │
│   • MikroTik Firewall: VLAN isolation, inter-VLAN rules        │
│   • No direct SSH/K3s API exposure to internet                 │
│                                                                  │
│ LAYER 2: VPN Authentication                                     │
│   • WireGuard public key cryptography                           │
│   • Separate keypairs per peer (never reuse)                   │
│   • Optional PreSharedKey for post-quantum protection           │
│                                                                  │
│ LAYER 3: VPN Authorization (AllowedIPs)                         │
│   • MikroTik: Only homelab subnets                              │
│   • Users: Only specific required resources                     │
│   • Break-glass: Full access (time-limited)                     │
│                                                                  │
│ LAYER 4: Host Firewall (iptables)                               │
│   • Oracle: Whitelist VPN sources only                          │
│   • Homelab: Rate limiting, connection tracking                 │
│   • Drop-by-default policies                                    │
│                                                                  │
│ LAYER 5: Kubernetes RBAC                                        │
│   • ArgoCD: Limited ServiceAccount (namespace-scoped)           │
│   • Developers: Read-only or specific namespace access          │
│   • Break-glass: cluster-admin (audited)                        │
│                                                                  │
│ LAYER 6: Network Policies                                       │
│   • Default deny all pod-to-pod traffic                         │
│   • Explicit allow rules per service                            │
│   • Deny egress except DNS, registry, external APIs            │
│                                                                  │
│ LAYER 7: Pod Security Standards                                 │
│   • Enforce "restricted" profile                                │
│   • No privileged containers                                    │
│   • Read-only root filesystems                                  │
│   • Drop all capabilities except required                       │
│                                                                  │
│ LAYER 8: Audit & Monitoring                                     │
│   • K3s API audit logs (all kubectl commands)                   │
│   • Oracle VCN Flow Logs (network traffic)                      │
│   • WireGuard connection logs                                   │
│   • Prometheus/Grafana/Loki (metrics & logs)                    │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

## Key Design Decisions Summary
```
┌──────────────────────────────────────────────────────────────────┐
│ ARCHITECTURE DECISIONS & RATIONALE                               │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│ ✓ Oracle as VPN Hub (not homelab)                               │
│   Why: Stable public IP, better uptime, simpler NAT traversal   │
│                                                                  │
│ ✓ Hub-and-Spoke VPN (not full mesh)                             │
│   Why: Simpler management, clearer routing, less peer config    │
│                                                                  │
│ ✓ MikroTik site-to-site (not individual peers per device)       │
│   Why: Centralized homelab access, one VPN tunnel for all       │
│                                                                  │
│ ✓ Single ArgoCD on homelab (not Oracle)                         │
│   Why: GitOps source of truth stays on-prem, controls both      │
│                                                                  │
│ ✓ Pull-based GitOps (not push)                                  │
│   Why: Better security, no credentials in CI, K8s-native        │
│                                                                  │
│ ✓ Separate break-glass network (10.99.2.0/24)                   │
│   Why: Clear separation, easy to audit, time-limited            │
│                                                                  │
│ ✓ VLAN segmentation on homelab                                  │
│   Why: Isolate IoT, protect management, separate workloads      │
│                                                                  │
│ ✓ blade005 as K3s master on separate link                       │
│   Why: Survives PoE switch failure, dedicated bandwidth         │
│                                                                  │
│ ✓ Different pod CIDRs per cluster                               │
│   Why: Avoid IP conflicts if clusters ever need to communicate  │
│                                                                  │
│ ✓ No bastion host (WireGuard instead)                           │
│   Why: VPN provides same function, saves resources              │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

## Resource Allocation
```
┌──────────────────────────────────────────────────────────────────┐
│ ORACLE CLOUD FREE TIER UTILIZATION                               │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│ Total Available: 4 ARM OCPU, 24GB RAM, 200GB storage            │
│                                                                  │
│ Allocation:                                                      │
│   K3s Master:  1.0 OCPU,  6GB RAM,  50GB storage                │
│   Worker 1:    1.5 OCPU,  9GB RAM,  75GB storage                │
│   Worker 2:    1.5 OCPU,  9GB RAM,  75GB storage                │
│   ─────────────────────────────────────────                     │
│   Total:       4.0 OCPU, 24GB RAM, 200GB storage ✅              │
│                                                                  │
│ Workload Distribution:                                           │
│   Master: K3s control plane, etcd, WireGuard, CoreDNS           │
│   Workers: Application pods, monitoring, logging                 │
│                                                                  │
│ Resource Requests (Reserved):                                    │
│   K3s system: ~0.5 OCPU, ~2GB RAM                               │
│   ArgoCD: N/A (runs on homelab)                                 │
│   Monitoring: ~0.3 OCPU, ~1GB RAM (if deployed)                 │
│   Available for apps: ~3 OCPU, ~20GB RAM                        │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────┐
│ HOMELAB RESOURCE UTILIZATION                                     │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│ Compute Blade Cluster: 5 nodes                                   │
│   Each: CM5 (4-core @ 2.4GHz, 4-8GB RAM, NVMe SSD)             │
│                                                                  │
│ Allocation:                                                      │
│   blade005 (Master): 1 node, dedicated link                      │
│   blade001-004 (Workers): 4 nodes, shared PoE switch            │
│                                                                  │
│ Total: 20 cores, 20-40GB RAM, 5x NVMe SSDs                      │
│                                                                  │
│ Power: 28-40W total (4-8W per blade)                            │
│        Well within 60W PoE budget                                │
│                                                                  │
│ Services Running:                                                │
│   • K3s cluster (homelab/staging workloads)                     │
│   • ArgoCD (manages both clusters)                              │
│   • Gitea (GitOps source of truth)                              │
│   • PostgreSQL (for ArgoCD, Gitea)                              │
│   • Node.js applications                                         │
│   • Prometheus/Grafana/Loki (monitoring)                        │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│ DNS ZONE OWNERSHIP                                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│ PUBLIC ZONES (🌍 Internet)                                      │
│   zengarden.space                                               │
│     Authoritative: Cloudflare                                   │
│     Writer:        external-dns (Oracle K3s)                    │
│     Ingress:       203.0.113.10:443 (Oracle public IP)         │
│     Purpose:       Production apps (retroboard.zengarden.space) │
│                                                                 │
│   homelab.zengarden.space                                       │
│     Authoritative: Cloudflare                                   │
│     Writer:        cloudflared Tunnel (Homelab)                 │
│     Ingress:       192.168.88.201 via Tunnel                    │
│     Purpose:       Selected public homelab apps (gitea)         │
│                                                                 │
│ INTERNAL ZONES (🔒 LAN/VPN Only)                                │
│   homelab.int.zengarden.space                                   │
│     Authoritative: MikroTik DNS (192.168.88.1)                  │
│     Writer:        external-dns (Homelab K3s)                   │
│     Ingress:       192.168.88.200 (MetalLB internal)           │
│     Purpose:       Internal homelab services (argocd, grafana)  │
│                                                                 │
│   prod.int.zengarden.space                                      │
│     Authoritative: CoreDNS (Oracle master 10.0.1.10)            │
│     Writer:        external-dns (Oracle K3s)                    │
│     Ingress:       10.0.2.x (Oracle private subnet)            │
│     Purpose:       Internal Oracle services (api)               │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘


┌─────────────────────────────────────────────────────────────────┐
│ DNS RESOLUTION FLOW                                             │
└─────────────────────────────────────────────────────────────────┘

                    ┌─────────────────────┐
                    │   CLOUDFLARE DNS    │
                    │   (Public Zones)    │
                    │                     │
                    │ • zengarden.space   │
                    │ • homelab           │
                    │   .zengarden.space  │
                    └──────────┬──────────┘
                               │
              ┌────────────────┼────────────────┐
              │                │                │
    ┌─────────▼───────┐ ┌─────▼──────┐  ┌─────▼──────┐
    │ Internet Users  │ │ VPN Users  │  │ LAN Users  │
    └─────────────────┘ └─────┬──────┘  └─────┬──────┘
                              │                │
                              │                │
                     ┌────────▼────────────────▼────────┐
                     │    INTERNAL DNS HIERARCHY        │
                     └────────┬─────────────────────────┘
                              │
                 ┌────────────┼────────────┐
                 │            │            │
        ┌────────▼──────┐  ┌──▼────────────────┐
        │ Oracle DNS Hub│  │ MikroTik DNS      │
        │ 10.99.0.1     │  │ 192.168.88.1      │
        │               │  │                   │
        │ Forwards:     │  │ Authoritative:    │
        │ homelab.int ──┼──┤ homelab.int       │
        │ prod.int      │  │                   │
        │ others        │  │ Forwards:         │
        └───────┬───────┘  │ prod.int → VPN    │
                │          └───────────────────┘
                │
       ┌────────▼─────────┐
       │ Oracle K3s       │
       │ CoreDNS          │
       │ 10.0.1.10        │
       │                  │
       │ Authoritative:   │
       │ prod.int         │
       └──────────────────┘


┌─────────────────────────────────────────────────────────────────┐
│ RESOLUTION EXAMPLES                                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│ 🌍 Internet User                                                │
│   retroboard.zengarden.space                                    │
│   → Cloudflare → 203.0.113.10 → Oracle ingress                 │
│                                                                 │
│   gitea.homelab.zengarden.space                                 │
│   → Cloudflare → Tunnel → 192.168.88.201 → Homelab ingress     │
│                                                                 │
│ 🏠 LAN User                                                     │
│   argocd.homelab.int.zengarden.space                            │
│   → MikroTik → 192.168.88.200 → Homelab ingress                │
│                                                                 │
│   api.prod.int.zengarden.space                                  │
│   → MikroTik → VPN → Oracle CoreDNS → 10.0.2.x                 │
│   ⚠️  Cannot reach (not on VPN)                                 │
│                                                                 │
│ 💻 VPN Developer                                                │
│   argocd.homelab.int.zengarden.space                            │
│   → Oracle hub → MikroTik → 192.168.88.200 → via VPN           │
│                                                                 │
│   api.prod.int.zengarden.space                                  │
│   → Oracle hub → Oracle CoreDNS → 10.0.2.x → via VPN           │
│                                                                 │
│   retroboard.zengarden.space                                    │
│   → Oracle hub → Cloudflare → 203.0.113.10 → public internet   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘


┌─────────────────────────────────────────────────────────────────┐
│ EXTERNAL-DNS WRITERS                                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│ Location           Provider    Domain Filter        Target DNS  │
│ ─────────────────  ──────────  ───────────────────  ────────── │
│ Oracle K3s         cloudflare  zengarden.space      Cloudflare  │
│ Oracle K3s         rfc2136     prod.int.zen...      10.0.1.10   │
│ Homelab K3s        rfc2136     homelab.int.zen...   MikroTik    │
│ Homelab cloudflared tunnel     homelab.zen...       Cloudflare  │
│                                                                 │
│ Key Rule: ONE writer per zone (no conflicts)                    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘


┌─────────────────────────────────────────────────────────────────┐
│ INGRESS CLASSES & IPS                                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│ Environment     Class      IP               Access     DNS Zone │
│ ─────────────── ────────── ──────────────── ────────── ──────── │
│ Homelab K3s     internal   192.168.88.200   LAN/VPN    .int     │
│ Homelab K3s     external   192.168.88.201   Tunnel     homelab  │
│ Oracle K3s      internal   10.0.2.x         VPN only   .int     │
│ Oracle K3s      external   203.0.113.10     Internet   apex     │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘


┌─────────────────────────────────────────────────────────────────┐
│ CERTIFICATES (Let's Encrypt DNS-01)                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│ Zone                      Issuer              Token Scope       │
│ ───────────────────────── ─────────────────── ───────────────── │
│ zengarden.space           letsencrypt-prod    Cloudflare (edit) │
│ homelab.zengarden.space   letsencrypt-prod    Cloudflare (edit) │
│ *.int.zengarden.space     letsencrypt-dns01   Cloudflare (edit) │
│                                                                 │
│ All certs use DNS-01 challenge (no HTTP-01 exposure)            │
│ Separate Cloudflare tokens per cluster (least privilege)        │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘


┌─────────────────────────────────────────────────────────────────┐
│ NAMING CONVENTIONS                                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│ Environment          Example FQDN                     Access    │
│ ──────────────────── ───────────────────────────────  ───────── │
│ Production Public    retroboard.zengarden.space       Internet  │
│ Homelab Public       gitea.homelab.zengarden.space    Internet  │
│ Homelab Internal     argocd.homelab.int.zen...        LAN/VPN   │
│ Production Internal  api.prod.int.zengarden.space     VPN only  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘


┌─────────────────────────────────────────────────────────────────┐
│ SECURITY RULES                                                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│ ❌ No wildcard *.zengarden.space at apex (prevents exposure)    │
│ ✅ One writer per zone (prevents TXT conflicts)                 │
│ 🔒 .int zones only on LAN/VPN (not public)                      │
│ 🌍 Public names via Cloudflare CDN or Tunnel                    │
│ 🔑 Separate API tokens per cluster                              │
│ 🧱 Public ingress: 80/443 only (iptables/NSG)                   │
│ 🧾 DNS-01 for all certs (no HTTP-01 exposure)                   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘


┌─────────────────────────────────────────────────────────────────┐
│ KEY DESIGN DECISIONS                                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│ ✓ Split-horizon DNS (.int for internal, apex for public)       │
│ ✓ Oracle DNS hub (10.99.0.1) for VPN users                     │
│ ✓ MikroTik DNS for LAN conditional forwarding                  │
│ ✓ Cloudflare Tunnel for selective homelab exposure             │
│ ✓ No wildcard DNS (explicit entries only)                      │
│ ✓ external-dns automates record management                     │
│ ✓ cert-manager + DNS-01 for all HTTPS                          │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘