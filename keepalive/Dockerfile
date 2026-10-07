# Service Railway « keepalive » : un processus permanent qui appelle /health toutes les
# 5 minutes, sans jamais s'arrêter. Voir docs/architecture.md §9.
FROM curlimages/curl:8.10.1
ENV CIBLE=https://mon-petit-podium-production.up.railway.app/health \
    INTERVALLE=300
# Un échec de curl est journalisé, jamais fatal : la boucle continue.
ENTRYPOINT ["sh", "-c", "while true; do curl -sS --retry 2 --max-time 60 -o /dev/null -w \"ping %{http_code} en %{time_total}s\\n\" \"$CIBLE\" || echo \"ping en échec\"; sleep \"$INTERVALLE\"; done"]
