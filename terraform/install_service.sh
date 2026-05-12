#!/bin/bash
cat > /etc/systemd/system/cacms-api.service << 'SVCEOF'
[Unit]
Description=CACMS FastAPI Backend
After=network.target redis-server.service
Wants=redis-server.service

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/home/ubuntu/cacms
EnvironmentFile=/home/ubuntu/cacms/.env.production
ExecStart=/home/ubuntu/cacms/.venv/bin/uvicorn cacms.main:app --host 0.0.0.0 --port 8000 --workers 2
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=cacms-api

[Install]
WantedBy=multi-user.target
SVCEOF

systemctl daemon-reload
systemctl enable cacms-api
systemctl start cacms-api
sleep 8
systemctl is-active cacms-api && echo SERVICE_ACTIVE || echo SERVICE_FAILED
curl -sf http://localhost:8000/health && echo API_HEALTHY || echo API_NOT_READY
