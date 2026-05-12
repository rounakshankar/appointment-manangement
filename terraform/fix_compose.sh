#!/bin/bash
# Add missing env vars to docker-compose.aws.yml
COMPOSE=/home/ubuntu/cacms/docker-compose.aws.yml

# Add SUPERADMIN_TOKEN after SENTRY_TRACES_SAMPLE_RATE line
python3 - << 'PYEOF'
import re

with open('/home/ubuntu/cacms/docker-compose.aws.yml', 'r') as f:
    content = f.read()

# Add missing env vars if not already present
additions = """      SUPERADMIN_TOKEN: ${SUPERADMIN_TOKEN:-}
      OTP_TTL_SECONDS: ${OTP_TTL_SECONDS:-300}
      JWT_EXPIRE_MINUTES: ${JWT_EXPIRE_MINUTES:-60}
      JWT_ALGORITHM: ${JWT_ALGORITHM:-HS256}"""

if 'SUPERADMIN_TOKEN' not in content:
    content = content.replace(
        '      SENTRY_TRACES_SAMPLE_RATE: ${SENTRY_TRACES_SAMPLE_RATE:-0.1}',
        '      SENTRY_TRACES_SAMPLE_RATE: ${SENTRY_TRACES_SAMPLE_RATE:-0.1}\n' + additions
    )
    with open('/home/ubuntu/cacms/docker-compose.aws.yml', 'w') as f:
        f.write(content)
    print("COMPOSE_UPDATED")
else:
    print("ALREADY_HAS_SUPERADMIN_TOKEN")
PYEOF
