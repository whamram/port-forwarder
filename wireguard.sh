#!/bin/bash

# iptables Port Forwarding Script

# Default variables
PROTOCOL="tcp"  # Default protocol
EXT_IFACE="eth0"  # External interface (default: eth0)
VPN_IFACE=""  # VPN interface (required, e.g., wg0, tailscale0)

# Function to display usage
usage() {
    echo "Usage: $0 -n VPN_IFACE [-e EXT_IFACE] [-i IP_ADDRESS] [-p PORT] [-r PORT] [-f] [-x] [-s] [-c]"
    echo "Note: -n must be specified before -p, -r, -f, or -c. -i must also be specified before these options."
    echo "  -n VPN_IFACE    Set the VPN interface (required, e.g., wg0, tailscale0)."
    echo "  -e EXT_IFACE    Set the external interface. Default is eth0."
    echo "  -i IP_ADDRESS   Set the IP address for port forwarding."
    echo "  -l PROTOCOL     Set the protocol for port forwarding (tcp/udp). Default is tcp."
    echo "  -p PORT         Initialize port forwarding for the specified port and IP address."
    echo "  -r PORT         Remove port forwarding for the specified port and IP address."
    echo "  -f              Enable forwarding of traffic out to the internet for the specified IP address."
    echo "  -x              Reset all port forwarding rules to default."
    echo "  -s              Show current port forwarding rules"
    echo "  -c              Remove port forwarding from the specified IP address to the internet."
    exit 1
}

# Check if the script is run as root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root."
    exit 1
fi

IP_ADDRESS=""
while getopts "n:e:i:l:p:r:fxsc" opt; do
    case $opt in
        n)
            VPN_IFACE=$OPTARG
            ;;
        e)
            EXT_IFACE=$OPTARG
            ;;
        i)
            IP_ADDRESS=$OPTARG
            ;;
        l)
            PROTOCOL=$OPTARG
            if [[ "$PROTOCOL" != "tcp" && "$PROTOCOL" != "udp" ]]; then
                echo "Error: Invalid protocol specified. Use 'tcp' or 'udp'."
                exit 1
            fi
            ;; 
        p)
            if [[ -z $VPN_IFACE ]]; then
                echo "Error: VPN interface (-n) must be set before initializing port forwarding."
                usage
            fi
            if [[ -z $IP_ADDRESS ]]; then
                echo "Error: IP address must be set before initializing port forwarding."
                usage
            fi
            PORT=$OPTARG
            if [[ $PORT -eq 2222 ]]; then
                echo "Error: Port 2222 is not allowed."
                exit 1
            fi
            echo "Initializing port forwarding for port $PORT to IP $IP_ADDRESS on $VPN_IFACE..."

            # Set prerouting, postrouting, and forwarding rules and check for duplicates
            { iptables -t nat -C PREROUTING -p "$PROTOCOL" -i "$EXT_IFACE" --dport "$PORT" -j DNAT --to-destination "$IP_ADDRESS:$PORT" 2>/dev/null || \
            iptables -t nat -A PREROUTING -p "$PROTOCOL" -i "$EXT_IFACE" --dport "$PORT" -j DNAT --to-destination "$IP_ADDRESS:$PORT"; } && \
            { iptables -t nat -C POSTROUTING -p "$PROTOCOL" -o "$VPN_IFACE" -d "$IP_ADDRESS" --dport "$PORT" -j MASQUERADE 2>/dev/null || \
            iptables -t nat -A POSTROUTING -p "$PROTOCOL" -o "$VPN_IFACE" -d "$IP_ADDRESS" --dport "$PORT" -j MASQUERADE; } && \
            { iptables -C FORWARD -i "$EXT_IFACE" -o "$VPN_IFACE" -p "$PROTOCOL" -d "$IP_ADDRESS" --dport "$PORT" -j ACCEPT 2>/dev/null || \
            iptables -A FORWARD -i "$EXT_IFACE" -o "$VPN_IFACE" -p "$PROTOCOL" -d "$IP_ADDRESS" --dport "$PORT" -j ACCEPT; } && \
            echo "Port forwarding initialized." || echo "Error: Failed to initialize port forwarding."
            ;;
        r)
            if [[ -z $VPN_IFACE ]]; then
                echo "Error: VPN interface (-n) must be set before removing port forwarding."
                usage
            fi
            if [[ -z $IP_ADDRESS ]]; then
                echo "Error: IP address must be set before removing port forwarding."
                usage
            fi
            PORT=$OPTARG
            if [[ $PORT -eq 2222 ]]; then
                echo "Error: Port 2222 is not allowed."
                exit 1
            fi
            iptables -t nat -D PREROUTING -p "$PROTOCOL" -i "$EXT_IFACE" --dport "$PORT" -j DNAT --to-destination "$IP_ADDRESS:$PORT" && \
            iptables -t nat -D POSTROUTING -p "$PROTOCOL" -o "$VPN_IFACE" -d "$IP_ADDRESS" --dport "$PORT" -j MASQUERADE && \
            iptables -D FORWARD -i "$EXT_IFACE" -o "$VPN_IFACE" -p "$PROTOCOL" -d "$IP_ADDRESS" --dport "$PORT" -j ACCEPT && \
            echo "Port forwarding removed." || echo "Error: Failed to remove port forwarding."
            ;;
        x)
            echo "Resetting all port forwarding rules to default..."
            iptables -t nat -F
            iptables -F FORWARD
            echo "All port forwarding rules reset."
            ;;
        f)
            if [[ -z $VPN_IFACE ]]; then
                echo "Error: VPN interface (-n) must be set before initializing forwarding."
                usage
            fi
            if [[ -z $IP_ADDRESS ]]; then
                echo "Error: IP address must be set before initializing forwarding."
                usage
            fi
            echo "Initializing forwarding from $IP_ADDRESS to the internet via $VPN_IFACE..."
            { iptables -t nat -C POSTROUTING -s "$IP_ADDRESS" -o "$EXT_IFACE" -j MASQUERADE 2>/dev/null || \
            iptables -t nat -A POSTROUTING -s "$IP_ADDRESS" -o "$EXT_IFACE" -j MASQUERADE; } && \
            { iptables -C FORWARD -i "$VPN_IFACE" -s "$IP_ADDRESS" -o "$EXT_IFACE" -j ACCEPT 2>/dev/null || \
            iptables -A FORWARD -i "$VPN_IFACE" -s "$IP_ADDRESS" -o "$EXT_IFACE" -j ACCEPT; } && \
            echo "Forwarding initialized." || echo "Error: Failed to initialize forwarding."
            ;;
        s)
            iptables -t nat -L -n -v
            ;;
        c)
            if [[ -z $VPN_IFACE ]]; then
                echo "Error: VPN interface (-n) must be set before removing forwarding."
                usage
            fi
            if [[ -z $IP_ADDRESS ]]; then
                echo "Error: IP address must be set before removing forwarding."
                usage
            fi
            echo "Removing forwarding from IP $IP_ADDRESS to the internet..."
            iptables -t nat -D POSTROUTING -s "$IP_ADDRESS" -o "$EXT_IFACE" -j MASQUERADE && \
            iptables -D FORWARD -i "$VPN_IFACE" -s "$IP_ADDRESS" -o "$EXT_IFACE" -j ACCEPT && \
            echo "Forwarding removed." || echo "Error: Failed to remove forwarding."
            ;;
        *)
            usage
            ;;
    esac
done

if [[ $OPTIND -eq 1 ]]; then
    usage
fi
