# Service cron Railway « keepalive » : un appel à /ping, puis le conteneur s'arrête.
# Railway le relance toutes les 5 minutes (railway.json). Voir docs/architecture.md §9.
FROM curlimages/curl:8.10.1
ENTRYPOINT ["curl", "-fsS", "--retry", "2", "--max-time", "60", "-o", "/dev/null", "-w", "ping %{http_code} en %{time_total}s\n"]
CMD ["https://mon-petit-podium-production.up.railway.app/ping"]
