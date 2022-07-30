#!/usr/bin/env bash

set -e


cleanup() {
    if [[ $openvpn_child ]]; then
        kill SIGTERM "$openvpn_child"
    fi

    sleep 0.5
    rm -f "$modified_config_file"
    echo "info: exiting"
    exit 0
}

is_enabled() {
    [[ ${1,,} =~ ^(true|t|yes|y|1|on|enable|enabled)$ ]]
}

mkdir -p /data/{config,scripts,vpn}

echo "--- Running with the following variables ---"

if [[ $VPN_CONFIG_FILE ]]; then
    echo "VPN configuration file: $VPN_CONFIG_FILE"
fi
if [[ $VPN_CONFIG_PATTERN ]]; then
    echo "VPN configuration file name pattern: $VPN_CONFIG_PATTERN"
fi

echo "Use default resolv.conf: ${USE_VPN_DNS:-off}
Allowing subnets: ${SUBNETS:-none}
Kill switch: $KILL_SWITCH
Using OpenVPN log level: $VPN_LOG_LEVEL"

if is_enabled "$HTTP_PROXY"; then
    echo "HTTP proxy: $HTTP_PROXY"
    if is_enabled "$HTTP_PROXY_USERNAME"; then
        echo "HTTP proxy username: $HTTP_PROXY_USERNAME"
    elif is_enabled "$HTTP_PROXY_USERNAME_SECRET"; then
        echo "HTTP proxy username secret: $HTTP_PROXY_USERNAME_SECRET"
    fi
fi
if is_enabled "$SOCKS_PROXY"; then
    echo "SOCKS proxy: $SOCKS_PROXY"
    if [[ $SOCKS_LISTEN_ON ]]; then
        echo "Listening on: $SOCKS_LISTEN_ON"
    fi
    if is_enabled "$SOCKS_PROXY_USERNAME"; then
        echo "SOCKS proxy username: $SOCKS_PROXY_USERNAME"
    elif is_enabled "$SOCKS_PROXY_USERNAME_SECRET"; then
        echo "SOCKS proxy username secret: $SOCKS_PROXY_USERNAME_SECRET"
    fi
fi

echo "---"

if [[ $VPN_CONFIG_FILE ]]; then
    original_config_file=vpn/$VPN_CONFIG_FILE
elif [[ $VPN_CONFIG_PATTERN ]]; then
    original_config_file=$(find vpn -name "$VPN_CONFIG_PATTERN" 2> /dev/null | sort | shuf -n 1)
else
    original_config_file=$(find vpn -name '*.conf' -o -name '*.ovpn' 2> /dev/null | sort | shuf -n 1)
fi

if [[ -z $original_config_file ]]; then
    >&2 echo 'erro: no vpn configuration file found'
    exit 1
fi

echo "info: original configuration file: $original_config_file"

# Create a new configuration file to modify so the original is left untouched.
modified_config_file=vpn/openvpn.$(tr -dc A-Za-z0-9 </dev/urandom | head -c8).conf
trap cleanup SIGTERM

echo "info: modified configuration file: $modified_config_file"
grep -Ev '(^up\s|^down\s)' "$original_config_file" > "$modified_config_file"

# Remove carriage returns (\r) from the config file
sed -i 's/\r$//g' "$modified_config_file"


#default_gateway=$(ip -4 route | grep 'default via' | awk '{print $3}')


if is_enabled "$HTTP_PROXY" ; then
    scripts/run-http-proxy.sh &
fi

if is_enabled "$SOCKS_PROXY" ; then
    scripts/run-socks-proxy.sh &
fi

openvpn_args=(
    "--config" "$modified_config_file"
    "--auth-nocache"
    "--cd" "vpn"
    "--pull-filter" "ignore" "ifconfig-ipv6 "
    "--pull-filter" "ignore" "route-ipv6 "
    "--script-security" "2"
    "--up-restart"
    "--verb" "$VPN_LOG_LEVEL"
)

if is_enabled "$USE_VPN_DNS" ; then
    openvpn_args+=(
        "--up" "/etc/openvpn/up.sh"
        "--down" "/etc/openvpn/down.sh"
    )
fi

if [[ $VPN_AUTH_SECRET ]]; then
    openvpn_args+=("--auth-user-pass" "/run/secrets/$VPN_AUTH_SECRET")
fi

openvpn "${openvpn_args[@]}" & openvpn_child=$!

wait $openvpn_child




