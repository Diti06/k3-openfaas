import math

def handle(event, context):
    try:
        n = int(event.body.decode('utf-8').strip()) if event.body else 10
        result = math.factorial(n)
        return {"statusCode": 200, "body": f"factorial({n}) = {result}\n"}
    except Exception as e:
        return {"statusCode": 400, "body": f"Error: {str(e)}\n"}
