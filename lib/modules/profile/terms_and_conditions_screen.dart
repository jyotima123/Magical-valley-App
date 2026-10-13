import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class TermsAndConditionsScreen extends StatelessWidget {
  const TermsAndConditionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Terms and Conditions'),
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
                'Terms and Conditions',
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
                '1. Acceptance of Terms',
                'By downloading, installing, or using the MVC app, you agree to be bound by these Terms and Conditions. If you do not agree to these terms, please do not use our service.',
              ),

              _buildSection(
                '2. Description of Service',
                'MVC is a community-focused social platform that connects local businesses, organizations, sports teams, and residents. Users can share updates, discover local events, and engage with their community.',
              ),

              _buildSection(
                '3. User Accounts',
                '• You must be at least 13 years old to create an account\n• You are responsible for maintaining the security of your account\n• You must provide accurate and complete information when creating your account\n• One person may not create multiple accounts',
              ),

              _buildSection(
                '4. Acceptable Use',
                'You agree NOT to:\n• Post illegal, harmful, or inappropriate content\n• Spam or harass other users\n• Impersonate others or create fake accounts\n• Share content that violates others\' privacy or intellectual property\n• Use the service for commercial purposes without permission',
              ),

              _buildSection(
                '5. Content Guidelines',
                '• Keep content relevant to your local community\n• Be respectful and constructive in interactions\n• Do not share false or misleading information\n• Business accounts may share promotional content appropriately',
              ),

              _buildSection(
                '6. User-Generated Content',
                '• You retain ownership of content you post\n• By posting, you grant MVC a license to display and distribute your content within the service\n• MVC may remove content that violates these terms\n• You are responsible for the content you share',
              ),

              _buildSection(
                '7. Privacy',
                'Your privacy is important to us. Please review our Privacy Policy, which explains how we collect, use, and protect your information.',
              ),

              _buildSection(
                '8. Service Availability',
                '• MVC is provided "as is" without warranties\n• We may modify, suspend, or discontinue the service at any time\n• We are not responsible for service interruptions or technical issues',
              ),

              _buildSection(
                '9. Liability Limitation',
                'MVC is not liable for:\n• Content posted by other users\n• Interactions between users\n• Business transactions facilitated through the platform\n• Any indirect or consequential damages',
              ),

              _buildSection(
                '10. Changes to Terms',
                'We may update these terms from time to time. Continued use of the service constitutes acceptance of any changes.',
              ),

              _buildSection(
                '11. Contact Information',
                'For questions about these terms, contact us at: support@mvc-app.com',
              ),

              const SizedBox(height: 32),

              // Link to original terms
              Center(
                child: TextButton.icon(
                  onPressed: _launchOriginalTermsURL,
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('View Original Terms'),
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

  Future<void> _launchOriginalTermsURL() async {
    // Replace with your actual terms URL
    const url = 'https://www.magicvalleycentral.com/terms';
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