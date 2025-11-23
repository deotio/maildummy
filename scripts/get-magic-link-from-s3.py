#!/usr/bin/env python3

"""
Retrieve magic link from S3 bucket for E2E testing

Usage:
    python scripts/get-magic-link-from-s3.py <bucket-name> <email-address> [--region <region>]

Example:
    python scripts/get-magic-link-from-s3.py my-maildummy-bucket test@maildummy.example.com
"""

import sys
import re
import boto3
from email.parser import Parser
from email import message_from_bytes
from datetime import datetime
from typing import Optional


def extract_magic_link(body: str) -> Optional[str]:
    """Extract magic link URL from email body."""
    # Try to find Supabase magic link URL
    # Format: https://{project}.supabase.co/auth/v1/verify?token=...&type=...
    supabase_pattern = r'https://[^/\s"<>]+\.supabase\.co/auth/v1/verify\?[^\s"<>]+'
    matches = re.findall(supabase_pattern, body, re.IGNORECASE)
    
    if matches:
        return matches[0]
    
    # Try to find any URL with token parameter
    token_pattern = r'https?://[^\s"<>]*[?&]token=[^\s"<>]+'
    token_matches = re.findall(token_pattern, body, re.IGNORECASE)
    
    if token_matches:
        return token_matches[0]
    
    return None


def get_magic_link_from_s3(bucket_name: str, email_address: str, region: str = 'eu-central-1') -> str:
    """Retrieve magic link from S3 bucket for given email address."""
    s3_client = boto3.client('s3', region_name=region)
    
    try:
        # List objects in the bucket (emails are stored under raw/ prefix)
        response = s3_client.list_objects_v2(
            Bucket=bucket_name,
            Prefix='raw/'
        )
        
        if 'Contents' not in response or len(response['Contents']) == 0:
            raise ValueError(f'No emails found in bucket {bucket_name}')
        
        # Sort by last modified (most recent first)
        objects = sorted(
            response['Contents'],
            key=lambda x: x['LastModified'],
            reverse=True
        )
        
        # Find the most recent email for the given address
        for obj in objects:
            key = obj['Key']
            
            # Get the email object
            email_obj = s3_client.get_object(Bucket=bucket_name, Key=key)
            email_bytes = email_obj['Body'].read()
            
            # Parse the email
            msg = message_from_bytes(email_bytes)
            
            # Check if this email is for the target address
            to_addresses = []
            if msg['To']:
                to_addresses.extend([addr.strip() for addr in msg['To'].split(',')])
            if msg['Cc']:
                to_addresses.extend([addr.strip() for addr in msg['Cc'].split(',')])
            
            # Extract email addresses from "Name <email>" format
            email_pattern = r'[\w\.-]+@[\w\.-]+\.\w+'
            all_addresses = []
            for addr in to_addresses:
                matches = re.findall(email_pattern, addr)
                all_addresses.extend([m.lower() for m in matches])
            
            if email_address.lower() not in all_addresses:
                continue
            
            # Extract magic link from email body
            body = ''
            if msg.is_multipart():
                for part in msg.walk():
                    if part.get_content_type() == 'text/html':
                        body = part.get_payload(decode=True).decode('utf-8', errors='ignore')
                        break
                    elif part.get_content_type() == 'text/plain' and not body:
                        body = part.get_payload(decode=True).decode('utf-8', errors='ignore')
            else:
                body = msg.get_payload(decode=True).decode('utf-8', errors='ignore')
            
            magic_link = extract_magic_link(body)
            
            if magic_link:
                return magic_link
        
        raise ValueError(f'No magic link found for email {email_address} in bucket {bucket_name}')
    
    except Exception as e:
        if 'No emails found' in str(e) or 'No magic link found' in str(e):
            raise
        raise ValueError(f'Failed to retrieve magic link: {str(e)}')


if __name__ == '__main__':
    if len(sys.argv) < 3:
        print('Usage: python scripts/get-magic-link-from-s3.py <bucket-name> <email-address> [--region <region>]', file=sys.stderr)
        sys.exit(1)
    
    bucket_name = sys.argv[1]
    email_address = sys.argv[2]
    region = 'eu-central-1'
    
    if '--region' in sys.argv:
        region_index = sys.argv.index('--region')
        if region_index + 1 < len(sys.argv):
            region = sys.argv[region_index + 1]
    
    try:
        magic_link = get_magic_link_from_s3(bucket_name, email_address, region)
        print(magic_link)
        sys.exit(0)
    except Exception as e:
        print(f'Error: {e}', file=sys.stderr)
        sys.exit(1)

