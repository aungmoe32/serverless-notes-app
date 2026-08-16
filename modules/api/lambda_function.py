import json
import boto3
import uuid
import os
import logging
from boto3.dynamodb.conditions import Key

logger = logging.getLogger()
logger.setLevel(logging.INFO)

TABLE_NAME = os.environ.get('TABLE_NAME', 'NotesTable')
dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(TABLE_NAME)

def lambda_handler(event, context):
    try:
        # 1. SECURE IDENTITY EXTRACTION
        authorizer = event.get('requestContext', {}).get('authorizer', {})
        jwt_claims = authorizer.get('jwt', {}).get('claims')

        if not jwt_claims:
            jwt_claims = authorizer.get('claims', {})

        user_id = jwt_claims.get('sub')
        if not user_id:
            logger.error("Unauthorized attempt.")
            return {"statusCode": 401, "body": json.dumps("Unauthorized")}

        # 2. EXTRACT HTTP METHOD
        # Supports both API Gateway HTTP API (Format 2.0) and REST API (Format 1.0)
        http_method = event.get('requestContext', {}).get('http', {}).get('method') or event.get('httpMethod')

        # --- ROUTER ---

        # CREATE NOTE (POST)
        if http_method == 'POST':
            body = json.loads(event.get('body', '{}'))
            note_content = body.get('Note')
            attachment = body.get('Attachment')

            if not note_content:
                return {"statusCode": 400, "body": json.dumps("Note content is required.")}

            note_id = str(uuid.uuid4())
            item = {'UserId': user_id, 'NoteId': note_id, 'Note': note_content}
            if attachment:
                item['Attachment'] = attachment

            table.put_item(
                Item=item
            )
            logger.info(json.dumps({"message": "Note created successfully", "user_id": user_id, "note_id": note_id}))
            return {
                'statusCode': 201,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({'NoteId': note_id, 'Note': note_content, 'Attachment': attachment, 'Message': 'Successfully saved note'})
            }

        # READ NOTES (GET)
        elif http_method == 'GET':
            # Query DynamoDB for ONLY this user's notes
            response = table.query(
                KeyConditionExpression=Key('UserId').eq(user_id)
            )
            return {
                'statusCode': 200,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps(response.get('Items', []))
            }

        # UPDATE NOTE (PUT)
        elif http_method == 'PUT':
            path_params = event.get('pathParameters', {}) or {}
            note_id = path_params.get('id')

            body = json.loads(event.get('body', '{}'))
            note_content = body.get('Note')

            if not note_id or not note_content:
                return {"statusCode": 400, "body": json.dumps("Note ID and Note content are required.")}

            # Perform a surgical update on just the 'Note' attribute
            table.update_item(
                Key={'UserId': user_id, 'NoteId': note_id},
                UpdateExpression="SET Note = :val1",
                ExpressionAttributeValues={":val1": note_content}
            )

            return {
                'statusCode': 200,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({"message": "Note updated successfully", "NoteId": note_id})
            }

        # DELETE NOTE (DELETE)
        elif http_method == 'DELETE':
            # Extract the {id} variable from the URL path (e.g., /notes/12345)
            path_params = event.get('pathParameters', {}) or {}
            note_id = path_params.get('id')

            if not note_id:
                return {"statusCode": 400, "body": json.dumps("Note ID is required in the path.")}

            table.delete_item(
                Key={'UserId': user_id, 'NoteId': note_id}
            )
            return {
                'statusCode': 200,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({"message": "Note deleted"})
            }

        else:
            return {"statusCode": 405, "body": json.dumps("Method Not Allowed")}

    except Exception as e:
        logger.exception("Internal Server Error occurred.")
        return {"statusCode": 500, "body": json.dumps("Internal Server Error")}