import json
import boto3
import uuid
import os
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

TABLE_NAME = os.environ.get('TABLE_NAME', 'NotesTable')
dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(TABLE_NAME)

def lambda_handler(event, context):
    try:
        authorizer = event.get('requestContext', {}).get('authorizer', {})
        
        jwt_claims = authorizer.get('jwt', {}).get('claims')
        
        if not jwt_claims:
            jwt_claims = authorizer.get('claims', {})
            
        user_id = jwt_claims.get('sub')
        
        if not user_id:
            logger.error(f"Unauthorized attempt. Payload received: {json.dumps(event)}")
            return {"statusCode": 401, "body": json.dumps("Unauthorized - Missing Sub Claim")}

        body = json.loads(event.get('body', '{}'))
        note_content = body.get('Note')
        
        if not note_content:
            return {"statusCode": 400, "body": json.dumps("Note content is required.")}
            
        note_id = str(uuid.uuid4())
        
        table.put_item(
            Item={
                'UserId': user_id,
                'NoteId': note_id,
                'Note': note_content
            }
        )
        
        logger.info(json.dumps({"message": "Note created successfully", "user_id": user_id, "note_id": note_id}))
        
        return {
            'statusCode': 201,
            'headers': {
                'Content-Type': 'application/json'
            },
            'body': json.dumps({'NoteId': note_id, 'Message': 'Successfully saved note'})
        }
        
    except json.JSONDecodeError:
        logger.error("Invalid JSON payload provided.")
        return {"statusCode": 400, "body": json.dumps("Invalid JSON payload")}
    except Exception as e:
        logger.exception("Internal Server Error occurred.")
        return {"statusCode": 500, "body": json.dumps("Internal Server Error")}