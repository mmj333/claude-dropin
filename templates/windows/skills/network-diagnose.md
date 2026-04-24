---
name: network-diagnose
description: Diagnose Windows network issues — no internet, slow Wi-Fi, DNS failures, captive-portal weirdness. Collects adapter state, IP config, DNS behavior, and runs a short connectivity matrix.
---

# Network diagnose

Invoke for any network complaint.

## Steps

1. **Adapter status**
   ```powershell
   Get-NetAdapter | Format-Table Name, InterfaceDescription, Status, LinkSpeed, MacAddress
   ```

2. **IP config**
   ```
   ipconfig /all
   ```

3. **Routing + DNS**
   ```powershell
   Get-NetRoute -AddressFamily IPv4 | Sort-Object RouteMetric | Select-Object -First 5
   Get-DnsClientServerAddress -AddressFamily IPv4
   ```

4. **Connectivity matrix** — test L2, L3, DNS, HTTP independently:
   ```
   ping -n 2 <default-gateway-from-ipconfig>
   ping -n 2 1.1.1.1
   ping -n 2 cloudflare.com
   curl -s -o NUL -w "%{http_code}\n" https://www.google.com
   ```
   Failures isolate the layer:
   - Gateway fails → cable / Wi-Fi / bridge problem
   - Gateway ok, 1.1.1.1 fails → routing / ISP
   - 1.1.1.1 ok, cloudflare.com fails → DNS
   - DNS ok, HTTPS fails → proxy / cert / captive portal

5. **Wi-Fi specifics** (if on wireless)
   ```
   netsh wlan show interfaces
   netsh wlan show profiles
   ```

6. **Firewall / proxy hints**
   ```powershell
   Get-NetFirewallProfile | Select-Object Name, Enabled, DefaultInboundAction, DefaultOutboundAction
   [System.Net.WebRequest]::DefaultWebProxy.GetProxy('https://www.google.com')
   ```

## Output format

`work/<ticket>-network.md` with:

- Adapter + link-speed summary
- IPv4 config table
- Connectivity matrix results (L2/L3/DNS/HTTPS)
- Identified failure layer
- Suggested remediation
