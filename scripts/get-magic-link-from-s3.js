#!/usr/bin/env node

/**
 * Retrieve magic link from S3 bucket for E2E testing
 * 
 * Usage:
 *   node scripts/get-magic-link-from-s3.js <bucket-name> <email-address> [--region <region>]
 * 
 * Example:
 *   node scripts/get-magic-link-from-s3.js my-maildummy-bucket test@maildummy.example.com
 */

const { S3Client, ListObjectsV2Command, GetObjectCommand } = require('@aws-sdk/client-s3');
const { parse } = require('mailparser');

async function getMagicLinkFromS3(bucketName, emailAddress, region = 'eu-central-1') {
  const s3Client = new S3Client({ region });

  try {
    // List objects in the bucket (emails are stored under raw/ prefix)
    const listCommand = new ListObjectsV2Command({
      Bucket: bucketName,
      Prefix: 'raw/',
    });

    const listResponse = await s3Client.send(listCommand);
    
    if (!listResponse.Contents || listResponse.Contents.length === 0) {
      throw new Error(`No emails found in bucket ${bucketName}`);
    }

    // Sort by last modified (most recent first)
    const objects = listResponse.Contents.sort((a, b) => 
      (b.LastModified?.getTime() || 0) - (a.LastModified?.getTime() || 0)
    );

    // Find the most recent email for the given address
    for (const object of objects) {
      if (!object.Key) continue;

      // Get the email object
      const getCommand = new GetObjectCommand({
        Bucket: bucketName,
        Key: object.Key,
      });

      const emailObject = await s3Client.send(getCommand);
      const emailBuffer = await streamToBuffer(emailObject.Body);

      // Parse the email
      const parsed = await parse(emailBuffer);

      // Check if this email is for the target address
      const toAddresses = [
        ...(parsed.to ? (Array.isArray(parsed.to) ? parsed.to : [parsed.to]) : []),
        ...(parsed.cc ? (Array.isArray(parsed.cc) ? parsed.cc : [parsed.cc]) : []),
      ].map(addr => addr.address?.toLowerCase() || '');

      if (!toAddresses.includes(emailAddress.toLowerCase())) {
        continue;
      }

      // Extract magic link from email body
      const body = parsed.html || parsed.text || '';
      const magicLink = extractMagicLink(body);

      if (magicLink) {
        return magicLink;
      }
    }

    throw new Error(`No magic link found for email ${emailAddress} in bucket ${bucketName}`);
  } catch (error) {
    if (error.message.includes('No emails found') || error.message.includes('No magic link found')) {
      throw error;
    }
    throw new Error(`Failed to retrieve magic link: ${error.message}`);
  }
}

function extractMagicLink(body) {
  // Try to find Supabase magic link URL
  // Format: https://{project}.supabase.co/auth/v1/verify?token=...&type=...
  const supabasePattern = /https:\/\/[^\/]+\.supabase\.co\/auth\/v1\/verify\?[^\s"<>]+/gi;
  const matches = body.match(supabasePattern);
  
  if (matches && matches.length > 0) {
    return matches[0];
  }

  // Try to find any URL with token parameter
  const tokenPattern = /https?:\/\/[^\s"<>]*[?&]token=[^\s"<>]+/gi;
  const tokenMatches = body.match(tokenPattern);
  
  if (tokenMatches && tokenMatches.length > 0) {
    return tokenMatches[0];
  }

  return null;
}

async function streamToBuffer(stream) {
  const chunks = [];
  for await (const chunk of stream) {
    chunks.push(chunk);
  }
  return Buffer.concat(chunks);
}

// CLI usage
if (require.main === module) {
  const args = process.argv.slice(2);
  
  if (args.length < 2) {
    console.error('Usage: node scripts/get-magic-link-from-s3.js <bucket-name> <email-address> [--region <region>]');
    process.exit(1);
  }

  const bucketName = args[0];
  const emailAddress = args[1];
  const regionIndex = args.indexOf('--region');
  const region = regionIndex !== -1 && args[regionIndex + 1] ? args[regionIndex + 1] : 'eu-central-1';

  getMagicLinkFromS3(bucketName, emailAddress, region)
    .then(magicLink => {
      console.log(magicLink);
      process.exit(0);
    })
    .catch(error => {
      console.error('Error:', error.message);
      process.exit(1);
    });
}

module.exports = { getMagicLinkFromS3 };

