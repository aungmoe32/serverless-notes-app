import json
import boto3
import uuid

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table('NotesTable')

def lambda_handler(event, context):
    try:
        body = json.loads(event.get('body', '{}'))
        user_id = body.get('UserId', 'test-user-123')
        note_content = body.get('Note', 'This is a test note!')
        
        note_id = str(uuid.uuid4())
        
        table.put_item(
            Item={
                'UserId': user_id,
                'NoteId': note_id,
                'Note': note_content
            }
        )
        
        return {
            'statusCode': 200,
            'headers': {
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Methods': 'OPTIONS,POST,GET'
            },
            'body': json.dumps('Successfully saved note!')
        }
    except Exception as e:
        print(e)
        return {
            'statusCode': 500,
            'body': json.dumps('Error saving note')
        }