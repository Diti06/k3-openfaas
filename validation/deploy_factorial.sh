#!/bin/bash
faas-cli template store pull python3-http
faas-cli new factorial --lang python3-http

cat > factorial/handler.py << 'EOF'
def handle(event, context):
    try:
        n = int(event.body)
        result = 1
        for i in range(2, n + 1):
            result *= i
        return {"statusCode": 200, "body": str(result)}
    except Exception as e:
        return {"statusCode": 400, "body": str(e)}
EOF

# Add scaling labels to factorial.yml
faas-cli deploy --image ghcr.io/openfaas/cron-connector:latest \
  --name factorial \
  --env RAW_BODY=true

# OR use a pre-built image for quick testing # quick smoke test alternative
faas-cli store deploy nodeinfo \
  --name factorial \
  --gateway http://127.0.0.1:8080