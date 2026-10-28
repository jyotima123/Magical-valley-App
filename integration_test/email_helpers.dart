// integration_test/email_helpers.dart
// ignore_for_file: avoid_print

import 'dart:convert' show jsonDecode, jsonEncode;
import 'package:http/http.dart' as http;
import 'test_helpers.dart';

/// Create a new inbox for testing
Future<Map<String, String>> createInbox() async {
  final createInboxUrl = Uri.parse('$MAILSLURP_API_BASE_URL/inboxes');
  final createInboxResponse = await http.post(
    createInboxUrl,
    headers: {
      'x-api-key': MAILSLURP_API_KEY,
      'Content-Type': 'application/json',
    },
    body: jsonEncode({}), // Empty body to create a default inbox
  );

  if (createInboxResponse.statusCode == 200 ||
      createInboxResponse.statusCode == 201) {
    final inboxData = jsonDecode(createInboxResponse.body);
    return {
      'inboxId': inboxData['id'],
      'emailAddress': inboxData['emailAddress'],
    };
  } else {
    throw Exception(
      'Failed to create inbox: ${createInboxResponse.statusCode} - ${createInboxResponse.body}',
    );
  }
}

/// Send an email to a specific inbox
Future<void> sendEmailToInbox(String inboxId, String emailAddress) async {
  final sendEmailUrl = Uri.parse('$MAILSLURP_API_BASE_URL/sendEmail');
  final sendEmailResponse = await http.post(
    sendEmailUrl,
    headers: {
      'x-api-key': MAILSLURP_API_KEY,
      'Content-Type': 'application/json',
    },
    body: jsonEncode({
      'inboxId': inboxId,
      'to': emailAddress,
      'subject': 'Hello from Dart HTTP!',
      'body':
          '<html><body><h1>This is a test email sent via MailSlurp REST API.</h1><p>Email content goes here.</p></body></html>',
      'isHTML': true,
    }),
  );

  if (sendEmailResponse.statusCode != 201) {
    throw Exception(
      'Failed to send test email: ${sendEmailResponse.statusCode} - ${sendEmailResponse.body}',
    );
  }
}

/// Check the latest email in a specific inbox
Future<Map<String, dynamic>> checkLatestEmailInInbox(String email) async {
  String inboxId = email.split('@')[0];

  print("Checking email in inbox $inboxId...");

  final waitForEmailUrl = Uri.parse(
    '$MAILSLURP_API_BASE_URL/waitForLatestEmail?inboxId=$inboxId&timeout=30000&unreadOnly=true',
  );

  final emailResponse = await http.get(
    waitForEmailUrl,
    headers: {'x-api-key': MAILSLURP_API_KEY, 'Accept': 'application/json'},
  );

  if (emailResponse.statusCode == 200) {
    print("Got response from inbox $inboxId");
    return jsonDecode(emailResponse.body);
  } else if (emailResponse.statusCode == 408) {
    throw Exception('Timeout: No email received within the specified time.');
  } else {
    print("Did not get response from inbox $inboxId");
    throw Exception(
      'Failed to fetch email: ${emailResponse.statusCode} - ${emailResponse.body}',
    );
  }
}

/// Extract OTP from email body
String getOtpFromEmail(String emailBody) {
  // Extract OTP using regex - looking for the pattern in the template
  final RegExp otpRegex = RegExp(r'[0-9]{6}'); // Assuming 6-digit OTP
  final match = otpRegex.firstMatch(emailBody);

  try {
    if (match != null) {
      final otpCode = match.group(0)!;
      print('✅ Extracted OTP: $otpCode');
      return otpCode;
    } else {
      throw Exception('OTP not found in email body');
    }
  } catch (e) {
    print('❌ Failed to get OTP from email: $e');
    rethrow;
  }
}

/// Extract reset link from email
String extractResetLinkFromEmail(String emailBody) {
  print('🔄 Extracting reset link from email...');

  // Look for reset password link pattern
  final RegExp linkRegex = RegExp(
    r'https?://[^\s]+/reset-password[^\s]*',
    caseSensitive: false,
  );

  final match = linkRegex.firstMatch(emailBody);

  if (match != null) {
    final resetLink = match.group(0)!;
    print('✅ Extracted reset link: ${resetLink.substring(0, 50)}...');
    return resetLink;
  }

  // Fallback: look for any link containing reset or token
  final RegExp fallbackRegex = RegExp(
    r'https?://[^\s]*(?:reset|token)[^\s]*',
    caseSensitive: false,
  );

  final fallbackMatch = fallbackRegex.firstMatch(emailBody);

  if (fallbackMatch != null) {
    final resetLink = fallbackMatch.group(0)!;
    print('✅ Extracted fallback reset link: ${resetLink.substring(0, 50)}...');
    return resetLink;
  }

  print('❌ No reset link found in email');
  return '';
}
