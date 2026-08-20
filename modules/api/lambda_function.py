import boto3
import uuid
import os
from boto3.dynamodb.conditions import Key

from aws_lambda_powertools import Logger, Tracer, Metrics
from aws_lambda_powertools.event_handler import APIGatewayHttpResolver
from aws_lambda_powertools.event_handler.exceptions import UnauthorizedError, BadRequestError

tracer = Tracer()
logger = Logger()
metrics = Metrics()
app = APIGatewayHttpResolver()

TABLE_NAME = os.environ.get('TABLE_NAME', 'NotesTable')
dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(TABLE_NAME)

def get_user_id():
    """Extracts the secure sub UUID from the injected JWT token"""
    # Use the raw_event dictionary to bypass strict object typing conflicts
    authorizer = app.current_event.raw_event.get('requestContext', {}).get('authorizer', {})
    
    # In Payload Format 2.0, HTTP API JWT claims are nested under 'jwt'
    jwt_claims = authorizer.get('jwt', {}).get('claims', {})
        
    user_id = jwt_claims.get('sub')
    if not user_id:
        raise UnauthorizedError("Missing sub claim in Token")
    
    return user_id

@app.post("/notes")
@tracer.capture_method
def create_note():
    user_id = get_user_id()
    body = app.current_event.json_body  # Powertools automatically parses the JSON!
    
    note_content = body.get('Note')
    if not note_content:
        raise BadRequestError("Note content is required.")
        
    note_id = str(uuid.uuid4())
    attachment = body.get('Attachment')
    
    item = {'UserId': user_id, 'NoteId': note_id, 'Note': note_content}
    if attachment:
        item['Attachment'] = attachment
        
    table.put_item(Item=item)
    
    # Structured JSON Logging + Custom Metric
    logger.info(f"Note {note_id} created successfully")
    metrics.add_metric(name="NotesCreated", unit="Count", value=1)
    
    # Powertools automatically formats the HTTP 200 response with CORS headers!
    return {'NoteId': note_id, 'Note': note_content, 'Attachment': attachment}


@app.get("/notes")
@tracer.capture_method
def get_notes():
    user_id = get_user_id()
    response = table.query(KeyConditionExpression=Key('UserId').eq(user_id))
    return response.get('Items', [])


@app.put("/notes/<note_id>")
@tracer.capture_method
def update_note(note_id: str): # <note_id> is automatically pulled from the URL!
    user_id = get_user_id()
    body = app.current_event.json_body
    note_content = body.get('Note')
    
    if not note_content:
        raise BadRequestError("Note content is required.")
        
    table.update_item(
        Key={'UserId': user_id, 'NoteId': note_id},
        UpdateExpression="SET Note = :val1",
        ExpressionAttributeValues={":val1": note_content}
    )
    
    logger.info(f"Note {note_id} updated")
    return {"message": "Note updated successfully", "NoteId": note_id}


@app.delete("/notes/<note_id>")
@tracer.capture_method
def delete_note(note_id: str):
    user_id = get_user_id()
    table.delete_item(Key={'UserId': user_id, 'NoteId': note_id})
    
    logger.info(f"Note {note_id} deleted")
    metrics.add_metric(name="NotesDeleted", unit="Count", value=1)
    
    return {"message": "Note deleted"}


@tracer.capture_lambda_handler
@logger.inject_lambda_context(correlation_id_path="requestContext.requestId", log_event=True)
@metrics.log_metrics(capture_cold_start_metric=True)
def lambda_handler(event, context):
    # Pass the raw AWS event to the Router to handle everything
    return app.resolve(event, context)