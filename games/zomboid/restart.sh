docker compose down --remove-orphans --timeout 60
ss -lunp | grep -E '1626(1|2)\>' && { echo "ports still busy"; exit 1; }
sleep 5                               # lets iptables rules vanish
docker compose up -d
