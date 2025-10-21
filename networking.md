
┌─────────────────────────────────────────────────────────────────┐
│ COMPLETE IP ALLOCATION SCHEME                                   │
├─────────────────────────────────────────────────────────────────┤
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


## Homelab Physical Network
```
┌──────────────────────────────────────────────────────────────────┐
│ MIKROTIK CHATEAU LTE18 - PHYSICAL PORT LAYOUT                   │
└──────────────────────────────────────────────────────────────────┘

Port Assignments:
  eth1 (1Gbps)   → Optical WAN
  eth2 (1Gbps)   → VLAN11 K3s → Zyxel PoE Switch → blade001-004
  eth3 (1Gbps)   → VLAN11 K3s → blade005 (direct)
  eth4 (1Gbps)   → VLAN88 home
  eth5 (2.5Gbps) → VLAN100 management
  
  wlan1 (2.4GHz) → "Home-WiFi" (VLAN88)
  wlan2 (5GHz)   → "Home-WiFi-5G" (VLAN88)
  
  lte1           → Cellular WAN (failover)

┌──────────────────────────────────────────────────────────────────┐
│ VLAN SEGMENTATION & FIREWALL RULES                              │
└──────────────────────────────────────────────────────────────────┘

VLAN88 (Home Network - 192.168.88.0/24)
  ├─ Devices: Laptops, phones, PCs, TVs, HA, IoT
  ├─ Access: Internet (full), K3s services (limited)
  └─ Firewall: Can access VLAN11 | Block VLAN100

VLAN11 (K3s Cluster - 192.168.11.0/24)
  ├─ Devices: 5x Compute Blade CM5
  ├─ Access: Internet, limited to VLAN11
  └─ Firewall: Allow VPN |o Block VLAN88→11 except specific ports

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
    ┌───────┼────────┬────────┐
    │       │        │        │        
┌───▼──┐ ┌──▼───┐ ┌──▼───┐ ┌───▼──┐
│blade1│ │blade2│ │blade3│ │blade4│
│ 001  │ │ 002  │ │ 003  │ │ 004  │
│.77.11│ │.77.12│ │.77.13│ │.77.14│
│Worker│ │Worker│ │Worker│ │Worker│
└──────┘ └──────┘ └──────┘ └──────┘

Each Compute Blade:
  • Raspberry Pi CM5 (Cortex-A76 quad-core @ 2.4GHz)
  • 8GB or 16GB RAM
  • NVMe SSD (M.2 2230/2242/2260/2280)
  • Powered via PoE+ (802.3at, up to 30W)
  • Actual power: 4-7W typical, up to 10W with NVMe
  • Gigabit Ethernet
  • Total cluster: 28-40W under load
```

┌─────────────────────────────────────────────────────────────────┐
│ DNS ZONE OWNERSHIP                                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│ PUBLIC ZONES (🌍 Internet)                                      │
│   zengarden.space                                               │
│     Authoritative: Cloudflare                                   │
│     Writer:        external-dns (Homelab K3S)                   │
│     Ingress:       203.0.113.10:443 (Oracle public IP)          │
│     Purpose:       Production/demo apps                         │
│                                                                 │
│   homelab.zengarden.space                                       │
│     Authoritative: Cloudflare                                   │
│     Writer:        cloudflared Tunnel (Homelab K3S)             │
│     Ingress:       192.168.88.201 via Tunnel                    │
│     Purpose:       Selected public homelab apps                 │
│                                                                 │
│ INTERNAL ZONES (🔒 LAN/VPN Only)                                │
│   homelab.int.zengarden.space                                   │
│     Authoritative: MikroTik DNS (192.168.88.1)                  │
│     Writer:        external-dns (Homelab K3s)                   │
│     Ingress:       192.168.88.200 (MetalLB internal)            │
│     Purpose:       Internal homelab services (argocd, grafana)  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘


# MikroTik WebFig Configuration Guide

I'll guide you through each step with WebFig instructions. We'll set up WireGuard first (no downtime), test it, then transition the cluster to VLAN77.

---

## **STEP 1: Configure WireGuard VPN**

### 1.1 Generate WireGuard Keys

**WebFig → WireGuard → Keys**
1. Click **[+]** (Add New)
2. Leave everything default
3. Click **Apply** → **OK**
4. Note the **Public Key** (you'll need this later)
5. Remember the key name (usually `wireguard1`)

### 1.2 Create WireGuard Interface

**WebFig → Interfaces → (+) → WireGuard**
- **Name:** `wireguard-vpn`
- **MTU:** `1420`
- **Listen Port:** `51820`
- **Private Key:** Select the key you just created
- Click **Apply** → **OK**

### 1.3 Assign IP to WireGuard Interface

**WebFig → IP → Addresses → (+)**
- **Address:** `10.8.0.1/24`
- **Interface:** `wireguard-vpn`
- Click **Apply** → **OK**

### 1.4 Add Firewall Rule to Allow WireGuard

**WebFig → IP → Firewall → Filter Rules → (+)**
- **Chain:** `input`
- **Protocol:** `udp`
- **Dst. Port:** `51820`
- **Action:** `accept`
- **Comment:** `Allow WireGuard VPN`
- Move this rule to the **top** (drag or use ↑ arrows)
- Click **Apply** → **OK**

---

## **STEP 2: Test WireGuard from Outside**

### 2.1 Create First Peer (Your Test Device)

**WebFig → WireGuard → Peers → (+)**
- **Interface:** `wireguard-vpn`
- **Public Key:** `[PASTE CLIENT PUBLIC KEY - generate on your laptop]`
- **Allowed Address:** `10.8.0.2/32`
- **Comment:** `dev-laptop-test`
- Click **Apply** → **OK**

### 2.2 Generate Client Configuration

**On your laptop/phone** (install WireGuard client first):

Generate client keys:
```bash
# Linux/Mac
wg genkey | tee privatekey | wg pubkey > publickey

# Windows: Use WireGuard GUI (generates automatically)
```

Create client config file `homelab-vpn.conf`:
```ini
[Interface]
PrivateKey = [YOUR_CLIENT_PRIVATE_KEY]
Address = 10.8.0.2/32
DNS = 192.168.77.1

[Peer]
PublicKey = [MIKROTIK_PUBLIC_KEY_FROM_STEP_1.1]
Endpoint = [YOUR_PUBLIC_IP]:51820
AllowedIPs = 10.8.0.0/24, 192.168.77.0/24
PersistentKeepalive = 25
```

### 2.3 Find Your Public IP

**WebFig → IP → Cloud**
- Enable **Cloud DDNS** (free)
- Wait 30 seconds
- Note your **DNS Name** (e.g., `abc123xyz.sn.mynetname.net`)
- OR check **Public Address** field

Alternative: Visit https://ifconfig.me from your home network

### 2.4 Test Connection

**From outside your network** (disable home WiFi, use mobile data):

1. **Import config** into WireGuard client
2. **Connect** to the VPN
3. **Test connectivity:**
   ```bash
   ping 10.8.0.1  # Should work - MikroTik WireGuard interface
   ```

4. **Check MikroTik:**
   - **WebFig → WireGuard → Peers**
   - Your peer should show **Last Handshake** (recent timestamp)
   - **Rx/Tx** counters should increment

✅ **If ping works, WireGuard is configured correctly!**

---

## **STEP 3: Add VLAN77 Network** (Preparation - No Downtime)

### 3.1 Create VLAN77 Interface on eth2

**WebFig → Interfaces → (+) → VLAN**
- **Name:** `vlan77-k3s`
- **VLAN ID:** `77`
- **Interface:** `eth2` (Zyxel switch)
- Click **Apply** → **OK**

### 3.2 Create VLAN77 Interface on eth3

**WebFig → Interfaces → (+) → VLAN**
- **Name:** `vlan77-blade5`
- **VLAN ID:** `77`
- **Interface:** `eth3` (blade005 direct)
- Click **Apply** → **OK**

### 3.3 Create Bridge for VLAN77

**WebFig → Bridge → (+)**
- **Name:** `bridge-vlan77`
- **Admin MAC Address:** (leave auto)
- **Protocol Mode:** `none`
- Click **Apply** → **OK**

### 3.4 Add VLAN Interfaces to Bridge

**WebFig → Bridge → Ports → (+)**
- **Interface:** `vlan77-k3s`
- **Bridge:** `bridge-vlan77`
- Click **Apply** → **OK**

**Repeat:**
- **Interface:** `vlan77-blade5`
- **Bridge:** `bridge-vlan77`
- Click **Apply** → **OK**

### 3.5 Assign IP to VLAN77 Bridge

**WebFig → IP → Addresses → (+)**
- **Address:** `192.168.77.1/24`
- **Interface:** `bridge-vlan77`
- Click **Apply** → **OK**

### 3.6 Enable DHCP Server for VLAN77 (Optional)

**WebFig → IP → DHCP Server → DHCP Setup**
- **DHCP Server Interface:** `bridge-vlan77`
- Follow wizard:
  - **Address Space:** `192.168.77.0/24`
  - **Gateway:** `192.168.77.1`
  - **Address Pool:** `192.168.77.20-192.168.77.100`
  - **DNS Servers:** `192.168.77.1` (or `1.1.1.1,8.8.8.8`)
  - **Lease Time:** `10m` (for testing), later change to `1d`
- Click **OK** through all steps

---

## **STEP 4: Configure Firewall - VPN Access Only to VLAN77**

### 4.1 Add NAT Rule for VPN (if needed for internet)

**WebFig → IP → Firewall → NAT → (+)**
- **Chain:** `srcnat`
- **Src. Address:** `10.8.0.0/24`
- **Out. Interface:** `eth1` (or your WAN interface)
- **Action:** `masquerade`
- **Comment:** `VPN internet access`
- Click **Apply** → **OK**

### 4.2 Allow VPN → VLAN77

**WebFig → IP → Firewall → Filter Rules → (+)**
- **Chain:** `forward`
- **Src. Address:** `10.8.0.0/24`
- **Dst. Address:** `192.168.77.0/24`
- **Action:** `accept`
- **Comment:** `Allow VPN to K3s VLAN77`
- **Move to top** of forward chain (above any drop rules)
- Click **Apply** → **OK**

### 4.3 Block VPN → VLAN88 (Home)

**WebFig → IP → Firewall → Filter Rules → (+)**
- **Chain:** `forward`
- **Src. Address:** `10.8.0.0/24`
- **Dst. Address:** `192.168.88.0/24`
- **Action:** `reject`
- **Reject With:** `icmp-network-unreachable`
- **Comment:** `Block VPN to Home VLAN88`
- Click **Apply** → **OK**

### 4.4 Block VPN → VLAN100 (Management)

**WebFig → IP → Firewall → Filter Rules → (+)**
- **Chain:** `forward`
- **Src. Address:** `10.8.0.0/24`
- **Dst. Address:** `192.168.100.0/24`
- **Action:** `reject`
- **Reject With:** `icmp-network-unreachable`
- **Comment:** `Block VPN to Management VLAN100`
- Click **Apply** → **OK**

### 4.5 Allow VPN → K3s Pod/Service Networks

**WebFig → IP → Firewall → Filter Rules → (+)**
- **Chain:** `forward`
- **Src. Address:** `10.8.0.0/24`
- **Dst. Address:** `10.42.0.0/16`
- **Action:** `accept`
- **Comment:** `Allow VPN to K3s Pods`
- Click **Apply** → **OK**

**Repeat for Services:**
- **Chain:** `forward`
- **Src. Address:** `10.8.0.0/24`
- **Dst. Address:** `10.43.0.0/16`
- **Action:** `accept`
- **Comment:** `Allow VPN to K3s Services`
- Click **Apply** → **OK**

### 4.6 Update WireGuard Client Config

Update your `homelab-vpn.conf`:
```ini
[Interface]
PrivateKey = [YOUR_CLIENT_PRIVATE_KEY]
Address = 10.8.0.2/32
DNS = 192.168.77.1

[Peer]
PublicKey = [MIKROTIK_PUBLIC_KEY]
Endpoint = [YOUR_PUBLIC_IP]:51820
AllowedIPs = 10.8.0.0/24, 192.168.77.0/24, 10.42.0.0/16, 10.43.0.0/16
PersistentKeepalive = 25
```

---

## **STEP 5: Test Everything**

### 5.1 Test VPN → VLAN77 (Before Migrating Cluster)

**Connect via VPN and test:**
```bash
ping 192.168.77.1    # Should work - MikroTik gateway
ping 192.168.88.1    # Should FAIL - blocked by firewall
ping 192.168.100.1   # Should FAIL - blocked by firewall
```

✅ **Firewall isolation working!**

### 5.2 Migrate K3s Cluster to VLAN77 (Minimal Downtime)

**⚠️ This is the only step that causes brief downtime**

**Option A: Zyxel Switch Configuration (if web-managed)**
1. Access Zyxel switch web interface
2. Go to **VLAN → 802.1Q VLAN**
3. Change ports 1-4 from VLAN11 → VLAN77
4. Set **PVID** to `77`
5. Apply changes

**Option B: Manual (if unmanaged switch)**
You'll need to configure VLAN tagging on each blade's network interface.

**On each K3s node** (blade001-005):
```bash
# SSH to each blade
sudo nmcli connection modify eth0 \
  802-1x.vlan-id 77 \
  ipv4.addresses 192.168.77.11/24 \
  ipv4.gateway 192.168.77.1 \
  ipv4.dns 192.168.77.1

sudo nmcli connection down eth0 && sudo nmcli connection up eth0
```

Assign IPs:
- blade001: `192.168.77.11`
- blade002: `192.168.77.12`
- blade003: `192.168.77.13`
- blade004: `192.168.77.14`
- blade005: `192.168.77.15`

**Downtime: ~2-5 minutes per blade**

### 5.3 Final Tests via VPN

**After cluster migration:**
```bash
# From VPN connection
ping 192.168.77.11   # blade001
ping 192.168.77.15   # blade005
ssh pi@192.168.77.15 # Should work
```

**Test K3s services:**
```bash
curl http://192.168.77.15:6443  # K3s API (if exposed)
# Or test your specific services
```

### 5.4 Verify Firewall Logs

**WebFig → Log**
- Look for rejected packets from `10.8.0.0/24` to `192.168.88.0/24`
- Confirms firewall is blocking home network access

---

## **🎯 Summary Checklist**

- [ ] WireGuard configured on MikroTik
- [ ] Can connect from outside via VPN
- [ ] VLAN77 created and configured
- [ ] K3s cluster migrated to 192.168.77.0/24
- [ ] Firewall allows VPN → VLAN77 only
- [ ] Firewall blocks VPN → VLAN88, VLAN100
- [ ] Can access K3s services via VPN
- [ ] Cannot access home network via VPN

---

## **🔧 Troubleshooting**

**VPN connects but can't ping anything:**
```
WebFig → IP → Routes → Check for 192.168.77.0/24 route
Should show: dst=192.168.77.0/24 gateway=bridge-vlan77
```

**Can't ping blade IPs:**
- Verify VLAN77 is configured on Zyxel switch
- Check blade IPs are in 192.168.77.0/24 range
- Check cables are connected to correct ports

**WireGuard won't connect:**
- Verify port 51820 UDP is open (check firewall rule is at top)
- Verify your public IP hasn't changed
- Check WireGuard peers in WebFig show "Last Handshake"

Need help with any specific step?