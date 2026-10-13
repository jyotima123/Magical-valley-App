import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Privacy Policy'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Privacy Policy',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFF28C6A),
                ),
              ),
              const SizedBox(height: 8),
              Text(

                'Last Updated: 2025-08-18',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 24),

              _buildSection(
                '1. Information We Collect',
                'Account Information:\n• Name and email address\n• Profile picture (optional)\n• Location/community information\n\nUsage Information:\n• Posts, comments, and interactions\n• App usage patterns and preferences\n• Device information (type, operating system)\n\nLocation Data:\n• General location to show relevant community content\n• We do not track precise location continuously',
              ),

              _buildSection(
                '2. How We Use Your Information',
                'We use your information to:\n• Provide and improve the MVC service\n• Show you relevant local content and events\n• Enable communication with other community members\n• Send important service notifications\n• Ensure platform security and prevent abuse',
              ),

              _buildSection(
                '3. Information Sharing',
                'We Do NOT sell your personal information.\n\nWe may share information:\n• With other users as part of the social platform (posts, public profile info)\n• With service providers who help us operate the app\n• When required by law or to protect our rights\n• In connection with a business transfer (with notice)',
              ),

              _buildSection(
                '4. Your Privacy Rights',
                'You can:\n• Update your profile information anytime\n• Control who sees your posts and information\n• Delete your account and associated data\n• Request a copy of your data\n• Opt out of promotional communications',
              ),

              _buildSection(
                '5. Data Security',
                'We implement reasonable security measures to protect your information, including:\n• Encrypted data transmission\n• Secure servers and databases\n• Regular security updates\n• Limited employee access to personal data',
              ),

              _buildSection(
                '6. Data Retention',
                'We retain your information:\n• While your account is active\n• For a reasonable period after account deletion to resolve disputes\n• As required by law or for legitimate business purposes',
              ),

              _buildSection(
                '7. Children\'s Privacy',
                'MVC is not intended for children under 13. We do not knowingly collect personal information from children under 13. If we become aware of such collection, we will delete the information immediately.',
              ),

              _buildSection(
                '8. International Users',
                'If you are outside the United States, your information may be transferred to and processed in the United States, where our servers are located.',
              ),

              _buildSection(
                '9. Third-Party Services',
                'MVC may integrate with third-party services (like Apple ID for login). Their privacy practices are governed by their own privacy policies.',
              ),

              _buildSection(
                '10. Cookies and Tracking',
                'We use minimal tracking technologies to:\n• Keep you logged in\n• Remember your preferences\n• Analyze app performance\n• You can control some tracking through your device settings',
              ),

              _buildSection(
                '11. Changes to Privacy Policy',
                'We may update this policy periodically. We will notify users of significant changes through the app or email.',
              ),

              _buildSection(
                '12. Contact Us',
                'For privacy questions or requests, contact us at:\n• Email: support@magicvalleycentral.com\n \nYour California Privacy Rights:\nCalifornia residents may request information about data sharing for marketing purposes and have additional rights under the California Consumer Privacy Act (CCPA).',
              ),

              const SizedBox(height: 24),

              // Quick Privacy Summary
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF28C6A).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: const Color(0xFFF28C6A).withOpacity(0.3),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Quick Privacy Summary',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFF28C6A),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildSummaryItem('What we collect:', 'Basic account info, your posts, and general location'),
                    _buildSummaryItem('Why we collect it:', 'To connect you with your local community'),
                    _buildSummaryItem('What we share:', 'Only what you choose to post publicly'),
                    _buildSummaryItem('Your control:', 'You can update, delete, or download your data anytime'),
                    const SizedBox(height: 8),
                    const Text(
                      'Questions? Contact us at support@magicvalleycentral.com',
                      style: TextStyle(
                        fontSize: 14,
                        color: Color(0xFFF28C6A),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // Link to original privacy policy
              Center(
                child: TextButton.icon(
                  onPressed: _launchOriginalPrivacyURL,
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('View Original Privacy Policy'),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFF28C6A),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSection(String title, String content) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            content,
            style: const TextStyle(
              fontSize: 14,
              color: Colors.black54,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(
            fontSize: 14,
            color: Colors.black87,
          ),
          children: [
            TextSpan(
              text: '$label ',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }

  Future<void> _launchOriginalPrivacyURL() async {
    // Replace with your actual privacy policy URL
    const url = 'https://www.magicvalleycentral.com/privacy';
    final uri = Uri.parse(url);

    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        // Handle error - could show a snackbar or dialog
        print('Could not launch $url');
      }
    } catch (e) {
      print('Error launching URL: $e');
    }
  }
}